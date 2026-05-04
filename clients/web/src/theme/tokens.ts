// OpenHand Web 端 M3 Expressive 设计 token。
// 颜色 token 通过 /api/meta 的 theme 字段从 Flutter 主控制台动态注入到
// `:root { --m3-* }`，组件统一通过 CSS 变量取色，保证与桌面端 OpenHand
// 主题变更同步（不需要重新构建 web 包）。fallback 默认值取 deep_sea_blue
// 预设的种子色推导，匹配 Flutter 端 OpenHandThemePreset.deepSeaBlue。

export interface M3ThemeTokens {
  primary: string;
  onPrimary: string;
  surface: string;
  surfaceContainer: string;
  onSurface: string;
  onSurfaceVariant: string;
  outline: string;
  error: string;
  brightness: 'light' | 'dark';
}

export const defaultThemeTokens: M3ThemeTokens = {
  primary: '#2D63B8',
  onPrimary: '#FFFFFF',
  surface: '#FDFCFF',
  surfaceContainer: '#EEF1F8',
  onSurface: '#1A1C1E',
  onSurfaceVariant: '#43474E',
  outline: '#73777F',
  error: '#B3261E',
  brightness: 'light',
};

/// 把 token 写入 `:root`，让所有 `var(--m3-*)` 立刻生效。
export function applyThemeTokens(tokens: M3ThemeTokens): void {
  const root = document.documentElement;
  root.style.setProperty('--m3-primary', tokens.primary);
  root.style.setProperty('--m3-on-primary', tokens.onPrimary);
  root.style.setProperty('--m3-surface', tokens.surface);
  root.style.setProperty('--m3-surface-container', tokens.surfaceContainer);
  root.style.setProperty('--m3-on-surface', tokens.onSurface);
  root.style.setProperty('--m3-on-surface-variant', tokens.onSurfaceVariant);
  root.style.setProperty('--m3-outline', tokens.outline);
  root.style.setProperty('--m3-error', tokens.error);
  root.dataset.brightness = tokens.brightness;
}
