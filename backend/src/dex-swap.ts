export type V2SwapAmounts = { amount0In: bigint; amount1In: bigint; amount0Out: bigint; amount1Out: bigint };
export type NormalizedSwap = { side: 'BUY'|'SELL'; amountIn: string; amountOut: string } | null;

/** Normalize a V2 pair event into the same quote/token convention as curve fills. */
export function normalizeV2Swap(a: V2SwapAmounts, tokenIs0: boolean): NormalizedSwap {
  const tokenIn=tokenIs0?a.amount0In:a.amount1In;
  const tokenOut=tokenIs0?a.amount0Out:a.amount1Out;
  const quoteIn=tokenIs0?a.amount1In:a.amount0In;
  const quoteOut=tokenIs0?a.amount1Out:a.amount0Out;
  if(tokenOut>0n&&quoteIn>0n)return {side:'BUY',amountIn:quoteIn.toString(),amountOut:tokenOut.toString()};
  if(tokenIn>0n&&quoteOut>0n)return {side:'SELL',amountIn:tokenIn.toString(),amountOut:quoteOut.toString()};
  return null;
}


export type V3SwapAmounts = { amount0: bigint; amount1: bigint };

/** Normalize a Uniswap V3 signed-delta Swap event into quote/token amounts.
 * Positive deltas are paid into the pool; negative deltas are received from it.
 */
export function normalizeV3Swap(a: V3SwapAmounts, tokenIs0: boolean): NormalizedSwap {
  const tokenDelta = tokenIs0 ? a.amount0 : a.amount1;
  const quoteDelta = tokenIs0 ? a.amount1 : a.amount0;
  if (quoteDelta > 0n && tokenDelta < 0n) {
    return { side: 'BUY', amountIn: quoteDelta.toString(), amountOut: (-tokenDelta).toString() };
  }
  if (tokenDelta > 0n && quoteDelta < 0n) {
    return { side: 'SELL', amountIn: tokenDelta.toString(), amountOut: (-quoteDelta).toString() };
  }
  return null;
}
