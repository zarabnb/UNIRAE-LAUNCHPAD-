import express from 'express';
import { randomBytes } from 'node:crypto';
import { signSession, requireWalletSession } from './wallet-session.js';
import { hashAuthMessage, matchesAuthMessage, isAllowedAuthDomain } from './auth-challenge.js';
import cors from 'cors';
import helmet from 'helmet';
import { isAddress, verifyMessage, createPublicClient, http, parseAbi, type Chain } from 'viem';
import { z } from 'zod';
import { prisma } from './db.js';
import { config, chainConfigs } from './config.js';
import { buildCandles } from './candles.js';
import { convertCandlesToUsd, readNativeUsdQuote } from './oracle.js';

const PORTFOLIO_TRANSFER_SCAN_CAP = 100_000;
async function readAllTransfers(field:'toAddress'|'fromAddress', wallet:string){
  const rows:any[]=[]; let cursor:string|undefined; let complete=false;
  while(rows.length < PORTFOLIO_TRANSFER_SCAN_CAP){
    const take=Math.min(5000,PORTFOLIO_TRANSFER_SCAN_CAP-rows.length);
    const batch=await prisma.transfer.findMany({where:field==='toAddress'?{toAddress:wallet}:{fromAddress:wallet},select:{id:true,chainId:true,tokenId:true,amount:true},orderBy:{id:'asc'},take,...(cursor?{skip:1,cursor:{id:cursor}}:{})});
    rows.push(...batch);
    if(batch.length<take){complete=true;break;}
    cursor=batch[batch.length-1].id;
  }
  return {rows,complete};
}

const erc20ReadAbi = parseAbi([
  'function balanceOf(address owner) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function totalSupply() view returns (uint256)',
]);
const evmChain = (c: typeof chainConfigs[number]): Chain => ({
  id: c.id, name: c.name, nativeCurrency: { name: 'Native', symbol: 'NATIVE', decimals: 18 },
  rpcUrls: { default: { http: [c.rpc!] } },
});
const publicClients = new Map<number, ReturnType<typeof createPublicClient>>();
function getReadClient(chainId: number) {
  const cfg = chainConfigs.find(c => c.id === chainId && c.rpc);
  if (!cfg) return null;
  if (!publicClients.has(chainId)) publicClients.set(chainId, createPublicClient({ chain: evmChain(cfg), transport: http(cfg.rpc, { timeout: 12_000, retryCount: 1 }) }));
  return publicClients.get(chainId)!;
}

const app = express();

// Small process-local safety net. Put a trusted reverse proxy/API gateway in front in production.
const rateBuckets = new Map<string, { start:number; count:number }>();
app.use((req,res,next)=>{
  const key=req.ip || req.socket.remoteAddress || 'unknown'; const now=Date.now();
  const bucket=rateBuckets.get(key);
  if(!bucket || now-bucket.start>60_000) rateBuckets.set(key,{start:now,count:1});
  else { bucket.count++; if(bucket.count>180) return res.status(429).json({error:'Rate limit exceeded'}); }
  if(rateBuckets.size>10_000) for(const [k,v] of rateBuckets) if(now-v.start>120_000) rateBuckets.delete(k);
  next();
});
app.disable('x-powered-by');
app.use(helmet());
app.use(cors({ origin(origin, cb) { if (!origin || config.corsOrigins.includes(origin)) return cb(null, true); cb(new Error('Origin not allowed')); } }));
app.use(express.json({ limit: '32kb' }));
app.post('/v1/auth/nonce', async (req,res,next)=>{try{
  const input=z.object({address:z.string().refine(isAddress),domain:z.string().min(3).max(255),chainId:z.coerce.number().int().positive()}).parse(req.body);
  const domain=input.domain.toLowerCase();
  if(!isAllowedAuthDomain(domain,config.corsOrigins))return res.status(400).json({error:'Domain is not allowlisted'});
  if(!chainConfigs.some(c=>c.id===input.chainId))return res.status(400).json({error:'Chain is not configured for wallet authentication'});
  const address=input.address.toLowerCase(); const nonce=randomBytes(24).toString('hex');
  const issuedAt=new Date(); const expiresAt=new Date(issuedAt.getTime()+5*60_000);
  const message=`${domain} wants you to sign in with your Ethereum account:\n${address}\n\nSign in to UNIRAE. This request will not trigger a blockchain transaction.\n\nURI: ${config.corsOrigins.find(o=>{try{return new URL(o).host.toLowerCase()===domain}catch{return false}})}\nVersion: 1\nChain ID: ${input.chainId}\nNonce: ${nonce}\nIssued At: ${issuedAt.toISOString()}\nExpiration Time: ${expiresAt.toISOString()}`;
  const messageHash=hashAuthMessage(message);
  await prisma.walletNonce.create({data:{address,nonce,domain,chainId:input.chainId,messageHash,expiresAt}});
  res.json({nonce,message,expiresIn:300});
}catch(e){next(e)}});
app.post('/v1/auth/verify', async (req,res,next)=>{try{
  const input=z.object({address:z.string().refine(isAddress),nonce:z.string().min(32).max(128),message:z.string().min(80).max(2000),signature:z.string().regex(/^0x[0-9a-fA-F]+$/)}).parse(req.body);
  const address=input.address.toLowerCase();
  const record=await prisma.walletNonce.findUnique({where:{nonce:input.nonce}});
  if(!record||record.address!==address||record.usedAt||record.expiresAt<=new Date())return res.status(401).json({error:'Nonce invalid, expired or already used'});
  if(!matchesAuthMessage(input.message,record.messageHash))return res.status(401).json({error:'Signed message does not match challenge'});
  const valid=await verifyMessage({address:address as `0x${string}`,message:input.message,signature:input.signature as `0x${string}`});
  if(!valid)return res.status(401).json({error:'Invalid wallet signature'});
  const consumed=await prisma.walletNonce.updateMany({where:{id:record.id,usedAt:null,expiresAt:{gt:new Date()}},data:{usedAt:new Date()}});
  if(consumed.count!==1)return res.status(409).json({error:'Nonce already consumed'});
  const expiresAt=Math.floor(Date.now()/1000)+3600;
  const token=signSession({sub:address,exp:expiresAt,domain:record.domain,chainId:record.chainId});
  res.json({authenticated:true,address,chainId:record.chainId,token,tokenType:'Bearer',expiresAt});
}catch(e){next(e)}});


app.get('/v1/auth/me', requireWalletSession, (req,res)=>res.json({authenticated:true,wallet:(req as any).walletSession.sub,domain:(req as any).walletSession.domain,chainId:(req as any).walletSession.chainId}));
app.get('/health', async (_req,res) => {
  let database = 'ok'; try { await prisma.$queryRaw`SELECT 1`; } catch { database = 'unavailable'; }
  res.status(database === 'ok' ? 200 : 503).json({ service:'unirae-api', status: database === 'ok' ? 'ok' : 'degraded', database, configuredChains: chainConfigs.map(c=>({id:c.id,slug:c.slug,configuredFactory:Boolean(c.factory),configuredFeeVault:Boolean(c.feeVault)})), timestamp:new Date().toISOString() });
});
app.get('/v1/chains', (_req,res) => res.json(chainConfigs.map(c=>({id:c.id,slug:c.slug,name:c.name,namespace:'evm',rpcConfigured:Boolean(c.rpc),indexerConfigured:Boolean(c.rpc&&c.factory),feeVaultConfigured:Boolean(c.feeVault),confirmations:c.confirmations}))));
app.get('/v1/indexer/status', async (_req,res,next)=>{try{
  const cursors=await prisma.indexerCursor.findMany({orderBy:{updatedAt:'desc'}});
  const recent=await prisma.indexedEvent.findMany({orderBy:{blockNumber:'desc'},take:10,select:{chainId:true,address:true,eventName:true,blockNumber:true,txHash:true}});
  res.json({chains:chainConfigs.map(c=>({chainId:c.id,slug:c.slug,rpcConfigured:Boolean(c.rpc),factoryConfigured:Boolean(c.factory),confirmations:c.confirmations})),cursors:cursors.map(c=>({...c,lastBlock:c.lastBlock.toString()})),recentEvents:recent.map(e=>({...e,blockNumber:e.blockNumber.toString()})),generatedAt:new Date().toISOString()});
}catch(e){next(e)}});
app.get('/v1/tokens', async (req,res,next) => { try {
  const q = z.object({ chainId:z.coerce.number().int().positive().optional(), limit:z.coerce.number().int().min(1).max(100).default(30), cursor:z.string().optional() }).parse(req.query);
  const rows = await prisma.token.findMany({ where:{...(q.chainId?{chainId:q.chainId}:{}),verified:true}, orderBy:{createdAt:'desc'}, take:q.limit, ...(q.cursor?{skip:1,cursor:{id:q.cursor}}:{}), include:{chain:{select:{name:true,slug:true}}} });
  res.json({items:rows.map(t=>({...t,createdBlock:t.createdBlock?.toString()??null})),nextCursor:rows.length===q.limit?rows.at(-1)?.id:null});
} catch(e){next(e)} });
app.get('/v1/fees/:chainId/:tokenAddress', async (req,res,next)=>{try{
  const chainId=z.coerce.number().int().positive().parse(req.params.chainId);
  const tokenAddress=req.params.tokenAddress;
  if(!isAddress(tokenAddress))return res.status(400).json({error:'Invalid token address'});
  const rows=await prisma.feeEvent.findMany({where:{chainId,tokenAddress:tokenAddress.toLowerCase()},orderBy:[{blockNumber:'desc'},{logIndex:'desc'}],take:100});
  const totals={deposited:0n,creatorClaimed:0n,platformClaimed:0n,buybackExecuted:0n,creatorAllocated:0n,buybackAllocated:0n,platformAllocated:0n};
  for(const row of rows){
    const amount=BigInt(row.amount||'0');
    if(row.eventName==='FeeDeposited'){totals.deposited+=amount;totals.creatorAllocated+=BigInt(row.creatorAmount||'0');totals.buybackAllocated+=BigInt(row.buybackAmount||'0');totals.platformAllocated+=BigInt(row.platformAmount||'0');}
    else if(row.eventName==='CreatorClaimed')totals.creatorClaimed+=amount;
    else if(row.eventName==='PlatformClaimed')totals.platformClaimed+=amount;
    else if(row.eventName==='BuybackExecuted')totals.buybackExecuted+=amount;
  }
  res.json({chainId,tokenAddress:tokenAddress.toLowerCase(),amountsAreRawNativeBaseUnits:true,coverage:'latest 100 indexed fee-vault events',totals:Object.fromEntries(Object.entries(totals).map(([k,v])=>[k,v.toString()])),events:rows.map(r=>({...r,blockNumber:r.blockNumber.toString()}))});
}catch(e){next(e)}});

app.get('/v1/prices/native-usd/:chainId', async (req,res,next)=>{try{
  const chainId=z.coerce.number().int().positive().parse(req.params.chainId);
  const cfg=chainConfigs.find(c=>c.id===chainId);
  if(!cfg?.rpc||!cfg.nativeUsdFeed||!isAddress(cfg.nativeUsdFeed))return res.status(404).json({error:'A verified native/USD feed is not configured for this chain'});
  const quote=await readNativeUsdQuote({chain:evmChain(cfg),rpc:cfg.rpc,feed:cfg.nativeUsdFeed as `0x${string}`,maxAgeSeconds:Number(process.env.ORACLE_MAX_AGE_SECONDS||3600)});
  res.json({chainId,base:'native',quote:'USD',...quote});
}catch(e){next(e)}});

app.get('/v1/tokens/:chainId/:address/candles', async (req,res,next)=>{try{
  const chainId=z.coerce.number().int().positive().parse(req.params.chainId);const address=req.params.address;
  if(!isAddress(address))return res.status(400).json({error:'Invalid token address'});
  const q=z.object({interval:z.enum(['1m','5m','15m','1h','4h','1d']).default('5m'),range:z.enum(['1h','24h','7d','30d','all']).default('24h'),currency:z.enum(['native','USD']).default('native')}).parse(req.query);
  const token=await prisma.token.findUnique({where:{chainId_address:{chainId,address:address.toLowerCase()}},select:{id:true,decimals:true,verified:true}});
  if(!token||!token.verified)return res.status(404).json({error:'Verified token not found'});
  const intervalSeconds:Record<string,number>={ '1m':60,'5m':300,'15m':900,'1h':3600,'4h':14400,'1d':86400 };
  const rangeMs:Record<string,number>={ '1h':3600000,'24h':86400000,'7d':604800000,'30d':2592000000 };
  const since=q.range==='all'?undefined:new Date(Date.now()-rangeMs[q.range]);
  const trades=await prisma.trade.findMany({where:{tokenId:token.id,timestamp:since?{gte:since}:{not:null}},orderBy:[{timestamp:'asc'},{blockNumber:'asc'},{logIndex:'asc'}],take:10_000,select:{timestamp:true,side:true,amountIn:true,amountOut:true}});
  const candles=buildCandles(trades,token.decimals,intervalSeconds[q.interval]);
  if(q.currency==='USD'){
    const cfg=chainConfigs.find(c=>c.id===chainId);
    if(!cfg?.rpc||!cfg.nativeUsdFeed||!isAddress(cfg.nativeUsdFeed))return res.status(422).json({error:'USD charting is unavailable: no verified native/USD feed configured',nativeCandles:candles});
    const quote=await readNativeUsdQuote({chain:evmChain(cfg),rpc:cfg.rpc,feed:cfg.nativeUsdFeed as `0x${string}`,maxAgeSeconds:Number(process.env.ORACLE_MAX_AGE_SECONDS||3600)});
    const usdCandles=convertCandlesToUsd(candles,quote.price);
    return res.json({chainId,address:address.toLowerCase(),interval:q.interval,range:q.range,priceUnit:'USD-per-token',source:'indexed-executions-converted-with-fresh-chainlink-native-usd-round',oracle:quote,complete:trades.length<10_000,tradeCount:trades.length,candles:usdCandles});
  }
  res.json({chainId,address:address.toLowerCase(),interval:q.interval,range:q.range,priceUnit:'native-token',source:'indexed-bonding-curve-and-graduation-discovered-v2-pair-executions',usdPriceAvailable:Boolean(chainConfigs.find(c=>c.id===chainId)?.nativeUsdFeed),complete:trades.length<10_000,tradeCount:trades.length,candles});
}catch(e){next(e)}});

app.get('/v1/tokens/:chainId/:address/trades', async (req,res,next)=>{try{
  const chainId=z.coerce.number().int().positive().parse(req.params.chainId);const address=req.params.address;
  if(!isAddress(address))return res.status(400).json({error:'Invalid token address'});
  const q=z.object({limit:z.coerce.number().int().min(1).max(100).default(30),cursor:z.string().optional()}).parse(req.query);
  const token=await prisma.token.findUnique({where:{chainId_address:{chainId,address:address.toLowerCase()}},select:{id:true,verified:true}});
  if(!token||!token.verified)return res.status(404).json({error:'Verified token not found'});
  const [rows,total]=await Promise.all([prisma.trade.findMany({where:{tokenId:token.id},orderBy:[{blockNumber:'desc'},{logIndex:'desc'}],take:q.limit,...(q.cursor?{skip:1,cursor:{id:q.cursor}}:{})}),prisma.trade.count({where:{tokenId:token.id}})]);
  res.json({items:rows.map(t=>({...t,blockNumber:t.blockNumber.toString()})),nextCursor:rows.length===q.limit?rows.at(-1)?.id:null,total,amountsAreRawBaseUnits:true});
}catch(e){next(e)}});

app.get('/v1/tokens/:chainId/:address', async (req,res,next)=>{try{
  const chainId=z.coerce.number().int().positive().parse(req.params.chainId);const address=req.params.address;
  if(!isAddress(address))return res.status(400).json({error:'Invalid token address'});
  const token=await prisma.token.findUnique({where:{chainId_address:{chainId,address:address.toLowerCase()}},include:{chain:{select:{name:true,slug:true}}}});
  if(!token||!token.verified)return res.status(404).json({error:'Verified token not found'});
  const [transferCount,holders,latestTrades,totalTrades,client]=await Promise.all([
    prisma.transfer.count({where:{tokenId:token.id}}),
    prisma.transfer.findMany({where:{tokenId:token.id},select:{fromAddress:true,toAddress:true},take:20_000,orderBy:{id:'asc'}}),
    prisma.trade.findMany({where:{tokenId:token.id},orderBy:{blockNumber:'desc'},take:20}),
    prisma.trade.count({where:{tokenId:token.id}}),
    Promise.resolve(getReadClient(chainId))
  ]);
  const holderSet=new Set<string>();for(const t of holders){if(t.fromAddress!=='0x0000000000000000000000000000000000000000')holderSet.add(t.fromAddress);if(t.toAddress!=='0x0000000000000000000000000000000000000000')holderSet.add(t.toAddress);}
  let onchainSupply:string|null=null; if(client){try{onchainSupply=(await client.readContract({address:token.address as `0x${string}`,abi:erc20ReadAbi,functionName:'totalSupply'})).toString()}catch{}}
  res.json({token:{id:token.id,chainId,chain:token.chain,name:token.name,symbol:token.symbol,address:token.address,curveAddress:token.curveAddress,decimals:token.decimals,creator:token.creator,totalSupply:token.totalSupply,onchainTotalSupply: onchainSupply,createdAt:token.createdAt,createdBlock:token.createdBlock?.toString()??null},metrics:{indexedTransfers:transferCount,uniqueAddressesObserved:holderSet.size,indexedTrades:totalTrades},trades:latestTrades.map(t=>({...t,blockNumber:t.blockNumber.toString()})),dataQuality:{holderCountIsObservedAddresses:true,holderCountIsNotAuthoritative:true,holderAddressSampleCapped:holders.length===20_000,launchProvenance:'configured_factory_event',verifiedDoesNotMeanSecurityAudited:true,tradeMetricsRequireVerifiedCurveDecoder:latestTrades.length===0}});
}catch(e){next(e)}});

app.get('/v1/portfolio/:address', async (req,res,next) => { try {
  const address = req.params.address;
  if (!isAddress(address)) return res.status(400).json({error:'Invalid EVM address'});
  const wallet=address.toLowerCase();
  const [incomingScan,outgoingScan,trades] = await Promise.all([
    readAllTransfers('toAddress',wallet),
    readAllTransfers('fromAddress',wallet),
    prisma.trade.findMany({where:{trader:wallet},orderBy:{blockNumber:'desc'},take:25,include:{token:{select:{name:true,symbol:true,address:true}},chain:{select:{name:true,slug:true}}}})
  ]);
  const balances=new Map<string,bigint>();
  for(const row of incomingScan.rows){const k=`${row.chainId}:${row.tokenId}`;balances.set(k,(balances.get(k)||0n)+BigInt(row.amount));}
  for(const row of outgoingScan.rows){const k=`${row.chainId}:${row.tokenId}`;balances.set(k,(balances.get(k)||0n)-BigInt(row.amount));}
  const tokenIds=[...new Set([...balances.keys()].map(k=>k.split(':')[1]))];
  const tokenRows=await prisma.token.findMany({where:{id:{in:tokenIds}},include:{chain:{select:{name:true,slug:true}}}});
  const tokenMap=new Map(tokenRows.map(t=>[t.id,t]));
  const candidates=[...balances].map(([key,balance])=>{const [chainId,tokenId]=key.split(':');const token=tokenMap.get(tokenId);return {chainId:Number(chainId),tokenId,token,balanceRaw:balance.toString(),coverageComplete:token?.indexFromBlock!==null&&token?.indexFromBlock!==undefined&&incomingScan.complete&&outgoingScan.complete};}).filter(p=>p.token&&BigInt(p.balanceRaw)>0n).slice(0,100);
  const positions=await Promise.all(candidates.map(async p=>{
    const client=getReadClient(p.chainId);
    let onchainBalanceRaw:string|null=null, reconciliation:'matched'|'mismatch'|'unavailable'='unavailable';
    if(client&&p.token){try{const actual=await client.readContract({address:p.token.address as `0x${string}`,abi:erc20ReadAbi,functionName:'balanceOf',args:[wallet as `0x${string}`]});onchainBalanceRaw=actual.toString();reconciliation=actual.toString()===p.balanceRaw?'matched':'mismatch';}catch{/* Non-standard or unavailable token RPC: retain indexed figure as non-authoritative. */}}
    return {chainId:p.chainId,token:{name:p.token!.name,symbol:p.token!.symbol,address:p.token!.address,decimals:p.token!.decimals,chain:p.token!.chain.name,indexingFromBlock:p.token!.indexFromBlock?.toString()??null},balanceRaw:p.balanceRaw,onchainBalanceRaw,reconciliation,coverageComplete:p.coverageComplete};
  }));
  res.json({address:wallet,source:'indexed-transfers-with-live-balance-reconciliation',valuation:'not_available_without_verified_price_feed',scan:{complete:incomingScan.complete&&outgoingScan.complete,transferScanCap:PORTFOLIO_TRANSFER_SCAN_CAP,incomingTransfersScanned:incomingScan.rows.length,outgoingTransfersScanned:outgoingScan.rows.length},positions,transactions:trades.map(t=>({...t,blockNumber:t.blockNumber.toString()}))});
} catch(e){next(e)} });
app.get('/v1/events/:chainId/:address', async (req,res,next)=>{try{const chainId=z.coerce.number().int().positive().parse(req.params.chainId);const address=req.params.address;if(!isAddress(address))return res.status(400).json({error:'Invalid contract address'});const limit=z.coerce.number().int().min(1).max(100).default(30).parse(req.query.limit??30);const rows=await prisma.indexedEvent.findMany({where:{chainId,address:address.toLowerCase()},orderBy:[{blockNumber:'desc'},{logIndex:'desc'}],take:limit});res.json(rows.map(row=>({...row,blockNumber:row.blockNumber.toString()})));}catch(e){next(e)}});
app.get('/v1/transactions/:address', async (req,res,next)=>{try{const a=req.params.address;if(!isAddress(a))return res.status(400).json({error:'Invalid EVM address'});const rows=await prisma.trade.findMany({where:{trader:a.toLowerCase()},orderBy:{blockNumber:'desc'},take:100,include:{token:{select:{name:true,symbol:true,address:true}},chain:{select:{name:true,slug:true}}}});res.json(rows.map(t=>({...t,blockNumber:t.blockNumber.toString()})));}catch(e){next(e)}});
app.use((err:any,_req:express.Request,res:express.Response,_next:express.NextFunction)=>{const status=err instanceof z.ZodError?400:500;res.status(status).json({error:status===400?'Invalid request':'Internal server error',...(process.env.NODE_ENV==='development'?{detail:err.message}:{})});});
app.listen(config.port,()=>console.log(`UNIRAE API listening on :${config.port}`));
