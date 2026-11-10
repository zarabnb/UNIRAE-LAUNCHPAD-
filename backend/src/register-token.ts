import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { createPublicClient, getAddress, http, isAddress, parseAbi, type Chain } from 'viem';
import { chainConfigs } from './config.js';

const [chainArg,addressArg,creatorArg,nameArg,symbolArg,decimalsArg='18',txHashArg='',startBlockArg=''] = process.argv.slice(2);
if(!chainArg||!addressArg||!creatorArg||!nameArg||!symbolArg||!isAddress(addressArg)||!isAddress(creatorArg)){
 console.error('Usage: npm run register-token -- <chainId> <tokenAddress> <creatorAddress> <name> <symbol> [decimals] [creationTxHash] [indexFromBlock]');process.exit(1);
}
const indexBlock=(value:string)=>{if(!value)return null;const n=BigInt(value);if(n<0n)throw new Error('indexFromBlock must be non-negative');return n};
const db=new PrismaClient();
const abi=parseAbi([
 'function name() view returns (string)',
 'function symbol() view returns (string)',
 'function decimals() view returns (uint8)',
 'function totalSupply() view returns (uint256)',
]);
try{
 const chainId=Number(chainArg),decimals=Number(decimalsArg),indexFromBlock=indexBlock(startBlockArg);
 if(!Number.isInteger(chainId)||!Number.isInteger(decimals)||decimals<0||decimals>36)throw new Error('Invalid chainId or decimals');
 const chain=await db.chain.findUnique({where:{id:chainId}});if(!chain)throw new Error('Chain is not in the configured registry');
 const cfg=chainConfigs.find(c=>c.id===chainId&&c.rpc);if(!cfg)throw new Error('No RPC configured for this chain');
 const viemChain:Chain={id:cfg.id,name:cfg.name,nativeCurrency:{name:'Native',symbol:'NATIVE',decimals:18},rpcUrls:{default:{http:[cfg.rpc!]}}};
 const client=createPublicClient({chain:viemChain,transport:http(cfg.rpc,{timeout:15000,retryCount:1})});
 const address=getAddress(addressArg),creator=getAddress(creatorArg);
 const code=await client.getCode({address});if(!code||code==='0x')throw new Error('No contract bytecode exists at this address on the selected chain');
 const [onchainName,onchainSymbol,onchainDecimals,onchainSupply]=await Promise.all([
  client.readContract({address,abi,functionName:'name'}),
  client.readContract({address,abi,functionName:'symbol'}),
  client.readContract({address,abi,functionName:'decimals'}),
  client.readContract({address,abi,functionName:'totalSupply'}),
 ]);
 if(onchainName!==nameArg||onchainSymbol!==symbolArg||Number(onchainDecimals)!==decimals){
  throw new Error(`Metadata mismatch. On-chain reports ${onchainName} (${onchainSymbol}), ${onchainDecimals} decimals; supplied values were ${nameArg} (${symbolArg}), ${decimals}.`);
 }
 let creationBlock:bigint|null=null;
 if(txHashArg){
  const receipt=await client.getTransactionReceipt({hash:txHashArg as `0x${string}`});
  if(receipt.status!=='success')throw new Error('Creation transaction did not succeed');
  if(receipt.to?.toLowerCase()===address.toLowerCase())throw new Error('Provided transaction appears to call the token, not create it; verify the deployment receipt manually');
  creationBlock=receipt.blockNumber;
 }
 if(indexFromBlock!==null&&creationBlock!==null&&indexFromBlock>creationBlock)throw new Error('Indexer start block cannot be later than the supplied creation transaction block');
 const token=await db.token.upsert({where:{chainId_address:{chainId,address:address.toLowerCase()}},create:{chainId,address:address.toLowerCase(),creator:creator.toLowerCase(),name:onchainName,symbol:onchainSymbol,decimals:Number(onchainDecimals),totalSupply:onchainSupply.toString(),txHash:txHashArg||null,createdBlock:creationBlock,indexFromBlock:indexFromBlock??creationBlock,verified:true},update:{creator:creator.toLowerCase(),name:onchainName,symbol:onchainSymbol,decimals:Number(onchainDecimals),totalSupply:onchainSupply.toString(),txHash:txHashArg||null,createdBlock:creationBlock??undefined,indexFromBlock:indexFromBlock??creationBlock??undefined,verified:true}});
 console.log(`Verified and registered ${token.name} (${token.symbol}) at ${token.address} on ${chain.name}.`);
 console.log(`On-chain total supply: ${onchainSupply.toString()}. Indexing starts at block ${token.indexFromBlock?.toString()??'default recent window'}.`);
}catch(error){console.error('Token registration failed:',error instanceof Error?error.message:error);process.exitCode=1}
finally{await db.$disconnect()}
