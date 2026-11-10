import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Request, Response, NextFunction } from 'express';

export type WalletSession = { sub: string; exp: number; domain: string; chainId: number };
const secret = () => process.env.SESSION_SECRET || '';
export function signSession(session: WalletSession): string {
  if (secret().length < 32) throw new Error('SESSION_SECRET must be at least 32 characters');
  const payload = Buffer.from(JSON.stringify(session)).toString('base64url');
  const signature = createHmac('sha256', secret()).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}
export function verifySession(token: string, nowSeconds = Math.floor(Date.now()/1000)): WalletSession | null {
  if (secret().length < 32 || token.length > 4096) return null;
  const parts = token.split('.'); if (parts.length !== 2) return null;
  const [payload, supplied] = parts;
  const expected = createHmac('sha256', secret()).update(payload).digest();
  let actual: Buffer; try { actual = Buffer.from(supplied, 'base64url'); } catch { return null; }
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return null;
  try {
    const value = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as WalletSession;
    if (!value || typeof value.sub !== 'string' || !/^0x[0-9a-f]{40}$/.test(value.sub) ||
        typeof value.domain !== 'string' || !Number.isSafeInteger(value.chainId) || value.chainId <= 0 || !Number.isSafeInteger(value.exp) || value.exp <= nowSeconds) return null;
    return value;
  } catch { return null; }
}
declare global { namespace Express { interface Request { walletSession?: WalletSession } } }
export function requireWalletSession(req: Request, res: Response, next: NextFunction) {
  const header = req.header('authorization') || '';
  if (!header.startsWith('Bearer ')) return res.status(401).json({error:'Wallet session required'});
  const session = verifySession(header.slice(7));
  if (!session) return res.status(401).json({error:'Wallet session invalid or expired'});
  req.walletSession = session; next();
}
