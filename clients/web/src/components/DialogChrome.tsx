import type { ComponentChildren, JSX } from 'preact';
import {
  STATUS_SUCCESS_COLOR,
  STATUS_WARNING_COLOR,
} from '../shared/ui/status_palette';
import { classNames } from '../shared/util/class_names';

export const DIALOG_ACCENT = {
  primary: 'var(--m3-primary)',
  secondary: 'var(--m3-secondary)',
  tertiary: 'var(--m3-tertiary)',
  success: STATUS_SUCCESS_COLOR,
  warning: STATUS_WARNING_COLOR,
  error: 'var(--m3-error)',
  info: '#3B82F6',
  caution: '#EAB308',
} as const;

export const DIALOG_ACCENT_CYCLE = [
  DIALOG_ACCENT.info,
  DIALOG_ACCENT.success,
  DIALOG_ACCENT.warning,
  DIALOG_ACCENT.tertiary,
  DIALOG_ACCENT.secondary,
  DIALOG_ACCENT.caution,
] as const;

export const DIALOG_SUMMARY_TILE_MIN_WIDTH_PX = 168;
export const DIALOG_ENTRY_LABEL_WIDTH_PX = 132;
export const DIALOG_ICON_BADGE_SIZE_PX = 36;
export const DIALOG_FOOTER_VARIANT = {
  inline: 'inline',
  padded: 'padded',
  divided: 'divided',
  confirm: 'confirm',
} as const;

export type DialogFooterActionsVariant =
  (typeof DIALOG_FOOTER_VARIANT)[keyof typeof DIALOG_FOOTER_VARIANT];

const DIALOG_PANEL_FILL_PERCENT = 10;
const DIALOG_SECTION_FILL_PERCENT = 8;
const DIALOG_CHIP_FILL_PERCENT = 12;
const DIALOG_ACCENT_BORDER_PERCENT = 22;
const DIALOG_SECTION_BORDER_PERCENT = 18;
const DIALOG_ICON_BADGE_FILL_PERCENT = 16;

export type DialogGlyphName =
  | 'layers'
  | 'chart'
  | 'spark'
  | 'chat'
  | 'hash'
  | 'clock'
  | 'cpu'
  | 'bolt'
  | 'file'
  | 'check'
  | 'alert'
  | 'model';

const DIALOG_GLYPHS: Record<DialogGlyphName, ComponentChildren> = {
  layers: (
    <>
      <path d="M12 2 2 7l10 5 10-5-10-5z" />
      <path d="m2 12 10 5 10-5" />
      <path d="m2 17 10 5 10-5" />
    </>
  ),
  chart: (
    <>
      <path d="M4 19V5" />
      <path d="M4 19h16" />
      <path d="M8 16v-5" />
      <path d="M12 16V8" />
      <path d="M16 16v-7" />
    </>
  ),
  spark: (
    <path d="M12 3 9.5 9.5 3 12l6.5 2.5L12 21l2.5-6.5L21 12l-6.5-2.5z" />
  ),
  chat: (
    <path d="M21 12a8 8 0 0 1-8 8H7l-4 3V12a8 8 0 1 1 18 0z" />
  ),
  hash: (
    <>
      <path d="M5 9h14" />
      <path d="M5 15h14" />
      <path d="m9 4-2 16" />
      <path d="m17 4-2 16" />
    </>
  ),
  clock: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v6l3.5 2" />
    </>
  ),
  cpu: (
    <>
      <rect x="6" y="6" width="12" height="12" rx="2" />
      <path d="M9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2" />
    </>
  ),
  bolt: <path d="M13 2 4 14h7l-1 8 9-12h-7z" />,
  file: (
    <>
      <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
      <path d="M14 3v5h5" />
    </>
  ),
  check: (
    <>
      <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
      <path d="M22 4 12 14.01 9 11.01" />
    </>
  ),
  alert: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M15 9 9 15" />
      <path d="m9 9 6 6" />
    </>
  ),
  model: (
    <>
      <path d="M21 8 12 3 3 8l9 5 9-5z" />
      <path d="m3 8 9 5v8" />
      <path d="m21 8-9 5v8" />
    </>
  ),
};

export function dialogAccentFill(
  accent: string,
  percent = DIALOG_PANEL_FILL_PERCENT,
): string {
  return `color-mix(in srgb, ${accent} ${percent}%, var(--m3-surface-container-low))`;
}

export function dialogAccentWash(
  accent: string,
  percent = DIALOG_PANEL_FILL_PERCENT,
): string {
  return `color-mix(in srgb, ${accent} ${percent}%, transparent)`;
}

export function dialogAccentBorder(
  accent: string,
  percent = DIALOG_ACCENT_BORDER_PERCENT,
): string {
  return `1px solid color-mix(in srgb, ${accent} ${percent}%, transparent)`;
}

export function DialogGlyph({
  name,
  size = 16,
}: {
  name: DialogGlyphName;
  size?: number;
}) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      {DIALOG_GLYPHS[name]}
    </svg>
  );
}

export function DialogIconBadge({
  accent,
  children,
  size = DIALOG_ICON_BADGE_SIZE_PX,
}: {
  accent: string;
  children: ComponentChildren;
  size?: number;
}) {
  return (
    <span
      class="oh-dialog-icon-badge"
      style={{
        width: size,
        height: size,
        color: accent,
        background: dialogAccentWash(accent, DIALOG_ICON_BADGE_FILL_PERCENT),
      }}
    >
      {children}
    </span>
  );
}

export function DialogTintedPanel({
  accent = DIALOG_ACCENT.primary,
  className,
  style,
  children,
}: {
  accent?: string;
  className?: string;
  style?: JSX.CSSProperties;
  children: ComponentChildren;
}) {
  return (
    <div
      class={classNames('oh-dialog-tinted-panel', className)}
      style={{
        background: dialogAccentFill(accent),
        border: dialogAccentBorder(accent),
        ...style,
      }}
    >
      {children}
    </div>
  );
}

export function DialogSectionCard({
  title,
  subtitle,
  icon,
  accent = DIALOG_ACCENT.primary,
  trailing,
  children,
  className,
}: {
  title: ComponentChildren;
  subtitle?: ComponentChildren;
  icon?: ComponentChildren;
  accent?: string;
  trailing?: ComponentChildren;
  children?: ComponentChildren;
  className?: string;
}) {
  return (
    <section
      class={classNames('oh-dialog-section-card', className)}
      style={{
        background: dialogAccentFill(accent, DIALOG_SECTION_FILL_PERCENT),
        border: dialogAccentBorder(accent, DIALOG_SECTION_BORDER_PERCENT),
      }}
    >
      <header class="oh-dialog-section-card-head">
        <DialogIconBadge accent={accent}>
          {icon ?? <DialogGlyph name="layers" />}
        </DialogIconBadge>
        <div class="min-w-0 flex-1">
          <h3 class="oh-dialog-section-card-title">{title}</h3>
          {subtitle ? (
            <p class="oh-dialog-section-card-subtitle">{subtitle}</p>
          ) : null}
        </div>
        {trailing ? <div class="shrink-0">{trailing}</div> : null}
      </header>
      {children != null ? (
        <div class="oh-dialog-section-card-body">{children}</div>
      ) : null}
    </section>
  );
}

export function DialogSummaryGrid({ children }: { children: ComponentChildren }) {
  return <div class="oh-dialog-summary-grid">{children}</div>;
}

export function DialogSummaryTile({
  label,
  value,
  accent = DIALOG_ACCENT.primary,
  icon,
}: {
  label: string;
  value: string;
  accent?: string;
  icon?: ComponentChildren;
}) {
  const display = value.trim() || '—';
  return (
    <DialogTintedPanel
      accent={accent}
      className="oh-dialog-summary-tile"
      style={{ flex: `1 1 ${DIALOG_SUMMARY_TILE_MIN_WIDTH_PX}px` }}
    >
      <div class="oh-dialog-summary-tile-inner">
        {icon ? <DialogIconBadge accent={accent}>{icon}</DialogIconBadge> : null}
        <div class="min-w-0 flex-1">
          <div class="oh-dialog-summary-tile-label">{label}</div>
          <div
            class="oh-dialog-summary-tile-value"
            style={{ color: accent }}
            title={display}
          >
            {display}
          </div>
        </div>
      </div>
    </DialogTintedPanel>
  );
}

export function DialogFactChip({
  label,
  accent = DIALOG_ACCENT.primary,
  icon,
}: {
  label: string;
  accent?: string;
  icon?: ComponentChildren;
}) {
  return (
    <span
      class="oh-dialog-fact-chip"
      style={{
        color: 'var(--m3-on-surface)',
        background: dialogAccentWash(accent, DIALOG_CHIP_FILL_PERCENT),
        border: dialogAccentBorder(accent),
      }}
    >
      {icon}
      {label}
    </span>
  );
}

export function DialogEntryRow({
  label,
  value,
}: {
  label: string;
  value: ComponentChildren;
}) {
  return (
    <div class="oh-dialog-entry-row">
      <div
        class="oh-dialog-entry-label"
        style={{ width: DIALOG_ENTRY_LABEL_WIDTH_PX }}
      >
        {label}
      </div>
      <div class="oh-dialog-entry-value">{value}</div>
    </div>
  );
}

export function DialogFooterActions({
  children,
  variant = DIALOG_FOOTER_VARIANT.inline,
  className,
}: {
  children: ComponentChildren;
  variant?: DialogFooterActionsVariant;
  className?: string;
}) {
  return (
    <div
      class={classNames(
        'oh-dialog-footer-actions',
        variant !== DIALOG_FOOTER_VARIANT.inline && `is-${variant}`,
        className,
      )}
    >
      {children}
    </div>
  );
}
