// OpenHand Web 端 M3 Expressive 设计 token。
// 颜色 token 通过 /api/meta 的 theme 字段从 Flutter 主控制台动态注入到
// `:root { --m3-* }`，组件统一通过 CSS 变量取色，保证与桌面端 OpenHand
// 主题变更同步（不需要重新构建 web 包）。fallback 默认值取 deep_sea_blue
// 预设的种子色推导，匹配 Flutter 端 OpenHandThemePreset.deepSeaBlue。

export interface M3ThemeTokens {
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  secondary: string;
  onSecondary: string;
  secondaryContainer: string;
  onSecondaryContainer: string;
  tertiary: string;
  onTertiary: string;
  tertiaryContainer: string;
  onTertiaryContainer: string;
  surface: string;
  surfaceContainerLowest: string;
  surfaceContainerLow: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  surfaceContainerHighest: string;
  onSurface: string;
  onSurfaceVariant: string;
  outline: string;
  outlineVariant: string;
  inverseSurface: string;
  inverseOnSurface: string;
  error: string;
  errorContainer: string;
  onErrorContainer: string;
  brightness: 'light' | 'dark';
}

export const defaultThemeTokens: M3ThemeTokens = {
  primary: '#2D63B8',
  onPrimary: '#FFFFFF',
  primaryContainer: '#D8E2FF',
  onPrimaryContainer: '#001A42',
  secondary: '#565F71',
  onSecondary: '#FFFFFF',
  secondaryContainer: '#DAE2F9',
  onSecondaryContainer: '#131C2B',
  tertiary: '#705575',
  onTertiary: '#FFFFFF',
  tertiaryContainer: '#FAD8FD',
  onTertiaryContainer: '#28132E',
  surface: '#FDFCFF',
  surfaceContainerLowest: '#FFFFFF',
  surfaceContainerLow: '#F7F9FF',
  surfaceContainer: '#EEF1F8',
  surfaceContainerHigh: '#E8ECF4',
  surfaceContainerHighest: '#E2E6EE',
  onSurface: '#1A1C1E',
  onSurfaceVariant: '#43474E',
  outline: '#73777F',
  outlineVariant: '#C3C7D0',
  inverseSurface: '#2F3033',
  inverseOnSurface: '#F1F0F4',
  error: '#B3261E',
  errorContainer: '#F9DEDC',
  onErrorContainer: '#410E0B',
  brightness: 'light',
};

/// 把 token 写入 `:root`，让所有 `var(--m3-*)` 立刻生效。
export function applyThemeTokens(tokens: M3ThemeTokens): void {
  const root = document.documentElement;
  root.style.setProperty('--m3-primary', tokens.primary);
  root.style.setProperty('--m3-on-primary', tokens.onPrimary);
  root.style.setProperty('--m3-primary-container', tokens.primaryContainer);
  root.style.setProperty('--m3-on-primary-container', tokens.onPrimaryContainer);
  root.style.setProperty('--m3-secondary', tokens.secondary);
  root.style.setProperty('--m3-on-secondary', tokens.onSecondary);
  root.style.setProperty('--m3-secondary-container', tokens.secondaryContainer);
  root.style.setProperty('--m3-on-secondary-container', tokens.onSecondaryContainer);
  root.style.setProperty('--m3-tertiary', tokens.tertiary);
  root.style.setProperty('--m3-on-tertiary', tokens.onTertiary);
  root.style.setProperty('--m3-tertiary-container', tokens.tertiaryContainer);
  root.style.setProperty('--m3-on-tertiary-container', tokens.onTertiaryContainer);
  root.style.setProperty('--m3-surface', tokens.surface);
  root.style.setProperty('--m3-surface-container-lowest', tokens.surfaceContainerLowest);
  root.style.setProperty('--m3-surface-container-low', tokens.surfaceContainerLow);
  root.style.setProperty('--m3-surface-container', tokens.surfaceContainer);
  root.style.setProperty('--m3-surface-container-high', tokens.surfaceContainerHigh);
  root.style.setProperty('--m3-surface-container-highest', tokens.surfaceContainerHighest);
  root.style.setProperty('--m3-on-surface', tokens.onSurface);
  root.style.setProperty('--m3-on-surface-variant', tokens.onSurfaceVariant);
  root.style.setProperty('--m3-outline', tokens.outline);
  root.style.setProperty('--m3-outline-variant', tokens.outlineVariant);
  root.style.setProperty('--m3-inverse-surface', tokens.inverseSurface);
  root.style.setProperty('--m3-inverse-on-surface', tokens.inverseOnSurface);
  root.style.setProperty('--m3-error', tokens.error);
  root.style.setProperty('--m3-error-container', tokens.errorContainer);
  root.style.setProperty('--m3-on-error-container', tokens.onErrorContainer);
  root.dataset.brightness = tokens.brightness;
}
