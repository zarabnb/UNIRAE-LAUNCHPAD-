import { describe, expect, it } from 'vitest';
import { convertCandlesToUsd, normalizeOracleRound } from './oracle.js';

describe('native USD oracle validation',()=>{
  const base={roundId:10n,answer:6500000000000n,updatedAt:1_000n,answeredInRound:10n};
  it('normalizes a valid feed round',()=>expect(normalizeOracleRound(base,8,1_100,300).price).toBe(65000));
  it('rejects stale data',()=>expect(()=>normalizeOracleRound(base,8,2_000,300)).toThrow(/stale/));
  it('rejects incomplete rounds',()=>expect(()=>normalizeOracleRound({...base,answeredInRound:9n},8,1_100,300)).toThrow(/Incomplete/));
  it('rejects non-positive answers',()=>expect(()=>normalizeOracleRound({...base,answer:0n},8,1_100,300)).toThrow(/positive/));
  it('converts OHLC and volume without mutating native source',()=>{
    const source=[{time:1,open:2,high:3,low:1,close:2.5,volumeNative:4,trades:2}];
    const result=convertCandlesToUsd(source,100);
    expect(result[0]).toMatchObject({open:200,high:300,low:100,close:250,volumeUsd:400});
    expect(source[0].close).toBe(2.5);
  });
});
