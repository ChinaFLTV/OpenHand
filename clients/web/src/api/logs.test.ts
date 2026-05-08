import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  apiRequest: vi.fn(),
}));

vi.mock('./client', () => ({
  apiRequest: mocks.apiRequest,
}));

import { listLogs } from './logs';

describe('logs api', () => {
  beforeEach(() => {
    mocks.apiRequest.mockResolvedValue({});
    mocks.apiRequest.mockClear();
  });

  it('passes AbortSignal while preserving listLogs query parameters', async () => {
    const ctrl = new AbortController();

    await listLogs({ offset: 200, limit: 50, signal: ctrl.signal });

    expect(mocks.apiRequest).toHaveBeenCalledWith('/api/logs?offset=200&limit=50', {
      signal: ctrl.signal,
    });
  });
});