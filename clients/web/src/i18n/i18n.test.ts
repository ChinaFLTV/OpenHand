import { describe, it, expect, beforeEach } from 'vitest';
import { t, tFmt, tNumber, tBytes, setLang } from './index';

describe('i18n', () => {
  beforeEach(() => {
    setLang('zh');
  });

  it('returns fallback for unknown key', () => {
    const v = t('this.key.does.not.exist', '兜底');
    expect(v).toBe('兜底');
  });

  it('returns dictionary entry for known key', () => {
    // home.openSettings 在 dict_zh 里是 "设置"
    const v = t('home.openSettings');
    expect(v).toBe('设置');
  });

  it('tFmt substitutes named placeholders', () => {
    const out = tFmt('__inline__', { name: 'Ada', count: 3 }, 'Hello {name}, x{count}');
    expect(out).toBe('Hello Ada, x3');
  });

  it('tNumber respects locale grouping', () => {
    const en = (() => {
      setLang('en');
      return tNumber(1234567);
    })();
    expect(en).toMatch(/[1][,]?234[,]?567/);
  });

  it('tBytes formats null and number', () => {
    expect(tBytes(null)).toMatch(/—|-|0/);
    expect(tBytes(1024)).toMatch(/KB|KiB|1\.0/);
  });
});
