export type CandleTrade = { timestamp: Date | string | null; side: string; amountIn: string; amountOut: string };
export type Candle = { time: number; open: number; high: number; low: number; close: number; volumeNative: number; trades: number };

/** Convert an unsigned base-unit integer to a finite JS number without first
 * coercing the full BigInt (which can overflow for high-supply tokens). */
function scaledBigInt(value: bigint, decimals: number): number {
  if (value <= 0n) return 0;
  const digits = value.toString();
  const significant = digits.slice(0, 16);
  const mantissa = Number(significant) / (10 ** (significant.length - 1));
  const exponent = digits.length - 1 - decimals;
  return mantissa * (10 ** exponent);
}

/** Compute (numerator / 10^numeratorDecimals) /
 * (denominator / 10^denominatorDecimals) without overflowing either operand. */
function tokenPrice(nativeRaw: bigint, tokenRaw: bigint, tokenDecimals: number): number {
  const n = nativeRaw.toString();
  const t = tokenRaw.toString();
  const ns = n.slice(0, 16), ts = t.slice(0, 16);
  const nm = Number(ns) / (10 ** (ns.length - 1));
  const tm = Number(ts) / (10 ** (ts.length - 1));
  const exponent = (n.length - 1) - (t.length - 1) + tokenDecimals - 18;
  return (nm / tm) * (10 ** exponent);
}

/** Build native-asset-denominated OHLC candles from indexed bonding-curve fills.
 * BUY: amountIn=native, amountOut=token. SELL: amountIn=token, amountOut=native.
 * This is execution-derived price, not an oracle USD price or an AMM spot price.
 */
export function buildCandles(rows: CandleTrade[], tokenDecimals: number, bucketSeconds: number): Candle[] {
  if (!Number.isInteger(tokenDecimals) || tokenDecimals < 0 || tokenDecimals > 36) throw new Error('Invalid token decimals');
  if (!Number.isInteger(bucketSeconds) || bucketSeconds <= 0) throw new Error('Invalid candle interval');
  const buckets = new Map<number, Candle>();
  const ordered = rows.map((row, index) => ({ row, index, ms: row.timestamp ? new Date(row.timestamp).getTime() : NaN }))
    .filter(item => Number.isFinite(item.ms)).sort((a, b) => a.ms - b.ms || a.index - b.index);
  for (const { row, ms } of ordered) {
    if (row.side !== 'BUY' && row.side !== 'SELL') continue;
    let tokenRaw: bigint, nativeRaw: bigint;
    try {
      tokenRaw = BigInt(row.side === 'BUY' ? row.amountOut : row.amountIn);
      nativeRaw = BigInt(row.side === 'BUY' ? row.amountIn : row.amountOut);
    } catch { continue; }
    if (tokenRaw <= 0n || nativeRaw <= 0n) continue;
    const nativeQty = scaledBigInt(nativeRaw, 18);
    const price = tokenPrice(nativeRaw, tokenRaw, tokenDecimals);
    if (!Number.isFinite(price) || price <= 0 || !Number.isFinite(nativeQty)) continue;
    const time = Math.floor(Math.floor(ms / 1000) / bucketSeconds) * bucketSeconds;
    const candle = buckets.get(time);
    if (!candle) buckets.set(time, { time, open: price, high: price, low: price, close: price, volumeNative: nativeQty, trades: 1 });
    else { candle.high = Math.max(candle.high, price); candle.low = Math.min(candle.low, price); candle.close = price; candle.volumeNative += nativeQty; candle.trades++; }
  }
  return [...buckets.values()].sort((a,b)=>a.time-b.time);
}
