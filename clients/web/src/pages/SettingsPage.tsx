// SettingsPage —— 远程修改本机 OpenHand 的核心偏好。
//
// 字段范围严格限定在 _getPreferencesHandler 暴露的白名单:
// reduce_motion / language / ai_message_compression_threshold_chars；
// dialog_animation_settings 只读同步 App 端弹窗动效。
// 其余设置必须在 App 端改，避免 Web 误改影响本机正在跑的会话。

import type { ComponentChildren } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { TopBar } from '../components/TopBar';
import { Appear } from '../components/Appear';
import { MenuSelect } from '../components/MenuSelect';
import { ApiError } from '../api/client';
import {
  fetchPreferences,
  updatePreferences,
  type PreferencesUpdate,
  type RemotePreferences,
} from '../api/preferences';
import { t, tNumber } from '../i18n';
import { setRemoteReducedMotion } from '../hooks/useReducedMotion';
import { syncRemoteDialogMotionSettings } from '../hooks/useDialogMotionSettings';
import { showSnackbar } from '../components/Snackbar';

const LANG_LABEL: Record<string, string> = {
  zh_Hans: '简体中文',
  zh_Hant: '繁體中文',
  en: 'English',
  fr: 'Français',
  de: 'Deutsch',
  ja: '日本語',
};

const MOTION_STYLE_LABEL: Record<string, string> = {
  none: '无',
  fade: '淡入淡出',
  fade_scale: '淡入缩放',
  slide_up: '上滑',
  slide_down: '下滑',
  slide_left: '左滑',
  slide_right: '右滑',
  expand: '展开',
  rotate_scale: '旋转缩放',
  elastic: '弹性',
  spring_scale: '弹簧缩放',
  flip_x: '翻转',
};

const MOTION_CURVE_LABEL: Record<string, string> = {
  ease_in_out: '标准缓入缓出',
  ease_out: '缓出',
  ease_out_cubic: '三次缓出',
  ease_in_out_cubic_emphasized: '强调缓动',
  elastic_out: '弹性缓出',
  bounce_out: '回弹缓出',
  decelerate: '减速',
};

function describeApiError(err: unknown): string {
  if (err instanceof ApiError) {
    const body = err.body as { error?: string } | null;
    return `HTTP ${err.status}${body?.error ? ` (${body.error})` : ''}`;
  }
  if (err instanceof Error) return err.message;
  return String(err);
}

function languageLabel(code: string): string {
  return LANG_LABEL[code] ?? code;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function normalizedThreshold(input: string, prefs: RemotePreferences): number | null {
  const parsed = parseInt(input, 10);
  if (Number.isNaN(parsed)) return null;
  const min = prefs.limits.ai_message_compression_threshold_chars_min;
  const max = prefs.limits.ai_message_compression_threshold_chars_max;
  return clamp(parsed, min, max);
}

function thresholdPercent(prefs: RemotePreferences, value: number): string {
  const min = prefs.limits.ai_message_compression_threshold_chars_min;
  const max = prefs.limits.ai_message_compression_threshold_chars_max;
  if (max <= min) return '0%';
  const percent = ((clamp(value, min, max) - min) / (max - min)) * 100;
  return `${clamp(Math.round(percent), 0, 100)}%`;
}

function motionStyleLabel(value: string | undefined): string {
  if (!value) return t('settings.motion.default', '跟随默认');
  return MOTION_STYLE_LABEL[value] ?? value;
}

function motionCurveLabel(value: string | undefined): string {
  if (!value) return t('settings.motion.default', '跟随默认');
  return MOTION_CURVE_LABEL[value] ?? value;
}

export function SettingsPage() {
  const [prefs, setPrefs] = useState<RemotePreferences | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [savedSignal, setSavedSignal] = useState(0);
  const [saveError, setSaveError] = useState<string | null>(null);

  const [thresholdInput, setThresholdInput] = useState('');
  const applyPreferences = (next: RemotePreferences) => {
    setPrefs(next);
    setRemoteReducedMotion(next.reduce_motion);
    syncRemoteDialogMotionSettings(next.dialog_animation_settings);
    setThresholdInput(String(next.ai_message_compression_threshold_chars));
  };

  useEffect(() => {
    let stop = false;
    setLoading(true);
    fetchPreferences()
      .then((next) => {
        if (stop) return;
        applyPreferences(next);
      })
      .catch((err) => {
        if (!stop) setLoadError(describeApiError(err));
      })
      .finally(() => {
        if (!stop) setLoading(false);
      });
    return () => {
      stop = true;
    };
  }, []);

  useEffect(() => {
    if (savedSignal <= 0) return undefined;
    const timer = window.setTimeout(() => setSavedSignal(0), 1600);
    return () => window.clearTimeout(timer);
  }, [savedSignal]);

  const refresh = async () => {
    setLoading(true);
    setLoadError(null);
    try {
      const next = await fetchPreferences();
      applyPreferences(next);
      showSnackbar(t('settings.refresh.ok', '设置已刷新'), { tone: 'success' });
    } catch (err) {
      const message = describeApiError(err);
      setLoadError(message);
      showSnackbar(`${t('settings.refresh.failed', '刷新设置失败')}：${message}`, { tone: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const commit = async (key: string, update: PreferencesUpdate) => {
    setSavingKey(key);
    setSaveError(null);
    try {
      const next = await updatePreferences(update);
      applyPreferences(next);
      setSavedSignal((signal) => signal + 1);
      showSnackbar(t('settings.saved', '已保存'), { tone: 'success' });
    } catch (err) {
      const message = describeApiError(err);
      setSaveError(message);
      showSnackbar(`${t('settings.save.failed', '保存设置失败')}：${message}`, { tone: 'error' });
    } finally {
      setSavingKey(null);
    }
  };

  const thresholdValue = prefs
    ? normalizedThreshold(thresholdInput, prefs) ?? prefs.ai_message_compression_threshold_chars
    : 0;
  const languageOptions = prefs?.language_options.map((code) => ({
    value: code,
    label: languageLabel(code),
    description: code,
  })) ?? [];

  return (
    <main class="oh-settings-page min-h-screen p-4 sm:p-6">
      <div class="max-w-7xl mx-auto">
        <TopBar
          title={t('settings.title', '偏好设置')}
          subtitle={t('settings.subtitle', '远程调整本机 OpenHand 的核心偏好')}
          actionSlot={(
            <button
              type="button"
              onClick={() => void refresh()}
              disabled={loading || savingKey != null}
              class="oh-tap-press oh-topbar-action text-sm rounded-m3-sm px-3 py-1.5"
            >
              {loading ? t('common.loading', '加载中…') : t('common.refresh', '刷新')}
            </button>
          )}
        />

        <div class="oh-settings-shell">
          <aside class="oh-settings-sidebar">
            <Appear variant="up" index={0}>
              <section class="oh-settings-summary-card">
                <p class="oh-settings-eyebrow">{t('settings.overview', '偏好概览')}</p>
                <h2>{prefs ? t('settings.synced', '已连接本机偏好') : t('common.loading', '加载中…')}</h2>
                <div class="oh-settings-summary-list">
                  <SummaryLine
                    label={t('settings.language.title', '界面语言')}
                    value={prefs ? languageLabel(prefs.language_storage_value) : '-'}
                  />
                  <SummaryLine
                    label={t('settings.reduceMotion.title', '减少动画')}
                    value={prefs?.reduce_motion ? t('common.on', '开') : t('common.off', '关')}
                  />
                  <SummaryLine
                    label={t('settings.memory.title', '记忆注入')}
                    value={prefs?.memory_enabled ? t('common.on', '开') : t('common.off', '关')}
                  />
                  <SummaryLine
                    label={t('settings.compress.short', '压缩阈值')}
                    value={prefs ? tNumber(prefs.ai_message_compression_threshold_chars) : '-'}
                  />
                </div>
              </section>
            </Appear>

            <Appear variant="up">
              <section class="oh-settings-boundary-card">
                <p class="oh-settings-eyebrow">{t('settings.boundary.title', '远程设置边界')}</p>
                <p>
                  {t(
                    'settings.boundary.body',
                    'Web 端只开放轻量偏好。模型、工具、网关、安全策略等会影响本机会话运行的配置仍在 App 端管理。',
                  )}
                </p>
              </section>
            </Appear>
          </aside>

          <section class="oh-settings-stack">
            {loadError ? <StatusBanner tone="error">{loadError}</StatusBanner> : null}
            {savedSignal > 0 ? (
              <StatusBanner tone="success">✓ {t('settings.saved', '已保存')}</StatusBanner>
            ) : null}
            {saveError ? <StatusBanner tone="error">{saveError}</StatusBanner> : null}

            {loading && prefs == null ? (
              <div class="oh-settings-empty-card">{t('common.loading', '加载中…')}</div>
            ) : null}

            {prefs ? (
              <>
                <Appear variant="up">
                  <SettingRow
                    title={t('settings.reduceMotion.title', '减少动画')}
                    description={t('settings.reduceMotion.desc', '关闭路由 / 弹窗 / 列表入场过渡动画。OS 的 Reduce Motion 设置仍然生效。')}
                    meta={<SavingPill active={savingKey === 'reduce_motion'} value={prefs.reduce_motion ? t('common.on', '开') : t('common.off', '关')} />}
                  >
                    <label class="oh-settings-switch">
                      <input
                        type="checkbox"
                        checked={prefs.reduce_motion}
                        disabled={savingKey === 'reduce_motion'}
                        onChange={(event) => void commit('reduce_motion', { reduce_motion: (event.currentTarget as HTMLInputElement).checked })}
                      />
                      <span class="oh-settings-switch-track"><span /></span>
                      <span class="oh-settings-control-label">
                        {prefs.reduce_motion ? t('common.on', '开') : t('common.off', '关')}
                      </span>
                    </label>
                  </SettingRow>
                </Appear>

                <Appear variant="up">
                  <SettingRow
                    title={t('settings.language.title', '界面语言')}
                    description={t('settings.language.desc', 'Web / App 共用同一个语言，修改后立即生效，后续会话沿用此语言。')}
                    meta={<SavingPill active={savingKey === 'language_storage_value'} value={prefs.locale} />}
                  >
                    <div class="oh-settings-control-row">
                      <MenuSelect
                        value={prefs.language_storage_value}
                        onChange={(next) => void commit('language_storage_value', { language_storage_value: next })}
                        options={languageOptions}
                        minWidth={190}
                        disabled={savingKey === 'language_storage_value'}
                        ariaLabel={t('settings.language.title', '界面语言')}
                      />
                      <span class="oh-settings-inline-note">{prefs.language_storage_value}</span>
                    </div>
                  </SettingRow>
                </Appear>

                <Appear variant="up">
                  <SettingRow
                    title={t('settings.compress.title', '消息压缩阈值 (字符)')}
                    description={t('settings.compress.desc', '单条历史消息超过该阈值后，会在送入模型前压缩。最小 2,000，最大 1,000,000。')}
                    meta={<SavingPill active={savingKey === 'ai_message_compression_threshold_chars'} value={tNumber(prefs.ai_message_compression_threshold_chars)} />}
                  >
                    <div class="oh-settings-slider-row">
                      <input
                        type="range"
                        class="oh-settings-range"
                        min={prefs.limits.ai_message_compression_threshold_chars_min}
                        max={prefs.limits.ai_message_compression_threshold_chars_max}
                        step={500}
                        value={thresholdValue}
                        disabled={savingKey === 'ai_message_compression_threshold_chars'}
                        onInput={(event) => setThresholdInput((event.currentTarget as HTMLInputElement).value)}
                        onChange={(event) => {
                          const next = normalizedThreshold((event.currentTarget as HTMLInputElement).value, prefs);
                          if (next != null) void commit('ai_message_compression_threshold_chars', { ai_message_compression_threshold_chars: next });
                        }}
                      />
                      <input
                        type="number"
                        class="oh-settings-number"
                        value={thresholdInput}
                        disabled={savingKey === 'ai_message_compression_threshold_chars'}
                        onInput={(event) => setThresholdInput((event.currentTarget as HTMLInputElement).value)}
                        onBlur={() => {
                          const next = normalizedThreshold(thresholdInput, prefs);
                          if (next != null && next !== prefs.ai_message_compression_threshold_chars) {
                            void commit('ai_message_compression_threshold_chars', { ai_message_compression_threshold_chars: next });
                          } else {
                            setThresholdInput(String(prefs.ai_message_compression_threshold_chars));
                          }
                        }}
                        onKeyDown={(event) => {
                          if (event.key === 'Enter') (event.currentTarget as HTMLInputElement).blur();
                        }}
                      />
                    </div>
                    <div class="oh-settings-meter" aria-hidden="true">
                      <span style={{ width: thresholdPercent(prefs, thresholdValue) }} />
                    </div>
                    <div class="oh-settings-range-meta">
                      <span>{tNumber(prefs.limits.ai_message_compression_threshold_chars_min)}</span>
                      <span>{tNumber(prefs.limits.ai_message_compression_threshold_chars_max)}</span>
                    </div>
                  </SettingRow>
                </Appear>

                <Appear variant="up">
                  <SettingRow
                    title={t('settings.memory.title', '记忆注入')}
                    description={t('settings.memory.desc', '当前模式 (只读)。修改请使用 App 端开关。')}
                    meta={<span class="oh-settings-readonly-pill">{t('settings.readonly', '只读')}</span>}
                  >
                    <span class={`oh-settings-state-pill${prefs.memory_enabled ? ' is-on' : ''}`}>
                      {prefs.memory_enabled ? t('common.on', '开') : t('common.off', '关')}
                    </span>
                  </SettingRow>
                </Appear>

                <Appear variant="up">
                  <SettingRow
                    title={t('settings.motion.title', '弹窗动效')}
                    description={t('settings.motion.desc', '当前 App 端弹窗动效同步到 Web 端使用，此处仅展示。')}
                    meta={<span class="oh-settings-readonly-pill">{t('settings.readonly', '只读')}</span>}
                  >
                    <div class="oh-settings-motion-grid">
                      <SummaryLine
                        label={t('settings.motion.enter', '进入')}
                        value={motionStyleLabel(prefs.dialog_animation_settings?.entrance_style)}
                      />
                      <SummaryLine
                        label={t('settings.motion.exit', '退出')}
                        value={motionStyleLabel(prefs.dialog_animation_settings?.exit_style)}
                      />
                      <SummaryLine
                        label={t('settings.motion.duration', '时长')}
                        value={`${prefs.dialog_animation_settings?.duration_ms ?? 320} ms`}
                      />
                      <SummaryLine
                        label={t('settings.motion.curve', '曲线')}
                        value={motionCurveLabel(prefs.dialog_animation_settings?.curve)}
                      />
                    </div>
                  </SettingRow>
                </Appear>
              </>
            ) : null}
          </section>
        </div>
      </div>
    </main>
  );
}

function StatusBanner(props: { tone: 'success' | 'error'; children: ComponentChildren }) {
  return (
    <div class={`oh-settings-status is-${props.tone}${props.tone === 'success' ? ' oh-pulse-soft' : ''}`}>
      {props.children}
    </div>
  );
}

function SummaryLine(props: { label: string; value: ComponentChildren }) {
  return (
    <div class="oh-settings-summary-line">
      <span>{props.label}</span>
      <strong>{props.value}</strong>
    </div>
  );
}

function SavingPill(props: { active: boolean; value: ComponentChildren }) {
  return (
    <span class={`oh-settings-saving-pill${props.active ? ' is-saving' : ''}`}>
      {props.active ? t('settings.saving', '保存中…') : props.value}
    </span>
  );
}

function SettingRow(props: {
  title: string;
  description: string;
  meta?: ComponentChildren;
  children: ComponentChildren;
}) {
  return (
    <section class="oh-settings-card">
      <div class="oh-settings-card-head">
        <div class="min-w-0">
          <h3>{props.title}</h3>
          <p>{props.description}</p>
        </div>
        {props.meta ? <div class="oh-settings-card-meta">{props.meta}</div> : null}
      </div>
      <div class="oh-settings-card-body">
        {props.children}
      </div>
    </section>
  );
}
