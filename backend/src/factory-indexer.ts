import 'dotenv/config';
import { createPublicClient, http, parseAbiItem, decodeEventLog, type Address, type Chain, type Hex } from 'viem';
import { prisma } from './db.js';
import { config, chainConfigs } from './config.js';
import { CURVE_EVENTS, FACTORY_LAUNCH_EVENT, mapCurveTrade, normalizeAddress } from './launch-decoder.js';
import { reorgReplayWindow } from './reorg-window.js';
import { keepCanonicalLogs } from './canonical-logs.js';
import { migrationCoordinatorMatches, quoteAssetFromPair } from './migration-discovery.js';

const sleep = (ms:number) => new Promise(r => setTimeout(r, ms));
const MIGRATED_EVENT = parseAbiItem('event Migrated(address indexed token,address indexed pair,uint256 tokenUsed,uint256 nativeUsed,uint256 liquidity,uint256 lockId)');
const CURVE_MIGRATION_ABI = [{type:'function',name:'migrationCoordinator',stateMutability:'view',inputs:[],outputs:[{type:'address'}]}] as const;
const COORDINATOR_ABI = [{type:'function',name:'router',stateMutability:'view',inputs:[],outputs:[{type:'address'}]}] as const;
const ROUTER_ABI = [{type:'function',name:'WETH',stateMutability:'view',inputs:[],outputs:[{type:'address'}]}] as const;
const PAIR_TOKENS_ABI = [{type:'function',name:'token0',stateMutability:'view',inputs:[],outputs:[{type:'address'}]},{type:'function',name:'token1',stateMutability:'view',inputs:[],outputs:[{type:'address'}]}] as const;
const chainFor = (c: typeof chainConfigs[number]): Chain => ({ id:c.id, name:c.name, nativeCurrency:{name:'Native',symbol:'NATIVE',decimals:18}, rpcUrls:{default:{http:[c.rpc!]}} });
type CanonicalLog = { transactionHash: Hex | null; logIndex: number | null; blockHash: Hex | null; blockNumber: bigint | null; eventName?: string; args?: Record<string, unknown> };
const jsonSafe = (v:any):any => typeof v === 'bigint' ? v.toString() : Array.isArray(v) ? v.map(jsonSafe) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k,x])=>[k,jsonSafe(x)])) : v;

async function cursorStart(client:any, chainId:number, address:string, startBlock:string, isFactory=false) {
  const cursor = await prisma.indexerCursor.findUnique({where:{chainId_contractAddress:{chainId,contractAddress:address}}});
  if (!cursor) return {from:BigInt(startBlock || '0'), cursor:null as any};
  const canonical = await client.getBlock({blockNumber:cursor.lastBlock});
  if (canonical.hash !== cursor.lastBlockHash) {
    // Replay the previous block as well as the changed tip. The cursor is
    // positioned immediately before that replay window so no deleted log is skipped.
    const { replayFrom:rewindFrom, cursorBlock } = reorgReplayWindow(cursor.lastBlock);
    await prisma.$transaction(async tx => {
      await tx.indexedEvent.deleteMany({where:{chainId,address,blockNumber:{gte:rewindFrom}}});
      if (isFactory) {
        const orphaned = await tx.token.findMany({where:{chainId,createdBlock:{gte:rewindFrom}},select:{id:true}});
        const ids = orphaned.map((t:any)=>t.id);
        if (ids.length) {
          await tx.dexPair.deleteMany({where:{tokenId:{in:ids}}});
          await tx.trade.deleteMany({where:{tokenId:{in:ids}}});
          await tx.transfer.deleteMany({where:{tokenId:{in:ids}}});
          await tx.token.deleteMany({where:{id:{in:ids}}});
        }
      } else {
        await tx.trade.deleteMany({where:{chainId,blockNumber:{gte:rewindFrom},token:{curveAddress:address}}});
        await tx.dexPair.deleteMany({where:{chainId,migrationBlock:{gte:rewindFrom},token:{curveAddress:address}}});
      }
      const hash = (await client.getBlock({blockNumber:cursorBlock})).hash;
      await tx.indexerCursor.update({where:{id:cursor.id},data:{lastBlock:cursorBlock,lastBlockHash:hash}});
    });
    return {from:rewindFrom,cursor};
  }
  return {from:cursor.lastBlock+1n,cursor};
}

async function saveCursor(chainId:number,address:string,to:bigint,hash:string) {
  await prisma.indexerCursor.upsert({where:{chainId_contractAddress:{chainId,contractAddress:address}},create:{chainId,contractAddress:address,lastBlock:to,lastBlockHash:hash},update:{lastBlock:to,lastBlockHash:hash}});
}

async function indexFactory(c:typeof chainConfigs[number], client:any, safeHead:bigint) {
  if (!c.factory) return;
  const address=normalizeAddress(c.factory);
  const {from}=await cursorStart(client,c.id,address,process.env[`FACTORY_START_BLOCK_${c.envSuffix}`]||'0',true);
  if(from>safeHead)return;
  const to=from+config.batchSize-1n>safeHead?safeHead:from+config.batchSize-1n;
  const event=parseAbiItem(FACTORY_LAUNCH_EVENT);
  const fetched=await client.getLogs({address:address as Address,event,fromBlock:from,toBlock:to});
  const logs=await keepCanonicalLogs<CanonicalLog>(client,fetched as unknown as CanonicalLog[]);
  for(const log of logs){
    if(!log.transactionHash||log.logIndex===null||!log.blockHash||log.blockNumber===null)continue;
    const a=log.args as Record<string, any>; const token=normalizeAddress(String(a.token)); const curve=normalizeAddress(a.curve); const creator=normalizeAddress(a.creator);
    const payload=jsonSafe(a);
    await prisma.$transaction(async tx=>{
      await tx.indexedEvent.createMany({data:[{chainId:c.id,txHash:log.transactionHash!.toLowerCase(),logIndex:log.logIndex!,blockNumber:log.blockNumber!,blockHash:log.blockHash!,address,eventName:'TokenLaunched',payload}],skipDuplicates:true});
      await tx.token.upsert({where:{chainId_address:{chainId:c.id,address:token}},create:{chainId:c.id,address:token,curveAddress:curve,creator,name:String(a.name),symbol:String(a.symbol),decimals:18,totalSupply:String(a.supply),txHash:log.transactionHash!.toLowerCase(),createdBlock:log.blockNumber!,indexFromBlock:log.blockNumber!,verified:true},update:{curveAddress:curve,creator,name:String(a.name),symbol:String(a.symbol),totalSupply:String(a.supply),txHash:log.transactionHash!.toLowerCase(),createdBlock:log.blockNumber!,indexFromBlock:log.blockNumber!,verified:true}});
    });
  }
  const block=await client.getBlock({blockNumber:to}); await saveCursor(c.id,address,to,block.hash);
  if(logs.length) console.log(`[${c.slug}] discovered ${logs.length} launch(es), blocks ${from}-${to}`);
}

async function indexCurve(c:typeof chainConfigs[number],client:any,safeHead:bigint,token: {id:string;address:string;curveAddress:string|null;indexFromBlock:bigint|null;symbol:string}) {
  if(!token.curveAddress)return;
  const address=normalizeAddress(token.curveAddress);
  const {from}=await cursorStart(client,c.id,address,token.indexFromBlock?.toString()||'0');
  if(from>safeHead)return;
  const to=from+config.batchSize-1n>safeHead?safeHead:from+config.batchSize-1n;
  const eventItems=CURVE_EVENTS.map(parseAbiItem);
  const fetched=await client.getLogs({address:address as Address,events:eventItems,fromBlock:from,toBlock:to});
  const logs=await keepCanonicalLogs<CanonicalLog>(client,fetched as unknown as CanonicalLog[]);
  const blockTimes=new Map<bigint,Date>();
  for(const log of logs){
    if(!log.transactionHash||log.logIndex===null||!log.blockHash||log.blockNumber===null||!log.eventName)continue;
    const payload=jsonSafe(log.args ?? {});
    if(log.eventName==='GraduationMigrated') {
      const emittedCoordinator=String((log.args as any).coordinator).toLowerCase();
      const configuredCoordinator=String(await client.readContract({address:address as Address,abi:CURVE_MIGRATION_ABI,functionName:'migrationCoordinator'})).toLowerCase();
      if(!migrationCoordinatorMatches(emittedCoordinator,configuredCoordinator)) throw new Error(`Graduation coordinator mismatch for ${token.symbol}; pair registration refused`);
      const receipt=await client.getTransactionReceipt({hash:log.transactionHash!});
      const migration=receipt.logs.map((entry:any)=>{try{return {...entry,decoded:decodeEventLog({abi:[MIGRATED_EVENT],data:entry.data,topics:entry.topics})}}catch{return null}}).find((entry:any)=>entry?.decoded?.eventName==='Migrated' && String(entry.decoded.args.token).toLowerCase()===token.address.toLowerCase());
      if(migration) {
        const pair=String(migration.decoded.args.pair).toLowerCase();
        const [t0,t1]=await Promise.all([client.readContract({address:pair as Address,abi:PAIR_TOKENS_ABI,functionName:'token0'}),client.readContract({address:pair as Address,abi:PAIR_TOKENS_ABI,functionName:'token1'})]);
        const quote=quoteAssetFromPair(token.address,String(t0),String(t1));
        if(!quote) throw new Error(`Migrated pair ${pair} does not contain ${token.address}`);
        const router=await client.readContract({address:configuredCoordinator as Address,abi:COORDINATOR_ABI,functionName:'router'});
        const wrappedNative=String(await client.readContract({address:router as Address,abi:ROUTER_ABI,functionName:'WETH'})).toLowerCase();
        if(quote!==wrappedNative) throw new Error(`Migrated pair quote asset ${quote} is not coordinator wrapped-native ${wrappedNative}; pair not charted as native-denominated`);
        await prisma.dexPair.upsert({where:{chainId_pairAddress:{chainId:c.id,pairAddress:pair}},create:{chainId:c.id,tokenId:token.id,pairAddress:pair,quoteToken:quote,migrationTxHash:log.transactionHash!.toLowerCase(),migrationBlock:log.blockNumber!,migrationLogIndex:migration.logIndex,blockHash:log.blockHash!,dex:'uniswap-v2-compatible',active:true},update:{tokenId:token.id,quoteToken:quote,migrationTxHash:log.transactionHash!.toLowerCase(),migrationBlock:log.blockNumber!,migrationLogIndex:migration.logIndex,blockHash:log.blockHash!,active:true}});
        console.log(`[${c.slug}] graduation migrated ${token.symbol}; registered verified pair ${pair}`);
      } else console.warn(`[${c.slug}] ${token.symbol} emitted GraduationMigrated but no coordinator Migrated event was found; pair not registered`);
    }
    const trade=mapCurveTrade(log.eventName,log.args ?? {});
    await prisma.$transaction(async tx=>{
      await tx.indexedEvent.createMany({data:[{chainId:c.id,txHash:log.transactionHash!.toLowerCase(),logIndex:log.logIndex!,blockNumber:log.blockNumber!,blockHash:log.blockHash!,address,eventName:log.eventName!,payload}],skipDuplicates:true});
      if(trade) {
        const tradeBlockNumber = log.blockNumber;
        if (tradeBlockNumber === null) throw new Error('Canonical trade log is missing its block number');
        let timestamp=blockTimes.get(tradeBlockNumber);
        if(!timestamp){const header=await client.getBlock({blockNumber:tradeBlockNumber});timestamp=new Date(Number(header.timestamp)*1000);blockTimes.set(tradeBlockNumber,timestamp);}
        await tx.trade.upsert({where:{chainId_txHash_logIndex:{chainId:c.id,txHash:log.transactionHash!.toLowerCase(),logIndex:log.logIndex!}},create:{chainId:c.id,tokenId:token.id,txHash:log.transactionHash!.toLowerCase(),logIndex:log.logIndex!,blockNumber:log.blockNumber!,blockHash:log.blockHash!,trader:trade.trader.toLowerCase(),side:trade.side,amountIn:trade.side==='BUY'?trade.nativeAmount.toString():trade.tokenAmount.toString(),amountOut:trade.side==='BUY'?trade.tokenAmount.toString():trade.nativeAmount.toString(),feeAmount:trade.feeAmount.toString(),timestamp},update:{timestamp,blockHash:log.blockHash!}});
      }
    });
  }
  const block=await client.getBlock({blockNumber:to}); await saveCursor(c.id,address,to,block.hash);
  if(logs.length)console.log(`[${c.slug}] ${token.symbol}: indexed ${logs.length} curve event(s), blocks ${from}-${to}`);
}

async function backfillTradeTimestamps(client:any,tokenId:string) {
  const missing=await prisma.trade.findMany({where:{tokenId,timestamp:null},select:{id:true,blockNumber:true},orderBy:{blockNumber:'asc'},take:500});
  const cache=new Map<bigint,Date>();
  for(const row of missing){
    let timestamp=cache.get(row.blockNumber);
    if(!timestamp){const block=await client.getBlock({blockNumber:row.blockNumber});timestamp=new Date(Number(block.timestamp)*1000);cache.set(row.blockNumber,timestamp);}
    await prisma.trade.updateMany({where:{id:row.id,timestamp:null},data:{timestamp}});
  }
  if(missing.length)console.log(`Backfilled ${missing.length} trade timestamps for ${tokenId}`);
}

async function run(){
  console.log('UNIRAE semantic launch + curve trade indexer started.');
  while(true){
    for(const c of chainConfigs){
      try{
        if(!c.rpc)continue;
        const client=createPublicClient({chain:chainFor(c),transport:http(c.rpc,{timeout:20000,retryCount:2})});
        const head=await client.getBlockNumber(); const safeHead=head-BigInt(c.confirmations); if(safeHead<0n)continue;
        await indexFactory(c,client,safeHead);
        const tokens=await prisma.token.findMany({where:{chainId:c.id,curveAddress:{not:null}},select:{id:true,address:true,curveAddress:true,indexFromBlock:true,symbol:true}});
        for(const token of tokens){try{await backfillTradeTimestamps(client,token.id);await indexCurve(c,client,safeHead,token)}catch(e){console.error(`[${c.slug}] curve ${token.curveAddress} failed:`,e)}}
      }catch(e){console.error(`[${c.slug}] factory indexing failed:`,e)}
    }
    await sleep(config.pollMs);
  }
}
run().catch(e=>{console.error(e);process.exit(1)}).finally(async()=>prisma.$disconnect());
