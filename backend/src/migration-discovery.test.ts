import { describe, it, expect } from 'vitest';
import { migrationCoordinatorMatches, quoteAssetFromPair } from './migration-discovery.js';
const token='0x2222222222222222222222222222222222222222';
const quote='0x4444444444444444444444444444444444444444';
const coordinator='0x3333333333333333333333333333333333333333';
describe('graduation migration discovery',()=>{
  it('requires the emitted coordinator to match the configured nonzero coordinator',()=>{
    expect(migrationCoordinatorMatches(coordinator,coordinator)).toBe(true);
    expect(migrationCoordinatorMatches(coordinator,quote)).toBe(false);
    expect(migrationCoordinatorMatches('0x0000000000000000000000000000000000000000','0x0000000000000000000000000000000000000000')).toBe(false);
  });
  it('accepts only a pair containing the registered token and returns its quote asset',()=>{
    expect(quoteAssetFromPair(token,token,quote)).toBe(quote);
    expect(quoteAssetFromPair(token,quote,token)).toBe(quote);
    expect(quoteAssetFromPair(token,quote,coordinator)).toBeNull();
    expect(quoteAssetFromPair(token,token,token)).toBeNull();
  });
});
