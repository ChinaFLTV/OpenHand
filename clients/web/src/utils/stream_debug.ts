import { readBrowserStorage } from '../shared/util/browser_storage';

const STREAM_DEBUG_STORAGE_KEY = 'openhand.debug.stream';
const lastLogAtByKey = new Map<string, number>();

export function streamDebugEnabled(): boolean {
  const raw = readBrowserStorage(STREAM_DEBUG_STORAGE_KEY);
  if (raw == null) return false;
  return raw === '1' || raw.toLowerCase() === 'true' || raw.toLowerCase() === 'on';
}

export function streamDebugLog(
  key: string,
  label: string,
  data: Record<string, unknown>,
  minIntervalMs = 500,
): void {
  if (!streamDebugEnabled()) return;
  const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
  const last = lastLogAtByKey.get(key) ?? -Infinity;
  if (now - last < minIntervalMs) return;
  lastLogAtByKey.set(key, now);
  console.debug(`[oh.stream] ${label}`, data);
}
