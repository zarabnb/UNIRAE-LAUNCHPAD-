import 'dotenv/config';
import { createPublicClient, http, parseAbi, type Address, type Chain } from 'viem';
import { prisma } from './db.js';
import { chainConfigs } from './config.js';

const [chainArg, tokenArg, poolArg, quoteArg, startArg] = process.argv.slice(2);
const address = (value: string): Address => {
  if (!/^0x[0-9a-fA-F]{40}$/.test(value)) throw new Error(`Invalid EVM address: ${value}`);
  return value.toLowerCase() as Address;
};
const poolAbi = parseAbi([
  'function token0() view returns (address)',
  'function token1() view returns (address)',
  'function factory() view returns (address)',
  'function fee() view returns (uint24)'
]);

async function main() {
  if (!chainArg || !tokenArg || !poolArg || !quoteArg || !startArg) {
    throw new Error('Usage: npm run register:v3-pool -- <chainId> <token> <pool> <wrappedNativeQuote> <startBlock>');
  }
  const chainId = Number(chainArg);
  if (!Number.isSafeInteger(chainId) || chainId <= 0) throw new Error('Invalid chain ID');
  if (!/^\d+$/.test(startArg)) throw new Error('startBlock must be a non-negative integer');
  const token = address(tokenArg), pool = address(poolArg), quote = address(quoteArg);
  const c = chainConfigs.find(x => x.id === chainId);
  if (!c?.rpc || !c.v3Factory || !c.wrappedNative) throw new Error(`RPC, Uniswap V3 factory and wrapped-native address must be configured for chain ${chainId}`);
  if (address(c.wrappedNative) !== quote) throw new Error('Quote asset must exactly match configured wrapped-native asset');

  const client = createPublicClient({
    chain: { id:c.id, name:c.name, nativeCurrency:{name:'Native',symbol:'NATIVE',decimals:18}, rpcUrls:{default:{http:[c.rpc]}} } as Chain,
    transport: http(c.rpc, { timeout:20_000, retryCount:2 })
  });
  const code = await client.getCode({ address:pool });
  if (!code || code === '0x') throw new Error('Pool address has no contract code');
  const [token0, token1, factory, fee, head] = await Promise.all([
    client.readContract({address:pool,abi:poolAbi,functionName:'token0'}),
    client.readContract({address:pool,abi:poolAbi,functionName:'token1'}),
    client.readContract({address:pool,abi:poolAbi,functionName:'factory'}),
    client.readContract({address:pool,abi:poolAbi,functionName:'fee'}),
    client.getBlockNumber()
  ]);
  if (address(factory) !== address(c.v3Factory)) throw new Error('Pool factory does not match configured Uniswap V3 factory');
  const t0=address(token0), t1=address(token1);
  if (!((t0===token && t1===quote) || (t1===token && t0===quote))) throw new Error('Pool must contain exactly the registered UNIRAE token and wrapped-native quote asset');
  const feeTier=Number(fee);
  if (![100,500,3000,10000].includes(feeTier)) throw new Error(`Unsupported Uniswap V3 fee tier: ${feeTier}`);
  const startBlock=BigInt(startArg);
  if (startBlock > head) throw new Error('startBlock cannot be ahead of the current chain head');
  const tokenRecord=await prisma.token.findUnique({where:{chainId_address:{chainId,address:token}}});
  if (!tokenRecord?.verified) throw new Error('UNIRAE token must already be registered and verified');
  await prisma.dexPool.upsert({
    where:{chainId_poolAddress:{chainId,poolAddress:pool}},
    create:{chainId,tokenId:tokenRecord.id,poolAddress:pool,quoteToken:quote,startBlock,feeTier,dex:'uniswap-v3',active:true},
    update:{tokenId:tokenRecord.id,quoteToken:quote,startBlock,feeTier,dex:'uniswap-v3',active:true}
  });
  console.log(`Registered verified Uniswap V3 pool ${pool} on ${c.slug}; fee=${feeTier}; indexing starts at ${startBlock}.`);
}

main().catch(error => { console.error(error); process.exitCode=1; }).finally(async () => prisma.$disconnect());
