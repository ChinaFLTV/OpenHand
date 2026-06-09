// 浏览器端「设备身份」与会话 token 的 localStorage 容器。OpenHand service
// 要求每个请求带 `x-openhand-device-id` 等头，token 走 Authorization: Bearer。
// 这里只承担「读 / 写 / 清空」，不做任何 UI 决策；登录态切换由 auth store
// 调度。所有 key 共用一个前缀方便调试时一键 clear。

import {
  readBrowserStorage,
  removeBrowserStorage,
  writeBrowserStorage,
} from '../shared/util/browser_storage';

const PREFIX = 'openhand.web.';
const DEVICE_ID_KEY = `${PREFIX}device_id`;
const TOKEN_KEY = `${PREFIX}token`;
const PROFILE_KEY = `${PREFIX}profile`;
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
  let id = readBrowserStorage(DEVICE_ID_KEY) ?? fallbackDeviceId;
  if (!id) {
    id =
      globalThis.crypto?.randomUUID?.() ??
      `web-${Math.random().toString(36).slice(2)}-${Date.now()}`;
    fallbackDeviceId = id;
    writeBrowserStorage(DEVICE_ID_KEY, id);
  }
  return id;
}

export function readToken(): string | null {
  return readBrowserStorage(TOKEN_KEY) ?? fallbackToken;
}

export function writeToken(token: string, profile: AuthProfile | null): void {
  fallbackToken = token;
  fallbackProfile = profile;
  writeBrowserStorage(TOKEN_KEY, token);
  if (profile) {
    writeBrowserStorage(PROFILE_KEY, JSON.stringify(profile));
  } else {
    removeBrowserStorage(PROFILE_KEY);
  }
}

export function readProfile(): AuthProfile | null {
  const raw = readBrowserStorage(PROFILE_KEY);
  if (!raw) return fallbackProfile;
  try {
    return JSON.parse(raw) as AuthProfile;
  } catch {
    return null;
  }
}

export function clearAuthStorage(): void {
  fallbackToken = null;
  fallbackProfile = null;
  removeBrowserStorage(TOKEN_KEY);
  removeBrowserStorage(PROFILE_KEY);
}
