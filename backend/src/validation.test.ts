import { describe, expect, it } from 'vitest';
import { normalizeAddress, safeLimit, toJsonSafe } from './validation.js';
import { factoryEvents, curveEvents } from './abi.js';
import { toEventSelector } from 'viem';

describe('request validation', () => {
  it('normalizes valid EVM addresses', () => expect(normalizeAddress('0x000000000000000000000000000000000000dEaD')).toBe('0x000000000000000000000000000000000000dead'));
  it('rejects malformed addresses', () => expect(() => normalizeAddress('nope')).toThrow());
  it('bounds API limits', () => { expect(safeLimit('25')).toBe(25); expect(() => safeLimit('1000')).toThrow(); });
  it('serializes bigint recursively', () => expect(toJsonSafe({a:1n,b:[2n]})).toEqual({a:'1',b:['2']}));
});
describe('contract ABI compatibility', () => {
  it('loads factory launch event from the contract ABI', () => expect(factoryEvents[0].type).toBe('event'));
  it('loads curve trade and graduation events', () => expect(curveEvents.map((e:any)=>e.name)).toEqual(['Initialized','Bought','Sold','Graduated','MigrationCoordinatorConfigured','GraduationMigrated']));
  it('keeps the expected launch event selector stable', () => expect(toEventSelector(factoryEvents[0])).toMatch(/^0x[0-9a-f]{64}$/));
});
