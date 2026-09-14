import { useEffect, useState } from 'preact/hooks';
import { apiRequest } from '../api/client';
import {
  fetchApiMeta,
  metaThemeToTokens,
  type ApiMetaResponse,
} from '../api/meta';
import { applyThemeTokens, defaultThemeTokens, type M3ThemeTokens } from '../theme/tokens';
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
let bootController: AbortController | null = null;
let refreshPromise: Promise<void> | null = null;
let bootGeneration = 0;
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
  installForegroundMetaSync();
  const generation = ++bootGeneration;
  const controller = new AbortController();
  bootController?.abort();
  bootController = controller;
  bootPromise = (async () => {
    try {
      const meta = await fetchApiMeta(controller.signal);
      if (generation !== bootGeneration) return;
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
        error: undefined,
      });
    } catch (e: unknown) {
      if (controller.signal.aborted || generation !== bootGeneration) return;
      const msg = e instanceof Error ? e.message : String(e);
      emit({ ...current, loading: false, error: msg });
    } finally {
      if (generation === bootGeneration) bootController = null;
    }
  })();
  return bootPromise;
}

export function useAuth(): AuthState {
  const [state, setState] = useState<AuthState>(current);
  useEffect(() => {
    subscribers.add(setState);
    setState(current);
    void bootOnce();
    return () => {
      subscribers.delete(setState);
    };
  }, []);
  return state;
}

// 登录后重新读取受鉴权保护的元数据，替换登录前的公开字段。
export function markLoggedIn(profile: AuthProfile): void {
  emit({
    ...current,
    isAuthenticated: true,
    profile,
  });
  void refreshMeta({ force: true }).catch(ignoreError);
}

export function logout(): void {
  if (readToken()) {
    void apiRequest('/api/logout', {
      method: 'POST',
      timeoutMs: LOGOUT_REQUEST_TIMEOUT_MS,
    }).catch(ignoreError);
  }
  clearAuthStorage();
  emit({
    ...current,
    isAuthenticated: !current.authRequired,
    profile: null,
  });
  // 内存里的 meta 还留着登录期间拿到的模型清单与用户指令，登出后补拉一次
  // 匿名版把它们换掉。
  if (current.authRequired) void refreshMeta({ force: true }).catch(ignoreError);
}

/// 显式刷新一次 /api/meta（例如桌面端切换了主题色后）。
export async function refreshMeta({ force = false }: { force?: boolean } = {}): Promise<void> {
  if (refreshPromise && !force) return refreshPromise;
  bootController?.abort();
  bootPromise = null;
  const pending = bootOnce();
  const refreshPending = pending.finally(() => {
    if (refreshPromise === refreshPending) {
      refreshPromise = null;
    }
  });
  refreshPromise = refreshPending;
  await refreshPending;
}
