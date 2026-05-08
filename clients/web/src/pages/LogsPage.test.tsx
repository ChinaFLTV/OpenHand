import { cleanup, render, waitFor } from '@testing-library/preact';
import { afterEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  listLogs: vi.fn(),
  exportLogsBundle: vi.fn(),
  route: vi.fn(),
}));

vi.mock('../api/logs', () => ({
  listLogs: mocks.listLogs,
  exportLogsBundle: mocks.exportLogsBundle,
}));

vi.mock('../hooks/useAnimatedLocation', () => ({
  useAnimatedLocation: () => ({ route: mocks.route }),
}));

import { LogsPage } from './LogsPage';

describe('LogsPage polling stability', () => {
  afterEach(() => {
    cleanup();
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it('aborts the active tail request when unmounted', async () => {
    vi.useFakeTimers();
    mocks.listLogs.mockReturnValue(new Promise(() => undefined));

    const view = render(<LogsPage />);

    await waitFor(() => expect(mocks.listLogs).toHaveBeenCalledTimes(1));
    const firstCallOptions = mocks.listLogs.mock.calls[0]?.[0] as { signal?: AbortSignal };
    expect(firstCallOptions.signal?.aborted).toBe(false);

    view.unmount();

    expect(firstCallOptions.signal?.aborted).toBe(true);
  });
});