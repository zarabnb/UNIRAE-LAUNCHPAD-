export type NormalizedFeeEvent = {
  tokenAddress: string;
  actor: string | null;
  eventName: 'FeeDeposited' | 'CreatorClaimed' | 'PlatformClaimed' | 'BuybackExecuted';
  amount: string;
  creatorAmount: string;
  buybackAmount: string;
  platformAmount: string;
  payload: Record<string, string | boolean | null>;
};

export function normalizeFeeEvent(eventName: string, args: Record<string, unknown>): NormalizedFeeEvent | null {
  const names = ['FeeDeposited','CreatorClaimed','PlatformClaimed','BuybackExecuted'] as const;
  if (!names.includes(eventName as typeof names[number])) return null;
  const token = args.token;
  if (typeof token !== 'string' || !/^0x[0-9a-fA-F]{40}$/.test(token)) throw new Error('Invalid fee event token address');
  const asAmount = (value: unknown, key: string): string => {
    if (typeof value === 'bigint' && value >= 0n) return value.toString();
    if (typeof value === 'string' && /^\d+$/.test(value)) return BigInt(value).toString();
    throw new Error(`Invalid ${key} in ${eventName}`);
  };
  const amountValue = eventName === 'BuybackExecuted' ? args.nativeAmount : args.amount;
  const actor = args.creator;
  if (actor !== undefined && (typeof actor !== 'string' || !/^0x[0-9a-fA-F]{40}$/.test(actor))) throw new Error(`Invalid actor in ${eventName}`);
  const safePayload: Record<string, string | boolean | null> = {};
  for (const [key,value] of Object.entries(args)) {
    if (typeof value === 'bigint') safePayload[key] = value.toString();
    else if (typeof value === 'string' || typeof value === 'boolean' || value === null) safePayload[key] = value;
    else safePayload[key] = null;
  }
  return {
    tokenAddress: token.toLowerCase(),
    actor: typeof actor === 'string' ? actor.toLowerCase() : null,
    eventName: eventName as NormalizedFeeEvent['eventName'],
    amount: asAmount(amountValue,'amount'),
    creatorAmount: eventName === 'FeeDeposited' ? asAmount(args.creatorAmount,'creatorAmount') : '0',
    buybackAmount: eventName === 'FeeDeposited' ? asAmount(args.buybackAmount,'buybackAmount') : '0',
    platformAmount: eventName === 'FeeDeposited' ? asAmount(args.platformAmount,'platformAmount') : '0',
    payload: safePayload
  };
}
