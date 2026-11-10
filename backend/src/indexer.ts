import 'dotenv/config';
import { createPublicClient, http, parseAbiItem, type Address, type Chain } from 'viem';
import { prisma } from './db.js';
import { config, chainConfigs } from './config.js';

const transferEvent=parseAbiItem('event Transfer(address indexed from,address indexed to,uint256 value)');
const sleep=(ms:number)=>new Promise(r=>setTimeout(r,ms));
const asViemChain=(c:typeof chainConfigs[number]):Chain=>({id:c.id,name:c.name,nativeCurrency:{name:'Native',symbol:'NATIVE',decimals:18},rpcUrls:{default:{http:[c.rpc!]}}});

async function indexToken(c:typeof chainConfigs[number], client:ReturnType<typeof createPublicClient>, token:{id:string,address:string,indexFromBlock:bigint|null}) {
  const contractAddress=token.address as Address;
  const cursor=await prisma.indexerCursor.findUnique({where:{chainId_contractAddress:{chainId:c.id,contractAddress:contractAddress.toLowerCase()}}});
  const head=await client.getBlockNumber();
  const safeHead=head-BigInt(c.confirmations);
  if(safeHead<0n)return;
  let from=cursor?cursor.lastBlock+1n:(token.indexFromBlock ?? (await client.getBlockNumber()-BigInt(c.confirmations+1000))); 
  if(from<0n)from=0n;
  if(cursor){
    const canonical=await client.getBlock({blockNumber:cursor.lastBlock});
    if(canonical.hash!==cursor.lastBlockHash){
      // Rewind this token's indexed history to the last known cursor minus one block.
      const rewind=cursor.lastBlock>0n?cursor.lastBlock-1n:0n;
      await prisma.$transaction([
        prisma.transfer.deleteMany({where:{chainId:c.id,tokenId:token.id,blockNumber:{gte:rewind}}}),
        prisma.indexedEvent.deleteMany({where:{chainId:c.id,address:contractAddress.toLowerCase(),blockNumber:{gte:rewind}}}),
        prisma.indexerCursor.update({where:{id:cursor.id},data:{lastBlock:rewind,lastBlockHash:(await client.getBlock({blockNumber:rewind})).hash}})
      ]);
      from=rewind+1n;
      console.warn(`[${c.slug}] reorg detected at ${cursor.lastBlock}; rewound ${contractAddress}`);
    }
  }
  if(from>safeHead)return;
  const to=from+config.batchSize-1n>safeHead?safeHead:from+config.batchSize-1n;
  const logs=await client.getLogs({address:contractAddress,event:transferEvent,fromBlock:from,toBlock:to});
  const transfers=[] as Array<{chainId:number,tokenId:string,txHash:string,logIndex:number,blockNumber:bigint,blockHash:string,fromAddress:string,toAddress:string,amount:string}>;
  const indexed=[] as Array<{chainId:number,txHash:string,logIndex:number,blockNumber:bigint,blockHash:string,address:string,eventName:string,payload:any}>;
  for(const log of logs){
    if(!log.transactionHash||log.logIndex===null||!log.blockHash||!log.blockNumber)continue;
    const args=log.args as {from:Address,to:Address,value:bigint};
    transfers.push({chainId:c.id,tokenId:token.id,txHash:log.transactionHash.toLowerCase(),logIndex:log.logIndex,blockNumber:log.blockNumber,blockHash:log.blockHash,fromAddress:args.from.toLowerCase(),toAddress:args.to.toLowerCase(),amount:args.value.toString()});
    indexed.push({chainId:c.id,txHash:log.transactionHash.toLowerCase(),logIndex:log.logIndex,blockNumber:log.blockNumber,blockHash:log.blockHash,address:contractAddress.toLowerCase(),eventName:'Transfer',payload:{from:args.from,to:args.to,value:args.value.toString()}});
  }
  const endBlock=await client.getBlock({blockNumber:to});
  await prisma.$transaction(async tx=>{
    if(transfers.length)await tx.transfer.createMany({data:transfers,skipDuplicates:true});
    if(indexed.length)await tx.indexedEvent.createMany({data:indexed,skipDuplicates:true});
    await tx.indexerCursor.upsert({where:{chainId_contractAddress:{chainId:c.id,contractAddress:contractAddress.toLowerCase()}},create:{chainId:c.id,contractAddress:contractAddress.toLowerCase(),lastBlock:to,lastBlockHash:endBlock.hash},update:{lastBlock:to,lastBlockHash:endBlock.hash}});
  });
  console.log(`[${c.slug}] ${contractAddress} blocks ${from}-${to}: ${logs.length} transfer logs`);
}

async function run(){
  for(const c of chainConfigs){
    await prisma.chain.upsert({where:{id:c.id},create:{id:c.id,slug:c.slug,name:c.name},update:{slug:c.slug,name:c.name}});
  }
  console.log(`Indexer started. ${chainConfigs.length} RPC network(s) configured. Factory addresses are not assumed.`);
  while(true){
    for(const c of chainConfigs){
      try{
        const client=createPublicClient({chain:asViemChain(c),transport:http(c.rpc,{timeout:15_000,retryCount:2})});
        const tokens=await prisma.token.findMany({where:{chainId:c.id,verified:true},select:{id:true,address:true,indexFromBlock:true}});
        for(const token of tokens){try{await indexToken(c,client,token)}catch(e){console.error(`[${c.slug}] token ${token.address}:`,e)}}
      }catch(e){console.error(`[${c.slug}] indexer cycle failed:`,e)}
    }
    await sleep(config.pollMs);
  }
}
run().catch(e=>{console.error(e);process.exit(1)}).finally(async()=>{await prisma.$disconnect()});
