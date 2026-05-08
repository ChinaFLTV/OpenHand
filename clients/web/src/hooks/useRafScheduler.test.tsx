import { cleanup, fireEvent, render, screen } from '@testing-library/preact';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useRafScheduler } from './useRafScheduler';

function SchedulerHarness({ onRun }: { onRun: () => void }) {
  const { schedule, flush, cancel } = useRafScheduler(onRun);
  return (
    <div>
      <button type="button" onClick={() => { schedule(); schedule(); }}>schedule</button>
      <button type="button" onClick={flush}>flush</button>
      <button type="button" onClick={cancel}>cancel</button>
    </div>
  );
}

describe('useRafScheduler', () => {
  let frames: Array<FrameRequestCallback | null>;

  beforeEach(() => {
    frames = [];
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      frames.push(callback);
      return frames.length;
    });
    vi.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => {
      frames[id - 1] = null;
    });
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('coalesces repeated schedules into one animation frame', () => {
    const onRun = vi.fn();
    render(<SchedulerHarness onRun={onRun} />);

    fireEvent.click(screen.getByRole('button', { name: 'schedule' }));

    expect(window.requestAnimationFrame).toHaveBeenCalledTimes(1);
    expect(onRun).not.toHaveBeenCalled();

    frames[0]?.(16);
    expect(onRun).toHaveBeenCalledTimes(1);
  });

  it('cancels a pending frame before it runs', () => {
    const onRun = vi.fn();
    render(<SchedulerHarness onRun={onRun} />);

    fireEvent.click(screen.getByRole('button', { name: 'schedule' }));
    fireEvent.click(screen.getByRole('button', { name: 'cancel' }));
    frames[0]?.(16);

    expect(window.cancelAnimationFrame).toHaveBeenCalledWith(1);
    expect(onRun).not.toHaveBeenCalled();
  });

  it('flushes a pending callback immediately', () => {
    const onRun = vi.fn();
    render(<SchedulerHarness onRun={onRun} />);

    fireEvent.click(screen.getByRole('button', { name: 'schedule' }));
    fireEvent.click(screen.getByRole('button', { name: 'flush' }));
    frames[0]?.(16);

    expect(window.cancelAnimationFrame).toHaveBeenCalledWith(1);
    expect(onRun).toHaveBeenCalledTimes(1);
  });
});