// 鉴权相关 API：仅承担 /api/login 的请求构造与 token 持久化。
// 其余「会话/消息/文件」API 后续阶段在自己的模块里复用 apiRequest。

import { apiRequest } from './client';
import {
  type AuthProfile,
  ensureDeviceId,
  writeToken,
} from '../state/storage';
import { collectClientEnvironment } from '../utils/client_env';

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
): Promise<LoginResponse> {
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
    method: 'POST',
    body,
    anonymous: true,
  });
  writeToken(res.token, res.profile);
  return res;
}
