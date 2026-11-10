import { describe, expect, it } from 'vitest';
import { hashAuthMessage, matchesAuthMessage, isAllowedAuthDomain } from './auth-challenge.js';

describe('wallet challenge binding', () => {
  const message = 'unirae.example wants you to sign in\nNonce: 0123456789abcdef0123456789abcdef';
  it('accepts the exact issued message', () => expect(matchesAuthMessage(message, hashAuthMessage(message))).toBe(true));
  it('rejects edits to any signed field', () => expect(matchesAuthMessage(message + '\nChain ID: 56', hashAuthMessage(message))).toBe(false));
  it('rejects malformed and legacy hashes', () => {
    expect(matchesAuthMessage(message, 'legacy-unbound')).toBe(false);
    expect(matchesAuthMessage(message, 'a'.repeat(63))).toBe(false);
  });
  it('requires an exact allowlisted host and rejects URL injection', () => {
    expect(isAllowedAuthDomain('app.unirae.example', ['https://app.unirae.example'])).toBe(true);
    expect(isAllowedAuthDomain('app.unirae.example.evil.test', ['https://app.unirae.example'])).toBe(false);
    expect(isAllowedAuthDomain('app.unirae.example/path', ['https://app.unirae.example'])).toBe(false);
    expect(isAllowedAuthDomain('evil.test@app.unirae.example', ['https://app.unirae.example'])).toBe(false);
  });
});
