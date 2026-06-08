export interface ApiDialogAnimationSettings {
  entrance_style?: string;
  exit_style?: string;
  duration_ms?: number | string;
  curve?: string;
}

const styleValues = new Set([
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
]);

const curveValues = new Set([
  'ease_in_out',
  'ease_out',
  'ease_out_cubic',
  'ease_in_out_cubic_emphasized',
  'elastic_out',
  'bounce_out',
  'decelerate',
]);

export const DIALOG_MOTION_DEFAULT_DURATION_MS = 320;
export const DIALOG_MOTION_MAX_DURATION_MS = 1200;

const defaultSettings = {
  entranceStyle: 'fade_scale',
  exitStyle: 'fade_scale',
  durationMs: DIALOG_MOTION_DEFAULT_DURATION_MS,
  curve: 'ease_out_cubic',
};

let currentSettings = { ...defaultSettings };

function normalizeStyle(value: string | undefined, fallback: string): string {
  return value && styleValues.has(value) ? value : fallback;
}

function normalizeCurve(value: string | undefined): string {
  return value && curveValues.has(value) ? value : defaultSettings.curve;
}

function normalizeDuration(value: number | string | undefined): number {
  const numericValue =
    typeof value === 'string' ? Number(value.trim()) : value;
  if (typeof numericValue !== 'number' || !Number.isFinite(numericValue)) {
    return defaultSettings.durationMs;
  }
  return Math.max(
    0,
    Math.min(DIALOG_MOTION_MAX_DURATION_MS, Math.round(numericValue)),
  );
}

function curveToCss(curve: string): string {
  switch (curve) {
    case 'ease_in_out':
      return 'ease-in-out';
    case 'ease_out':
      return 'ease-out';
    case 'ease_in_out_cubic_emphasized':
      return 'cubic-bezier(0.2, 0, 0, 1)';
    case 'elastic_out':
      return 'cubic-bezier(0.34, 1.56, 0.64, 1)';
    case 'bounce_out':
      return 'cubic-bezier(0.22, 1.45, 0.36, 1)';
    case 'decelerate':
      return 'cubic-bezier(0, 0, 0.2, 1)';
    case 'ease_out_cubic':
    default:
      return 'cubic-bezier(0.215, 0.61, 0.355, 1)';
  }
}

function reverseCurveToCss(curve: string): string {
  switch (curve) {
    case 'ease_in_out':
      return 'ease-in-out';
    case 'ease_in_out_cubic_emphasized':
      return 'cubic-bezier(0.2, 0, 0, 1)';
    case 'decelerate':
      return 'cubic-bezier(0, 0, 0.2, 1)';
    case 'ease_out_cubic':
      return 'cubic-bezier(0.55, 0.055, 0.675, 0.19)';
    case 'ease_out':
    case 'elastic_out':
    case 'bounce_out':
    default:
      return 'ease-in';
  }
}

export function syncRemoteDialogMotionSettings(
  raw: ApiDialogAnimationSettings | undefined,
): void {
  currentSettings = {
    entranceStyle: normalizeStyle(raw?.entrance_style, defaultSettings.entranceStyle),
    exitStyle: normalizeStyle(raw?.exit_style, defaultSettings.exitStyle),
    durationMs: normalizeDuration(raw?.duration_ms),
    curve: normalizeCurve(raw?.curve),
  };
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  root.dataset.dialogEnter = currentSettings.entranceStyle;
  root.dataset.dialogExit = currentSettings.exitStyle;
  root.style.setProperty('--oh-dialog-duration', `${currentSettings.durationMs}ms`);
  root.style.setProperty('--oh-dialog-curve', curveToCss(currentSettings.curve));
  root.style.setProperty('--oh-dialog-exit-curve', reverseCurveToCss(currentSettings.curve));
}

export function getDialogExitDurationMs(): number {
  return currentSettings.exitStyle === 'none' ? 0 : currentSettings.durationMs;
}

/// 进场（展开）动画时长：entrance_style=none 时返回 0；否则使用全局 durationMs。
export function getDialogEnterDurationMs(): number {
  return currentSettings.entranceStyle === 'none' ? 0 : currentSettings.durationMs;
}

/// 供 CollapsibleCardBody 等复用：同时反映进场 + 退场 duration（取较大值作
/// 为“一个交互的完整节奏”）。避免 collapse 与 expand 节奏相差过大。
export function getDialogMotionDurationMs(): number {
  const enter = getDialogEnterDurationMs();
  const exit = getDialogExitDurationMs();
  return enter === 0 && exit === 0 ? 0 : Math.max(enter, exit);
}

/// 展开（enter 方向）缓动曲线，CSS 字符串形式，可直接传给 WAAPI。
export function getDialogMotionCurve(): string {
  return curveToCss(currentSettings.curve);
}

/// 折叠（exit 方向）缓动曲线，CSS 字符串形式，可直接传给 WAAPI。
export function getDialogMotionExitCurve(): string {
  return reverseCurveToCss(currentSettings.curve);
}
