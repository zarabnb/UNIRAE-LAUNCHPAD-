import { describe, expect, it } from 'vitest';
import { buildCandles } from './candles.js';
const W=10n**18n;
describe('buildCandles',()=>{
 it('aggregates buy and sell fills into chronological OHLC candles',()=>{
  const rows=[
   {timestamp:new Date('2026-01-01T00:00:05Z'),side:'BUY',amountIn:(2n*W).toString(),amountOut:(4n*W).toString()},
   {timestamp:new Date('2026-01-01T00:00:20Z'),side:'SELL',amountIn:(2n*W).toString(),amountOut:(2n*W).toString()},
   {timestamp:new Date('2026-01-01T00:01:05Z'),side:'BUY',amountIn:(3n*W).toString(),amountOut:(3n*W).toString()}
  ];
  const c=buildCandles(rows,18,60);expect(c).toHaveLength(2);expect(c[0]).toMatchObject({open:0.5,high:1,low:0.5,close:1,trades:2});expect(c[1].close).toBe(1);
 });
 it('ignores null/invalid timestamps and zero-size fills',()=>{
  const c=buildCandles([{timestamp:null,side:'BUY',amountIn:W.toString(),amountOut:W.toString()},{timestamp:'bad',side:'BUY',amountIn:W.toString(),amountOut:W.toString()},{timestamp:new Date(),side:'BUY',amountIn:'0',amountOut:'1'},{timestamp:new Date(),side:'UNKNOWN',amountIn:W.toString(),amountOut:W.toString()}],18,60);expect(c).toEqual([]);
 });
 it('handles very large base-unit amounts without overflowing intermediate BigInts',()=>{
  const huge=(10n**50n).toString();
  const c=buildCandles([{timestamp:'2026-01-01T00:00:01Z',side:'BUY',amountIn:huge,amountOut:(2n*10n**50n).toString()}],18,60);
  expect(c).toHaveLength(1);expect(c[0].close).toBeCloseTo(0.5);expect(Number.isFinite(c[0].volumeNative)).toBe(true);
 });
 it('orders fills by timestamp before calculating open and close',()=>{
  const c=buildCandles([
   {timestamp:'2026-01-01T00:00:30Z',side:'BUY',amountIn:W.toString(),amountOut:W.toString()},
   {timestamp:'2026-01-01T00:00:10Z',side:'BUY',amountIn:W.toString(),amountOut:(2n*W).toString()}
  ],18,60);expect(c[0].open).toBe(0.5);expect(c[0].close).toBe(1);
 });
 it('rejects invalid decimal and interval configuration',()=>{expect(()=>buildCandles([],37,60)).toThrow();expect(()=>buildCandles([],18,0)).toThrow()});
});
