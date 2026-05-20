// Vitest 全局 setup. 注入 jest-dom 断言扩展, 抑制 happy-dom 在缺失 API 时的告警。
import '@testing-library/jest-dom/vitest';

function createMemoryStorage(): Storage {
  const values = new Map<string, string>();
  return {
    get length() {
      return values.size;
    },
    clear() {
      values.clear();
    },
    getItem(key: string) {
      return values.get(String(key)) ?? null;
    },
    key(index: number) {
      return Array.from(values.keys())[index] ?? null;
    },
    removeItem(key: string) {
      values.delete(String(key));
    },
    setItem(key: string, value: string) {
      values.set(String(key), String(value));
    },
  };
}

function ensureLocalStorage(): void {
  const windowStorage = typeof window !== 'undefined'
    ? storageValueFromDescriptor(window)
    : null;
  if (windowStorage) {
    Object.defineProperty(globalThis, 'localStorage', {
      configurable: true,
      value: windowStorage,
    });
    return;
  }
  const globalStorage = storageValueFromDescriptor(globalThis);
  if (globalStorage) return;
  const storage = createMemoryStorage();
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: storage,
  });
  if (typeof window !== 'undefined') {
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      value: storage,
    });
  }
}

function storageValueFromDescriptor(target: object): Storage | null {
  const descriptor = Object.getOwnPropertyDescriptor(target, 'localStorage');
  if (descriptor && 'value' in descriptor && descriptor.value?.getItem) {
    return descriptor.value;
  }
  return null;
}

ensureLocalStorage();
