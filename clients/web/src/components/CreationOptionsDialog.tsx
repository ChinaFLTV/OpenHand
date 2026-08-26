// 多媒体生成选项弹窗：对齐 APP 端 _CreationOptionsSheet 的参数与动效。
import { useRef, useState } from 'preact/hooks';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { normalizeInteger, strictPositiveIntegerFromText } from '../shared/util/number';
import {
  DIALOG_OVERLAY_EDGE_SHEET_CLASS,
  DIALOG_OVERLAY_PRIORITY_Z_INDEX,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

export interface CreationOptions {
  aspectRatio?: string;
  durationSeconds?: number;
  count?: number;
  quality?: string;
  style?: string;
  outputFormat?: string;
  background?: string;
  negativePrompt?: string;
  promptEnhance?: boolean;
  watermark?: boolean;
  seed?: number;
  resolution?: string;
  frameRate?: number;
  numFrames?: number;
  mode?: string;
  voice?: string;
  omitVoice?: boolean;
  speed?: number;
  sampleRate?: number;
  bitrate?: number;
  volume?: number;
  pitch?: number;
}

interface CreationOptionsDialogProps {
  mode: 'image' | 'video' | 'audio';
  initial?: CreationOptions;
  onConfirm: (options: CreationOptions) => void;
  onCancel: () => void;
}

const IMAGE_RATIOS = ['1:1', '16:9', '9:16', '4:3', '3:4'];
const VIDEO_RATIOS = ['16:9', '9:16', '1:1', '4:3'];
const VIDEO_DURATIONS = [3, 5, 8, 10];
const AUDIO_DURATIONS = [5, 10, 20, 30, 60];
const IMAGE_QUALITIES = ['auto', 'standard', 'hd', 'high'];
const IMAGE_STYLES = ['natural', 'vivid'];
const IMAGE_FORMATS = ['png', 'jpeg', 'webp'];
const IMAGE_BACKGROUNDS = ['auto', 'transparent', 'opaque'];
const VIDEO_RESOLUTIONS = ['480p', '720p', '1080p'];
const VIDEO_FRAME_RATES = [16, 24, 30, 60];
const VIDEO_FRAMES = [81, 121, 161, 241, 441];
const VIDEO_MODES = ['keyframes'];
const AUDIO_FORMATS = ['mp3', 'wav', 'opus', 'aac', 'flac', 'pcm'];
const AUDIO_SPEEDS = [0.75, 1, 1.25, 1.5];
const AUDIO_SAMPLE_RATES = [16000, 24000, 32000, 44100];
const AUDIO_BITRATES = [64000, 128000, 192000, 256000];
const AUDIO_VOLUMES = [0.8, 1, 1.2];
const AUDIO_PITCHES = [-2, 0, 2];
const MIN_CREATION_COUNT = 1;
const MAX_CREATION_COUNT = 4;

function clampCreationCount(value: number | undefined): number {
  return normalizeInteger(value, {
    fallback: MIN_CREATION_COUNT,
    min: MIN_CREATION_COUNT,
    max: MAX_CREATION_COUNT,
  });
}

function modeTitle(mode: string): string {
  switch (mode) {
    case 'image': return t('creation.options.imageTitle', '图像生成选项');
    case 'video': return t('creation.options.videoTitle', '视频生成选项');
    case 'audio': return t('creation.options.audioTitle', '音频生成选项');
    default: return '';
  }
}

function trimToUndefined(value: string): string | undefined {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

interface ChipGroupProps<T extends string | number> {
  title: string;
  values: readonly T[];
  selected: T | undefined;
  labelFor?: (value: T) => string;
  onSelect: (value: T | undefined) => void;
}

function ChipGroup<T extends string | number>({
  title,
  values,
  selected,
  labelFor = (value) => String(value),
  onSelect,
}: ChipGroupProps<T>) {
  return (
    <div class="mb-4">
      <p class="text-xs font-medium mb-2 oh-text-muted">
        {title}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => onSelect(undefined)}
          class={`oh-tap-press px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
            selected === undefined ? 'oh-creation-chip-active' : 'oh-creation-chip'
          }`}
        >
          {selected === undefined ? `✓ ${t('creation.options.auto', '默认')}` : t('creation.options.auto', '默认')}
        </button>
        {values.map((value) => {
          const active = selected === value;
          const label = labelFor(value);
          return (
            <button
              key={String(value)}
              type="button"
              onClick={() => onSelect(value)}
              class={`oh-tap-press px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
                active ? 'oh-creation-chip-active' : 'oh-creation-chip'
              }`}
            >
              {active ? `✓ ${label}` : label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

interface TriStateGroupProps {
  title: string;
  value: boolean | undefined;
  onChange: (value: boolean | undefined) => void;
}

function TriStateGroup({ title, value, onChange }: TriStateGroupProps) {
  const items: Array<[boolean | undefined, string]> = [
    [undefined, t('creation.options.auto', '默认')],
    [true, t('common.on', '开')],
    [false, t('common.off', '关')],
  ];
  return (
    <div class="mb-4">
      <p class="text-xs font-medium mb-2 oh-text-muted">
        {title}
      </p>
      <div class="flex flex-wrap gap-2">
        {items.map(([itemValue, label]) => {
          const active = value === itemValue;
          return (
            <button
              key={String(itemValue)}
              type="button"
              onClick={() => onChange(itemValue)}
              class={`oh-tap-press px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
                active ? 'oh-creation-chip-active' : 'oh-creation-chip'
              }`}
            >
              {active ? `✓ ${label}` : label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

interface TextOptionProps {
  label: string;
  value: string;
  onInput: (value: string) => void;
  type?: string;
  rows?: number;
}

function TextOption({ label, value, onInput, type = 'text', rows = 1 }: TextOptionProps) {
  const sharedClass = 'w-full rounded-xl px-3 py-2 text-sm outline-none';
  const sharedStyle = {
    background: 'var(--m3-surface-container)',
    border: '1px solid var(--m3-outline-variant)',
    color: 'var(--m3-on-surface)',
  };
  return (
    <label class="block mb-3">
      <span class="block text-xs font-medium mb-2 oh-text-muted">
        {label}
      </span>
      {rows > 1 ? (
        <textarea
          value={value}
          rows={rows}
          onInput={(event) => onInput((event.currentTarget as HTMLTextAreaElement).value)}
          class={sharedClass}
          style={sharedStyle}
        />
      ) : (
        <input
          type={type}
          value={value}
          onInput={(event) => onInput((event.currentTarget as HTMLInputElement).value)}
          class={sharedClass}
          style={sharedStyle}
        />
      )}
    </label>
  );
}

export function CreationOptionsDialog({ mode, initial, onConfirm, onCancel }: CreationOptionsDialogProps) {
  const selectedOptionsRef = useRef<CreationOptions>({});
  const [aspectRatio, setAspectRatio] = useState(
    initial?.aspectRatio ?? (mode === 'image' ? '1:1' : mode === 'video' ? '16:9' : undefined),
  );
  const [durationSeconds, setDurationSeconds] = useState(
    initial?.durationSeconds ?? (mode === 'video' ? 5 : mode === 'audio' ? 10 : undefined),
  );
  const [count, setCount] = useState(clampCreationCount(initial?.count));
  const [quality, setQuality] = useState(initial?.quality);
  const [style, setStyle] = useState(initial?.style);
  const [outputFormat, setOutputFormat] = useState(initial?.outputFormat);
  const [background, setBackground] = useState(initial?.background);
  const [negativePrompt, setNegativePrompt] = useState(initial?.negativePrompt ?? '');
  const [promptEnhance, setPromptEnhance] = useState(initial?.promptEnhance);
  const [watermark, setWatermark] = useState(initial?.watermark);
  const [seed, setSeed] = useState(initial?.seed !== undefined ? String(initial.seed) : '');
  const [resolution, setResolution] = useState(initial?.resolution);
  const [frameRate, setFrameRate] = useState(initial?.frameRate);
  const [numFrames, setNumFrames] = useState(initial?.numFrames);
  const [videoMode, setVideoMode] = useState(initial?.mode);
  const [voice, setVoice] = useState(initial?.voice ?? '');
  const [omitVoice, setOmitVoice] = useState(initial?.omitVoice ?? false);
  const [speed, setSpeed] = useState(initial?.speed);
  const [sampleRate, setSampleRate] = useState(initial?.sampleRate);
  const [bitrate, setBitrate] = useState(initial?.bitrate);
  const [volume, setVolume] = useState(initial?.volume);
  const [pitch, setPitch] = useState(initial?.pitch);

  const selectedOptions = (): CreationOptions => ({
    aspectRatio: mode !== 'audio' ? aspectRatio : undefined,
    durationSeconds: mode !== 'image' ? durationSeconds : undefined,
    count,
    quality: mode === 'image' ? quality : undefined,
    style: mode === 'image' ? style : undefined,
    outputFormat: mode === 'image' || mode === 'audio' ? outputFormat : undefined,
    background: mode === 'image' ? background : undefined,
    negativePrompt: mode === 'image' || mode === 'video' ? trimToUndefined(negativePrompt) : undefined,
    promptEnhance: mode === 'image' || mode === 'video' ? promptEnhance : undefined,
    watermark: mode === 'image' || mode === 'video' ? watermark : undefined,
    seed:
      mode === 'image' || mode === 'video'
        ? strictPositiveIntegerFromText(seed) ?? undefined
        : undefined,
    resolution: mode === 'video' ? resolution : undefined,
    frameRate: mode === 'video' ? frameRate : undefined,
    numFrames: mode === 'video' ? numFrames : undefined,
    mode: mode === 'video' ? videoMode : undefined,
    voice: mode === 'audio' && !omitVoice ? trimToUndefined(voice) : undefined,
    omitVoice: mode === 'audio' ? omitVoice : undefined,
    speed: mode === 'audio' ? speed : undefined,
    sampleRate: mode === 'audio' ? sampleRate : undefined,
    bitrate: mode === 'audio' ? bitrate : undefined,
    volume: mode === 'audio' ? volume : undefined,
    pitch: mode === 'audio' ? pitch : undefined,
  });

  const { closing, requestCloseWithReason } = useDialogExitMotion<
    'cancel' | 'confirm'
  >((reason) => {
    if (reason === 'confirm') {
      onConfirm(selectedOptionsRef.current);
      return;
    }
    onCancel();
  });

  const requestCancel = () => requestCloseWithReason('cancel');

  const requestConfirm = () => {
    selectedOptionsRef.current = selectedOptions();
    requestCloseWithReason('confirm');
  };

  const ratios = mode === 'image' ? IMAGE_RATIOS : mode === 'video' ? VIDEO_RATIOS : [];
  const durations = mode === 'video' ? VIDEO_DURATIONS : mode === 'audio' ? AUDIO_DURATIONS : [];

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestCancel}
      closeOnBackdrop={!closing}
      panelAnimation="slideUp"
      {...createStandardDialogFrameAppearance({
        overlayClassName: DIALOG_OVERLAY_EDGE_SHEET_CLASS,
        overlay: {
          background: 'color-mix(in srgb, black 32%, transparent)',
          blurPx: 0,
        },
        overlayZIndex: DIALOG_OVERLAY_PRIORITY_Z_INDEX,
        panelClassName:
          'w-full max-w-3xl rounded-t-2xl px-6 py-5 flex flex-col overflow-hidden',
        panelBorder: 'none',
        panelSurface: {
          background: 'var(--m3-surface-container-low)',
          maxHeight: '82vh',
        },
      })}
      ariaLabel={modeTitle(mode)}
    >
      <h3 class="text-base font-semibold mb-4">{modeTitle(mode)}</h3>
      <div class="min-h-0 flex-1 overflow-y-auto pr-1">
        {ratios.length > 0 ? (
          <ChipGroup
            title={t('creation.options.aspectRatio', '宽高比')}
            values={ratios}
            selected={aspectRatio}
            onSelect={setAspectRatio}
          />
        ) : null}
        {durations.length > 0 ? (
          <ChipGroup
            title={t('creation.options.duration', '时长（秒）')}
            values={durations}
            selected={durationSeconds}
            labelFor={(value) => `${value}s`}
            onSelect={setDurationSeconds}
          />
        ) : null}
        {mode === 'image' ? (
          <>
            <ChipGroup title={t('creation.options.quality', '质量')} values={IMAGE_QUALITIES} selected={quality} onSelect={setQuality} />
            <ChipGroup title={t('creation.options.style', '风格')} values={IMAGE_STYLES} selected={style} onSelect={setStyle} />
            <ChipGroup title={t('creation.options.outputFormat', '输出格式')} values={IMAGE_FORMATS} selected={outputFormat} onSelect={setOutputFormat} />
            <ChipGroup title={t('creation.options.background', '背景')} values={IMAGE_BACKGROUNDS} selected={background} onSelect={setBackground} />
          </>
        ) : null}
        {mode === 'video' ? (
          <>
            <ChipGroup title={t('creation.options.resolution', '分辨率')} values={VIDEO_RESOLUTIONS} selected={resolution} onSelect={setResolution} />
            <ChipGroup title={t('creation.options.frameRate', '帧率')} values={VIDEO_FRAME_RATES} selected={frameRate} labelFor={(value) => `${value} fps`} onSelect={setFrameRate} />
            <ChipGroup title={t('creation.options.frames', '帧数')} values={VIDEO_FRAMES} selected={numFrames} onSelect={setNumFrames} />
            <ChipGroup title={t('creation.options.mode', '模式')} values={VIDEO_MODES} selected={videoMode} onSelect={setVideoMode} />
          </>
        ) : null}
        {mode === 'image' || mode === 'video' ? (
          <>
            <TriStateGroup title={t('creation.options.promptEnhance', 'Prompt 增强')} value={promptEnhance} onChange={setPromptEnhance} />
            <TriStateGroup title={t('creation.options.watermark', '水印')} value={watermark} onChange={setWatermark} />
            <TextOption label={t('creation.options.negativePrompt', '负向提示')} value={negativePrompt} onInput={setNegativePrompt} rows={2} />
            <TextOption label="Seed" value={seed} onInput={setSeed} type="number" />
          </>
        ) : null}
        {mode === 'audio' ? (
          <>
            <div class="mb-4">
              <p class="text-xs font-medium mb-2 oh-text-muted">
                {t('creation.options.voice', '音色/发音人')}
              </p>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => setOmitVoice(true)}
                  class={`oh-tap-press px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
                    omitVoice ? 'oh-creation-chip-active' : 'oh-creation-chip'
                  }`}
                >
                  {omitVoice ? `✓ ${t('creation.options.voiceUnspecified', '不指定')}` : t('creation.options.voiceUnspecified', '不指定')}
                </button>
                <button
                  type="button"
                  onClick={() => setOmitVoice(false)}
                  class={`oh-tap-press px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
                    !omitVoice ? 'oh-creation-chip-active' : 'oh-creation-chip'
                  }`}
                >
                  {!omitVoice ? `✓ ${t('creation.options.customVoice', '自定义 ID')}` : t('creation.options.customVoice', '自定义 ID')}
                </button>
              </div>
            </div>
            {!omitVoice ? (
              <TextOption label={t('creation.options.customVoiceId', '自定义音色 ID')} value={voice} onInput={setVoice} />
            ) : null}
            <ChipGroup title={t('creation.options.audioFormat', '音频格式')} values={AUDIO_FORMATS} selected={outputFormat} onSelect={setOutputFormat} />
            <ChipGroup title={t('creation.options.speed', '语速')} values={AUDIO_SPEEDS} selected={speed} labelFor={(value) => `${value}x`} onSelect={setSpeed} />
            <ChipGroup title={t('creation.options.sampleRate', '采样率')} values={AUDIO_SAMPLE_RATES} selected={sampleRate} onSelect={setSampleRate} />
            <ChipGroup title={t('creation.options.bitrate', '码率')} values={AUDIO_BITRATES} selected={bitrate} labelFor={(value) => `${Math.round(value / 1000)} kbps`} onSelect={setBitrate} />
            <ChipGroup title={t('creation.options.volume', '音量')} values={AUDIO_VOLUMES} selected={volume} labelFor={(value) => `${value}x`} onSelect={setVolume} />
            <ChipGroup title={t('creation.options.pitch', '音高')} values={AUDIO_PITCHES} selected={pitch} onSelect={setPitch} />
          </>
        ) : null}
        <div class="mb-5">
          <p class="text-xs font-medium mb-2 oh-text-muted">
            {t('creation.options.count', '数量')}
          </p>
          <div class="flex items-center gap-3">
            <button
              type="button"
              onClick={() => setCount((current) => clampCreationCount(current - 1))}
              disabled={closing || count <= MIN_CREATION_COUNT}
              class="oh-tap-press w-8 h-8 rounded-full flex items-center justify-center text-lg disabled:opacity-30"
              style={{ border: '1px solid var(--m3-outline-variant)' }}
            >
              −
            </button>
            <span class="text-base font-semibold w-6 text-center">{count}</span>
            <button
              type="button"
              onClick={() => setCount((current) => clampCreationCount(current + 1))}
              disabled={closing || count >= MAX_CREATION_COUNT}
              class="oh-tap-press w-8 h-8 rounded-full flex items-center justify-center text-lg disabled:opacity-30"
              style={{ border: '1px solid var(--m3-outline-variant)' }}
            >
              +
            </button>
          </div>
        </div>
      </div>
      <div class="flex justify-end gap-3 pt-4">
        <button
          type="button"
          onClick={requestCancel}
          disabled={closing}
          class="oh-tap-press px-5 py-2.5 rounded-full text-sm font-medium"
          style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
        >
          {t('common.cancel', '取消')}
        </button>
        <button
          type="button"
          onClick={requestConfirm}
          disabled={closing}
          class="oh-tap-press px-5 py-2.5 rounded-full text-sm font-medium disabled:opacity-60"
          style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
        >
          {t('common.confirm', '确认')}
        </button>
      </div>
    </DialogFrame>
  );
}
