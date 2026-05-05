import type { M3ThemeTokens } from '../theme/tokens';
import { tFmt } from '../i18n';

export interface ApiMetaService {
  bound_url?: string;
  accessible_urls?: string[];
  auth_enabled?: boolean;
  telemetry_enabled?: boolean;
  logging_enabled?: boolean;
  ops_enabled?: boolean;
  plan_mode_enabled?: boolean;
  session_management_enabled?: boolean;
  single_message_token_limit?: number;
  max_messages_per_session?: number;
  name?: string;
  description?: string;
}

export interface ApiMetaWorkspaceFiles {
  enabled?: boolean;
  operations_enabled?: boolean;
  write_enabled?: boolean;
  max_file_bytes?: number;
  allowed_extensions?: string[];
}

export interface ApiMetaPreferences {
  reduce_motion?: boolean;
  locale?: string;
  language_storage_value?: string;
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

export interface ApiMetaTemplate {
  id: string;
  name: string;
  description?: string;
  icon?: string;
}

export interface ApiMetaModel {
  key: string;
  provider_id: string;
  provider: string;
  protocol?: string;
  model_id: string;
  label: string;
  supports_attachments?: boolean;
  supports_image_generation?: boolean;
  supports_video_generation?: boolean;
  supports_audio_generation?: boolean;
}

export interface ApiMetaResponse {
  service?: ApiMetaService;
  workspace_files?: ApiMetaWorkspaceFiles;
  preferences?: ApiMetaPreferences;
  theme?: ApiMetaThemeRaw;
  templates?: ApiMetaTemplate[];
  conversation_modes?: string[];
  message_types?: string[];
  models?: ApiMetaModel[];
  config?: Record<string, unknown>;
}

export async function fetchApiMeta(signal?: AbortSignal): Promise<ApiMetaResponse> {
  const res = await fetch('/api/meta', { signal });
  if (!res.ok) {
    throw new Error(tFmt('error.meta.failed', { status: res.status }));
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
