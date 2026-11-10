import type { Address, Hex } from 'viem';

export type LaunchEvent = { token: Address; curve: Address; creator: Address; name: string; symbol: string; supply: bigint };
export type CurveTradeEvent =
  | { side: 'BUY'; trader: Address; tokenAmount: bigint; nativeAmount: bigint; feeAmount: bigint }
  | { side: 'SELL'; trader: Address; tokenAmount: bigint; nativeAmount: bigint; feeAmount: bigint };

export function normalizeAddress(value: string): string {
  if (!/^0x[0-9a-fA-F]{40}$/.test(value)) throw new Error('Invalid EVM address');
  return value.toLowerCase();
}

export function mapCurveTrade(eventName: string, args: Record<string, unknown>): CurveTradeEvent | null {
  const asBigInt = (v: unknown, key: string) => {
    if (typeof v === 'bigint') return v;
    if (typeof v === 'string' && /^\d+$/.test(v)) return BigInt(v);
    throw new Error(`Invalid ${key} in ${eventName}`);
  };
  const trader = args.buyer ?? args.seller;
  if (typeof trader !== 'string') return null;
  if (eventName === 'Bought') return { side: 'BUY', trader: trader as Address, tokenAmount: asBigInt(args.tokenAmount,'tokenAmount'), nativeAmount: asBigInt(args.curveCost,'curveCost'), feeAmount: asBigInt(args.fee,'fee') };
  if (eventName === 'Sold') return { side: 'SELL', trader: trader as Address, tokenAmount: asBigInt(args.tokenAmount,'tokenAmount'), nativeAmount: asBigInt(args.netNative,'netNative'), feeAmount: asBigInt(args.fee,'fee') };
  return null;
}

export const FACTORY_LAUNCH_EVENT = 'event TokenLaunched(address indexed token, address indexed curve, address indexed creator, string name, string symbol, uint256 supply)';
export const CURVE_EVENTS = [
  'event Bought(address indexed buyer, uint256 tokenAmount, uint256 curveCost, uint256 fee)',
  'event Sold(address indexed seller, uint256 tokenAmount, uint256 grossNative, uint256 fee, uint256 netNative)',
  'event GraduationMigrated(address indexed coordinator, uint256 nativeAmount, uint256 tokenAmount)'
] as const;
