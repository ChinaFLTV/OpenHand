import { cleanup, fireEvent, render, screen } from '@testing-library/preact';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ConfirmDialog } from './ConfirmDialog';

describe('ConfirmDialog motion', () => {
  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  it('plays the shared exit animation before canceling', () => {
    vi.useFakeTimers();
    const onCancel = vi.fn();
    const onConfirm = vi.fn();
    render(
      <ConfirmDialog
        title="删除确认"
        body="确认删除当前项目"
        confirmLabel="删除"
        onCancel={onCancel}
        onConfirm={onConfirm}
      />,
    );

    const dialog = screen.getByRole('dialog');
    const overlay = dialog.parentElement as HTMLElement;
    fireEvent.click(screen.getByRole('button', { name: '取消' }));

    expect(onCancel).not.toHaveBeenCalled();
    expect(overlay.className).toContain('oh-dialog-fade-out');
    expect(dialog.className).toContain('oh-dialog-pop-out');

    vi.advanceTimersByTime(180);
    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(onConfirm).not.toHaveBeenCalled();
  });
});