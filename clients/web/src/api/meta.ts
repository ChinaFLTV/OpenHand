import type { M3ThemeTokens } from '../theme/tokens';

export interface ApiMetaService {
  bound_url?: string;
  accessible_urls?: string[];
}

export interface ApiMetaThemeRaw {
  primary?: string;
  on_primary?: string;
  surface?: string;
  surface_container?: string;
  on_surface?: string;
  on_surface_variant?: string;
  outline?: string;
  error?: string;
  brightness?: string;
}

export interface ApiMetaResponse {
  service?: ApiMetaService;
  theme?: ApiMetaThemeRaw;
  config?: Record<string, unknown>;
}

export async function fetchApiMeta(signal?: AbortSignal): Promise<ApiMetaResponse> {
  const res = await fetch('/api/meta', { signal });
  if (!res.ok) {
    throw new Error(`/api/meta 失败：HTTP ${res.status}`);
  }
  return (await res.json()) as ApiMetaResponse;
}

/// 把 service 端 snake_case 的 theme 字段映射为前端 token 体系，缺失字段
/// 走默认值（避免后端临时缺字段时整个页面没色）。
export function metaThemeToTokens(
  raw: ApiMetaThemeRaw | undefined,
  fallback: M3ThemeTokens,
): M3ThemeTokens {
  const brightness = raw?.brightness === 'dark' ? 'dark' : 'light';
  return {
    primary: raw?.primary ?? fallback.primary,
    onPrimary: raw?.on_primary ?? fallback.onPrimary,
    surface: raw?.surface ?? fallback.surface,
    surfaceContainer: raw?.surface_container ?? fallback.surfaceContainer,
    onSurface: raw?.on_surface ?? fallback.onSurface,
    onSurfaceVariant: raw?.on_surface_variant ?? fallback.onSurfaceVariant,
    outline: raw?.outline ?? fallback.outline,
    error: raw?.error ?? fallback.error,
    brightness,
  };
}
