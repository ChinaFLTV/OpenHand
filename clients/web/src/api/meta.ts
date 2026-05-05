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
  primary_container?: string;
  on_primary_container?: string;
  secondary?: string;
  on_secondary?: string;
  secondary_container?: string;
  on_secondary_container?: string;
  tertiary?: string;
  on_tertiary?: string;
  tertiary_container?: string;
  on_tertiary_container?: string;
  surface?: string;
  surface_container_lowest?: string;
  surface_container_low?: string;
  surface_container?: string;
  surface_container_high?: string;
  surface_container_highest?: string;
  on_surface?: string;
  on_surface_variant?: string;
  outline?: string;
  outline_variant?: string;
  inverse_surface?: string;
  inverse_on_surface?: string;
  error?: string;
  error_container?: string;
  on_error_container?: string;
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
    primaryContainer: raw?.primary_container ?? fallback.primaryContainer,
    onPrimaryContainer: raw?.on_primary_container ?? fallback.onPrimaryContainer,
    secondary: raw?.secondary ?? fallback.secondary,
    onSecondary: raw?.on_secondary ?? fallback.onSecondary,
    secondaryContainer: raw?.secondary_container ?? fallback.secondaryContainer,
    onSecondaryContainer: raw?.on_secondary_container ?? fallback.onSecondaryContainer,
    tertiary: raw?.tertiary ?? fallback.tertiary,
    onTertiary: raw?.on_tertiary ?? fallback.onTertiary,
    tertiaryContainer: raw?.tertiary_container ?? fallback.tertiaryContainer,
    onTertiaryContainer: raw?.on_tertiary_container ?? fallback.onTertiaryContainer,
    surface: raw?.surface ?? fallback.surface,
    surfaceContainerLowest: raw?.surface_container_lowest ?? fallback.surfaceContainerLowest,
    surfaceContainerLow: raw?.surface_container_low ?? fallback.surfaceContainerLow,
    surfaceContainer: raw?.surface_container ?? fallback.surfaceContainer,
    surfaceContainerHigh: raw?.surface_container_high ?? fallback.surfaceContainerHigh,
    surfaceContainerHighest: raw?.surface_container_highest ?? fallback.surfaceContainerHighest,
    onSurface: raw?.on_surface ?? fallback.onSurface,
    onSurfaceVariant: raw?.on_surface_variant ?? fallback.onSurfaceVariant,
    outline: raw?.outline ?? fallback.outline,
    outlineVariant: raw?.outline_variant ?? fallback.outlineVariant,
    inverseSurface: raw?.inverse_surface ?? fallback.inverseSurface,
    inverseOnSurface: raw?.inverse_on_surface ?? fallback.inverseOnSurface,
    error: raw?.error ?? fallback.error,
    errorContainer: raw?.error_container ?? fallback.errorContainer,
    onErrorContainer: raw?.on_error_container ?? fallback.onErrorContainer,
    brightness,
  };
}
