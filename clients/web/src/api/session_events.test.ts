import { afterEach, describe, expect, it, vi } from 'vitest';
import { subscribeSessionEvents } from './session_events';

class FakeEventSource {
  static instances: FakeEventSource[] = [];

  readonly listeners = new Map<string, Array<(event: MessageEvent) => void>>();
  onopen: (() => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  close = vi.fn();

  constructor(readonly url: string, readonly init?: EventSourceInit) {
    FakeEventSource.instances.push(this);
  }

  addEventListener(type: string, listener: EventListenerOrEventListenerObject) {
    const callback = typeof listener === 'function'
      ? listener
      : (event: Event) => listener.handleEvent(event);
    const list = this.listeners.get(type) ?? [];
    list.push(callback as (event: MessageEvent) => void);
    this.listeners.set(type, list);
  }

  emit(type: string, data: unknown) {
    for (const listener of this.listeners.get(type) ?? []) {
      listener(new MessageEvent(type, { data: JSON.stringify(data) }));
    }
  }
}

describe('subscribeSessionEvents', () => {
  afterEach(() => {
    FakeEventSource.instances = [];
    vi.unstubAllGlobals();
    window.localStorage.clear();
  });

  it('dispatches session_deleted events to the caller', () => {
    vi.stubGlobal('EventSource', FakeEventSource);
    const onDeleted = vi.fn();
    const onSnapshot = vi.fn();
    const onError = vi.fn();

    const close = subscribeSessionEvents('session-1', {
      onSnapshot,
      onDeleted,
      onError,
    });

    const source = FakeEventSource.instances[0]!;
    source.emit('session_deleted', {
      error: 'session_deleted_or_not_found',
      session_id: 'session-1',
      served_at: '2026-05-06T00:00:00.000Z',
    });

    expect(onDeleted).toHaveBeenCalledWith({
      error: 'session_deleted_or_not_found',
      session_id: 'session-1',
      served_at: '2026-05-06T00:00:00.000Z',
    });
    expect(onSnapshot).not.toHaveBeenCalled();
    expect(onError).not.toHaveBeenCalled();

    close();
    expect(source.close).toHaveBeenCalledTimes(1);
  });
});