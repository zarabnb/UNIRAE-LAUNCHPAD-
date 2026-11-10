import { beforeEach, describe, expect, it } from 'vitest';
import { signSession, verifySession } from './wallet-session.js';

describe('wallet bearer sessions',()=>{
 beforeEach(()=>{process.env.SESSION_SECRET='test-only-secret-that-is-at-least-32-characters-long';});
 const session={sub:'0x'+'1'.repeat(40),domain:'unirae.example',chainId:97,exp:2_000_000_000};
 it('signs and verifies an unexpired wallet session',()=>expect(verifySession(signSession(session),1_900_000_000)).toEqual(session));
 it('rejects tampered payloads',()=>{const t=signSession(session).split('.');t[0]=Buffer.from(JSON.stringify({...session,sub:'0x'+'2'.repeat(40)})).toString('base64url');expect(verifySession(t.join('.'),1_900_000_000)).toBeNull();});
 it('rejects expired sessions',()=>expect(verifySession(signSession(session),2_000_000_000)).toBeNull());
 it('rejects sessions without a valid chain binding',()=>{const t=signSession({...session,chainId:0});expect(verifySession(t,1_900_000_000)).toBeNull();});
 it('rejects malformed tokens',()=>expect(verifySession('bad.token.extra')).toBeNull());
 it('fails closed without a strong secret',()=>{process.env.SESSION_SECRET='short';expect(()=>signSession(session)).toThrow();expect(verifySession('x.y')).toBeNull();});
});
