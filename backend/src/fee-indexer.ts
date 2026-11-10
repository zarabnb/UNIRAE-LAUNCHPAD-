import 'dotenv/config';
import { createPublicClient, decodeEventLog, http, parseAbi, type Address, type Chain } from 'viem';
import { prisma } from './db.js';
import { chainConfigs } from './config.js';
import { normalizeFeeEvent } from './fee-events.js';

const feeVaultAbi = parseAbi([
  'event FeeDeposited(address indexed token,address indexed creator,uint256 amount,uint256 creatorAmount,uint256 buybackAmount,uint256 platformAmount)',
  'event CreatorClaimed(address indexed token,address indexed creator,uint256 amount)',
  'event PlatformClaimed(address indexed token,uint256 amount)',
  'event BuybackExecuted(address indexed token,uint256 nativeAmount,uint256 minTokensOut)'
]);
const sleep = (ms:number) => new Promise(resolve => setTimeout(resolve, ms));
const normalized = (value:string) => value.toLowerCase() as Address;

async function indexVault(chainConfig: typeof chainConfigs[number]) {
  if (!chainConfig.rpc || !chainConfig.feeVault || !/^0x[0-9a-fA-F]{40}$/.test(chainConfig.feeVault)) return;
  const chain:Chain = {
    id: chainConfig.id,
    name: chainConfig.name,
    nativeCurrency: { name:'Native', symbol:'NATIVE', decimals:18 },
    rpcUrls: { default: { http:[chainConfig.rpc] } }
  };
  const client = createPublicClient({chain,transport:http(chainConfig.rpc,{timeout:20_000,retryCount:2})});
  const vault = normalized(chainConfig.feeVault);
  const cursor = await prisma.indexerCursor.findUnique({where:{chainId_contractAddress:{chainId:chainConfig.id,contractAddress:vault}}});
  if (!cursor && (!chainConfig.feeVaultStartBlock || !/^\d+$/.test(chainConfig.feeVaultStartBlock))) {
    console.warn(`[${chainConfig.slug}] fee vault ${vault} skipped: set FEE_VAULT_START_BLOCK_${chainConfig.envSuffix}`);
    return;
  }
  const head = await client.getBlockNumber();
  const safeHead = head - BigInt(chainConfig.confirmations);
  if (safeHead < 0n) return;
  let from = cursor ? cursor.lastBlock + 1n : BigInt(chainConfig.feeVaultStartBlock!);
  if (cursor) {
    const canonical = await client.getBlock({blockNumber:cursor.lastBlock});
    if (canonical.hash !== cursor.lastBlockHash) {
      const rewind = cursor.lastBlock > 12n ? cursor.lastBlock - 12n : 1n;
      const cursorBlock = rewind - 1n;
      const rewindBlock = await client.getBlock({blockNumber:cursorBlock});
      await prisma.$transaction(async tx => {
        await tx.feeEvent.deleteMany({where:{chainId:chainConfig.id,vaultAddress:vault,blockNumber:{gte:rewind}}});
        await tx.indexerCursor.update({where:{id:cursor.id},data:{lastBlock:cursorBlock,lastBlockHash:rewindBlock.hash}});
      });
      from = rewind;
    }
  }
  if (from > safeHead) return;
  const batch = BigInt(process.env.FEE_INDEXER_BATCH_SIZE || '500');
  const to = from + batch - 1n > safeHead ? safeHead : from + batch - 1n;
  const logs = await client.getLogs({address:vault,fromBlock:from,toBlock:to});
  const timestamps = new Map<bigint,Date>();
  for (const log of logs) {
    if (!log.transactionHash || log.logIndex === null || log.blockNumber === null || !log.blockHash) continue;
    let decoded:any;
    try { decoded = decodeEventLog({abi:feeVaultAbi,data:log.data,topics:log.topics,strict:false}); }
    catch { continue; }
    const args:any = decoded.args || {};
    let normalizedEvent: ReturnType<typeof normalizeFeeEvent>;
    try { normalizedEvent = normalizeFeeEvent(String(decoded.eventName),args); }
    catch (error) { console.warn(`[${chainConfig.slug}] invalid fee event at ${log.transactionHash}:${log.logIndex}`,error); continue; }
    if (!normalizedEvent) continue;
    const token = normalizedEvent.tokenAddress;
    let timestamp = timestamps.get(log.blockNumber);
    if (!timestamp) {
      const block = await client.getBlock({blockNumber:log.blockNumber});
      timestamp = new Date(Number(block.timestamp)*1000);
      timestamps.set(log.blockNumber,timestamp);
    }
    const data = {
      chainId:chainConfig.id,vaultAddress:vault,tokenAddress:token,actor:normalizedEvent.actor,eventName:normalizedEvent.eventName,amount:normalizedEvent.amount,
      creatorAmount:normalizedEvent.creatorAmount,buybackAmount:normalizedEvent.buybackAmount,platformAmount:normalizedEvent.platformAmount,
      txHash:log.transactionHash.toLowerCase(),logIndex:log.logIndex,blockNumber:log.blockNumber,blockHash:log.blockHash,timestamp,
      payload:normalizedEvent.payload
    };
    await prisma.feeEvent.upsert({
      where:{chainId_txHash_logIndex:{chainId:chainConfig.id,txHash:data.txHash,logIndex:log.logIndex}},
      create:data,
      update:{...data}
    });
  }
  const lastBlock = await client.getBlock({blockNumber:to});
  await prisma.indexerCursor.upsert({
    where:{chainId_contractAddress:{chainId:chainConfig.id,contractAddress:vault}},
    create:{chainId:chainConfig.id,contractAddress:vault,lastBlock:to,lastBlockHash:lastBlock.hash},
    update:{lastBlock:to,lastBlockHash:lastBlock.hash}
  });
  if (logs.length) console.log(`[${chainConfig.slug}] fee vault ${vault}: scanned ${logs.length} logs, blocks ${from}-${to}`);
}

async function run() {
  console.log('UNIRAE fee-vault event indexer started.');
  while (true) {
    for (const c of chainConfigs) {
      if (!c.feeVault) continue;
      try { await indexVault(c); } catch (error) { console.error(`[FEE ${c.id}]`,error); }
    }
    await sleep(Number(process.env.FEE_INDEXER_POLL_MS || 7000));
  }
}
run().catch(error=>{console.error(error);process.exit(1)}).finally(async()=>prisma.$disconnect());
