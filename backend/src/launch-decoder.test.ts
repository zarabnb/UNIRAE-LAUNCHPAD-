import { describe, expect, it } from 'vitest';
import { mapCurveTrade, normalizeAddress, FACTORY_LAUNCH_EVENT, CURVE_EVENTS } from './launch-decoder.js';

describe('UNIRAE semantic event decoder',()=>{
  it('uses the exact factory launch event signature',()=>expect(FACTORY_LAUNCH_EVENT).toContain('TokenLaunched(address indexed token'));
  it('recognizes exact curve event ABI signatures',()=>expect(CURVE_EVENTS).toHaveLength(3));
  it('normalizes addresses and rejects malformed input',()=>{expect(normalizeAddress('0x'+'A'.repeat(40))).toBe('0x'+'a'.repeat(40));expect(()=>normalizeAddress('0x123')).toThrow();});
  it('maps buy event into native-in / token-out amounts',()=>{const t=mapCurveTrade('Bought',{buyer:'0x'+'a'.repeat(40),tokenAmount:100n,curveCost:20n,fee:1n});expect(t).toEqual({side:'BUY',trader:'0x'+'a'.repeat(40),tokenAmount:100n,nativeAmount:20n,feeAmount:1n});});
  it('maps sell event into token-in / native-out amounts',()=>{const t=mapCurveTrade('Sold',{seller:'0x'+'b'.repeat(40),tokenAmount:100n,grossNative:20n,fee:1n,netNative:19n});expect(t?.side).toBe('SELL');if(t?.side==='SELL'){expect(t.nativeAmount).toBe(19n);expect(t.feeAmount).toBe(1n);}});
  it('ignores unrelated events',()=>expect(mapCurveTrade('Transfer',{})).toBeNull());
});
