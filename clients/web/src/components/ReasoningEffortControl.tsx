import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { t } from '../i18n';
import type { ApiMetaModel, ApiReasoningEffortOption } from '../api/meta';
import { PopMenu } from './PopMenu';

export interface ReasoningEffortControlProps {
  model?: ApiMetaModel;
  disabled?: boolean;
  saving?: boolean;
  onSelect: (effort: string) => Promise<void>;
}

function ReasoningIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M9.5 4.5a3.5 3.5 0 0 1 5.7 2.7 3.6 3.6 0 0 1 2.4 5.8 3.6 3.6 0 0 1-3.3 5.4H13v2.1" />
      <path d="M10.6 19.4H9.2a3.7 3.7 0 0 1-3.3-5.3 3.6 3.6 0 0 1 1.8-6.2A3.5 3.5 0 0 1 9.5 4.5v14.9" />
      <path d="M9.5 8.4c-1.1.1-1.9.7-2.3 1.7M14.8 10.1c-1.2 0-2.2.8-2.5 1.9M9.5 14.4c.9 0 1.7.5 2.1 1.2" />
    </svg>
  );
}

function selectableOptions(model?: ApiMetaModel): ApiReasoningEffortOption[] {
  if (!model?.reasoning_effort_control_enabled) return [];
  const seen = new Set<string>();
  const result: ApiReasoningEffortOption[] = [];
  for (const option of model.reasoning_effort_options ?? []) {
    const value = option.value.trim();
    if (!value || seen.has(value.toLowerCase())) continue;
    seen.add(value.toLowerCase());
    result.push({ value, label: option.label.trim() || value });
  }
  return result;
}

function hasDeclaredOptions(model?: ApiMetaModel): boolean {
  return (model?.reasoning_effort_options ?? []).some(
    (option) => option.value.trim().length > 0,
  );
}

function optionIndex(
  options: ApiReasoningEffortOption[],
  currentValue: string | null | undefined,
): number {
  const normalized = currentValue?.trim().toLowerCase() ?? '';
  const found = options.findIndex(
    (option) => option.value.toLowerCase() === normalized,
  );
  return found >= 0 ? found : Math.floor(options.length / 2);
}

function clampIndex(value: number, options: ApiReasoningEffortOption[]): number {
  if (options.length <= 1) return 0;
  return Math.max(0, Math.min(options.length - 1, Math.round(value)));
}

function ReasoningEffortPanel({
  options,
  currentValue,
  close,
  onSelect,
}: {
  options: ApiReasoningEffortOption[];
  currentValue?: string | null;
  close: () => void;
  onSelect: (effort: string) => Promise<void>;
}) {
  const currentIndex = optionIndex(options, currentValue);
  const [draftIndex, setDraftIndex] = useState(currentIndex);
  const committedRef = useRef(false);
  useEffect(() => setDraftIndex(currentIndex), [currentIndex, currentValue]);
  const maxIndex = Math.max(1, options.length - 1);
  const selected = options[clampIndex(draftIndex, options)]!;
  const progress = options.length <= 1 ? 1 : draftIndex / maxIndex;
  const energy = progress >= 0.96 ? 'max' : progress >= 0.7 ? 'high' : progress >= 0.38 ? 'balanced' : 'fast';

  const commit = (value: number) => {
    if (committedRef.current) return;
    committedRef.current = true;
    const next = options[clampIndex(value, options)];
    if (!next) return;
    close();
    if (next.value.toLowerCase() !== currentValue?.trim().toLowerCase()) {
      void onSelect(next.value);
    }
  };

  return (
    <div class="oh-reasoning-effort-panel" data-energy={energy}>
      <div class="oh-reasoning-effort-heading" aria-hidden="true">
        <span>{t('composer.reasoning.faster', '更快')}</span>
        <span>{t('composer.reasoning.smarter', '更智能')}</span>
      </div>
      <div
        class="oh-reasoning-effort-track-shell"
        style={{ '--oh-reasoning-progress': `${progress * 100}%` }}
      >
        <div class="oh-reasoning-effort-track" aria-hidden="true">
          <span class="oh-reasoning-effort-fill" />
          <span class="oh-reasoning-effort-sparkles" />
          {options.map((option, index) => (
            <span
              key={option.value}
              class={`oh-reasoning-effort-tick ${index <= draftIndex ? 'is-active' : ''}`}
              style={{ left: `${options.length <= 1 ? 50 : (index / maxIndex) * 100}%` }}
            />
          ))}
          <span class="oh-reasoning-effort-orb" />
        </div>
        <input
          class="oh-reasoning-effort-range"
          type="range"
          autoFocus
          min="0"
          max={maxIndex}
          step="1"
          value={draftIndex}
          aria-label={t('composer.reasoning.title', '推理强度')}
          aria-valuetext={selected.label}
          onInput={(event) => {
            setDraftIndex(
              clampIndex(Number(event.currentTarget.value), options),
            );
          }}
          onPointerUp={(event) => commit(Number(event.currentTarget.value))}
          onKeyDown={(event) => {
            if (event.key === 'Enter') {
              event.preventDefault();
              commit(draftIndex);
              return;
            }
            const next = event.key === 'Home'
              ? 0
              : event.key === 'End'
                ? options.length - 1
                : event.key === 'ArrowLeft' || event.key === 'ArrowDown'
                  ? draftIndex - 1
                  : event.key === 'ArrowRight' || event.key === 'ArrowUp'
                    ? draftIndex + 1
                    : null;
            if (next != null) {
              event.preventDefault();
              setDraftIndex(clampIndex(next, options));
            }
          }}
          onBlur={(event) => commit(Number(event.currentTarget.value))}
        />
      </div>
      <div class="oh-reasoning-effort-current" aria-live="polite">
        <span key={selected.value} class="oh-soft-replace">
          {selected.label}
        </span>
      </div>
    </div>
  );
}

export function ReasoningEffortControl({
  model,
  disabled = false,
  saving = false,
  onSelect,
}: ReasoningEffortControlProps) {
  const options = useMemo(
    () => selectableOptions(model),
    [model?.key, model?.reasoning_effort_control_enabled, model?.reasoning_effort_options],
  );
  const supported = options.length > 0;
  const current = supported
    ? options[optionIndex(options, model?.reasoning_effort)]
    : undefined;
  const label = saving
    ? t('composer.reasoning.saving', '保存中')
    : current?.label ??
      (model && hasDeclaredOptions(model)
        ? t('composer.reasoning.notEnabled', '推理未启用')
        : model
        ? t('composer.reasoning.unsupported', '不支持推理')
        : t('composer.reasoning.unavailable', '推理不可用'));
  const tooltip = supported
    ? t('composer.reasoning.adjust', '调整当前模型的推理强度')
    : t('composer.reasoning.disabled', '当前模型未启用或不支持推理强度控制');

  return (
    <PopMenu
      align="left"
      width={360}
      wrapperClassName="oh-composer-reasoning-menu"
      panelClassName="oh-reasoning-effort-popover"
      ariaLabel={t('composer.reasoning.title', '推理强度')}
      content={({ close }) => (
        <ReasoningEffortPanel
          options={options}
          currentValue={model?.reasoning_effort}
          close={close}
          onSelect={onSelect}
        />
      )}
      trigger={({ open, toggle }) => (
        <button
          type="button"
          onClick={toggle}
          disabled={disabled || saving || !supported}
          class={`oh-composer-control oh-composer-reasoning-control oh-tap-press ${supported ? 'is-tonal' : 'is-muted'}`}
          aria-expanded={supported ? open : undefined}
          aria-haspopup={supported ? 'dialog' : undefined}
          title={tooltip}
        >
          <span class="oh-composer-control-icon">
            <ReasoningIcon />
          </span>
          <span key={label} class="oh-soft-replace">{label}</span>
          {supported ? <span class={`oh-reasoning-energy-dot ${open ? 'is-open' : ''}`} /> : null}
        </button>
      )}
    />
  );
}
