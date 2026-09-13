// 多媒体生成选项弹窗：对齐 APP 端 _CreationOptionsDialog 的参数与居中弹窗动效。
import { useRef, useState } from 'preact/hooks';
import { t, tFmt } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { normalizeInteger, strictPositiveIntegerFromText } from '../shared/util/number';
import {
  creationBackgroundLabel,
  creationMultiplierLabel,
  creationQualityLabel,
  creationStyleLabel,
  creationVideoModeLabel,
} from '../shared/ui/creation_option_labels';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_PRIORITY_Z_INDEX,
  DialogActionButton,
  DialogFrame,
  DialogHeader,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import {
  DIALOG_ACCENT,
  DIALOG_FOOTER_VARIANT,
  DialogFooterActions,
  DialogGlyph,
  DialogIconBadge,
  DialogSectionCard,
  type DialogGlyphName,
} from './DialogChrome';

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

function modeCopy(mode: string): {
  title: string;
  subtitle: string;
  glyph: DialogGlyphName;
  accent: string;
} {
  switch (mode) {
    case 'video':
      return {
        title: t('creation.options.videoTitle', '视频生成选项'),
        subtitle: t('creation.options.videoSubtitle', '画面、运动节奏与生成控制'),
        glyph: 'video',
        accent: DIALOG_ACCENT.secondary,
      };
    case 'audio':
      return {
        title: t('creation.options.audioTitle', '音频生成选项'),
        subtitle: t('creation.options.audioSubtitle', '音色、编码与播放参数'),
        glyph: 'audio',
        accent: DIALOG_ACCENT.tertiary,
      };
    default:
      return {
        title: t('creation.options.imageTitle', '图像生成选项'),
        subtitle: t('creation.options.imageSubtitle', '画面比例、质量与生成控制'),
        glyph: 'image',
        accent: DIALOG_ACCENT.primary,
      };
  }
}

function trimToUndefined(value: string): string | undefined {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function chipClass(active: boolean): string {
  return `oh-tap-press oh-creation-chip ${active ? 'is-active' : ''}`;
}

interface ChipGroupProps<T extends string | number | boolean> {
  title: string;
  values: readonly T[];
  selected: T | undefined;
  labelFor?: (value: T) => string;
  onSelect: (value: T | undefined) => void;
  allowUnset?: boolean;
}

function ChipGroup<T extends string | number | boolean>({
  title,
  values,
  selected,
  labelFor = (value) => String(value),
  onSelect,
  allowUnset = true,
}: ChipGroupProps<T>) {
  return (
    <div class="oh-creation-field">
      <p class="oh-creation-field-label">{title}</p>
      <div class="oh-creation-chip-row">
        {allowUnset ? (
          <button
            type="button"
            onClick={() => onSelect(undefined)}
            class={chipClass(selected === undefined)}
          >
            {selected === undefined ? `✓ ${t('creation.options.auto', '默认')}` : t('creation.options.auto', '默认')}
          </button>
        ) : null}
        {values.map((value) => {
          const active = selected === value;
          const label = labelFor(value);
          return (
            <button
              key={String(value)}
              type="button"
              onClick={() => onSelect(value)}
              class={chipClass(active)}
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
  return (
    <ChipGroup
      title={title}
      values={[true, false]}
      selected={value}
      labelFor={(item) => item ? t('creation.options.on', '开') : t('creation.options.off', '关')}
      onSelect={onChange}
    />
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
  const sharedClass = 'oh-creation-input';
  return (
    <label class="oh-creation-field">
      <span class="oh-creation-field-label">{label}</span>
      {rows > 1 ? (
        <textarea
          value={value}
          rows={rows}
          onInput={(event) => onInput((event.currentTarget as HTMLTextAreaElement).value)}
          class={sharedClass}
        />
      ) : (
        <input
          type={type}
          value={value}
          onInput={(event) => onInput((event.currentTarget as HTMLInputElement).value)}
          class={sharedClass}
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

  const copy = modeCopy(mode);
  const ratios = mode === 'image' ? IMAGE_RATIOS : mode === 'video' ? VIDEO_RATIOS : [];

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestCancel}
      closeOnBackdrop={!closing}
      {...createStandardDialogFrameAppearance({
        overlayClassName: DIALOG_OVERLAY_CENTER_CLASS,
        overlay: {
          background: 'color-mix(in srgb, black 38%, transparent)',
          blurPx: 0,
        },
        overlayZIndex: DIALOG_OVERLAY_PRIORITY_Z_INDEX,
        panelClassName: 'oh-creation-options-dialog rounded-2xl overflow-hidden flex flex-col',
        panelBorder: 'none',
        panelSurface: {
          boxShadow: 'var(--m3-elev-4)',
        },
      })}
      ariaLabel={copy.title}
    >
      <DialogHeader
        title={copy.title}
        subtitle={copy.subtitle}
        icon={
          <DialogIconBadge accent={copy.accent}>
            <DialogGlyph name={copy.glyph} />
          </DialogIconBadge>
        }
        onClose={requestCancel}
        closeLabel={t('common.close', '关闭')}
        closeDisabled={closing}
      />
      <div class="oh-creation-options-body">
        {mode === 'image' || mode === 'video' ? (
          <DialogSectionCard
            title={t('creation.options.sectionFrame', '画面')}
            subtitle={t('creation.options.sectionFrameHint', '比例、分辨率与输出样式')}
            accent={DIALOG_ACCENT.primary}
            icon={<DialogGlyph name="crop" />}
          >
            {ratios.length > 0 ? (
              <ChipGroup
                title={t('creation.options.aspectRatio', '宽高比')}
                values={ratios}
                selected={aspectRatio}
                onSelect={setAspectRatio}
                allowUnset={false}
              />
            ) : null}
            {mode === 'video' ? (
              <ChipGroup
                title={t('creation.options.resolution', '分辨率')}
                values={VIDEO_RESOLUTIONS}
                selected={resolution}
                onSelect={setResolution}
              />
            ) : null}
            {mode === 'image' ? (
              <>
                <ChipGroup
                  title={t('creation.options.quality', '质量')}
                  values={IMAGE_QUALITIES}
                  selected={quality}
                  labelFor={creationQualityLabel}
                  onSelect={setQuality}
                />
                <ChipGroup
                  title={t('creation.options.style', '风格')}
                  values={IMAGE_STYLES}
                  selected={style}
                  labelFor={creationStyleLabel}
                  onSelect={setStyle}
                />
                <ChipGroup
                  title={t('creation.options.outputFormat', '输出格式')}
                  values={IMAGE_FORMATS}
                  selected={outputFormat}
                  onSelect={setOutputFormat}
                />
                <ChipGroup
                  title={t('creation.options.background', '背景')}
                  values={IMAGE_BACKGROUNDS}
                  selected={background}
                  labelFor={creationBackgroundLabel}
                  onSelect={setBackground}
                />
              </>
            ) : null}
          </DialogSectionCard>
        ) : null}

        {mode === 'video' ? (
          <DialogSectionCard
            title={t('creation.options.sectionMotion', '运动')}
            subtitle={t('creation.options.sectionMotionHint', '时长、帧率与生成模式')}
            accent={DIALOG_ACCENT.tertiary}
            icon={<DialogGlyph name="bolt" />}
          >
            <ChipGroup
              title={t('creation.options.duration', '时长')}
              values={VIDEO_DURATIONS}
              selected={durationSeconds}
              labelFor={(value) => tFmt('creation.options.durationSeconds', { count: value }, '{count} 秒')}
              onSelect={setDurationSeconds}
              allowUnset={false}
            />
            <ChipGroup
              title={t('creation.options.frameRate', '帧率')}
              values={VIDEO_FRAME_RATES}
              selected={frameRate}
              labelFor={(value) => tFmt('creation.options.frameRateFps', { rate: value }, '{rate} 帧/秒')}
              onSelect={setFrameRate}
            />
            <ChipGroup
              title={t('creation.options.frames', '帧数')}
              values={VIDEO_FRAMES}
              selected={numFrames}
              onSelect={setNumFrames}
            />
            <ChipGroup
              title={t('creation.options.mode', '模式')}
              values={VIDEO_MODES}
              selected={videoMode}
              labelFor={creationVideoModeLabel}
              onSelect={setVideoMode}
            />
          </DialogSectionCard>
        ) : null}

        {mode === 'image' || mode === 'video' ? (
          <DialogSectionCard
            title={t('creation.options.sectionGenerate', '生成控制')}
            subtitle={t('creation.options.sectionGenerateHint', '提示词增强、水印与随机种子')}
            accent={DIALOG_ACCENT.warning}
            icon={<DialogGlyph name="spark" />}
          >
            <TriStateGroup
              title={t('creation.options.promptEnhance', '提示词增强')}
              value={promptEnhance}
              onChange={setPromptEnhance}
            />
            <TriStateGroup
              title={t('creation.options.watermark', '水印')}
              value={watermark}
              onChange={setWatermark}
            />
            <TextOption
              label={t('creation.options.negativePrompt', '负向提示')}
              value={negativePrompt}
              onInput={setNegativePrompt}
              rows={2}
            />
            <TextOption
              label={t('creation.options.seed', '随机种子')}
              value={seed}
              onInput={setSeed}
              type="number"
            />
          </DialogSectionCard>
        ) : null}

        {mode === 'audio' ? (
          <>
            <DialogSectionCard
              title={t('creation.options.sectionSound', '声音')}
              subtitle={t('creation.options.sectionSoundHint', '音色、语速、音量与音高')}
              accent={DIALOG_ACCENT.success}
              icon={<DialogGlyph name="audio" />}
            >
              <div class="oh-creation-field">
                <p class="oh-creation-field-label">
                  {t('creation.options.voice', '音色')}
                </p>
                <div class="oh-creation-chip-row">
                  <button
                    type="button"
                    onClick={() => setOmitVoice(true)}
                    class={chipClass(omitVoice)}
                  >
                    {omitVoice
                      ? `✓ ${t('creation.options.voiceUnspecified', '不指定')}`
                      : t('creation.options.voiceUnspecified', '不指定')}
                  </button>
                  <button
                    type="button"
                    onClick={() => setOmitVoice(false)}
                    class={chipClass(!omitVoice)}
                  >
                    {!omitVoice
                      ? `✓ ${t('creation.options.customVoice', '自定义标识')}`
                      : t('creation.options.customVoice', '自定义标识')}
                  </button>
                </div>
              </div>
              {!omitVoice ? (
                <TextOption
                  label={t('creation.options.customVoiceId', '自定义音色标识')}
                  value={voice}
                  onInput={setVoice}
                />
              ) : null}
              <ChipGroup
                title={t('creation.options.duration', '时长')}
                values={AUDIO_DURATIONS}
                selected={durationSeconds}
                labelFor={(value) => tFmt('creation.options.durationSeconds', { count: value }, '{count} 秒')}
                onSelect={setDurationSeconds}
                allowUnset={false}
              />
              <ChipGroup
                title={t('creation.options.speed', '语速')}
                values={AUDIO_SPEEDS}
                selected={speed}
                labelFor={creationMultiplierLabel}
                onSelect={setSpeed}
              />
              <ChipGroup
                title={t('creation.options.volume', '音量')}
                values={AUDIO_VOLUMES}
                selected={volume}
                labelFor={creationMultiplierLabel}
                onSelect={setVolume}
              />
              <ChipGroup
                title={t('creation.options.pitch', '音高')}
                values={AUDIO_PITCHES}
                selected={pitch}
                onSelect={setPitch}
              />
            </DialogSectionCard>
            <DialogSectionCard
              title={t('creation.options.sectionEncode', '编码')}
              subtitle={t('creation.options.sectionEncodeHint', '格式、采样率与码率')}
              accent={DIALOG_ACCENT.info}
              icon={<DialogGlyph name="cpu" />}
            >
              <ChipGroup
                title={t('creation.options.audioFormat', '音频格式')}
                values={AUDIO_FORMATS}
                selected={outputFormat}
                onSelect={setOutputFormat}
              />
              <ChipGroup
                title={t('creation.options.sampleRate', '采样率')}
                values={AUDIO_SAMPLE_RATES}
                selected={sampleRate}
                onSelect={setSampleRate}
              />
              <ChipGroup
                title={t('creation.options.bitrate', '码率')}
                values={AUDIO_BITRATES}
                selected={bitrate}
                labelFor={(value) => tFmt('creation.options.bitrateKbps', { rate: Math.round(value / 1000) }, '{rate} 千比特/秒')}
                onSelect={setBitrate}
              />
            </DialogSectionCard>
          </>
        ) : null}

        <DialogSectionCard
          title={t('creation.options.sectionCount', '数量')}
          subtitle={t('creation.options.sectionCountHint', '一次生成的条数')}
          accent={DIALOG_ACCENT.caution}
          icon={<DialogGlyph name="hash" />}
        >
          <div class="oh-creation-count">
            <button
              type="button"
              onClick={() => setCount((current) => clampCreationCount(current - 1))}
              disabled={closing || count <= MIN_CREATION_COUNT}
              class="oh-tap-press oh-creation-count-button"
            >
              −
            </button>
            <span class="oh-creation-count-value">{count}</span>
            <button
              type="button"
              onClick={() => setCount((current) => clampCreationCount(current + 1))}
              disabled={closing || count >= MAX_CREATION_COUNT}
              class="oh-tap-press oh-creation-count-button"
            >
              +
            </button>
          </div>
        </DialogSectionCard>
      </div>
      <DialogFooterActions variant={DIALOG_FOOTER_VARIANT.divided}>
        <DialogActionButton tone="secondary" onClick={requestCancel} disabled={closing} className="oh-creation-options-action">
          {t('common.cancel', '取消')}
        </DialogActionButton>
        <DialogActionButton tone="primary" onClick={requestConfirm} disabled={closing} className="oh-creation-options-action">
          {t('common.confirm', '确认')}
        </DialogActionButton>
      </DialogFooterActions>
    </DialogFrame>
  );
}
