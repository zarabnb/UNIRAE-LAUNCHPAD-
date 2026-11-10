import 'dotenv/config';
import { createPublicClient, http, parseAbi, parseAbiItem, type Address, type Chain } from 'viem';
import { prisma } from './db.js';
import { chainConfigs } from './config.js';
import { normalizeV2Swap, normalizeV3Swap, type V2SwapAmounts, type V3SwapAmounts, type NormalizedSwap } from './dex-swap.js';

/**
 * Post-graduation V2/V3 pool indexer.
 * V2 pairs are discovered from confirmed graduation receipts. V3 pools must be explicitly
 * registered in DexPair after independent factory/fee-tier/quote-asset verification.
 * Every pool's token0/token1 are read back on-chain before swaps are indexed.
 */
type PairConfig = { chainId:number; token:string; pair:string; quoteToken:string; dex:string; startBlock?:string };
const pairsFromDatabase = async (): Promise<PairConfig[]> => {
  const [v2Pairs,v3Pools] = await Promise.all([
    prisma.dexPair.findMany({where:{active:true},select:{chainId:true,token:{select:{address:true}},pairAddress:true,quoteToken:true,dex:true,migrationBlock:true}}),
    prisma.dexPool.findMany({where:{active:true},select:{chainId:true,token:{select:{address:true}},poolAddress:true,quoteToken:true,dex:true,startBlock:true}})
  ]);
  return [
    ...v2Pairs.map((p:any)=>({chainId:p.chainId,token:p.token.address,pair:p.pairAddress,quoteToken:p.quoteToken,dex:p.dex,startBlock:p.migrationBlock.toString()})),
    ...v3Pools.map((p:any)=>({chainId:p.chainId,token:p.token.address,pair:p.poolAddress,quoteToken:p.quoteToken,dex:p.dex,startBlock:p.startBlock.toString()}))
  ];
};
const v2SwapEvent = parseAbiItem('event Swap(address indexed sender,uint256 amount0In,uint256 amount1In,uint256 amount0Out,uint256 amount1Out,address indexed to)');
const v3SwapEvent = parseAbiItem('event Swap(address indexed sender,address indexed recipient,int256 amount0,int256 amount1,uint160 sqrtPriceX96,uint128 liquidity,int24 tick)');
const pairAbi = parseAbi(['function token0() view returns (address)','function token1() view returns (address)']);
const sleep = (ms:number) => new Promise(r=>setTimeout(r,ms));
const addr = (v:string) => v.toLowerCase() as Address;
const chainFor = (c: typeof chainConfigs[number]):Chain => ({id:c.id,name:c.name,nativeCurrency:{name:'Native',symbol:'NATIVE',decimals:18},rpcUrls:{default:{http:[c.rpc!]}}});

async function indexPair(p:PairConfig) {
  const c=chainConfigs.find(x=>x.id===p.chainId); if(!c?.rpc) throw new Error(`No configured RPC for chain ${p.chainId}`);
  const client=createPublicClient({chain:chainFor(c),transport:http(c.rpc,{timeout:20000,retryCount:2})});
  const pair=addr(p.pair), token=addr(p.token), quote=addr(p.quoteToken);
  const [token0,token1]=await Promise.all([
    client.readContract({address:pair,abi:pairAbi,functionName:'token0'}),
    client.readContract({address:pair,abi:pairAbi,functionName:'token1'})
  ]);
  const t0=addr(token0),t1=addr(token1);
  if(!((t0===token&&t1===quote)||(t1===token&&t0===quote))) throw new Error(`Pair ${pair} does not contain configured token and quote asset`);
  const tokenIs0=t0===token;
  const isV3=p.dex==='uniswap-v3' || p.dex==='uniswap-v3-compatible';
  if(!isV3 && p.dex!=='uniswap-v2-compatible') throw new Error(`Unsupported DEX pool type ${p.dex} for ${pair}`);
  const record=await prisma.token.findUnique({where:{chainId_address:{chainId:p.chainId,address:token}}});
  if(!record?.verified) throw new Error(`Token ${token} is not registered and verified in UNIRAE`);
  let cursor=await prisma.indexerCursor.findUnique({where:{chainId_contractAddress:{chainId:p.chainId,contractAddress:pair}}});
  const head=await client.getBlockNumber(); const safeHead=head-BigInt(c.confirmations); if(safeHead<0n)return;
  let from=cursor?cursor.lastBlock+1n:BigInt(p.startBlock??0);
  if(cursor){
    const canonical=await client.getBlock({blockNumber:cursor.lastBlock});
    if(canonical.hash!==cursor.lastBlockHash){
      const rewind=cursor.lastBlock>12n?cursor.lastBlock-12n:1n;
      const cursorBlock=rewind-1n;
      await prisma.$transaction(async tx=>{
        const orphaned=await tx.indexedEvent.findMany({where:{chainId:p.chainId,address:pair,blockNumber:{gte:rewind}},select:{txHash:true,logIndex:true}});
        if(orphaned.length) await tx.trade.deleteMany({where:{chainId:p.chainId,tokenId:record.id,OR:orphaned.map(x=>({chainId:p.chainId,txHash:x.txHash,logIndex:x.logIndex}))}});
        await tx.indexedEvent.deleteMany({where:{chainId:p.chainId,address:pair,blockNumber:{gte:rewind}}});
        await tx.indexerCursor.update({where:{id:cursor!.id},data:{lastBlock:cursorBlock,lastBlockHash:(await client.getBlock({blockNumber:cursorBlock})).hash}});
      });
      from=rewind;
    }
  }
  if(from>safeHead)return;
  const to=from+499n>safeHead?safeHead:from+499n;
  const logs=await client.getLogs({address:pair,event:isV3?v3SwapEvent:v2SwapEvent,fromBlock:from,toBlock:to});
  const timestamps=new Map<bigint,Date>();
  for(const log of logs){
    if(!log.transactionHash||log.logIndex===null||log.blockNumber===null||!log.blockHash)continue;
    const rawArgs=log.args; if(!rawArgs)continue;
    // viem infers a union for the two Swap ABIs; narrow it explicitly using the
    // already-verified pool type before reading event-specific fields.
    let normalized: NormalizedSwap;
    let traderValue: string;
    if(isV3) {
      const a=rawArgs as unknown as V3SwapAmounts & {sender:Address;recipient:Address};
      normalized=normalizeV3Swap({amount0:a.amount0,amount1:a.amount1},tokenIs0);
      traderValue=a.recipient;
    } else {
      const a=rawArgs as unknown as V2SwapAmounts & {sender:Address;to:Address};
      normalized=normalizeV2Swap({amount0In:a.amount0In,amount1In:a.amount1In,amount0Out:a.amount0Out,amount1Out:a.amount1Out},tokenIs0);
      traderValue=a.to;
    }
    if(!normalized)continue; // Ignore liquidity events and malformed/ambiguous flows.
    const {side,amountIn,amountOut}=normalized;
    const trader=addr(traderValue);
    let timestamp=timestamps.get(log.blockNumber);
    if(!timestamp){const block=await client.getBlock({blockNumber:log.blockNumber});timestamp=new Date(Number(block.timestamp)*1000);timestamps.set(log.blockNumber,timestamp);}
    await prisma.$transaction(async tx=>{
      await tx.trade.upsert({where:{chainId_txHash_logIndex:{chainId:p.chainId,txHash:log.transactionHash!.toLowerCase(),logIndex:log.logIndex!}},create:{chainId:p.chainId,tokenId:record.id,txHash:log.transactionHash!.toLowerCase(),logIndex:log.logIndex!,blockNumber:log.blockNumber!,blockHash:log.blockHash!,trader,side,amountIn,amountOut,feeAmount:'0',timestamp},update:{tokenId:record.id,blockNumber:log.blockNumber!,blockHash:log.blockHash!,trader,side,amountIn,amountOut,timestamp}});
      await tx.indexedEvent.createMany({data:[{chainId:p.chainId,txHash:log.transactionHash!.toLowerCase(),logIndex:log.logIndex!,blockNumber:log.blockNumber!,blockHash:log.blockHash!,address:pair,eventName:isV3?'DexV3Swap':'DexV2Swap',payload:{token,quoteToken:quote,dex:p.dex,side,amountIn,amountOut}}],skipDuplicates:true});
    });
  }
  const block=await client.getBlock({blockNumber:to});
  await prisma.indexerCursor.upsert({where:{chainId_contractAddress:{chainId:p.chainId,contractAddress:pair}},create:{chainId:p.chainId,contractAddress:pair,lastBlock:to,lastBlockHash:block.hash},update:{lastBlock:to,lastBlockHash:block.hash}});
  if(logs.length)console.log(`[${c.slug}] ${p.dex} pool ${pair}: indexed ${logs.length} swap log(s), blocks ${from}-${to}`);
}

async function run(){
  console.log('UNIRAE post-graduation V2/V3 DEX indexer started.');
  while(true){const pairs=await pairsFromDatabase();for(const p of pairs){try{await indexPair(p)}catch(e){console.error(`[DEX ${p.chainId} ${p.pair}]`,e)}}await sleep(Number(process.env.DEX_INDEXER_POLL_MS||7000));}
}
run().catch(e=>{console.error(e);process.exit(1)}).finally(async()=>prisma.$disconnect());
