import { t, tFmt } from '../../i18n';
import { strictPositiveIntegerFromUnknown, strictPositiveNumberFromUnknown } from '../util/number';
import { strictStringFromUnknown } from '../util/value';

export function creationQualityLabel(value: string): string {
  switch (value) {
    case 'auto':
      return t('creation.options.qualityAuto', '自动');
    case 'standard':
      return t('creation.options.qualityStandard', '标准');
    case 'hd':
      return t('creation.options.qualityHd', '高清');
    case 'high':
      return t('creation.options.qualityHigh', '最高');
    default:
      return value;
  }
}

export function creationStyleLabel(value: string): string {
  switch (value) {
    case 'natural':
      return t('creation.options.styleNatural', '自然');
    case 'vivid':
      return t('creation.options.styleVivid', '鲜明');
    default:
      return value;
  }
}

export function creationBackgroundLabel(value: string): string {
  switch (value) {
    case 'auto':
      return t('creation.options.backgroundAuto', '自动');
    case 'transparent':
      return t('creation.options.backgroundTransparent', '透明');
    case 'opaque':
      return t('creation.options.backgroundOpaque', '不透明');
    default:
      return value;
  }
}

export function creationVideoModeLabel(value: string): string {
  return value === 'keyframes'
    ? t('creation.options.modeKeyframes', '关键帧')
    : value;
}

export function creationMultiplierLabel(value: number): string {
  return tFmt('creation.options.multiplier', { value: String(value) }, '×{value}');
}

export function formatCreationOptionDetail(
  options: Record<string, unknown> | null,
): string {
  if (!options) return '';
  const parts: string[] = [];
  const aspectRatio = strictStringFromUnknown(options['aspect_ratio']);
  const size = strictStringFromUnknown(options['size']);
  const quality = strictStringFromUnknown(options['quality']);
  const style = strictStringFromUnknown(options['style']);
  const outputFormat = strictStringFromUnknown(options['output_format']);
  const background = strictStringFromUnknown(options['background']);
  const resolution = strictStringFromUnknown(options['resolution']);
  const mode = strictStringFromUnknown(options['mode']);
  const voice = strictStringFromUnknown(options['voice']);
  const omitVoice = options['omit_voice'] === true;
  const duration = strictPositiveIntegerFromUnknown(options['duration_seconds']);
  const count = strictPositiveIntegerFromUnknown(options['count']);
  const frameRate = strictPositiveIntegerFromUnknown(options['frame_rate']);
  const numFrames = strictPositiveIntegerFromUnknown(options['num_frames']);
  const seed = strictPositiveIntegerFromUnknown(options['seed']);
  const speed = strictPositiveNumberFromUnknown(options['speed']);
  const sampleRate = strictPositiveIntegerFromUnknown(options['sample_rate']);
  const bitrate = strictPositiveIntegerFromUnknown(options['bitrate']);
  if (aspectRatio) parts.push(aspectRatio);
  else if (size) parts.push(size);
  if (duration != null) {
    parts.push(tFmt('creation.options.durationSeconds', { count: duration }, '{count} 秒'));
  }
  if (resolution) parts.push(resolution);
  if (frameRate != null) {
    parts.push(tFmt('creation.options.frameRateFps', { rate: frameRate }, '{rate} 帧/秒'));
  }
  if (numFrames != null) {
    parts.push(tFmt('creation.options.framesValue', { count: numFrames }, '{count} 帧'));
  }
  if (quality) parts.push(creationQualityLabel(quality));
  if (style) parts.push(creationStyleLabel(style));
  if (outputFormat) parts.push(outputFormat);
  if (background) parts.push(creationBackgroundLabel(background));
  if (mode) parts.push(creationVideoModeLabel(mode));
  if (voice) parts.push(voice);
  if (omitVoice) parts.push(t('creation.options.voiceUnspecified', '不指定'));
  if (speed != null) parts.push(creationMultiplierLabel(speed));
  if (sampleRate != null) {
    parts.push(tFmt('creation.options.sampleRateValue', { rate: sampleRate }, '{rate} 赫兹'));
  }
  if (bitrate != null) {
    parts.push(
      tFmt('creation.options.bitrateKbps', { rate: Math.round(bitrate / 1000) }, '{rate} 千比特/秒'),
    );
  }
  if (seed != null) {
    parts.push(tFmt('creation.options.seedValue', { value: seed }, '随机种子 {value}'));
  }
  if (typeof options['prompt_enhance'] === 'boolean') {
    parts.push(
      options['prompt_enhance']
        ? t('creation.options.promptEnhanceOn', '已增强提示词')
        : t('creation.options.promptEnhanceOff', '未增强提示词'),
    );
  }
  if (typeof options['watermark'] === 'boolean') {
    parts.push(
      options['watermark']
        ? t('creation.options.watermarkOn', '含水印')
        : t('creation.options.watermarkOff', '无水印'),
    );
  }
  if (strictStringFromUnknown(options['negative_prompt'])) {
    parts.push(t('creation.options.negativeOn', '含负向提示'));
  }
  if (count != null && count > 1) {
    parts.push(tFmt('creation.options.countValue', { count }, '×{count}'));
  }
  return parts.join(' · ');
}
