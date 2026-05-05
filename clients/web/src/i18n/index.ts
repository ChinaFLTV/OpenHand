// Web 端 i18n 入口。Stage 7+：四语词表 + Intl 全套（复数 / 数字 / 字节 / 日期 / 相对时间 / 时长）+ RTL 方向钩子。
//
// 设计要点：
// - dict_zh / dict_zhHant / dict_en / dict_ja 拆分为独立模块，键集合一一对应。
// - currentLang 维护在模块级，所有 t(key) 调用直接读取，无需 Context。
// - subscribe / setLang 通过简单的发布订阅触发 Preact 组件重渲染（useLang hook）。
// - 首次启动从 localStorage 读取，缺省时按浏览器 navigator.language 自动判断。
// - dict[key] 缺词时回退顺序：当前语言 → zh → 调用方 fallback → key 本身。
// - Intl 适配器（PluralRules / NumberFormat / DateTimeFormat / RelativeTimeFormat）
//   按 BCP-47 标签每语言一份并缓存，避免在每次渲染时重新构造。
// - RTL：当前 4 语全 LTR；通过 RTL_LANGS Set + dirOf() 钩子留好扩展点
//   （添加阿拉伯语 / 希伯来语时只需把 Lang 加入 RTL_LANGS 并在 setLang 同步 <html dir>）。

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

// 文字方向：当前 4 语全是 LTR；新增阿拉伯语 / 希伯来语时把 Lang 加入此 Set 即可。
const RTL_LANGS: ReadonlySet<Lang> = new Set<Lang>();
export function dirOf(lang: Lang): 'ltr' | 'rtl' {
  return RTL_LANGS.has(lang) ? 'rtl' : 'ltr';
}
export function getDir(): 'ltr' | 'rtl' {
  return dirOf(currentLang);
}

// Intl 适配器：每语言一份，懒构造、缓存复用。
type IntlBundle = {
  pluralRules: Intl.PluralRules;
  number: Intl.NumberFormat;
  relativeTime: Intl.RelativeTimeFormat;
  dateTime: Intl.DateTimeFormat;
  date: Intl.DateTimeFormat;
  time: Intl.DateTimeFormat;
};
const intlCache = new Map<Lang, IntlBundle>();
function intlOf(lang: Lang): IntlBundle {
  const cached = intlCache.get(lang);
  if (cached) return cached;
  const tag = toBcp47(lang);
  const bundle: IntlBundle = {
    pluralRules: new Intl.PluralRules(tag),
    number: new Intl.NumberFormat(tag),
    // numeric:'auto' 让 "今天 / 昨天" 自动取代 "0 天前 / 1 天前"。
    relativeTime: new Intl.RelativeTimeFormat(tag, { numeric: 'auto' }),
    dateTime: new Intl.DateTimeFormat(tag, { dateStyle: 'medium', timeStyle: 'medium' }),
    date: new Intl.DateTimeFormat(tag, { dateStyle: 'medium' }),
    time: new Intl.DateTimeFormat(tag, { timeStyle: 'medium', hour12: false }),
  };
  intlCache.set(lang, bundle);
  return bundle;
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
    // 同步 <html dir>，配合未来引入的 RTL 语言。
    document.documentElement.dir = dirOf(lang);
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
  return formatTemplate(t(key, fallback), params);
}

function formatTemplate(template: string, params: Record<string, string | number>): string {
  let out = template;
  for (const [k, v] of Object.entries(params)) {
    // 使用全局 split/join 避免 RegExp 转义 / 恶意输入带入的特殊字符。
    out = out.split(`{${k}}`).join(String(v));
  }
  return out;
}

// CLDR 复数：词条按子键存储，约定 `${key}.${cat}`，cat ∈ {zero,one,two,few,many,other}。
// 不存在精确分类时回退到 `${key}.other`，再回退到 zh 同结构，最后退化为 key 本身。
// `count` 自动注入 params，模板可用 {count} 引用。
export function tPlural(
  key: string,
  count: number,
  params: Record<string, string | number> = {},
): string {
  const cat = intlOf(currentLang).pluralRules.select(count);
  const composite = { count, ...params };
  for (const candidate of [`${key}.${cat}`, `${key}.other`]) {
    const direct = dicts[currentLang][candidate];
    if (direct !== undefined) return formatTemplate(direct, composite);
  }
  for (const candidate of [`${key}.${cat}`, `${key}.other`]) {
    const zh = dicts.zh[candidate];
    if (zh !== undefined) return formatTemplate(zh, composite);
  }
  return formatTemplate(key, composite);
}

// 数字：默认走当前语言的本地化分隔符；传入 opts 时（如 currency / percent）按需即时构造。
export function tNumber(value: number, opts?: Intl.NumberFormatOptions): string {
  if (!Number.isFinite(value)) return '—';
  if (opts) return new Intl.NumberFormat(toBcp47(currentLang), opts).format(value);
  return intlOf(currentLang).number.format(value);
}

// 字节智能格式：自动按 1024 进位选 B/KB/MB/GB/TB/PB，数字部分走 Intl.NumberFormat。
const BYTE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'] as const;
export function tBytes(bytes: number | null | undefined): string {
  if (bytes == null || !Number.isFinite(bytes)) return '—';
  const sign = bytes < 0 ? -1 : 1;
  let n = Math.abs(bytes);
  let unitIndex = 0;
  while (n >= 1024 && unitIndex < BYTE_UNITS.length - 1) {
    n /= 1024;
    unitIndex += 1;
  }
  const fractionDigits = unitIndex === 0 ? 0 : unitIndex >= 3 ? 2 : 1;
  const formatted = new Intl.NumberFormat(toBcp47(currentLang), {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(n * sign);
  return `${formatted} ${BYTE_UNITS[unitIndex]}`;
}

function toDate(v: Date | string | number | null | undefined): Date | null {
  if (v == null) return null;
  const dt = v instanceof Date ? v : new Date(v);
  return Number.isNaN(dt.getTime()) ? null : dt;
}

// 本地化日期 / 时间 / 日期时间。空值与非法输入统一返回 '—'。
export function tDate(d: Date | string | number | null | undefined): string {
  const dt = toDate(d);
  return dt ? intlOf(currentLang).date.format(dt) : '—';
}
export function tTime(d: Date | string | number | null | undefined): string {
  const dt = toDate(d);
  return dt ? intlOf(currentLang).time.format(dt) : '—';
}
export function tDateTime(d: Date | string | number | null | undefined): string {
  const dt = toDate(d);
  return dt ? intlOf(currentLang).dateTime.format(dt) : '—';
}

// 相对时间："3 分钟前 / 昨天 / 2 周后"。base 默认 now，便于注入测试时间。
export function tRelativeTime(d: Date | string | number, base: Date = new Date()): string {
  const dt = toDate(d);
  if (!dt) return '—';
  const diffMs = dt.getTime() - base.getTime();
  const abs = Math.abs(diffMs);
  const fmt = intlOf(currentLang).relativeTime;
  const SEC = 1000,
    MIN = 60 * SEC,
    HOUR = 60 * MIN,
    DAY = 24 * HOUR,
    WEEK = 7 * DAY,
    MONTH = 30 * DAY,
    YEAR = 365 * DAY;
  if (abs < MIN) return fmt.format(Math.round(diffMs / SEC), 'second');
  if (abs < HOUR) return fmt.format(Math.round(diffMs / MIN), 'minute');
  if (abs < DAY) return fmt.format(Math.round(diffMs / HOUR), 'hour');
  if (abs < WEEK) return fmt.format(Math.round(diffMs / DAY), 'day');
  if (abs < MONTH) return fmt.format(Math.round(diffMs / WEEK), 'week');
  if (abs < YEAR) return fmt.format(Math.round(diffMs / MONTH), 'month');
  return fmt.format(Math.round(diffMs / YEAR), 'year');
}

// 持续时长（ms → "1 天 2 时 3 分 4 秒" / "1d 2h 3m 4s"）。各单位文案从词表读取。
export function tDuration(ms: number): string {
  if (!Number.isFinite(ms)) return '—';
  if (ms < 1000) return `${tNumber(ms)} ${t('common.duration.millisecond')}`;
  let secs = Math.floor(ms / 1000);
  const days = Math.floor(secs / 86400);
  secs -= days * 86400;
  const hrs = Math.floor(secs / 3600);
  secs -= hrs * 3600;
  const mins = Math.floor(secs / 60);
  secs -= mins * 60;
  const parts: string[] = [];
  if (days) parts.push(`${days}${t('common.duration.day')}`);
  if (hrs) parts.push(`${hrs}${t('common.duration.hour')}`);
  if (mins) parts.push(`${mins}${t('common.duration.minute')}`);
  parts.push(`${secs}${t('common.duration.second')}`);
  return parts.join(' ');
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

// 启动时立刻同步 <html lang> / <html dir>，便于浏览器加载首屏时即生效。
try {
  document.documentElement.lang = toBcp47(currentLang);
  document.documentElement.dir = dirOf(currentLang);
} catch {
  // 非浏览器环境：忽略。
}
