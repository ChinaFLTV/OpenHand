import { collectClientEnvironment } from './client_env';
import { ensureDeviceId, readToken } from '../state/storage';

export function buildSessionAssetUrl(sessionId: string, path: string): string {
  const qs = new URLSearchParams();
  const env = collectClientEnvironment();
  qs.set('path', path);
  qs.set('device_id', ensureDeviceId());
  qs.set('source', env.source);
  const token = readToken();
  if (token) qs.set('token', token);
  return `/api/sessions/${encodeURIComponent(sessionId)}/asset?${qs.toString()}`;
}