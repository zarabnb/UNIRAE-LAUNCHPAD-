import { describe, expect, it, vi } from 'vitest';
import { keepCanonicalLogs } from './canonical-logs.js';

const A = `0x${'a'.repeat(64)}` as const;
const B = `0x${'b'.repeat(64)}` as const;

describe('canonical log filtering', () => {
  it('drops logs whose block hash is no longer canonical', async () => {
    const client = { getBlock: vi.fn(async ({ blockNumber }: { blockNumber: bigint }) => ({ hash: blockNumber === 10n ? A : B })) };
    const logs: Array<{ blockNumber?: bigint | null; blockHash?: `0x${string}` | null; id: string }> = [
      { blockNumber: 10n, blockHash: A, id: 'canonical' },
      { blockNumber: 10n, blockHash: B, id: 'orphaned' },
      { blockNumber: 11n, blockHash: B, id: 'next' },
    ];
    await expect(keepCanonicalLogs(client, logs)).resolves.toEqual([logs[0], logs[2]]);
    expect(client.getBlock).toHaveBeenCalledTimes(2);
  });

  it('drops incomplete logs without block metadata', async () => {
    const client = { getBlock: vi.fn(async () => ({ hash: A })) };
    await expect(keepCanonicalLogs(client, [{ id: 'missing' }])).resolves.toEqual([]);
    expect(client.getBlock).not.toHaveBeenCalled();
  });
});
