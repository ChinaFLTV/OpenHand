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

export function readBrowserStorage(key: string): string | null {
  try {
    return getBrowserStorage()?.getItem(key) ?? null;
  } catch {
    return null;
  }
}

export function readBrowserJsonStorage(key: string): unknown | null {
  const raw = readBrowserStorage(key);
  if (raw == null) return null;
  try {
    return JSON.parse(raw) as unknown;
  } catch {
    removeBrowserStorage(key);
    return null;
  }
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
