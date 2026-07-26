import type { ComponentChildren } from 'preact';

export type DashboardTone = 'ok' | 'warn' | 'muted';

export function DashboardHeaderIcon({ children }: { children: ComponentChildren }) {
  return (
    <div
      class="w-10 h-10 rounded-m3-sm flex items-center justify-center shrink-0"
      style={{
        background: 'var(--m3-primary-container)',
        color: 'var(--m3-on-primary-container)',
      }}
    >
      {children}
    </div>
  );
}

export function DashboardTabPill({
  label,
  active,
  onClick,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      class="px-3 py-1.5 rounded-full text-sm font-semibold transition-colors"
      onClick={onClick}
      style={{
        background: active ? 'var(--m3-primary-container)' : 'transparent',
        color: active
          ? 'var(--m3-on-primary-container)'
          : 'var(--m3-on-surface-variant)',
        border: active
          ? '1px solid var(--m3-primary)'
          : '1px solid var(--m3-outline-variant)',
      }}
    >
      {label}
    </button>
  );
}

export function DashboardMetric({ label, value }: { label: string; value: string }) {
  return (
    <div
      class="rounded-m3-sm border px-3 py-3"
      style={{
        borderColor: 'var(--m3-outline-variant)',
        background: 'var(--m3-surface-container-high)',
      }}
    >
      <div
        class="text-xs font-semibold oh-text-muted"
      >
        {label}
      </div>
      <div
        class="mt-1 text-sm font-bold break-all"
        style={{ color: 'var(--m3-on-surface)' }}
      >
        {value}
      </div>
    </div>
  );
}

export function DashboardInfoRow({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div class="flex items-start gap-3">
      <div
        class="text-xs uppercase pt-0.5 shrink-0 w-24 oh-text-muted"
      >
        {label}
      </div>
      <div
        class={`text-sm break-all ${mono ? 'font-mono' : ''}`}
        style={{ color: 'var(--m3-on-surface)' }}
      >
        {value}
      </div>
    </div>
  );
}

export function DashboardSection({
  title,
  children,
}: {
  title: string;
  children: ComponentChildren;
}) {
  return (
    <section
      class="rounded-m3-sm border px-4 py-3"
      style={{
        borderColor: 'var(--m3-outline-variant)',
        background: 'var(--m3-surface-container-low)',
      }}
    >
      <div
        class="text-xs font-semibold mb-2.5 oh-text-muted"
      >
        {title}
      </div>
      {children}
    </section>
  );
}

export function DashboardChipList({
  values,
  mono,
  emptyLabel = '暂无数据。',
}: {
  values: string[];
  mono?: boolean;
  emptyLabel?: string;
}) {
  if (values.length === 0) {
    return (
      <p class="text-sm oh-text-muted">
        {emptyLabel}
      </p>
    );
  }
  return (
    <div class="flex flex-wrap gap-1.5">
      {values.map((value, index) => (
        <span
          key={`${value}-${index}`}
          class={`rounded-full px-2 py-1 text-[11px] ${mono ? 'font-mono' : 'font-semibold'}`}
          style={{
            background: 'var(--m3-surface-container-high)',
            color: 'var(--m3-on-surface-variant)',
          }}
        >
          {value}
        </span>
      ))}
    </div>
  );
}

export function DashboardReadonlyHint({ children }: { children: ComponentChildren }) {
  return (
    <div
      class="rounded-m3-sm border px-4 py-3 text-sm leading-relaxed"
      style={{
        borderColor: 'var(--m3-outline-variant)',
        background: 'var(--m3-surface-container-high)',
        color: 'var(--m3-on-surface-variant)',
      }}
    >
      {children}
    </div>
  );
}

export function DashboardStatusPanel({
  tone,
  label,
  detail,
  warning,
}: {
  tone: DashboardTone;
  label: string;
  detail: string;
  warning?: string;
}) {
  const toneStyle =
    tone === 'ok'
      ? {
          background: 'color-mix(in srgb, var(--m3-primary) 12%, transparent)',
          color: 'var(--m3-primary)',
          borderColor: 'color-mix(in srgb, var(--m3-primary) 34%, transparent)',
        }
      : tone === 'warn'
        ? {
            background: 'color-mix(in srgb, var(--m3-error) 12%, transparent)',
            color: 'var(--m3-error)',
            borderColor: 'color-mix(in srgb, var(--m3-error) 34%, transparent)',
          }
        : {
            background: 'var(--m3-surface-container-high)',
            color: 'var(--m3-on-surface-variant)',
            borderColor: 'var(--m3-outline-variant)',
          };

  return (
    <section
      class="rounded-m3-sm border px-4 py-4"
      style={{
        background: 'var(--m3-surface-container-low)',
        borderColor: 'var(--m3-outline-variant)',
      }}
    >
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold"
          style={toneStyle}
        >
          {label}
        </span>
        <span
          class="text-sm oh-text-muted"
        >
          {detail}
        </span>
      </div>
      {warning ? (
        <div
          class="mt-3 text-xs leading-relaxed"
          style={{ color: 'var(--m3-error)' }}
        >
          {warning}
        </div>
      ) : null}
    </section>
  );
}
