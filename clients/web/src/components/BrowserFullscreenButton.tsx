import { t } from '../i18n';
import { svgIconProps } from '../shared/ui/svg_icon';

export function BrowserFullscreenIcon({
  active,
  size = 17,
  className,
}: {
  active: boolean;
  size?: number;
  className?: string;
}) {
  const common = svgIconProps({ size, strokeWidth: 1.9, class: className });
  return active ? (
    <svg {...common}><path d="M10 4v6H4" /><path d="m10 10-6-6" /><path d="M14 4v6h6" /><path d="m14 10 6-6" /><path d="M10 20v-6H4" /><path d="m10 14-6 6" /><path d="M14 20v-6h6" /><path d="m14 14 6 6" /></svg>
  ) : (
    <svg {...common}><path d="M8 4H4v4" /><path d="M4 4l6 6" /><path d="M16 4h4v4" /><path d="m20 4-6 6" /><path d="M8 20H4v-4" /><path d="m4 20 6-6" /><path d="M16 20h4v-4" /><path d="m20 20-6-6" /></svg>
  );
}

export function BrowserFullscreenButton({
  active,
  onClick,
}: {
  active: boolean;
  onClick: () => void;
}) {
  const label = active
    ? t('topbar.fullscreen.exit', '退出全屏')
    : t('topbar.fullscreen.enter', '浏览器全屏');
  return (
    <button
      type="button"
      onClick={onClick}
      class="oh-tap-press oh-icon-button oh-session-fullscreen-button flex-none"
      style={{
        color: active ? 'var(--m3-primary)' : 'var(--m3-on-surface-variant)',
        border: active
          ? '1px solid color-mix(in srgb, var(--m3-primary) 48%, var(--m3-outline-variant))'
          : '1px solid var(--m3-outline-variant)',
        background: active ? 'var(--m3-primary-container)' : 'var(--m3-surface)',
      }}
      title={label}
      aria-label={label}
      aria-pressed={active}
    >
      <BrowserFullscreenIcon active={active} />
    </button>
  );
}
