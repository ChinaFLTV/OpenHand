// PWA / Notification 模块的纯逻辑校验。
// happy-dom 提供 document/window, 但默认没有 Notification —— 用 stub 注入。
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { notifyIfHidden } from './pwa';

describe('notifyIfHidden', () => {
  let originalNotification: typeof globalThis.Notification | undefined;
  let originalSW: ServiceWorkerContainer | undefined;
  let createdNotifications: Array<{ title: string; opts?: NotificationOptions }>;

  beforeEach(() => {
    createdNotifications = [];
    originalNotification = (globalThis as { Notification?: typeof Notification }).Notification;
    originalSW = globalThis.navigator?.serviceWorker;
    class FakeNotification {
      static permission: NotificationPermission = 'granted';
      static requestPermission = vi.fn(async () => 'granted' as NotificationPermission);
      onclick: (() => void) | null = null;
      constructor(public title: string, public opts?: NotificationOptions) {
        createdNotifications.push({ title, opts });
      }
      close() {}
    }
    // @ts-expect-error stub
    globalThis.Notification = FakeNotification;
    // @ts-expect-error 移除 SW 走 page-level fallback 路径
    globalThis.navigator.serviceWorker = undefined;
  });

  afterEach(() => {
    // @ts-expect-error 还原
    globalThis.Notification = originalNotification;
    // @ts-expect-error 还原
    globalThis.navigator.serviceWorker = originalSW;
  });

  it('skips when document is visible', async () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'visible',
    });
    await notifyIfHidden({ title: 'foo' });
    expect(createdNotifications).toHaveLength(0);
  });

  it('creates a Notification when document is hidden', async () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
    await notifyIfHidden({ title: '新消息', body: 'hello', sessionId: 'abc' });
    expect(createdNotifications).toHaveLength(1);
    expect(createdNotifications[0].title).toBe('新消息');
    expect(createdNotifications[0].opts?.tag).toBe('openhand-abc');
  });
});
