// 远程偏好 API. 服务端字段集见 _getPreferencesHandler。
import { apiRequest } from '../../../api/client';
import type { ApiDialogAnimationSettings } from '../../../hooks/useDialogMotionSettings';

export interface RemotePreferences {
  reduce_motion: boolean;
  locale: string;
  language_storage_value: string;
  dialog_animation_settings?: ApiDialogAnimationSettings;
  memory_enabled: boolean;
  ai_message_compression_threshold_chars: number;
  limits: {
    ai_message_compression_threshold_chars_min: number;
    ai_message_compression_threshold_chars_max: number;
  };
  language_options: string[];
}

export interface PreferencesUpdate {
  reduce_motion?: boolean;
  language_storage_value?: string;
  ai_message_compression_threshold_chars?: number;
}

export function fetchPreferences(): Promise<RemotePreferences> {
  return apiRequest<RemotePreferences>('/api/settings/preferences');
}

export function updatePreferences(update: PreferencesUpdate): Promise<RemotePreferences> {
  return apiRequest<RemotePreferences>('/api/settings/preferences', {
    method: 'PUT',
    body: update,
  });
}
