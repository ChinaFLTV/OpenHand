import { cleanup, fireEvent, render, screen } from '@testing-library/preact';
import { useLayoutEffect } from 'preact/hooks';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { useEventCallback } from './useEventCallback';

function EventCallbackHarness({
  value,
  onCapture,
  onFire,
}: {
  value: string;
  onCapture: (handler: () => void) => void;
  onFire: (value: string) => void;
}) {
  const handler = useEventCallback(() => onFire(value));

  useLayoutEffect(() => {
    onCapture(handler);
  });

  return <button type="button" onClick={handler}>fire</button>;
}

describe('useEventCallback', () => {
  afterEach(() => cleanup());

  it('keeps a stable function identity while calling the latest callback body', () => {
    const captures: Array<() => void> = [];
    const onFire = vi.fn();
    const onCapture = (handler: () => void) => captures.push(handler);
    const { rerender } = render(
      <EventCallbackHarness value="first" onCapture={onCapture} onFire={onFire} />,
    );

    rerender(<EventCallbackHarness value="second" onCapture={onCapture} onFire={onFire} />);
    fireEvent.click(screen.getByRole('button', { name: 'fire' }));

    expect(captures).toHaveLength(2);
    expect(captures[1]).toBe(captures[0]);
    expect(onFire).toHaveBeenCalledWith('second');
  });
});
