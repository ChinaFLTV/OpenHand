// 浏览器端「设备身份」与会话 token 的 localStorage 容器。OpenHand service
// 要求每个请求带 `x-openhand-device-id` 等头，token 走 Authorization: Bearer。
// 这里只承担「读 / 写 / 清空」，不做任何 UI 决策；登录态切换由 auth store
// 调度。所有 key 统一登记在 shared/util/storage_keys，并统一使用既定前缀。

import {
  readBrowserJsonStorage,
  readBrowserStorage,
  removeBrowserStorage,
  writeBrowserJsonStorage,
  writeBrowserStorage,
} from '../shared/util/browser_storage';
import { STORAGE_KEY_DEVICE_ID, STORAGE_KEY_PROFILE, STORAGE_KEY_TOKEN } from '../shared/util/storage_keys';
import { recordOrNullFromUnknown, strictStringFromUnknown } from '../shared/util/value';

let fallbackDeviceId = '';
let fallbackToken: string | null = null;
let fallbackProfile: AuthProfile | null = null;
let tokenStorageOverridden = false;
let profileStorageOverridden = false;
let authRevision = 0;

export interface AuthProfile {
  device_id?: string;
  device_name?: string;
  device_platform?: string;
  source?: string;
  username?: string;
  [k: string]: unknown;
}

/// 首次访问时生成一个 v4 UUID 作为设备 ID 持久化；不依赖 cookie，避免
/// 跨域 / 隐私模式的兼容问题。
export function ensureDeviceId(): string {
  let id = readBrowserStorage(STORAGE_KEY_DEVICE_ID, fallbackDeviceId)?.trim() || fallbackDeviceId;
  if (!id) {
    id =
      globalThis.crypto?.randomUUID?.() ??
      `web-${Math.random().toString(36).slice(2)}-${Date.now()}`;
    writeBrowserStorage(STORAGE_KEY_DEVICE_ID, id);
  }
  fallbackDeviceId = id;
  return id;
}

export function readToken(): string | null {
  if (!tokenStorageOverridden) {
    fallbackToken = readBrowserStorage(STORAGE_KEY_TOKEN, fallbackToken)?.trim() || null;
  }
  return fallbackToken;
}

/** 绑定请求发起时的登录状态，拒绝旧会话的迟到响应。 */
export function captureAuthSession(): () => boolean {
  const revision = authRevision;
  const token = readToken();
  return () => revision === authRevision && token === readToken();
}

export function writeToken(token: unknown, profile: AuthProfile | null): string {
  const normalizedToken = strictStringFromUnknown(token);
  if (!normalizedToken) {
    throw new TypeError('登录响应缺少有效令牌。');
  }
  authRevision += 1;
  fallbackToken = normalizedToken;
  fallbackProfile = profile;
  tokenStorageOverridden = !writeBrowserStorage(STORAGE_KEY_TOKEN, fallbackToken);
  if (profile) {
    profileStorageOverridden = !writeBrowserJsonStorage(STORAGE_KEY_PROFILE, profile);
  } else {
    profileStorageOverridden = !removeBrowserStorage(STORAGE_KEY_PROFILE);
  }
  return normalizedToken;
}

export function readProfile(): AuthProfile | null {
  if (!profileStorageOverridden) {
    fallbackProfile = recordOrNullFromUnknown(
      readBrowserJsonStorage(STORAGE_KEY_PROFILE, fallbackProfile),
    ) as AuthProfile | null;
  }
  return fallbackProfile;
}

export function clearAuthStorage(): void {
  authRevision += 1;
  fallbackToken = null;
  fallbackProfile = null;
  tokenStorageOverridden = !removeBrowserStorage(STORAGE_KEY_TOKEN);
  profileStorageOverridden = !removeBrowserStorage(STORAGE_KEY_PROFILE);
}
