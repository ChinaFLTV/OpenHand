// SettingsPage —— 远程修改本机 OpenHand 的核心偏好。
//
// 字段范围严格限定在 _getPreferencesHandler 暴露的白名单:
// reduce_motion / language / ai_message_compression_threshold_chars。
// 其余设置必须在 App 端改 (避免 Web 误改影响本机正在跑的会话)。
//
// UI 规范:
// - 每个 row 自己保存自己, 失败回滚, 顶部红条横幅 + Body 内 inline 提示。
// - 滑杆使用 input[type=range] + 数字输入框双绑定。
// - 保存成功用 oh-pulse-soft 横幅高亮, 1.6 秒自动消失。

import { useEffect, useRef, useState } from 'preact/hooks';
import { TopBar } from '../components/TopBar';
import { Appear } from '../components/Appear';
import { ApiError } from '../api/client';
import {
  PreferencesUpdate,
  RemotePreferences,
  fetchPreferences,
  updatePreferences,
} from '../api/preferences';
import { t, tNumber } from '../i18n';

const LANG_LABEL: Record<string, string> = {
  zh_Hans: '简体中文',
  zh_Hant: '繁體中文',
  en: 'English',
  fr: 'Français',
  de: 'Deutsch',
  ja: '日本語',
};

function describeApiError(err: unknown): string {
  if (err instanceof ApiError) {
    const body = err.body as { error?: string } | null;
    return `HTTP ${err.status}${body?.error ? ` (${body.error})` : ''}`;
  }
  if (err instanceof Error) return err.message;
  return String(err);
}

export function SettingsPage() {
  const [prefs, setPrefs] = useState<RemotePreferences | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [savedSignal, setSavedSignal] = useState(0);
  const [saveError, setSaveError] = useState<string | null>(null);

  // 数字输入临时态: 编辑过程允许 unparsable 文本, 仅在确认时归一化。
  const [thresholdInput, setThresholdInput] = useState('');
  const thresholdInitialized = useRef(false);

  useEffect(() => {
    let stop = false;
    fetchPreferences()
      .then((p) => {
        if (stop) return;
        setPrefs(p);
        if (!thresholdInitialized.current) {
          setThresholdInput(String(p.ai_message_compression_threshold_chars));
          thresholdInitialized.current = true;
        }
      })
      .catch((err) => {
        if (!stop) setLoadError(describeApiError(err));
      });
    return () => {
      stop = true;
    };
  }, []);

  const commit = async (key: string, update: PreferencesUpdate) => {
    setSavingKey(key);
    setSaveError(null);
    try {
      const next = await updatePreferences(update);
      setPrefs(next);
      setThresholdInput(String(next.ai_message_compression_threshold_chars));
      setSavedSignal((s) => s + 1);
    } catch (err) {
      setSaveError(describeApiError(err));
    } finally {
      setSavingKey(null);
    }
  };

  return (
    <main
      class="min-h-screen"
      style={{ background: 'var(--m3-background)', color: 'var(--m3-on-surface)' }}
    >
      <TopBar
        title={t('settings.title', '偏好设置')}
        subtitle={t('settings.subtitle', '远程调整本机 OpenHand 的核心偏好')}
      />

      <div class="max-w-3xl mx-auto px-4 py-6 space-y-4">
        {loadError ? (
          <div
            class="rounded-m3-md px-3 py-2 text-sm"
            style={{
              background: 'rgba(239,68,68,0.08)',
              color: 'var(--m3-error)',
              border: '1px solid rgba(239,68,68,0.30)',
            }}
          >
            {loadError}
          </div>
        ) : null}

        {savedSignal > 0 ? (
          <div
            key={savedSignal}
            class="rounded-m3-md px-3 py-2 text-sm oh-pulse-soft"
            style={{
              background: 'rgba(22,163,74,0.10)',
              color: '#16a34a',
              border: '1px solid rgba(22,163,74,0.30)',
            }}
          >
            ✓ {t('settings.saved', '已保存')}
          </div>
        ) : null}

        {saveError ? (
          <div
            class="rounded-m3-md px-3 py-2 text-sm"
            style={{
              background: 'rgba(239,68,68,0.08)',
              color: 'var(--m3-error)',
              border: '1px solid rgba(239,68,68,0.30)',
            }}
          >
            {saveError}
          </div>
        ) : null}

        {prefs == null && !loadError ? (
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {t('common.loading', '加载中…')}
          </p>
        ) : prefs ? (
          <>
            <Appear variant="up" index={0}>
              <SettingRow
                title={t('settings.reduceMotion.title', '减少动画')}
                description={t('settings.reduceMotion.desc', '关闭路由 / 弹窗 / 列表入场过渡动画。OS 的 Reduce Motion 设置仍然生效。')}
              >
                <label class="inline-flex items-center gap-2 cursor-pointer text-sm">
                  <input
                    type="checkbox"
                    checked={prefs.reduce_motion}
                    disabled={savingKey === 'reduce_motion'}
                    onChange={(e) => commit('reduce_motion', { reduce_motion: (e.currentTarget as HTMLInputElement).checked })}
                  />
                  <span>{prefs.reduce_motion ? t('common.on', '开') : t('common.off', '关')}</span>
                </label>
              </SettingRow>
            </Appear>

            <Appear variant="up" index={1}>
              <SettingRow
                title={t('settings.language.title', '界面语言')}
                description={t('settings.language.desc', 'Web / App 共用同一个语言, 修改后立即生效, 后续会话沿用此语言。')}
              >
                <select
                  class="rounded-m3-sm px-2 py-1 text-sm"
                  style={{
                    background: 'var(--m3-surface-container-high)',
                    color: 'var(--m3-on-surface)',
                    border: '1px solid var(--m3-outline-variant)',
                  }}
                  value={prefs.language_storage_value}
                  disabled={savingKey === 'language_storage_value'}
                  onChange={(e) => commit('language_storage_value', { language_storage_value: (e.currentTarget as HTMLSelectElement).value })}
                >
                  {prefs.language_options.map((code) => (
                    <option key={code} value={code}>
                      {LANG_LABEL[code] ?? code}
                    </option>
                  ))}
                </select>
              </SettingRow>
            </Appear>

            <Appear variant="up" index={2}>
              <SettingRow
                title={t('settings.compress.title', '消息压缩阈值 (字符)')}
                description={t('settings.compress.desc', '单条历史消息超过该阈值后, 会在送入模型前压缩。最小 2,000, 最大 1,000,000。')}
              >
                <div class="flex items-center gap-3">
                  <input
                    type="range"
                    min={prefs.limits.ai_message_compression_threshold_chars_min}
                    max={prefs.limits.ai_message_compression_threshold_chars_max}
                    step={500}
                    value={prefs.ai_message_compression_threshold_chars}
                    disabled={savingKey === 'ai_message_compression_threshold_chars'}
                    style={{ flex: 1 }}
                    onInput={(e) => setThresholdInput((e.currentTarget as HTMLInputElement).value)}
                    onChange={(e) => {
                      const v = parseInt((e.currentTarget as HTMLInputElement).value, 10);
                      if (!Number.isNaN(v)) commit('ai_message_compression_threshold_chars', { ai_message_compression_threshold_chars: v });
                    }}
                  />
                  <input
                    type="number"
                    class="rounded-m3-sm px-2 py-1 text-sm"
                    style={{
                      width: 110,
                      background: 'var(--m3-surface-container-high)',
                      color: 'var(--m3-on-surface)',
                      border: '1px solid var(--m3-outline-variant)',
                      fontFamily: 'var(--font-mono)',
                    }}
                    value={thresholdInput}
                    disabled={savingKey === 'ai_message_compression_threshold_chars'}
                    onInput={(e) => setThresholdInput((e.currentTarget as HTMLInputElement).value)}
                    onBlur={() => {
                      const v = parseInt(thresholdInput, 10);
                      if (!Number.isNaN(v) && v !== prefs.ai_message_compression_threshold_chars) {
                        commit('ai_message_compression_threshold_chars', { ai_message_compression_threshold_chars: v });
                      } else {
                        // 复位非法输入
                        setThresholdInput(String(prefs.ai_message_compression_threshold_chars));
                      }
                    }}
                  />
                </div>
                <p class="text-[11px] mt-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
                  {t('settings.compress.current', '当前值')}: {tNumber(prefs.ai_message_compression_threshold_chars)}
                </p>
              </SettingRow>
            </Appear>

            <Appear variant="up" index={3}>
              <SettingRow
                title={t('settings.memory.title', '记忆注入')}
                description={t('settings.memory.desc', '当前模式 (只读). 修改请使用 App 端开关。')}
              >
                <span
                  class="text-xs px-2 py-0.5 rounded-m3-xs"
                  style={{
                    background: prefs.memory_enabled ? 'rgba(22,163,74,0.10)' : 'rgba(120,120,120,0.10)',
                    color: prefs.memory_enabled ? '#16a34a' : 'var(--m3-on-surface-variant)',
                  }}
                >
                  {prefs.memory_enabled ? t('common.on', '开') : t('common.off', '关')}
                </span>
              </SettingRow>
            </Appear>
          </>
        ) : null}
      </div>
    </main>
  );
}

function SettingRow(props: { title: string; description: string; children: preact.ComponentChildren }) {
  return (
    <section
      class="rounded-m3-md p-4"
      style={{
        background: 'var(--m3-surface-container)',
        border: '1px solid var(--m3-outline-variant)',
      }}
    >
      <h3 class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface)' }}>{props.title}</h3>
      <p class="text-xs mt-1 mb-3 leading-relaxed" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {props.description}
      </p>
      {props.children}
    </section>
  );
}
