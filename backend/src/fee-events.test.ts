import { describe, expect, it } from 'vitest';
import { normalizeFeeEvent } from './fee-events.js';
const TOKEN='0x0000000000000000000000000000000000000001';
const CREATOR='0x0000000000000000000000000000000000000002';
describe('fee vault event normalization',()=>{
  it('normalizes deposits and all allocation amounts',()=>{
    const result=normalizeFeeEvent('FeeDeposited',{token:TOKEN,creator:CREATOR,amount:1000n,creatorAmount:400n,buybackAmount:200n,platformAmount:400n});
    expect(result).toMatchObject({tokenAddress:TOKEN,actor:CREATOR,eventName:'FeeDeposited',amount:'1000',creatorAmount:'400',buybackAmount:'200',platformAmount:'400'});
  });
  it('normalizes creator and platform claims',()=>{
    expect(normalizeFeeEvent('CreatorClaimed',{token:TOKEN,creator:CREATOR,amount:50n})?.amount).toBe('50');
    expect(normalizeFeeEvent('PlatformClaimed',{token:TOKEN,amount:25n})?.amount).toBe('25');
  });
  it('normalizes buyback native amount',()=>{
    expect(normalizeFeeEvent('BuybackExecuted',{token:TOKEN,nativeAmount:75n,minTokensOut:3n})?.amount).toBe('75');
  });
  it('rejects malformed token addresses and negative amounts',()=>{
    expect(()=>normalizeFeeEvent('FeeDeposited',{token:'bad',amount:1n,creatorAmount:0n,buybackAmount:0n,platformAmount:1n})).toThrow();
    expect(()=>normalizeFeeEvent('PlatformClaimed',{token:TOKEN,amount:-1n})).toThrow();
  });
  it('ignores unknown event names',()=>expect(normalizeFeeEvent('Unknown',{token:TOKEN})).toBeNull());
});
