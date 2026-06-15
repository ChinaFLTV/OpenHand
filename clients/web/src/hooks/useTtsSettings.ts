import { useEffect, useState } from 'preact/hooks';
import { readBrowserStorage, writeBrowserStorage } from '../shared/util/browser_storage';

export type TtsProvider = 'system' | 'xfyun' | 'youdao' | 'bing' | 'google' | 'baidu' | 'doubao' | 'mimo' | 'apple';

export interface TtsProviderSettings {
  enabled: boolean;
  voice: string;
  language: string;
  speed: number;
  volume: number;
  pitch: number;
  endpoint: string;
  appId: string;
  apiKey: string;
  apiSecret: string;
  accessToken: string;
  region: string;
  extra: Record<string, unknown>;
}

export interface TtsSettings {
  enabled: boolean;
  timeoutSeconds: number;
  maxTextCharacters: number;
  providerPriority: TtsProvider[];
  providers: Record<TtsProvider, TtsProviderSettings>;
}

export interface TtsPlaybackState {
  playing: boolean;
  messageId: string | null;
  provider: TtsProvider | null;
}

const STORAGE_KEY = 'openhand_tts_settings';
const EVENT_NAME = 'openhand:tts-settings-changed';
const PLAYBACK_EVENT_NAME = 'openhand:tts-playback-changed';
const MIN_TIMEOUT_SECONDS = 3;
const MAX_TIMEOUT_SECONDS = 120;
const MIN_TEXT_CHARS = 20;
const MAX_TEXT_CHARS = 20000;

export const TTS_PROVIDERS: readonly TtsProvider[] = [
  'system',
  'apple',
  'xfyun',
  'bing',
  'google',
  'baidu',
  'doubao',
  'youdao',
  'mimo',
];

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.min(Math.max(value, min), max);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function stringField(
  raw: Record<string, unknown>,
  key: string,
  fallback: string,
): string {
  return Object.prototype.hasOwnProperty.call(raw, key)
    ? asString(raw[key])
    : fallback;
}

function asNumber(value: unknown, fallback: number): number {
  if (typeof value === 'number') return Number.isFinite(value) ? value : fallback;
  if (typeof value === 'string') {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}

function asBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function defaultProviderSettings(provider: TtsProvider): TtsProviderSettings {
  switch (provider) {
    case 'system':
      return {
        enabled: true,
        voice: '',
        language: 'zh-CN',
        speed: 1,
        volume: 1,
        pitch: 1,
        endpoint: '',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {},
      };
    case 'xfyun':
      return {
        enabled: false,
        voice: 'xiaoyan',
        language: 'zh-CN',
        speed: 50,
        volume: 50,
        pitch: 50,
        endpoint: 'wss://tts-api.xfyun.cn/v2/tts',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {
          aue: 'lame',
          auf: 'audio/L16;rate=16000',
        },
      };
    case 'youdao':
      return {
        enabled: false,
        voice: '',
        language: 'zh-CHS',
        speed: 1,
        volume: 1,
        pitch: 1,
        endpoint: '',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {},
      };
    case 'bing':
      return {
        enabled: false,
        voice: 'zh-CN-XiaoxiaoNeural',
        language: 'zh-CN',
        speed: 1,
        volume: 1,
        pitch: 1,
        endpoint: '',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {},
      };
    case 'google':
      return {
        enabled: false,
        voice: 'zh-CN-Standard-A',
        language: 'zh-CN',
        speed: 1,
        volume: 1,
        pitch: 0,
        endpoint: '',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: { audioEncoding: 'MP3' },
      };
    case 'baidu':
      return {
        enabled: false,
        voice: '0',
        language: 'zh',
        speed: 5,
        volume: 5,
        pitch: 5,
        endpoint: 'https://tsn.baidu.com/text2audio',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {},
      };
    case 'doubao':
      return {
        enabled: false,
        voice: 'zh_female_vv_uranus_bigtts',
        language: 'zh-CN',
        speed: 0,
        volume: 0,
        pitch: 0,
        endpoint: 'https://openspeech.bytedance.com/api/v3/tts/unidirectional',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {
          resource_id: 'seed-tts-2.0',
          model: 'seed-tts-2.0-standard',
          format: 'mp3',
          sample_rate: 24000,
          bit_rate: 128000,
        },
      };
    case 'mimo':
      return {
        enabled: false,
        voice: '冰糖',
        language: 'zh-CN',
        speed: 1,
        volume: 1,
        pitch: 1,
        endpoint: 'https://api.xiaomimimo.com/v1/chat/completions',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {
          model: 'mimo-v2.5-tts',
          format: 'wav',
          style_prompt: '自然清晰，语速适中，语气友好。',
          sample_rate: 24000,
          voice_sample_path: '',
        },
      };
    case 'apple':
      return {
        enabled: false,
        voice: '',
        language: 'zh-CN',
        speed: 1,
        volume: 1,
        pitch: 1,
        endpoint: '',
        appId: '',
        apiKey: '',
        apiSecret: '',
        accessToken: '',
        region: '',
        extra: {},
      };
  }
}

function defaultProviders(): Record<TtsProvider, TtsProviderSettings> {
  return Object.fromEntries(
    TTS_PROVIDERS.map((provider) => [provider, defaultProviderSettings(provider)]),
  ) as Record<TtsProvider, TtsProviderSettings>;
}

export function defaultTtsSettings(): TtsSettings {
  return {
    enabled: false,
    timeoutSeconds: 30,
    maxTextCharacters: 4000,
    providerPriority: [...TTS_PROVIDERS],
    providers: defaultProviders(),
  };
}

function normalizeProviderSettings(
  provider: TtsProvider,
  value: unknown,
): TtsProviderSettings {
  const defaults = defaultProviderSettings(provider);
  const raw = asRecord(value);
  if (!raw) return defaults;
  const extra = asRecord(raw.extra) ?? defaults.extra;
  const voice = stringField(raw, 'voice', defaults.voice);
  const language = stringField(raw, 'language', defaults.language);
  return {
    enabled: asBoolean(raw.enabled, defaults.enabled),
    voice: voice || defaults.voice,
    language: language || defaults.language,
    speed: clamp(asNumber(raw.speed, defaults.speed), 0.1, 200),
    volume: clamp(asNumber(raw.volume, defaults.volume), 0, 100),
    pitch: clamp(asNumber(raw.pitch, defaults.pitch), -20, 100),
    endpoint: stringField(raw, 'endpoint', defaults.endpoint),
    appId: asString(raw.appId ?? raw.app_id),
    apiKey: asString(raw.apiKey ?? raw.api_key),
    apiSecret: asString(raw.apiSecret ?? raw.api_secret),
    accessToken: asString(raw.accessToken ?? raw.access_token),
    region: stringField(raw, 'region', defaults.region),
    extra: { ...extra },
  };
}

function normalizePriority(value: unknown): TtsProvider[] {
  const seen = new Set<TtsProvider>();
  const result: TtsProvider[] = [];
  const raw = Array.isArray(value) ? value : TTS_PROVIDERS;
  for (const item of raw) {
    if (typeof item !== 'string') continue;
    if (!TTS_PROVIDERS.includes(item as TtsProvider)) continue;
    const provider = item as TtsProvider;
    if (seen.has(provider)) continue;
    seen.add(provider);
    result.push(provider);
  }
  for (const provider of TTS_PROVIDERS) {
    if (!seen.has(provider)) result.push(provider);
  }
  return result;
}

export function normalizeTtsSettings(value: unknown): TtsSettings {
  const defaults = defaultTtsSettings();
  const raw = asRecord(value);
  if (!raw) return defaults;
  const rawProviders = asRecord(raw.providers);
  return {
    enabled: asBoolean(raw.enabled, false),
    timeoutSeconds: Math.round(clamp(
      asNumber(raw.timeoutSeconds ?? raw.timeout_seconds, defaults.timeoutSeconds),
      MIN_TIMEOUT_SECONDS,
      MAX_TIMEOUT_SECONDS,
    )),
    maxTextCharacters: Math.round(clamp(
      asNumber(raw.maxTextCharacters ?? raw.max_text_characters, defaults.maxTextCharacters),
      MIN_TEXT_CHARS,
      MAX_TEXT_CHARS,
    )),
    providerPriority: normalizePriority(raw.providerPriority ?? raw.provider_priority),
    providers: Object.fromEntries(
      TTS_PROVIDERS.map((provider) => [
        provider,
        normalizeProviderSettings(provider, rawProviders?.[provider]),
      ]),
    ) as Record<TtsProvider, TtsProviderSettings>,
  };
}

function readTtsSettings(): TtsSettings {
  const raw = readBrowserStorage(STORAGE_KEY);
  if (!raw) return defaultTtsSettings();
  try {
    return normalizeTtsSettings(JSON.parse(raw));
  } catch {
    return defaultTtsSettings();
  }
}

export function saveTtsSettings(settings: TtsSettings): void {
  const normalized = normalizeTtsSettings(settings);
  writeBrowserStorage(STORAGE_KEY, JSON.stringify(normalized));
  window.dispatchEvent(new CustomEvent(EVENT_NAME));
}

export function useTtsSettings(): TtsSettings {
  const [settings, setSettings] = useState<TtsSettings>(readTtsSettings);
  useEffect(() => {
    const refresh = () => setSettings(readTtsSettings());
    window.addEventListener(EVENT_NAME, refresh);
    window.addEventListener('storage', refresh);
    return () => {
      window.removeEventListener(EVENT_NAME, refresh);
      window.removeEventListener('storage', refresh);
    };
  }, []);
  return settings;
}

let playbackState: TtsPlaybackState = {
  playing: false,
  messageId: null,
  provider: null,
};
let speechGeneration = 0;
let speechTimeout: number | null = null;

function emitPlaybackState(next: TtsPlaybackState): void {
  playbackState = next;
  window.dispatchEvent(new CustomEvent(PLAYBACK_EVENT_NAME));
}

function clearSpeechTimer(): void {
  if (speechTimeout != null) {
    window.clearTimeout(speechTimeout);
    speechTimeout = null;
  }
}

export function stopTtsPlayback(): void {
  speechGeneration += 1;
  clearSpeechTimer();
  try {
    window.speechSynthesis?.cancel();
  } catch {
    // Ignore browser engine failures; state is still cleared below.
  }
  emitPlaybackState({ playing: false, messageId: null, provider: null });
}

function normalizeSpeechText(text: string, maxCharacters: number): string {
  const normalized = (text ?? '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (normalized.length <= maxCharacters) return normalized;
  return normalized.slice(0, maxCharacters);
}

function browserVoiceFor(settings: TtsProviderSettings): SpeechSynthesisVoice | null {
  const voices = window.speechSynthesis?.getVoices?.() ?? [];
  const voiceKey = settings.voice.trim().toLowerCase();
  const language = settings.language.trim().toLowerCase();
  if (voiceKey) {
    const exact = voices.find((voice) => (
      voice.name.toLowerCase() === voiceKey ||
      voice.voiceURI.toLowerCase() === voiceKey
    ));
    if (exact) return exact;
  }
  if (language) {
    return voices.find((voice) => voice.lang.toLowerCase() === language) ??
      voices.find((voice) => voice.lang.toLowerCase().startsWith(language.split('-')[0] ?? language)) ??
      null;
  }
  return null;
}

async function speakWithBrowserSystem(
  messageId: string,
  text: string,
  provider: TtsProvider,
  providerSettings: TtsProviderSettings,
  timeoutMs: number,
  generation: number,
): Promise<void> {
  if (typeof window === 'undefined' || !('speechSynthesis' in window)) {
    throw new Error('Browser speech synthesis is unavailable.');
  }
  if (generation !== speechGeneration) return;
  const utterance = new SpeechSynthesisUtterance(text);
  const voice = browserVoiceFor(providerSettings);
  if (voice) utterance.voice = voice;
  if (providerSettings.language) utterance.lang = providerSettings.language;
  utterance.rate = clamp(providerSettings.speed > 10 ? providerSettings.speed / 50 : providerSettings.speed, 0.1, 10);
  utterance.volume = clamp(providerSettings.volume > 1 ? providerSettings.volume / 100 : providerSettings.volume, 0, 1);
  utterance.pitch = clamp(providerSettings.pitch > 10 ? providerSettings.pitch / 50 : providerSettings.pitch, 0, 2);

  return new Promise<void>((resolve, reject) => {
    let settled = false;
    const finish = (error?: unknown) => {
      if (settled) return;
      settled = true;
      clearSpeechTimer();
      if (generation === speechGeneration) {
        emitPlaybackState({ playing: false, messageId: null, provider: null });
      }
      if (error) reject(error);
      else resolve();
    };
    utterance.onend = () => finish();
    utterance.onerror = (event) => {
      const reason = typeof event.error === 'string' && event.error
        ? event.error
        : 'Speech synthesis failed.';
      finish(new Error(reason));
    };
    speechTimeout = window.setTimeout(() => {
      try {
        window.speechSynthesis.cancel();
      } catch {
        // Ignore; timeout still ends this attempt.
      }
      finish(new Error('Speech synthesis timed out.'));
    }, timeoutMs);
    emitPlaybackState({ playing: true, messageId, provider });
    try {
      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(utterance);
    } catch (error) {
      finish(error);
    }
  });
}

async function speakWithProvider(
  messageId: string,
  text: string,
  provider: TtsProvider,
  settings: TtsProviderSettings,
  timeoutMs: number,
  generation: number,
): Promise<void> {
  if (provider === 'system' || provider === 'apple') {
    return speakWithBrowserSystem(messageId, text, provider, settings, timeoutMs, generation);
  }
  throw new Error(`${provider} TTS playback is not available in the browser runtime.`);
}

export async function toggleTtsPlayback(
  messageId: string,
  text: string,
  settings: TtsSettings,
): Promise<void> {
  if (playbackState.playing && playbackState.messageId === messageId) {
    stopTtsPlayback();
    return;
  }
  stopTtsPlayback();
  const normalized = normalizeTtsSettings(settings);
  if (!normalized.enabled) return;
  const speechText = normalizeSpeechText(text, normalized.maxTextCharacters);
  if (!speechText) return;
  const generation = ++speechGeneration;
  const timeoutMs = normalized.timeoutSeconds * 1000;
  for (const provider of normalized.providerPriority) {
    if (generation !== speechGeneration) return;
    const providerSettings = normalized.providers[provider];
    if (!providerSettings.enabled) continue;
    try {
      await speakWithProvider(
        messageId,
        speechText,
        provider,
        providerSettings,
        timeoutMs,
        generation,
      );
      return;
    } catch {
      if (generation !== speechGeneration) return;
      clearSpeechTimer();
      try {
        window.speechSynthesis?.cancel();
      } catch {
        // Continue to the next configured provider.
      }
    }
  }
  if (generation === speechGeneration) {
    emitPlaybackState({ playing: false, messageId: null, provider: null });
  }
}

export async function testTtsProvider(
  provider: TtsProvider,
  settings: TtsSettings,
  text = '这是一段文本转语音测试。',
): Promise<void> {
  stopTtsPlayback();
  const normalized = normalizeTtsSettings({
    ...settings,
    enabled: true,
  });
  const speechText = normalizeSpeechText(
    text,
    normalized.maxTextCharacters,
  );
  if (!speechText) throw new Error('TTS test text is empty.');
  const generation = ++speechGeneration;
  await speakWithProvider(
    '__settings_tts_test__',
    speechText,
    provider,
    normalized.providers[provider],
    normalized.timeoutSeconds * 1000,
    generation,
  );
}

export function useTtsPlaybackState(): TtsPlaybackState {
  const [state, setState] = useState<TtsPlaybackState>(playbackState);
  useEffect(() => {
    const refresh = () => setState(playbackState);
    window.addEventListener(PLAYBACK_EVENT_NAME, refresh);
    return () => window.removeEventListener(PLAYBACK_EVENT_NAME, refresh);
  }, []);
  return state;
}
