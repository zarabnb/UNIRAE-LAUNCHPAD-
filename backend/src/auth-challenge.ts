import { createHash, timingSafeEqual } from 'node:crypto';

export function hashAuthMessage(message: string): string {
  return createHash('sha256').update(message, 'utf8').digest('hex');
}

/** Exact byte-for-byte challenge binding; never accept a caller-reconstructed SIWE-like message. */
export function matchesAuthMessage(message: string, expectedHash: string): boolean {
  if (!/^[0-9a-f]{64}$/.test(expectedHash)) return false;
  const actual = Buffer.from(hashAuthMessage(message), 'hex');
  const expected = Buffer.from(expectedHash, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function isAllowedAuthDomain(domain: string, allowedOrigins: string[]): boolean {
  if (domain.length > 255 || domain.includes('/') || domain.includes('\\') || /[\s\r\n@]/.test(domain)) return false;
  const normalized = domain.toLowerCase();
  return allowedOrigins.some(origin => {
    try {
      const parsed = new URL(origin);
      return (parsed.protocol === 'https:' || parsed.hostname === 'localhost') && parsed.host.toLowerCase() === normalized;
    } catch { return false; }
  });
}
