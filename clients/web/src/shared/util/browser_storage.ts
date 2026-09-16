import { parseJsonSafely } from './value';

function getBrowserStorage(): Storage | null {
  try {
    if (typeof window !== 'undefined') {
      return window.localStorage ?? null;
    }
  } catch {
    return null;
  }
  try {
    const descriptor = Object.getOwnPropertyDescriptor(
      globalThis,
      'localStorage',
    );
    if (descriptor && 'value' in descriptor) {
      return descriptor.value ?? null;
    }
  } catch {
    return null;
  }
  return null;
}

function readStorageValue(key: string): string | null | undefined {
  try {
    return getBrowserStorage()?.getItem(key);
  } catch {
    return undefined;
  }
}

/** 仅在存储不可用时使用内存值，已删除的键仍返回 null。 */
export function readBrowserStorage(
  key: string,
  fallback: string | null = null,
): string | null {
  const value = readStorageValue(key);
  return value === undefined ? fallback : value;
}

export function readBrowserJsonStorage(
  key: string,
  fallback: unknown = null,
): unknown {
  const raw = readStorageValue(key);
  if (raw === undefined) return fallback;
  if (raw == null) return null;
  const parsed = parseJsonSafely(raw);
  // JSON null 是合法值，不能和损坏文本混为一谈并删除。
  if (parsed == null && raw.trim() !== 'null') {
    removeBrowserStorage(key);
    return null;
  }
  return parsed;
}

export function writeBrowserStorage(key: string, value: string): boolean {
  try {
    const storage = getBrowserStorage();
    if (storage == null) return false;
    storage.setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

export function writeBrowserJsonStorage(key: string, value: unknown): boolean {
  try {
    const serialized = JSON.stringify(value);
    return typeof serialized === 'string'
      && writeBrowserStorage(key, serialized);
  } catch {
    return false;
  }
}

export function removeBrowserStorage(key: string): boolean {
  try {
    const storage = getBrowserStorage();
    if (storage == null) return false;
    storage.removeItem(key);
    return true;
  } catch {
    return false;
  }
}
