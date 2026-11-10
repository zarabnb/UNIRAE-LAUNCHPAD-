/**
 * Compute a one-block rollback window for a cursor whose stored tip hash no
 * longer matches canonical chain data. Replay begins one block before the tip.
 * The caller must delete all indexed data at/after replayFrom before advancing.
 */
export function reorgReplayWindow(lastBlock: bigint): { replayFrom: bigint; cursorBlock: bigint } {
  if (lastBlock < 0n) throw new Error('lastBlock cannot be negative');
  const replayFrom = lastBlock > 1n ? lastBlock - 1n : 0n;
  const cursorBlock = replayFrom > 0n ? replayFrom - 1n : 0n;
  return { replayFrom, cursorBlock };
}
