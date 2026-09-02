import type { ComponentChildren } from 'preact';
import { StatusBanner } from '../../../components/StatusBanner';
import { useEffect, useState } from 'preact/hooks';
import { TopBar } from '../../../components/TopBar';
import { Appear } from '../../../components/Appear';
import { MenuSelect } from '../../../components/MenuSelect';
import {
  fetchPreferences,
  updatePreferences,
  type PreferencesUpdate,
  type RemotePreferences,
} from '../api/preferences';
import { t, tNumber } from '../../../i18n';
import { setRemoteReducedMotion } from '../../../hooks/useReducedMotion';
import {
  useMessageContentFormat,
  setMessageContentFormat,
  setHtmlRenderFallback,
} from '../../../hooks/useMessageContentFormat';
import {
  MIMO_DEFAULT_AUDIO_FORMAT,
  normalizeTtsSettings,
  saveTtsSettings,
  stopTtsPlayback,
  testTtsProvider,
  type TtsProvider,
  type TtsProviderSettings,
  type TtsSettings,
  useTtsSettings,
} from '../../../hooks/useTtsSettings';
import {
  DIALOG_MOTION_DEFAULT_DURATION_MS,
  syncRemoteDialogMotionSettings,
} from '../../../hooks/useDialogMotionSettings';
import { useTransientFlag } from '../../../hooks/useTransientFlag';
import { showSnackbar } from '../../../components/Snackbar';
import { clampNumber, finiteNumberFromText } from '../../../shared/util/number';
import { truncateEndText } from '../../../shared/util/text';
import { finiteNumberOrNullFromUnknown } from '../../../shared/util/value';
import { describeApiError } from '../../../utils/api_error';

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

function languageLabel(code: string): string {
  return LANG_LABEL[code] ?? code;
}

function ttsLanguageLabel(value: string): string | null {
  switch (value.trim()) {
    case 'zh':
    case 'zh-CN':
    case 'zh-CHS':
      return t('settings.language.simplifiedChinese', '简体中文');
    case 'zh-TW':
      return t('settings.language.traditionalChinese', '繁體中文');
    case 'en':
      return t('settings.language.english', 'English');
    case 'en-US':
      return t('settings.language.englishUs', '英语（美国）');
    case 'en-GB':
      return t('settings.language.englishUk', '英语（英国）');
    case 'ja':
    case 'ja-JP':
      return t('settings.language.japanese', '日语');
    case 'ko':
    case 'ko-KR':
      return t('settings.language.korean', '韩语');
    case 'fr':
    case 'fr-FR':
      return t('settings.language.french', '法语');
    case 'de':
    case 'de-DE':
      return t('settings.language.german', '德语');
    case 'es':
      return t('settings.language.spanish', '西班牙语');
    case 'ru':
      return t('settings.language.russian', '俄语');
    default:
      return null;
  }
}

function stripTrailingLanguageCode(label: string): string {
  return label
    .replace(/\s+(?:[a-z]{2,3}(?:-[A-Z]{2,4})?|zh-[A-Z]{2,4})$/, '')
    .trim();
}

function localizedVoiceLabel(label: string): string {
  const trimmed = label.trim();
  if (trimmed === '自动匹配系统默认音色') {
    return t('settings.tts.voice.autoSystem', '自动匹配系统默认音色');
  }
  if (trimmed === '有道默认发音人') {
    return t('settings.tts.voice.youdaoDefault', '有道默认发音人');
  }
  const suffixes: Array<[string, string]> = [
    ['English Female', t('settings.tts.voice.englishFemale', '英语女声')],
    ['English Male', t('settings.tts.voice.englishMale', '英语男声')],
    ['English', t('settings.tts.voice.english', '英语')],
    ['中文女声', t('settings.tts.voice.chineseFemale', '中文女声')],
    ['中文男声', t('settings.tts.voice.chineseMale', '中文男声')],
    ['繁中女声', t('settings.tts.voice.traditionalChineseFemale', '繁体中文女声')],
    ['日本語', t('settings.tts.voice.japanese', '日语')],
    ['女声', t('settings.tts.voice.female', '女声')],
    ['男声', t('settings.tts.voice.male', '男声')],
    ['童声', t('settings.tts.voice.child', '童声')],
  ];
  for (const [suffix, localized] of suffixes) {
    const marker = ` - ${suffix}`;
    if (trimmed.endsWith(marker)) {
      const prefix = trimmed.slice(0, -marker.length).trim();
      return prefix ? `${prefix} - ${localized}` : localized;
    }
  }
  return stripTrailingLanguageCode(trimmed);
}

function displayTtsOptionLabel(option: TtsCatalogOption): string {
  return ttsLanguageLabel(option.value) ?? localizedVoiceLabel(option.label);
}

function displayCurrentTtsValue(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return t('settings.tts.default', '默认');
  const language = ttsLanguageLabel(trimmed);
  if (language) return language;
  const humanized = trimmed
    .replace(/^(?:zh-CN|zh-TW|en-US|en-GB|ja-JP|ko-KR|fr-FR|de-DE|[a-z]{2})[-_]/i, '')
    .replace(/[_-]+/g, ' ')
    .replace(/\bbigtts\b/gi, '')
    .replace(/\s+/g, ' ')
    .trim();
  return localizedVoiceLabel(humanized || trimmed);
}

function normalizedThreshold(input: string, prefs: RemotePreferences): number | null {
  const parsed = finiteNumberOrNullFromUnknown(input);
  if (parsed == null) return null;
  const min = prefs.limits.ai_message_compression_threshold_chars_min;
  const max = prefs.limits.ai_message_compression_threshold_chars_max;
  return Math.round(clampNumber(parsed, min, max));
}

function thresholdPercent(prefs: RemotePreferences, value: number): string {
  const min = prefs.limits.ai_message_compression_threshold_chars_min;
  const max = prefs.limits.ai_message_compression_threshold_chars_max;
  if (max <= min) return '0%';
  const percent = ((clampNumber(value, min, max) - min) / (max - min)) * 100;
  return `${clampNumber(Math.round(percent), 0, 100)}%`;
}

function motionStyleLabel(value: string | undefined): string {
  if (!value) return t('settings.motion.default', '跟随默认');
  return MOTION_STYLE_LABEL[value] ?? value;
}

function motionCurveLabel(value: string | undefined): string {
  if (!value) return t('settings.motion.default', '跟随默认');
  return MOTION_CURVE_LABEL[value] ?? value;
}

function messageFormatLabel(value: 'markdown' | 'plain_text' | 'html'): string {
  if (value === 'plain_text') return t('settings.messageContentFormat.plainText', '纯文本');
  if (value === 'html') return t('settings.messageContentFormat.html', 'HTML');
  return t('settings.messageContentFormat.markdown', 'Markdown');
}

function htmlFallbackLabel(value: 'markdown' | 'plain_text'): string {
  if (value === 'plain_text') return t('settings.messageContentFormat.plainText', '纯文本');
  return t('settings.messageContentFormat.markdown', 'Markdown');
}

interface TtsCatalogOption {
  value: string;
  label: string;
}

interface TtsProviderCatalog {
  voices: TtsCatalogOption[];
  languages: TtsCatalogOption[];
  resourceIds?: TtsCatalogOption[];
  models?: TtsCatalogOption[];
  formats?: TtsCatalogOption[];
}

const COMMON_TTS_LANGUAGES: TtsCatalogOption[] = [
  { value: 'zh-CN', label: '简体中文 zh-CN' },
  { value: 'zh-TW', label: '繁体中文 zh-TW' },
  { value: 'en-US', label: 'English en-US' },
  { value: 'en-GB', label: 'English en-GB' },
  { value: 'ja-JP', label: '日本語 ja-JP' },
  { value: 'ko-KR', label: '한국어 ko-KR' },
  { value: 'fr-FR', label: 'Français fr-FR' },
  { value: 'de-DE', label: 'Deutsch de-DE' },
];

const BROWSER_SYSTEM_VOICES: TtsCatalogOption[] = [
  { value: '', label: '自动匹配系统默认音色' },
  { value: 'Tingting', label: 'macOS Tingting' },
  { value: 'Sin-ji', label: 'macOS Sin-ji' },
  { value: 'Mei-Jia', label: 'macOS Mei-Jia' },
  { value: 'Samantha', label: 'macOS Samantha' },
  { value: 'Microsoft Xiaoxiao', label: 'Windows Xiaoxiao' },
  { value: 'Microsoft Yunxi', label: 'Windows Yunxi' },
  { value: 'Google 普通话', label: 'Chrome 普通话' },
];

const TTS_PROVIDER_CATALOG: Record<TtsProvider, TtsProviderCatalog> = {
  system: {
    voices: BROWSER_SYSTEM_VOICES,
    languages: COMMON_TTS_LANGUAGES,
  },
  apple: {
    voices: BROWSER_SYSTEM_VOICES,
    languages: COMMON_TTS_LANGUAGES,
  },
  xfyun: {
    voices: [
      { value: 'xiaoyan', label: '讯飞小燕 - 女声' },
      { value: 'aisjiuxu', label: '讯飞许久 - 男声' },
      { value: 'aisxping', label: '讯飞小萍 - 女声' },
      { value: 'aisjinger', label: '讯飞小婧 - 女声' },
      { value: 'aisbabyxu', label: '讯飞许小宝 - 童声' },
      { value: 'x2_xiaoyan', label: '讯飞小燕 2.0 - 女声' },
      { value: 'x2_xiaofeng', label: '讯飞小峰 2.0 - 男声' },
    ],
    languages: [{ value: 'zh-CN', label: '中文 zh-CN' }],
    formats: [
      { value: 'lame', label: 'MP3 (lame)' },
      { value: 'raw', label: 'PCM raw' },
    ],
  },
  youdao: {
    voices: [
      { value: '', label: '有道默认发音人' },
      { value: '0', label: '女声' },
      { value: '1', label: '男声' },
    ],
    languages: [
      { value: 'zh-CHS', label: '中文 zh-CHS' },
      { value: 'en', label: 'English en' },
      { value: 'ja', label: '日本語 ja' },
      { value: 'ko', label: '한국어 ko' },
      { value: 'fr', label: 'Français fr' },
      { value: 'de', label: 'Deutsch de' },
      { value: 'es', label: 'Español es' },
      { value: 'ru', label: 'Русский ru' },
    ],
  },
  bing: {
    voices: [
      { value: 'zh-CN-XiaoxiaoNeural', label: '晓晓 - 中文女声' },
      { value: 'zh-CN-YunxiNeural', label: '云希 - 中文男声' },
      { value: 'zh-CN-YunjianNeural', label: '云健 - 中文男声' },
      { value: 'zh-CN-XiaoyiNeural', label: '晓伊 - 中文女声' },
      { value: 'zh-CN-YunyangNeural', label: '云扬 - 中文男声' },
      { value: 'zh-TW-HsiaoChenNeural', label: '曉臻 - 繁中女声' },
      { value: 'en-US-JennyNeural', label: 'Jenny - English' },
      { value: 'en-US-GuyNeural', label: 'Guy - English' },
      { value: 'ja-JP-NanamiNeural', label: 'Nanami - 日本語' },
    ],
    languages: COMMON_TTS_LANGUAGES,
  },
  google: {
    voices: [
      { value: 'zh-CN-Standard-A', label: '中文女声 Standard-A' },
      { value: 'zh-CN-Standard-B', label: '中文男声 Standard-B' },
      { value: 'zh-CN-Standard-C', label: '中文男声 Standard-C' },
      { value: 'zh-CN-Standard-D', label: '中文女声 Standard-D' },
      { value: 'zh-CN-Wavenet-A', label: '中文女声 Wavenet-A' },
      { value: 'zh-CN-Wavenet-B', label: '中文男声 Wavenet-B' },
      { value: 'en-US-Standard-C', label: 'English Standard-C' },
      { value: 'en-US-Standard-D', label: 'English Standard-D' },
      { value: 'ja-JP-Standard-A', label: '日本語 Standard-A' },
    ],
    languages: COMMON_TTS_LANGUAGES,
    formats: [
      { value: 'MP3', label: 'MP3' },
      { value: 'LINEAR16', label: 'WAV LINEAR16' },
      { value: 'OGG_OPUS', label: 'OGG Opus' },
    ],
  },
  baidu: {
    voices: [
      { value: '0', label: '普通女声' },
      { value: '1', label: '普通男声' },
      { value: '3', label: '度逍遥' },
      { value: '4', label: '度丫丫' },
    ],
    languages: [{ value: 'zh', label: '中文 zh' }],
  },
  doubao: {
    voices: [
      { value: 'zh_female_vv_uranus_bigtts', label: 'Vivi 2.0 - 女声' },
      { value: 'zh_female_wanwanxiaohe_moon_bigtts', label: '湾湾小何 - 女声' },
      { value: 'zh_male_beijingxiaoye_moon_bigtts', label: '北京小爷 - 男声' },
      { value: 'zh_female_shuangkuaisisi_moon_bigtts', label: '爽快思思 - 女声' },
      { value: 'zh_male_yangguangqingnian_moon_bigtts', label: '阳光青年 - 男声' },
      { value: 'zh_female_tianmeixiaoyuan_moon_bigtts', label: '甜美小源 - 女声' },
      { value: 'en_female_amanda_mars_bigtts', label: 'Amanda - English' },
      { value: 'en_male_jackson_mars_bigtts', label: 'Jackson - English' },
    ],
    languages: COMMON_TTS_LANGUAGES,
    resourceIds: [
      { value: 'seed-tts-2.0', label: 'Seed TTS 2.0' },
      { value: 'seed-icl-2.0', label: 'Seed ICL 2.0 复刻音色' },
    ],
    models: [
      { value: 'seed-tts-2.0-standard', label: 'Seed TTS 2.0 标准版' },
      { value: 'seed-tts-2.0-expressive', label: 'Seed TTS 2.0 高表现力版' },
    ],
    formats: [
      { value: 'mp3', label: 'MP3' },
      { value: 'wav', label: 'WAV' },
      { value: 'ogg_opus', label: 'OGG Opus' },
      { value: 'pcm', label: 'PCM' },
    ],
  },
  mimo: {
    voices: [
      { value: 'mimo_default', label: 'MiMo 默认音色（随部署区域）' },
      { value: '冰糖', label: '冰糖 - 中文女声' },
      { value: '茉莉', label: '茉莉 - 中文女声' },
      { value: '苏打', label: '苏打 - 中文男声' },
      { value: '白桦', label: '白桦 - 中文男声' },
      { value: 'Mia', label: 'Mia - English Female' },
      { value: 'Chloe', label: 'Chloe - English Female' },
      { value: 'Milo', label: 'Milo - English Male' },
      { value: 'Dean', label: 'Dean - English Male' },
    ],
    languages: [
      { value: 'zh-CN', label: '简体中文 zh-CN' },
      { value: 'zh-TW', label: '繁体中文 zh-TW' },
      { value: 'en-US', label: 'English en-US' },
      { value: 'en-GB', label: 'English en-GB' },
    ],
    models: [
      { value: 'mimo-v2.5-tts', label: 'MiMo V2.5 TTS' },
      { value: 'mimo-v2.5-tts-voicedesign', label: 'MiMo V2.5 TTS Voice Design' },
      { value: 'mimo-v2.5-tts-voiceclone', label: 'MiMo V2.5 TTS Voice Clone' },
    ],
    formats: [
      { value: MIMO_DEFAULT_AUDIO_FORMAT, label: 'WAV' },
      { value: 'mp3', label: 'MP3' },
    ],
  },
};

function ttsProviderLabel(provider: TtsProvider): string {
  switch (provider) {
    case 'system':
      return t('settings.tts.provider.system', '系统 TTS');
    case 'xfyun':
      return t('settings.tts.provider.xfyun', '讯飞 TTS');
    case 'youdao':
      return t('settings.tts.provider.youdao', '有道 TTS');
    case 'bing':
      return 'Bing TTS';
    case 'google':
      return 'Google TTS';
    case 'baidu':
      return t('settings.tts.provider.baidu', '百度 TTS');
    case 'doubao':
      return t('settings.tts.provider.doubao', '豆包 TTS');
    case 'mimo':
      return 'Mimo TTS';
    case 'apple':
      return t('settings.tts.provider.apple', '苹果 TTS');
  }
}

function providerNeedsEndpoint(provider: TtsProvider): boolean {
  return provider === 'xfyun' || provider === 'baidu' || provider === 'doubao' || provider === 'mimo';
}

function providerNeedsCredentials(provider: TtsProvider): boolean {
  return provider !== 'system' && provider !== 'apple';
}

function providerHint(provider: TtsProvider): string {
  switch (provider) {
    case 'system':
      return t('settings.tts.provider.system.desc', '默认使用浏览器或系统原生语音能力，无需密钥。');
    case 'apple':
      return t('settings.tts.provider.apple.desc', '在 Apple 平台优先匹配系统语音；Web 端会回退到浏览器语音。');
    case 'xfyun':
      return t('settings.tts.provider.xfyun.desc', '官方在线 TTS 使用 WebSocket 与 HMAC 鉴权；App 端可按凭据调用。');
    case 'baidu':
      return t('settings.tts.provider.baidu.desc', '填写 access token 后 App 端可调用百度语音合成接口。');
    case 'doubao':
      return t('settings.tts.provider.doubao.desc', 'HTTP 单向流式语音合成，需填写 API Key、Resource ID 与音色 ID。');
    case 'mimo':
      return t('settings.tts.provider.mimo.desc', '小米 Mimo V2.5 语音合成，支持预置音色、风格提示和音频格式配置。');
    case 'youdao':
    case 'bing':
    case 'google':
      return t('settings.tts.provider.generic.desc', '保留服务参数与优先级配置，服务不可用时自动回退。');
  }
}

function friendlyTtsError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  const normalized = message.replace(/\s+/g, ' ').trim();
  if (!normalized) return 'unknown error';
  return truncateEndText(normalized, 140, { ellipsis: '...' });
}

export function SettingsPage() {
  const [prefs, setPrefs] = useState<RemotePreferences | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const { active: saved, trigger: showSaved } = useTransientFlag();
  const [saveError, setSaveError] = useState<string | null>(null);
  const { format: messageContentFormat, htmlFallback: htmlRenderFallback } = useMessageContentFormat();
  const ttsSettings = useTtsSettings();

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
      showSaved();
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
    description: t('settings.language.optionDesc', '界面语言'),
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
            {saved ? (
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
                    meta={<SavingPill active={savingKey === 'language_storage_value'} value={languageLabel(prefs.language_storage_value)} />}
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
                        value={`${
                          prefs.dialog_animation_settings?.duration_ms ??
                          DIALOG_MOTION_DEFAULT_DURATION_MS
                        } ms`}
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

            {/* 本地偏好（不依赖服务端 prefs，始终展示） */}
            <Appear variant="up">
              <SettingRow
                title={t('settings.messageContentFormat.title', '消息内容格式')}
                description={t('settings.messageContentFormat.desc', '助手消息按所选格式渲染。HTML 模式会调用第三方安全清洗后展示原始 HTML，token 与渲染成本更高，请按需开启。')}
                meta={<SavingPill active={false} value={messageFormatLabel(messageContentFormat)} />}
              >
                <div class="oh-settings-control-row">
                  <MenuSelect
                    value={messageContentFormat}
                    onChange={(next) => {
                      setMessageContentFormat(next as 'markdown' | 'plain_text' | 'html');
                      if (next === 'html') {
                        showSnackbar(t(
                          'settings.messageContentFormat.htmlWarning',
                          'HTML 模式 token 消耗较高，请按需启用。',
                        ));
                      }
                    }}
                    options={[
                      { value: 'markdown', label: t('settings.messageContentFormat.markdown', 'Markdown') },
                      { value: 'plain_text', label: t('settings.messageContentFormat.plainText', '纯文本') },
                      { value: 'html', label: t('settings.messageContentFormat.html', 'HTML') },
                    ]}
                    minWidth={190}
                    ariaLabel={t('settings.messageContentFormat.title', '消息内容格式')}
                  />
                </div>
              </SettingRow>
            </Appear>

            {messageContentFormat === 'html' ? (
              <Appear variant="up">
                <SettingRow
                  title={t('settings.htmlRenderFallback.title', 'HTML 回退渲染')}
                  description={t('settings.htmlRenderFallback.desc', '当消息正文不包含 HTML 标签时，回退采用此渲染方式。')}
                  meta={<SavingPill active={false} value={htmlFallbackLabel(htmlRenderFallback)} />}
                >
                  <div class="oh-settings-control-row">
                    <MenuSelect
                      value={htmlRenderFallback}
                      onChange={(next) => setHtmlRenderFallback(next as 'markdown' | 'plain_text')}
                      options={[
                        { value: 'markdown', label: t('settings.messageContentFormat.markdown', 'Markdown') },
                        { value: 'plain_text', label: t('settings.messageContentFormat.plainText', '纯文本') },
                      ]}
                      minWidth={190}
                      ariaLabel={t('settings.htmlRenderFallback.title', 'HTML 回退渲染')}
                    />
                  </div>
                </SettingRow>
              </Appear>
            ) : null}

            <Appear variant="up">
              <SettingRow
                title={t('settings.tts.title', '开启文本转语音')}
                description={t('settings.tts.desc', '配置朗读偏好与服务优先级。消息平台朗读开关启用时，可朗读文本卡片会显示朗读胶囊。')}
                meta={<SavingPill active={false} value={ttsSettings.enabled ? t('common.on', '开') : t('common.off', '关')} />}
              >
                <label class="oh-settings-switch">
                  <input
                    type="checkbox"
                    checked={ttsSettings.enabled}
                    onChange={(event) => {
                      const enabled = (event.currentTarget as HTMLInputElement).checked;
                      if (!enabled) stopTtsPlayback();
                      saveTtsSettings({
                        ...ttsSettings,
                        enabled,
                      });
                    }}
                  />
                  <span class="oh-settings-switch-track"><span /></span>
                  <span class="oh-settings-control-label">
                    {ttsSettings.enabled ? t('common.on', '开') : t('common.off', '关')}
                  </span>
                </label>
                <AnimatedReveal visible={ttsSettings.enabled}>
                  <TtsSettingsPanel settings={ttsSettings} />
                </AnimatedReveal>
              </SettingRow>
            </Appear>
          </section>
        </div>
      </div>
    </main>
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

function AnimatedReveal(props: { visible: boolean; children: ComponentChildren }) {
  return (
    <div class={`oh-settings-reveal${props.visible ? ' is-visible' : ''}`} aria-hidden={props.visible ? 'false' : 'true'}>
      <div class="oh-settings-reveal-inner">
        {props.children}
      </div>
    </div>
  );
}

function TtsSettingsPanel(props: { settings: TtsSettings }) {
  const [draggingProvider, setDraggingProvider] = useState<TtsProvider | null>(null);
  const update = (patch: Partial<TtsSettings>) => {
    saveTtsSettings(normalizeTtsSettings({ ...props.settings, ...patch }));
  };
  const updateProvider = (provider: TtsProvider, patch: Partial<TtsProviderSettings>) => {
    saveTtsSettings(normalizeTtsSettings({
      ...props.settings,
      providers: {
        ...props.settings.providers,
        [provider]: {
          ...props.settings.providers[provider],
          ...patch,
        },
      },
    }));
  };
  const reorderProvider = (source: TtsProvider, target: TtsProvider) => {
    if (source === target) return;
    const next = props.settings.providerPriority.filter((provider) => provider !== source);
    const targetIndex = next.indexOf(target);
    if (targetIndex < 0) return;
    next.splice(targetIndex, 0, source);
    update({ providerPriority: next });
  };

  return (
    <div class="oh-settings-tts-panel">
      <div class="oh-settings-tts-grid">
        <NumberSetting
          label={t('settings.tts.timeout', '朗读超时')}
          value={props.settings.timeoutSeconds}
          min={3}
          max={120}
          onCommit={(value) => update({ timeoutSeconds: value })}
        />
        <NumberSetting
          label={t('settings.tts.maxChars', '最大朗读字符')}
          value={props.settings.maxTextCharacters}
          min={20}
          max={20000}
          onCommit={(value) => update({ maxTextCharacters: value })}
        />
      </div>
      <div class="oh-settings-tts-section">
        <h4>{t('settings.tts.priority', 'TTS 服务优先级')}</h4>
        <p>{t('settings.tts.priority.desc', '拖动下方服务卡片调整优先级；不可用、超时或未配置时自动回退。')}</p>
      </div>
      <div class="oh-settings-tts-providers">
        {props.settings.providerPriority.map((provider, index) => (
          <TtsProviderCard
            key={provider}
            provider={provider}
            priorityIndex={index}
            settings={props.settings.providers[provider]}
            allSettings={props.settings}
            dragging={draggingProvider === provider}
            onDragStart={() => setDraggingProvider(provider)}
            onDragEnd={() => setDraggingProvider(null)}
            onDropProvider={(target) => {
              if (draggingProvider) reorderProvider(draggingProvider, target);
              setDraggingProvider(null);
            }}
            onChange={(patch) => updateProvider(provider, patch)}
          />
        ))}
      </div>
    </div>
  );
}

function NumberSetting(props: {
  label: string;
  value: number;
  min: number;
  max: number;
  onCommit: (value: number) => void;
}) {
  const [value, setValue] = useState(String(props.value));
  useEffect(() => {
    setValue(String(props.value));
  }, [props.value]);
  const commit = () => {
    const parsed = finiteNumberFromText(value);
    if (parsed == null) {
      setValue(String(props.value));
      return;
    }
    const next = clampNumber(parsed, props.min, props.max);
    const display = Number.isInteger(next) ? String(next) : String(Number(next.toFixed(2)));
    setValue(display);
    if (next !== props.value) props.onCommit(next);
  };
  return (
    <label class="oh-settings-tts-number">
      <span>{props.label}</span>
      <input
        type="number"
        min={props.min}
        max={props.max}
        step="any"
        value={value}
        onInput={(event) => setValue((event.currentTarget as HTMLInputElement).value)}
        onBlur={commit}
        onKeyDown={(event) => {
          if (event.key === 'Enter') (event.currentTarget as HTMLInputElement).blur();
        }}
      />
    </label>
  );
}

function TtsProviderCard(props: {
  provider: TtsProvider;
  priorityIndex: number;
  settings: TtsProviderSettings;
  allSettings: TtsSettings;
  dragging: boolean;
  onDragStart: () => void;
  onDragEnd: () => void;
  onDropProvider: (target: TtsProvider) => void;
  onChange: (patch: Partial<TtsProviderSettings>) => void;
}) {
  const [testing, setTesting] = useState(false);
  const catalog = TTS_PROVIDER_CATALOG[props.provider];
  const mimoModel = String(props.settings.extra.model ?? 'mimo-v2.5-tts');
  const usesMimoPresetVoice =
    props.provider !== 'mimo' || mimoModel === 'mimo-v2.5-tts';
  const test = async () => {
    if (testing) return;
    setTesting(true);
    try {
      await testTtsProvider(props.provider, props.allSettings);
      showSnackbar(t('settings.tts.test.ok', 'TTS 测试播放完成'), { tone: 'success' });
    } catch (error) {
      showSnackbar(`${t('settings.tts.test.fail', 'TTS 测试失败')}：${friendlyTtsError(error)}`, {
        tone: 'error',
        durationMs: 4200,
      });
    } finally {
      setTesting(false);
    }
  };
  return (
    <section
      class={`oh-settings-tts-provider-card${props.dragging ? ' is-dragging' : ''}${props.settings.enabled ? ' is-enabled' : ''}`}
      draggable
      onDragStart={(event) => {
        const transfer = event.dataTransfer;
        if (transfer) {
          transfer.effectAllowed = 'move';
          transfer.setData('text/plain', props.provider);
        }
        props.onDragStart();
      }}
      onDragEnd={props.onDragEnd}
      onDragOver={(event) => {
        event.preventDefault();
        if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
      }}
      onDrop={(event) => {
        event.preventDefault();
        props.onDropProvider(props.provider);
      }}
    >
      <div class="oh-settings-tts-provider-head">
        <span class="oh-settings-tts-drag-handle" title={t('settings.tts.drag', '拖动调整优先级')} aria-hidden="true">⋮⋮</span>
        <div class="oh-settings-tts-provider-title">
          <div class="oh-settings-tts-provider-title-row">
            <span class="oh-settings-tts-rank">#{props.priorityIndex + 1}</span>
            <h4>{ttsProviderLabel(props.provider)}</h4>
            <span class={`oh-settings-tts-state${props.settings.enabled ? ' is-on' : ''}`}>
              {props.settings.enabled ? t('common.on', '开') : t('common.off', '关')}
            </span>
          </div>
          <p>{providerHint(props.provider)}</p>
        </div>
        <div class="oh-settings-tts-card-actions">
          <button type="button" class="oh-settings-tts-test" onClick={() => { void test(); }} disabled={testing}>
            {testing ? t('settings.tts.testing', '测试中') : t('settings.tts.test', '测试')}
          </button>
          <label class="oh-settings-switch">
            <input
              type="checkbox"
              checked={props.settings.enabled}
              onChange={(event) => props.onChange({ enabled: (event.currentTarget as HTMLInputElement).checked })}
            />
            <span class="oh-settings-switch-track"><span /></span>
          </label>
        </div>
      </div>
      <AnimatedReveal visible={props.settings.enabled}>
        <div class="oh-settings-tts-provider-body">
          <TtsProviderSection title={t('settings.tts.voice.section', '声音参数')}>
            <div class="oh-settings-tts-provider-fields">
              {usesMimoPresetVoice ? (
                <SelectSetting
                  label={t('settings.tts.voice', '音色/发音人')}
                  value={props.settings.voice}
                  options={catalog.voices}
                  onCommit={(voice) => props.onChange({ voice })}
                />
              ) : null}
              <SelectSetting
                label={t('settings.tts.language', '语言')}
                value={props.settings.language}
                options={catalog.languages}
                onCommit={(language) => props.onChange({ language })}
              />
              {props.provider !== 'mimo' ? (
                <NumberSetting label={t('settings.tts.speed', '语速')} value={props.settings.speed} min={0} max={200} onCommit={(speed) => props.onChange({ speed })} />
              ) : null}
              <NumberSetting label={t('settings.tts.volume', '音量')} value={props.settings.volume} min={0} max={100} onCommit={(volume) => props.onChange({ volume })} />
              {props.provider !== 'mimo' ? (
                <NumberSetting label={t('settings.tts.pitch', '音调')} value={props.settings.pitch} min={-20} max={100} onCommit={(pitch) => props.onChange({ pitch })} />
              ) : null}
            </div>
          </TtsProviderSection>
          {providerNeedsEndpoint(props.provider) || providerNeedsCredentials(props.provider) ? (
            <TtsProviderSection title={t('settings.tts.access.section', '连接与凭据')}>
              <div class="oh-settings-tts-provider-fields">
                {providerNeedsEndpoint(props.provider) ? (
                  <TextSetting label={t('settings.tts.endpoint', '接口地址')} value={props.settings.endpoint} onCommit={(endpoint) => props.onChange({ endpoint })} />
                ) : null}
                {providerNeedsCredentials(props.provider) && props.provider !== 'baidu' && props.provider !== 'doubao' && props.provider !== 'mimo' ? (
                  <TextSetting label="App ID" value={props.settings.appId} onCommit={(appId) => props.onChange({ appId })} />
                ) : null}
                {providerNeedsCredentials(props.provider) ? (
                  <TextSetting
                    label={props.provider === 'baidu' ? 'Access Token' : 'API Key'}
                    value={props.provider === 'baidu' ? props.settings.accessToken : props.settings.apiKey}
                    secret
                    onCommit={(value) => props.onChange(props.provider === 'baidu' ? { accessToken: value } : { apiKey: value })}
                  />
                ) : null}
                {providerNeedsCredentials(props.provider) && props.provider !== 'baidu' && props.provider !== 'doubao' && props.provider !== 'mimo' ? (
                  <TextSetting label="API Secret / Token" value={props.settings.apiSecret} secret onCommit={(apiSecret) => props.onChange({ apiSecret })} />
                ) : null}
              </div>
            </TtsProviderSection>
          ) : null}
          {props.provider === 'doubao' ? (
            <TtsProviderSection title={t('settings.tts.doubao.section', '豆包参数')}>
              <div class="oh-settings-tts-provider-fields">
                <SelectSetting
                  label="Resource ID"
                  value={String(props.settings.extra.resource_id ?? 'seed-tts-2.0')}
                  options={catalog.resourceIds ?? []}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, resource_id: value || 'seed-tts-2.0' } })}
                />
                <SelectSetting
                  label={t('settings.tts.model', '模型')}
                  value={String(props.settings.extra.model ?? 'seed-tts-2.0-standard')}
                  options={catalog.models ?? []}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, model: value || 'seed-tts-2.0-standard' } })}
                />
                <SelectSetting
                  label={t('settings.tts.format', '音频格式')}
                  value={String(props.settings.extra.format ?? 'mp3')}
                  options={catalog.formats ?? []}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, format: value || 'mp3' } })}
                />
              </div>
            </TtsProviderSection>
          ) : props.provider === 'mimo' ? (
            <TtsProviderSection title="Mimo TTS">
              <div class="oh-settings-tts-provider-fields">
                <SelectSetting
                  label={t('settings.tts.model', '模型')}
                  value={String(props.settings.extra.model ?? 'mimo-v2.5-tts')}
                  options={catalog.models ?? []}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, model: value || 'mimo-v2.5-tts' } })}
                />
                <SelectSetting
                  label={t('settings.tts.format', '音频格式')}
                  value={String(props.settings.extra.format ?? MIMO_DEFAULT_AUDIO_FORMAT)}
                  options={catalog.formats ?? []}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, format: value || MIMO_DEFAULT_AUDIO_FORMAT } })}
                />
                <TextSetting
                  label={t('settings.tts.stylePrompt', '风格提示')}
                  value={String(props.settings.extra.style_prompt ?? '自然清晰，语速适中，语气友好。')}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, style_prompt: value || '自然清晰，语速适中，语气友好。' } })}
                />
                {mimoModel === 'mimo-v2.5-tts-voicedesign' ? (
                  <label class="oh-settings-switch">
                    <input
                      type="checkbox"
                      checked={Boolean(props.settings.extra.optimize_text_preview)}
                      onChange={(event) => props.onChange({
                        extra: {
                          ...props.settings.extra,
                          optimize_text_preview: (event.currentTarget as HTMLInputElement).checked,
                        },
                      })}
                    />
                    <span class="oh-settings-switch-track"><span /></span>
                    <span class="oh-settings-control-label">
                      {t('settings.tts.optimizeTextPreview', '优化文本预览')}
                    </span>
                  </label>
                ) : null}
                {mimoModel === 'mimo-v2.5-tts-voiceclone' ? (
                  <TextSetting
                    label={t('settings.tts.voiceSamplePath', '克隆样本路径')}
                    value={String(props.settings.extra.voice_sample_path ?? '')}
                    onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, voice_sample_path: value } })}
                  />
                ) : null}
              </div>
            </TtsProviderSection>
          ) : null}
          {props.provider === 'xfyun' ? (
            <TtsProviderSection title={t('settings.tts.audio.section', '音频编码')}>
              <div class="oh-settings-tts-provider-fields">
                <SelectSetting
                  label={t('settings.tts.format', '音频格式')}
                  value={String(props.settings.extra.aue ?? 'lame')}
                  options={catalog.formats ?? []}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, aue: value || 'lame' } })}
                />
              </div>
            </TtsProviderSection>
          ) : null}
          {props.provider === 'google' ? (
            <TtsProviderSection title={t('settings.tts.audio.section', '音频编码')}>
              <div class="oh-settings-tts-provider-fields">
                <SelectSetting
                  label={t('settings.tts.format', '音频格式')}
                  value={String(props.settings.extra.audioEncoding ?? 'MP3')}
                  options={catalog.formats ?? []}
                  onCommit={(value) => props.onChange({ extra: { ...props.settings.extra, audioEncoding: value || 'MP3' } })}
                />
              </div>
            </TtsProviderSection>
          ) : null}
        </div>
      </AnimatedReveal>
    </section>
  );
}

function TtsProviderSection(props: { title: string; children: ComponentChildren }) {
  return (
    <section class="oh-settings-tts-provider-section">
      <h5>{props.title}</h5>
      {props.children}
    </section>
  );
}

function SelectSetting(props: {
  label: string;
  value: string;
  options: TtsCatalogOption[];
  onCommit: (value: string) => void;
}) {
  const normalized = props.value.trim();
  const displayOptions = props.options.map((option) => ({
    ...option,
    label: displayTtsOptionLabel(option),
  }));
  const hasCurrent = displayOptions.some((option) => option.value === normalized);
  const options = hasCurrent || normalized.length === 0
    ? displayOptions
    : [{ value: normalized, label: `${t('settings.tts.current', '当前配置')}：${displayCurrentTtsValue(normalized)}` }, ...displayOptions];
  const safeOptions = options.length > 0 ? options : [{ value: normalized, label: displayCurrentTtsValue(normalized) }];
  const value = safeOptions.some((option) => option.value === normalized)
    ? normalized
    : safeOptions[0]?.value ?? '';
  return (
    <label class="oh-settings-tts-select">
      <span>{props.label}</span>
      <select
        value={value}
        onChange={(event) => {
          const next = (event.currentTarget as HTMLSelectElement).value;
          if (next !== normalized) props.onCommit(next);
        }}
      >
        {safeOptions.map((option) => (
          <option key={`${props.label}-${option.value}`} value={option.value}>{option.label}</option>
        ))}
      </select>
    </label>
  );
}

function TextSetting(props: {
  label: string;
  value: string;
  secret?: boolean;
  onCommit: (value: string) => void;
}) {
  const [value, setValue] = useState(props.value);
  useEffect(() => {
    setValue(props.value);
  }, [props.value]);
  const commit = () => {
    const next = value.trim();
    setValue(next);
    if (next !== props.value) props.onCommit(next);
  };
  return (
    <label class="oh-settings-tts-text">
      <span>{props.label}</span>
      <input
        type={props.secret ? 'password' : 'text'}
        value={value}
        onInput={(event) => setValue((event.currentTarget as HTMLInputElement).value)}
        onBlur={commit}
        onKeyDown={(event) => {
          if (event.key === 'Enter') (event.currentTarget as HTMLInputElement).blur();
        }}
      />
    </label>
  );
}
