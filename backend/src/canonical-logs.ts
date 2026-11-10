/**
 * Filter RPC logs against canonical block headers before persisting them.
 * Providers can return logs from a branch that was reorganized while a range
 * query was in flight. Fetch each distinct header once and retain only exact
 * block-hash matches. This is a guard against stale RPC results, not a full
 * finality guarantee; configure an appropriate confirmation depth as well.
 */
type CanonicalMetadata = { blockNumber?: bigint | null; blockHash?: `0x${string}` | null };
export async function keepCanonicalLogs<T>(
  client: { getBlock(args: { blockNumber: bigint }): Promise<{ hash: `0x${string}` }> },
  logs: readonly T[],
): Promise<T[]> {
  const numbers = [...new Set(logs.flatMap(raw => {
    const log = raw as T & CanonicalMetadata;
    return log.blockNumber == null ? [] : [log.blockNumber];
  }))];
  const headers = new Map<bigint, `0x${string}`>();
  await Promise.all(numbers.map(async number => {
    const block = await client.getBlock({ blockNumber: number });
    headers.set(number, block.hash.toLowerCase() as `0x${string}`);
  }));
  return logs.filter(raw => {
    const log = raw as T & CanonicalMetadata;
    if (log.blockNumber == null || !log.blockHash) return false;
    return headers.get(log.blockNumber) === log.blockHash.toLowerCase();
  });
}
