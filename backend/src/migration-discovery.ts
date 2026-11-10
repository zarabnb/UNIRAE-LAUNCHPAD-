/** Pure validation helpers for discovering a pool from a confirmed graduation receipt. */
export function migrationCoordinatorMatches(emitted: string, configured: string): boolean {
  const a = emitted.toLowerCase();
  const b = configured.toLowerCase();
  return /^0x[0-9a-f]{40}$/.test(a) && /^0x[0-9a-f]{40}$/.test(b) && !/^0x0{40}$/.test(b) && a === b;
}

export function quoteAssetFromPair(tokenAddress: string, token0: string, token1: string): string | null {
  const token = tokenAddress.toLowerCase();
  const a = token0.toLowerCase();
  const b = token1.toLowerCase();
  if (!/^0x[0-9a-f]{40}$/.test(token) || !/^0x[0-9a-f]{40}$/.test(a) || !/^0x[0-9a-f]{40}$/.test(b)) return null;
  if (a === token && b !== token) return b;
  if (b === token && a !== token) return a;
  return null;
}
