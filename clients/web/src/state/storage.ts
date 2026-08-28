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
import { recordOrNullFromUnknown } from '../shared/util/value';

let fallbackDeviceId = '';
let fallbackToken: string | null = null;
let fallbackProfile: AuthProfile | null = null;

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
  let id = readBrowserStorage(STORAGE_KEY_DEVICE_ID)?.trim() || fallbackDeviceId;
  if (!id) {
    id =
      globalThis.crypto?.randomUUID?.() ??
      `web-${Math.random().toString(36).slice(2)}-${Date.now()}`;
    fallbackDeviceId = id;
    writeBrowserStorage(STORAGE_KEY_DEVICE_ID, id);
  }
  return id;
}

export function readToken(): string | null {
  return readBrowserStorage(STORAGE_KEY_TOKEN)?.trim() || fallbackToken;
}

export function writeToken(token: string, profile: AuthProfile | null): void {
  fallbackToken = token;
  fallbackProfile = profile;
  writeBrowserStorage(STORAGE_KEY_TOKEN, token);
  if (profile) {
    writeBrowserJsonStorage(STORAGE_KEY_PROFILE, profile);
  } else {
    removeBrowserStorage(STORAGE_KEY_PROFILE);
  }
}

export function readProfile(): AuthProfile | null {
  const profile = recordOrNullFromUnknown(
    readBrowserJsonStorage(STORAGE_KEY_PROFILE),
  ) as AuthProfile | null;
  if (profile != null) {
    fallbackProfile = profile;
    return profile;
  }
  // 损坏的持久化数据无需反复解析，保留内存中的最近有效资料。
  removeBrowserStorage(STORAGE_KEY_PROFILE);
  return fallbackProfile;
}

export function clearAuthStorage(): void {
  fallbackToken = null;
  fallbackProfile = null;
  removeBrowserStorage(STORAGE_KEY_TOKEN);
  removeBrowserStorage(STORAGE_KEY_PROFILE);
}
