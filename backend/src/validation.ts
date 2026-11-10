import { isAddress } from 'viem';

export function normalizeAddress(value: unknown): `0x${string}` {
  if (typeof value !== 'string' || !isAddress(value)) throw new Error('Invalid EVM address');
  return value.toLowerCase() as `0x${string}`;
}
export function safeLimit(value: unknown, fallback = 30, max = 100): number {
  const n = Number(value ?? fallback);
  if (!Number.isInteger(n) || n < 1 || n > max) throw new Error(`limit must be an integer from 1 to ${max}`);
  return n;
}
export function toJsonSafe(value: any): any {
  if (typeof value === 'bigint') return value.toString();
  if (Array.isArray(value)) return value.map(toJsonSafe);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,toJsonSafe(v)]));
  return value;
}
