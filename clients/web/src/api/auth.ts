// 鉴权相关 API：仅承担 /api/login 的请求构造与 token 持久化。
// 其余「会话/消息/文件」API 后续阶段在自己的模块里复用 apiRequest。

import { apiRequest } from './client';
import {
  type AuthProfile,
  ensureDeviceId,
  writeToken,
} from '../state/storage';

interface LoginRequestBody {
  username: string;
  password: string;
  device_id: string;
  source: string;
  device_name: string;
  device_platform: string;
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
  const body: LoginRequestBody = {
    username,
    password,
    device_id: ensureDeviceId(),
    source: 'WEB_PC',
    device_name: 'OpenHand Web',
    device_platform: navigator.platform || 'web',
  };
  const res = await apiRequest<LoginResponse>('/api/login', {
    method: 'POST',
    body,
    anonymous: true,
  });
  writeToken(res.token, res.profile);
  return res;
}
