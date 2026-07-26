import type { M3ThemeTokens } from '../theme/tokens';
import { tFmt } from '../i18n';
import type { ApiDialogAnimationSettings } from '../hooks/useDialogMotionSettings';
import { recordOrNullFromUnknown } from '../shared/util/value';
import { ApiError, apiRequest } from './client';

const API_META_REQUEST_TIMEOUT_MS = 30_000;

interface ApiMetaService {
  listen_host?: string;
  listen_port?: number;
  bound_url?: string;
  bound_port?: number;
  port_fallback_active?: boolean;
  accessible_urls?: string[];
  auth_enabled?: boolean;
  telemetry_enabled?: boolean;
  logging_enabled?: boolean;
  ops_enabled?: boolean;
  auto_start_on_launch?: boolean;
  auto_reload_on_change?: boolean;
  plan_mode_enabled?: boolean;
  knowledge_base_enabled?: boolean;
  read_aloud_enabled?: boolean;
  translation_enabled?: boolean;
  feedback_enabled?: boolean;
  regeneration_enabled?: boolean;
  session_management_enabled?: boolean;
  single_message_token_limit?: number;
  max_messages_per_session?: number;
  name?: string;
  description?: string;
}

interface ApiMetaWorkspaceFiles {
  enabled?: boolean;
  operations_enabled?: boolean;
  write_enabled?: boolean;
  max_file_bytes?: number;
  allowed_extensions?: string[];
}

interface ApiMetaAttachments {
  max_count?: number;
  max_file_bytes?: number;
  max_total_bytes?: number;
}

interface ApiMetaPreferences {
  reduce_motion?: boolean;
  locale?: string;
  language_storage_value?: string;
  dialog_animation_settings?: ApiDialogAnimationSettings;
}

interface ApiMetaMessageContentSettings {
  tts_enabled?: boolean;
  translation_enabled?: boolean;
  translation_settings_fingerprint?: string;
  translation_model_settings_fingerprint?: string;
  message_content_format?: string;
}

export interface ApiMetaShortcutBinding {
  key_ids?: number[];
  label?: string;
}

interface ApiMetaThemeRaw {
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
  internal_version?: string;
}

export interface ApiMetaModel {
  key: string;
  provider_id: string;
  provider: string;
  protocol?: string;
  model_id: string;
  label: string;
  supports_attachments?: boolean;
  supports_image_input?: boolean;
  supports_video_input?: boolean;
  supports_audio_input?: boolean;
  supports_file_input?: boolean;
  attachment_extensions?: string[];
  supports_image_generation?: boolean;
  supports_video_generation?: boolean;
  supports_audio_generation?: boolean;
  supports_text_title_generation?: boolean;
  supports_embeddings?: boolean;
  provider_default_title_model_key?: string | null;
  is_global_default_title_model?: boolean;
  reasoning_effort_control_enabled?: boolean;
  reasoning_effort?: string | null;
  reasoning_effort_options?: ApiReasoningEffortOption[];
}

export interface ApiReasoningEffortOption {
  value: string;
  label: string;
}

interface UpdateModelReasoningEffortResponse {
  model_key: string;
  reasoning_effort: string;
}

export interface ApiMetaInstruction {
  id: string;
  name: string;
  description?: string;
  /// 指令正文，已被 service 端截断到 4 KiB 以内（超出会带省略号），
  /// 仅用于 Web composer 胶囊 hover 卡片快速预览。
  body?: string;
  body_truncated?: boolean;
}

export interface ApiMetaResponse {
  service?: ApiMetaService;
  message_content_settings?: ApiMetaMessageContentSettings;
  workspace_files?: ApiMetaWorkspaceFiles;
  attachments?: ApiMetaAttachments;
  preferences?: ApiMetaPreferences;
  shortcut_bindings?: Record<string, ApiMetaShortcutBinding>;
  theme?: ApiMetaThemeRaw;
  templates?: ApiMetaTemplate[];
  conversation_modes?: string[];
  message_types?: string[];
  active_model_key?: string | null;
  models?: ApiMetaModel[];
  instructions?: ApiMetaInstruction[];
  config?: Record<string, unknown>;
}

export async function fetchApiMeta(signal?: AbortSignal): Promise<ApiMetaResponse> {
  try {
    const value = await apiRequest<unknown>('/api/meta', {
      anonymous: true,
      signal,
      timeoutMs: API_META_REQUEST_TIMEOUT_MS,
    });
    if (recordOrNullFromUnknown(value) == null) {
      throw new Error(tFmt('error.meta.failed', { status: 'invalid_response' }));
    }
    return value as ApiMetaResponse;
  } catch (error) {
    if (error instanceof ApiError) {
      throw new Error(tFmt('error.meta.failed', { status: error.status }));
    }
    throw error;
  }
}

export function updateModelReasoningEffort(
  modelKey: string,
  effort: string,
  sessionId: string,
): Promise<UpdateModelReasoningEffortResponse> {
  return apiRequest<UpdateModelReasoningEffortResponse>(
    '/api/settings/models/reasoning-effort',
    {
      method: 'PUT',
      body: { model_key: modelKey, effort, session_id: sessionId },
    },
  );
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
