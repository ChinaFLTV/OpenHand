import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  apiRequest: vi.fn(),
}));

vi.mock('./client', () => ({
  ApiError: class ApiError extends Error {
    constructor(public readonly status: number, public readonly body: unknown) {
      super(`API ${status}`);
    }
  },
  UnauthorizedError: class UnauthorizedError extends Error {},
  apiRequest: mocks.apiRequest,
}));

import { getSession, listMessages } from './sessions';

describe('sessions api', () => {
  beforeEach(() => {
    mocks.apiRequest.mockResolvedValue({});
    mocks.apiRequest.mockClear();
  });

  it('passes AbortSignal to getSession requests', async () => {
    const ctrl = new AbortController();

    await getSession('session-1', { signal: ctrl.signal });

    expect(mocks.apiRequest).toHaveBeenCalledWith('/api/sessions/session-1', {
      signal: ctrl.signal,
    });
  });

  it('passes AbortSignal while preserving listMessages query parameters', async () => {
    const ctrl = new AbortController();

    await listMessages('session/with space', {
      limit: 20,
      offset: 10,
      tail: true,
      signal: ctrl.signal,
    });

    expect(mocks.apiRequest).toHaveBeenCalledWith(
      '/api/sessions/session%2Fwith%20space/messages?limit=20&offset=10&tail=1',
      { signal: ctrl.signal },
    );
  });
});