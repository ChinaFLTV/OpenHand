// PWA 与后台消息通知入口；注册失败不阻断启动，同一会话的通知复用标签。

import { ignoreError, runIgnoringErrors } from '../shared/util/errors';
import { NOTIFICATION_TAG_MESSAGE, SW_MESSAGE_TYPE_NOTIFY } from '../shared/util/storage_keys';
import { truncateEndText } from '../shared/util/text';

let _swRegistration: ServiceWorkerRegistration | null = null;
let _permissionRequestedOnce = false;
const NOTIFICATION_TITLE_MAX_CHARACTERS = 120;
const NOTIFICATION_BODY_MAX_CHARACTERS = 600;
const NOTIFICATION_TAG_MAX_CHARACTERS = 160;
const NOTIFICATION_SESSION_ID_MAX_CHARACTERS = 256;

export function registerServiceWorker(): void {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;
  // 开发态走 vite 开发服务器，关闭会拦截 HMR 请求的 SW。
  const meta = import.meta as unknown as { env?: { DEV?: boolean } };
  if (meta.env?.DEV) {
    // 主动反注册生产模式安装过的 SW，防止 vite HMR 走缓存。
    navigator.serviceWorker.getRegistrations().then((regs) => {
      regs.forEach((r) => {
        r.unregister().catch(ignoreError);
      });
    }).catch(ignoreError);
    return;
  }
  const tryRegister = () => {
    navigator.serviceWorker
      .register('/sw.js', { scope: '/' })
      .then((reg) => {
        _swRegistration = reg;
      })
      .catch(ignoreError);
  };
  if (document.readyState === 'complete') {
    tryRegister();
  } else {
    window.addEventListener('load', tryRegister, { once: true });
  }
}

function _isHidden(): boolean {
  if (typeof document === 'undefined') return false;
  return document.visibilityState === 'hidden';
}

async function _ensurePermission(): Promise<boolean> {
  if (typeof Notification === 'undefined') return false;
  if (Notification.permission === 'granted') return true;
  if (Notification.permission === 'denied') return false;
  if (_permissionRequestedOnce) return false;
  _permissionRequestedOnce = true;
  try {
    const result = await Notification.requestPermission();
    return result === 'granted';
  } catch {
    return false;
  }
}

/// 仅在页面隐藏时触发桌面通知。
/// 优先由已注册的 Service Worker 发送，否则使用页面通知。
export async function notifyIfHidden(opts: {
  title: string;
  body?: string;
  sessionId?: string;
}): Promise<void> {
  if (!_isHidden()) return;
  const title = truncateEndText(
    opts.title.trim(),
    NOTIFICATION_TITLE_MAX_CHARACTERS,
    { ellipsis: '' },
  );
  if (!title) return;
  const body = truncateEndText(
    opts.body?.trim() ?? '',
    NOTIFICATION_BODY_MAX_CHARACTERS,
  );
  const sessionId = truncateEndText(
    opts.sessionId?.trim() ?? '',
    NOTIFICATION_SESSION_ID_MAX_CHARACTERS,
    { ellipsis: '' },
  );
  const ok = await _ensurePermission();
  if (!ok) return;
  const tag = truncateEndText(
    sessionId ? `openhand-${sessionId}` : NOTIFICATION_TAG_MESSAGE,
    NOTIFICATION_TAG_MAX_CHARACTERS,
    { ellipsis: '' },
  );
  const controller =
    typeof navigator !== 'undefined' && 'serviceWorker' in navigator
      ? navigator.serviceWorker.controller
      : null;
  if (_swRegistration && controller) {
    if (runIgnoringErrors(() => {
      controller.postMessage({
        type: SW_MESSAGE_TYPE_NOTIFY,
        title,
        body,
        tag,
        sessionId,
      });
    })) {
      return;
    }
  }
  try {
    const n = new Notification(title, {
      body,
      icon: '/openhand_logo.png',
      tag,
    });
    n.onclick = () => {
      runIgnoringErrors(() => window.focus());
      if (sessionId) {
        location.href = `/threads/${encodeURIComponent(sessionId)}`;
      }
      n.close();
    };
  } catch {
    // 系统通知不可用时，消息仍由页面展示。
  }
}
