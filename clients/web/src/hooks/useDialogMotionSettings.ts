import { normalizeDurationMs } from '../shared/util/number';
import {
  finiteNumberOrNullFromUnknown,
  stringFromUnknown,
} from '../shared/util/value';

export interface ApiDialogAnimationSettings {
  entrance_style?: string;
  exit_style?: string;
  duration_ms?: number | string;
  curve?: string;
}

const DIALOG_MOTION_STYLE_VALUES = [
  'none',
  'fade',
  'fade_scale',
  'slide_up',
  'slide_down',
  'slide_left',
  'slide_right',
  'expand',
  'rotate_scale',
  'elastic',
  'spring_scale',
  'flip_x',
] as const;

type DialogMotionStyle = (typeof DIALOG_MOTION_STYLE_VALUES)[number];

const DIALOG_MOTION_CURVE_VALUES = [
  'ease_in_out',
  'ease_out',
  'ease_out_cubic',
  'ease_in_out_cubic_emphasized',
  'elastic_out',
  'bounce_out',
  'decelerate',
] as const;

type DialogMotionCurve = (typeof DIALOG_MOTION_CURVE_VALUES)[number];

export const DIALOG_MOTION_DEFAULT_DURATION_MS = 360;
const DIALOG_MOTION_MIN_ANIMATED_DURATION_MS = 80;
const DIALOG_MOTION_MAX_DURATION_MS = 1200;
const DIALOG_MOTION_DEFAULT_STYLE: DialogMotionStyle = 'spring_scale';
const DIALOG_MOTION_DEFAULT_CURVE: DialogMotionCurve = 'ease_out_cubic';
const DIALOG_MOTION_DEFAULT_CSS_CURVE = 'cubic-bezier(0.215, 0.61, 0.355, 1)';
const DIALOG_MOTION_DEFAULT_REVERSE_CSS_CURVE =
  'cubic-bezier(0.55, 0.055, 0.675, 0.19)';

interface DialogMotionSettings {
  entranceStyle: DialogMotionStyle;
  exitStyle: DialogMotionStyle;
  durationMs: number;
  curve: DialogMotionCurve;
}

const styleValues = new Set<string>(DIALOG_MOTION_STYLE_VALUES);
const curveValues = new Set<string>(DIALOG_MOTION_CURVE_VALUES);

const DEFAULT_DIALOG_MOTION_SETTINGS: DialogMotionSettings = {
  entranceStyle: DIALOG_MOTION_DEFAULT_STYLE,
  exitStyle: DIALOG_MOTION_DEFAULT_STYLE,
  durationMs: DIALOG_MOTION_DEFAULT_DURATION_MS,
  curve: DIALOG_MOTION_DEFAULT_CURVE,
};

let currentSettings = { ...DEFAULT_DIALOG_MOTION_SETTINGS };

const DIALOG_MOTION_CURVE_CSS: Record<DialogMotionCurve, string> = {
  ease_in_out: 'ease-in-out',
  ease_out: 'ease-out',
  ease_out_cubic: DIALOG_MOTION_DEFAULT_CSS_CURVE,
  ease_in_out_cubic_emphasized: 'cubic-bezier(0.2, 0, 0, 1)',
  elastic_out: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
  bounce_out: 'cubic-bezier(0.22, 1.45, 0.36, 1)',
  decelerate: 'cubic-bezier(0, 0, 0.2, 1)',
};

const DIALOG_MOTION_REVERSE_CURVE_CSS: Record<DialogMotionCurve, string> = {
  ease_in_out: 'ease-in-out',
  ease_out: 'ease-in',
  ease_out_cubic: DIALOG_MOTION_DEFAULT_REVERSE_CSS_CURVE,
  ease_in_out_cubic_emphasized: 'cubic-bezier(0.2, 0, 0, 1)',
  elastic_out: 'ease-in',
  bounce_out: 'ease-in',
  decelerate: 'cubic-bezier(0, 0, 0.2, 1)',
};

function isDialogMotionStyle(value: string | undefined): value is DialogMotionStyle {
  return value != null && styleValues.has(value);
}

function isDialogMotionCurve(value: string | undefined): value is DialogMotionCurve {
  return value != null && curveValues.has(value);
}

function normalizeStyle(
  value: string | undefined,
  fallback: DialogMotionStyle,
): DialogMotionStyle {
  return isDialogMotionStyle(value) ? value : fallback;
}

function normalizeCurve(value: string | undefined): DialogMotionCurve {
  return isDialogMotionCurve(value)
    ? value
    : DEFAULT_DIALOG_MOTION_SETTINGS.curve;
}

function normalizeDuration(value: number | string | undefined): number {
  const numericValue = finiteNumberOrNullFromUnknown(value);
  return normalizeDurationMs(
    numericValue == null || numericValue <= 0
      ? DEFAULT_DIALOG_MOTION_SETTINGS.durationMs
      : numericValue,
    {
      fallback: DEFAULT_DIALOG_MOTION_SETTINGS.durationMs,
      min: DIALOG_MOTION_MIN_ANIMATED_DURATION_MS,
      max: DIALOG_MOTION_MAX_DURATION_MS,
    },
  );
}

function curveToCss(curve: DialogMotionCurve): string {
  return DIALOG_MOTION_CURVE_CSS[curve] ?? DIALOG_MOTION_DEFAULT_CSS_CURVE;
}

function reverseCurveToCss(curve: DialogMotionCurve): string {
  return (
    DIALOG_MOTION_REVERSE_CURVE_CSS[curve] ??
    DIALOG_MOTION_DEFAULT_REVERSE_CSS_CURVE
  );
}

function applyDialogMotionSettingsToDocument(): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  root.dataset.dialogEnter = currentSettings.entranceStyle;
  root.dataset.dialogExit = currentSettings.exitStyle;
  root.style.setProperty(
    '--oh-dialog-duration',
    `${getDialogMotionDurationMs()}ms`,
  );
  root.style.setProperty(
    '--oh-dialog-enter-duration',
    `${getDialogEnterDurationMs()}ms`,
  );
  root.style.setProperty(
    '--oh-dialog-exit-duration',
    `${getDialogExitDurationMs()}ms`,
  );
  root.style.setProperty('--oh-dialog-curve', curveToCss(currentSettings.curve));
  root.style.setProperty('--oh-dialog-exit-curve', reverseCurveToCss(currentSettings.curve));
}

export function initDialogMotionSettingsAttribute(): void {
  applyDialogMotionSettingsToDocument();
}

function normalizeDialogMotionSettings(
  raw: ApiDialogAnimationSettings | null | undefined,
): DialogMotionSettings {
  const entranceStyle = normalizeStyle(
    stringFromUnknown(raw?.entrance_style, { coerce: false }),
    DEFAULT_DIALOG_MOTION_SETTINGS.entranceStyle,
  );
  const exitStyle = normalizeStyle(
    stringFromUnknown(raw?.exit_style, { coerce: false }),
    DEFAULT_DIALOG_MOTION_SETTINGS.exitStyle,
  );
  return {
    entranceStyle,
    exitStyle,
    durationMs: normalizeDuration(raw?.duration_ms),
    curve: normalizeCurve(stringFromUnknown(raw?.curve, { coerce: false })),
  };
}

export function syncRemoteDialogMotionSettings(
  raw: ApiDialogAnimationSettings | null | undefined,
): void {
  currentSettings = normalizeDialogMotionSettings(raw);
  applyDialogMotionSettingsToDocument();
}

export function getDialogExitDurationMs(): number {
  return currentSettings.exitStyle === 'none' ? 0 : currentSettings.durationMs;
}

export function normalizeDialogExitDurationMs(value?: number): number {
  if (currentSettings.exitStyle === 'none') return 0;
  return normalizeDurationMs(value, {
    fallback: getDialogExitDurationMs(),
    min: 0,
    max: DIALOG_MOTION_MAX_DURATION_MS,
  });
}

// 进场（展开）动画时长：entrance_style=none 时返回 0；否则使用全局 durationMs。
export function getDialogEnterDurationMs(): number {
  return currentSettings.entranceStyle === 'none' ? 0 : currentSettings.durationMs;
}

// 供折叠面板等复用：同时反映进场 + 退场 duration（取较大值作
// 为“一个交互的完整节奏”）。避免 collapse 与 expand 节奏相差过大。
function getDialogMotionDurationMs(): number {
  const enter = getDialogEnterDurationMs();
  const exit = getDialogExitDurationMs();
  return enter === 0 && exit === 0 ? 0 : Math.max(enter, exit);
}

// 展开（enter 方向）缓动曲线，CSS 字符串形式，可直接传给 WAAPI。
export function getDialogMotionCurve(): string {
  return curveToCss(currentSettings.curve);
}

// 折叠（exit 方向）缓动曲线，CSS 字符串形式，可直接传给 WAAPI。
export function getDialogMotionExitCurve(): string {
  return reverseCurveToCss(currentSettings.curve);
}
