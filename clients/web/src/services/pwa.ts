// PWA 与桌面通知统一入口。
//
// 设计原则:
// - 注册 SW 异步进行, 任何失败都吞掉, 不影响主应用启动。
// - 通知权限只在「用户已经收到至少一次后台消息」时主动请求, 不打扰首次访问。
// - 页面前台 (document.visibilityState === 'visible') 时永远不弹通知, 避免与
//   App 内的红点 + 列表行为重复。
// - 同一 sessionId 共用一个 tag, 后到的会替换旧的, 不堆叠成长串。

import { ignoreError, runIgnoringErrors } from '../shared/util/errors';
import { NOTIFICATION_TAG_MESSAGE, SW_MESSAGE_TYPE_NOTIFY } from '../shared/util/storage_keys';

let _swRegistration: ServiceWorkerRegistration | null = null;
let _permissionRequestedOnce = false;

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
  } catch (error) {
    ignoreError(error);
    return false;
  }
}

/// 仅在页面隐藏时触发桌面通知。
/// SW 已注册时优先 postMessage 让 SW 发 (PWA 安装后即使页面关闭也能弹);
/// 否则降级为页面级 Notification。
export async function notifyIfHidden(opts: {
  title: string;
  body?: string;
  sessionId?: string;
}): Promise<void> {
  if (!_isHidden()) return;
  const ok = await _ensurePermission();
  if (!ok) return;
  const tag = opts.sessionId ? `openhand-${opts.sessionId}` : NOTIFICATION_TAG_MESSAGE;
  const controller = navigator.serviceWorker.controller;
  if (_swRegistration && controller) {
    if (runIgnoringErrors(() => {
      controller.postMessage({
        type: SW_MESSAGE_TYPE_NOTIFY,
        title: opts.title,
        body: opts.body ?? '',
        tag,
        sessionId: opts.sessionId,
      });
    })) {
      return;
    }
  }
  try {
    const n = new Notification(opts.title, {
      body: opts.body ?? '',
      icon: '/openhand_logo.png',
      tag,
    });
    n.onclick = () => {
      runIgnoringErrors(() => window.focus());
      if (opts.sessionId) {
        location.href = `/threads/${encodeURIComponent(opts.sessionId)}`;
      }
      n.close();
    };
  } catch (error) {
    ignoreError(error);
  }
}
