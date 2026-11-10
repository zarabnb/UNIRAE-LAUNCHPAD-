import { createPublicClient, http, parseAbi, type Address, type Chain } from 'viem';

const feedAbi = parseAbi([
  'function decimals() view returns (uint8)',
  'function latestRoundData() view returns (uint80 roundId,int256 answer,uint256 startedAt,uint256 updatedAt,uint80 answeredInRound)'
]);

export type NativeUsdQuote = { price: number; updatedAt: number; decimals: number; roundId: string };

export function normalizeOracleRound(input: { roundId: bigint; answer: bigint; updatedAt: bigint; answeredInRound: bigint }, decimals: number, nowSeconds: number, maxAgeSeconds: number): NativeUsdQuote {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 18) throw new Error('Invalid oracle decimals');
  if (input.roundId <= 0n || input.answeredInRound < input.roundId) throw new Error('Incomplete oracle round');
  if (input.answer <= 0n) throw new Error('Oracle answer must be positive');
  const updatedAt = Number(input.updatedAt);
  if (!Number.isSafeInteger(updatedAt) || updatedAt <= 0 || updatedAt > nowSeconds + 30 || nowSeconds - updatedAt > maxAgeSeconds) throw new Error('Oracle price is stale or has an invalid timestamp');
  const price = Number(input.answer) / (10 ** decimals);
  if (!Number.isFinite(price) || price <= 0) throw new Error('Oracle price is outside supported numeric range');
  return { price, updatedAt, decimals, roundId: input.roundId.toString() };
}

export async function readNativeUsdQuote(args: { chain: Chain; rpc: string; feed: Address; maxAgeSeconds: number }): Promise<NativeUsdQuote> {
  const client = createPublicClient({ chain: args.chain, transport: http(args.rpc, { timeout: 12_000, retryCount: 1 }) });
  const [decimals, round] = await Promise.all([
    client.readContract({ address: args.feed, abi: feedAbi, functionName: 'decimals' }),
    client.readContract({ address: args.feed, abi: feedAbi, functionName: 'latestRoundData' })
  ]);
  return normalizeOracleRound({ roundId: round[0], answer: round[1], updatedAt: round[3], answeredInRound: round[4] }, Number(decimals), Math.floor(Date.now() / 1000), args.maxAgeSeconds);
}

export function convertCandlesToUsd<T extends { open:number; high:number; low:number; close:number; volumeNative:number }>(candles:T[], nativeUsd:number): (T & { volumeUsd:number })[] {
  if (!Number.isFinite(nativeUsd) || nativeUsd <= 0) throw new Error('Invalid native/USD conversion rate');
  return candles.map(c => ({ ...c, open:c.open*nativeUsd, high:c.high*nativeUsd, low:c.low*nativeUsd, close:c.close*nativeUsd, volumeUsd:c.volumeNative*nativeUsd }));
}
