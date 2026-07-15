// 鉴权状态 hook：把「是否需要登录 / 当前是否已登录 / loading」三种状态
// 收敛到一个 hook，供 LoginPage / HomePage / RouteGuard 复用。
// 实现取舍：避免 React Context（Preact 也能用，但会让 children 全量重渲染）；
// 直接用 module-scoped subscribers 列表做最轻量的发布订阅。

import { useEffect, useState } from 'preact/hooks';
import { apiRequest } from '../api/client';
import { fetchApiMeta, type ApiMetaResponse } from '../api/meta';
import { applyThemeTokens, defaultThemeTokens, type M3ThemeTokens } from '../theme/tokens';
import { metaThemeToTokens } from '../api/meta';
import { clearAuthStorage, readProfile, readToken, type AuthProfile } from './storage';
import { setRemoteReducedMotion } from '../hooks/useReducedMotion';
import { syncRemoteDialogMotionSettings } from '../hooks/useDialogMotionSettings';
import { syncLangFromAppPreferences } from '../i18n';
import { ignoreError } from '../shared/util/errors';

interface AuthState {
  meta: ApiMetaResponse | null;
  loading: boolean;
  authRequired: boolean;
  isAuthenticated: boolean;
  profile: AuthProfile | null;
  themeTokens: M3ThemeTokens;
  themeSource: 'default' | 'api';
  error?: string;
}

const initialState: AuthState = {
  meta: null,
  loading: true,
  authRequired: false,
  isAuthenticated: false,
  profile: null,
  themeTokens: defaultThemeTokens,
  themeSource: 'default',
};

let current: AuthState = initialState;
const subscribers = new Set<(s: AuthState) => void>();
const FOREGROUND_META_REFRESH_MIN_INTERVAL_MS = 2000;
const LOGOUT_REQUEST_TIMEOUT_MS = 2000;

function emit(next: AuthState): void {
  current = next;
  for (const sub of subscribers) sub(next);
}

let bootPromise: Promise<void> | null = null;
let syncListenersInstalled = false;
let lastForegroundMetaRefreshAt = 0;

function applyMetaSideEffects(meta: ApiMetaResponse): M3ThemeTokens {
  const tokens = metaThemeToTokens(meta.theme, defaultThemeTokens);
  applyThemeTokens(tokens);
  setRemoteReducedMotion(Boolean(meta.preferences?.reduce_motion));
  syncRemoteDialogMotionSettings(meta.preferences?.dialog_animation_settings);
  syncLangFromAppPreferences(
    meta.preferences?.language_storage_value,
    meta.preferences?.locale,
  );
  return tokens;
}

function installForegroundMetaSync(): void {
  if (syncListenersInstalled || typeof window === 'undefined') return;
  syncListenersInstalled = true;
  const refreshIfStale = () => {
    const now = Date.now();
    if (
      now - lastForegroundMetaRefreshAt <
      FOREGROUND_META_REFRESH_MIN_INTERVAL_MS
    ) {
      return;
    }
    lastForegroundMetaRefreshAt = now;
    void refreshMeta().catch(ignoreError);
  };
  const refreshIfVisible = () => {
    if (document.visibilityState === 'visible') refreshIfStale();
  };
  window.addEventListener('focus', refreshIfStale);
  document.addEventListener('visibilitychange', refreshIfVisible);
}

/// 第一次调用会拉取 /api/meta + 应用主题 + 检查 token；后续 useAuth 复用结果。
function bootOnce(): Promise<void> {
  if (bootPromise) return bootPromise;
  bootPromise = (async () => {
    try {
      const meta = await fetchApiMeta();
      const tokens = applyMetaSideEffects(meta);
      const authRequired = Boolean(meta.service?.auth_enabled);
      const token = readToken();
      const profile = readProfile();
      emit({
        ...current,
        loading: false,
        meta,
        authRequired,
        isAuthenticated: !authRequired || Boolean(token),
        profile,
        themeTokens: tokens,
        themeSource: 'api',
      });
      installForegroundMetaSync();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      emit({ ...current, loading: false, error: msg });
    }
  })();
  return bootPromise;
}

export function useAuth(): AuthState {
  const [state, setState] = useState<AuthState>(current);
  useEffect(() => {
    subscribers.add(setState);
    void bootOnce();
    return () => {
      subscribers.delete(setState);
    };
  }, []);
  return state;
}

/// 登录成功后调用：直接把 service 端 auth_enabled 视为已通过的状态。
export function markLoggedIn(profile: AuthProfile): void {
  emit({
    ...current,
    isAuthenticated: true,
    profile,
  });
}

export function logout(): void {
  const revokeRequest = readToken()
    ? apiRequest('/api/logout', {
      method: 'POST',
      timeoutMs: LOGOUT_REQUEST_TIMEOUT_MS,
    }).catch(ignoreError)
    : null;
  clearAuthStorage();
  emit({
    ...current,
    isAuthenticated: !current.authRequired,
    profile: null,
  });
  if (revokeRequest) void revokeRequest;
}

/// 显式刷新一次 /api/meta（例如桌面端切换了主题色后）。
export async function refreshMeta(): Promise<void> {
  bootPromise = null;
  await bootOnce();
}
