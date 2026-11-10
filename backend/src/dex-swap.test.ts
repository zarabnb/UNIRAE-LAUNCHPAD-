import { describe,it,expect } from 'vitest';
import { normalizeV2Swap, normalizeV3Swap } from './dex-swap.js';

describe('normalizeV2Swap',()=>{
  it('normalizes a buy when the UNIRAE token is token0',()=>{
    expect(normalizeV2Swap({amount0In:0n,amount1In:10n,amount0Out:100n,amount1Out:0n},true)).toEqual({side:'BUY',amountIn:'10',amountOut:'100'});
  });
  it('normalizes a buy when the UNIRAE token is token1',()=>{
    expect(normalizeV2Swap({amount0In:8n,amount1In:0n,amount0Out:0n,amount1Out:90n},false)).toEqual({side:'BUY',amountIn:'8',amountOut:'90'});
  });
  it('ignores swaps that do not exchange configured token and quote asset',()=>{
    expect(normalizeV2Swap({amount0In:0n,amount1In:0n,amount0Out:0n,amount1Out:0n},true)).toBeNull();
  });
});


describe('normalizeV3Swap',()=>{
  it('normalizes a buy when the UNIRAE token is token0',()=>{
    expect(normalizeV3Swap({amount0:-100n,amount1:12n},true)).toEqual({side:'BUY',amountIn:'12',amountOut:'100'});
  });
  it('normalizes a sell when the UNIRAE token is token1',()=>{
    expect(normalizeV3Swap({amount0:-9n,amount1:75n},false)).toEqual({side:'SELL',amountIn:'75',amountOut:'9'});
  });
  it('ignores zero or same-direction deltas',()=>{
    expect(normalizeV3Swap({amount0:0n,amount1:0n},true)).toBeNull();
    expect(normalizeV3Swap({amount0:10n,amount1:5n},true)).toBeNull();
  });
});
