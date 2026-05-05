// Web 端 i18n 入口。Stage 7：引入 zh + en 双词表，运行时可切换并持久化到 localStorage。
//
// 设计要点：
// - dict_zh / dict_en 拆分为独立模块，键集合一一对应。
// - currentLang 维护在模块级，所有 t(key) 调用直接读取，无需 Context。
// - subscribe / setLang 通过简单的发布订阅触发 Preact 组件重渲染（useLang hook）。
// - 首次启动从 localStorage 读取，缺省时按浏览器 navigator.language 自动判断。
// - dict[key] 缺词时回退顺序：当前语言 → zh → 调用方 fallback → key 本身。

import { useEffect, useState } from 'preact/hooks';
import { dict_zh } from './dict_zh';
import { dict_zhHant } from './dict_zhHant';
import { dict_en } from './dict_en';
import { dict_ja } from './dict_ja';

export type Lang = 'zh' | 'zh-Hant' | 'en' | 'ja';
export const SUPPORTED_LANGS: readonly Lang[] = ['zh', 'zh-Hant', 'en', 'ja'];

const STORAGE_KEY = 'openhand_web_lang';
const dicts: Record<Lang, Record<string, string>> = {
  zh: dict_zh,
  'zh-Hant': dict_zhHant,
  en: dict_en,
  ja: dict_ja,
};

function isLang(v: unknown): v is Lang {
  return v === 'zh' || v === 'zh-Hant' || v === 'en' || v === 'ja';
}

function detectInitialLang(): Lang {
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (isLang(stored)) return stored;
  } catch {
    // localStorage 不可用（隐私模式 / SSR）：忽略，落入自动检测。
  }
  try {
    const navLang = (navigator.language || '').toLowerCase();
    if (navLang.startsWith('ja')) return 'ja';
    // 繁体中文：zh-Hant / zh-TW / zh-HK / zh-MO
    if (navLang.startsWith('zh')) {
      if (
        navLang.includes('hant') ||
        navLang.includes('-tw') ||
        navLang.includes('-hk') ||
        navLang.includes('-mo')
      ) {
        return 'zh-Hant';
      }
      return 'zh';
    }
    if (navLang.startsWith('en')) return 'en';
  } catch {
    // 非浏览器环境：忽略。
  }
  return 'zh';
}

// BCP 47 语言标记（供 <html lang> / 屏幕阅读器 / Intl API 使用）。
function toBcp47(lang: Lang): string {
  switch (lang) {
    case 'zh':
      return 'zh-Hans';
    case 'zh-Hant':
      return 'zh-Hant';
    case 'en':
      return 'en';
    case 'ja':
      return 'ja';
  }
}

let currentLang: Lang = detectInitialLang();
const listeners = new Set<(lang: Lang) => void>();

export function getLang(): Lang {
  return currentLang;
}

export function setLang(lang: Lang): void {
  if (!isLang(lang)) return;
  if (lang === currentLang) return;
  currentLang = lang;
  try {
    window.localStorage.setItem(STORAGE_KEY, lang);
  } catch {
    // 持久化失败不影响内存切换。
  }
  // 同步设置 <html lang> 便于浏览器 / 屏幕阅读器识别。
  try {
    document.documentElement.lang = toBcp47(lang);
  } catch {
    // 忽略：非浏览器环境。
  }
  for (const fn of listeners) {
    try {
      fn(lang);
    } catch {
      // 单个订阅者抛错不应影响其他订阅者。
    }
  }
}

export function subscribeLang(fn: (lang: Lang) => void): () => void {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

export function t(key: string, fallback?: string): string {
  const direct = dicts[currentLang][key];
  if (direct !== undefined) return direct;
  // 当前语言缺词：先回退到 zh（保证生产链路不出现裸 key）。
  const zh = dicts.zh[key];
  if (zh !== undefined) return zh;
  return fallback ?? key;
}

// 带占位符的翻译助手：词条中以 {name} 形式描述变量，
// 调用时传入 params 同名键即可。例：
//   t('ops.cleanup.result') === '{target} · 删除 {files} 个文件…'
//   tFmt('ops.cleanup.result', { target: 'all', files: 12, dirs: 3, bytes: '4.2 MB' })
// 同一占位可重复出现，所有同名位置都会被替换。
export function tFmt(key: string, params: Record<string, string | number>, fallback?: string): string {
  let template = t(key, fallback);
  for (const [k, v] of Object.entries(params)) {
    // 使用全局 split/join 避免 RegExp 转义 / 恶意输入带入的特殊字符。
    template = template.split(`{${k}}`).join(String(v));
  }
  return template;
}

// Preact hook：在组件中订阅当前语言，语言切换后自动重渲染。
export function useLang(): Lang {
  const [lang, setLangState] = useState<Lang>(currentLang);
  useEffect(() => {
    const off = subscribeLang((next) => setLangState(next));
    return off;
  }, []);
  return lang;
}

// 启动时立刻同步 <html lang>，便于浏览器加载首屏时即生效。
try {
  document.documentElement.lang = toBcp47(currentLang);
} catch {
  // 非浏览器环境：忽略。
}
