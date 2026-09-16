import { apiRequest, type ApiRequestSignalOptions } from './client';
import {
  type AuthProfile,
  captureAuthSession,
  ensureDeviceId,
  writeToken,
} from '../state/storage';
import { collectClientEnvironment } from '../utils/client_env';
import { recordOrNullFromUnknown } from '../shared/util/value';

interface LoginRequestBody {
  username: string;
  password: string;
  device_id: string;
  source: string;
  device_name: string;
  device_platform: string;
  os_name: string;
  os_version: string;
  browser_name: string;
  browser_version: string;
  web_client_version: string;
  locale: string;
  timezone: string;
  screen_class: string;
  user_agent: string;
}

interface LoginResponse {
  token: string;
  expires_in: number | null;
  profile: AuthProfile;
}

export async function loginWithCredentials(
  username: string,
  password: string,
  options: ApiRequestSignalOptions = {},
): Promise<LoginResponse> {
  const isCurrentSession = captureAuthSession();
  const env = collectClientEnvironment();
  const body: LoginRequestBody = {
    username,
    password,
    device_id: ensureDeviceId(),
    source: env.source,
    device_name: env.deviceName,
    device_platform: env.devicePlatform,
    os_name: env.osName,
    os_version: env.osVersion,
    browser_name: env.browserName,
    browser_version: env.browserVersion,
    web_client_version: env.webClientVersion,
    locale: env.locale,
    timezone: env.timezone,
    screen_class: env.screenClass,
    user_agent: env.userAgent,
  };
  const res = await apiRequest<LoginResponse>('/api/login', {
    ...options,
    method: 'POST',
    body,
    anonymous: true,
  });
  options.signal?.throwIfAborted();
  if (!isCurrentSession()) {
    throw new DOMException('登录状态已变更，忽略旧登录响应。', 'AbortError');
  }
  const profile = recordOrNullFromUnknown(res?.profile);
  if (!profile) throw new TypeError('登录响应缺少有效用户资料。');
  const token = writeToken(res.token, profile);
  return { ...res, token, profile };
}
