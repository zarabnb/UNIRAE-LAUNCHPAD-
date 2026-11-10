import { describe, expect, it } from 'vitest';
import { reorgReplayWindow } from './reorg-window.js';

describe('reorg replay window', () => {
  it('replays from genesis for a cursor at block zero', () => {
    expect(reorgReplayWindow(0n)).toEqual({ replayFrom: 0n, cursorBlock: 0n });
  });
  it('replays from genesis for a cursor at block one', () => {
    expect(reorgReplayWindow(1n)).toEqual({ replayFrom: 0n, cursorBlock: 0n });
  });
  it('rewinds two blocks of cursor position to replay the previous tip block', () => {
    expect(reorgReplayWindow(2n)).toEqual({ replayFrom: 1n, cursorBlock: 0n });
  });
  it('replays the previous block and resets cursor immediately before it', () => {
    expect(reorgReplayWindow(100n)).toEqual({ replayFrom: 99n, cursorBlock: 98n });
  });
  it('rejects negative block numbers', () => {
    expect(() => reorgReplayWindow(-1n)).toThrow('lastBlock cannot be negative');
  });
});
