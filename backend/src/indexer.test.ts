import { describe,it,expect } from 'vitest';
import { isAddress } from 'viem';
describe('address input validation',()=>{
  it('accepts a valid EVM address',()=>expect(isAddress('0x0000000000000000000000000000000000000001')).toBe(true));
  it('rejects malformed address strings',()=>expect(isAddress('not-a-wallet')).toBe(false));
});
