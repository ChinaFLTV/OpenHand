import { useMemo, useRef, useState } from 'preact/hooks';
import { t } from '../i18n';
import type { ApiMetaModel, ApiReasoningEffortOption } from '../api/meta';
import { PopMenu } from './PopMenu';

export interface ReasoningEffortControlProps {
  model?: ApiMetaModel;
  disabled?: boolean;
  saving?: boolean;
  onSelect: (effort: string) => Promise<boolean>;
}

const REASONING_PARTICLES = [
  [3, 32, 2.2, -0.7, 2.8],
  [8, 67, 1.5, -1.8, 3.7],
  [14, 43, 2.7, -2.6, 3.1],
  [21, 73, 1.2, -0.2, 4.3],
  [27, 25, 1.8, -3.4, 2.6],
  [34, 58, 2.3, -1.1, 3.9],
  [42, 37, 1.1, -2.1, 4.6],
  [49, 77, 2.8, -0.4, 3.3],
  [57, 19, 1.4, -3.8, 4.1],
  [63, 53, 2.1, -1.5, 2.9],
  [71, 72, 1.3, -2.9, 3.6],
  [78, 29, 2.6, -0.9, 4.4],
  [85, 62, 1.7, -3.1, 3.2],
  [92, 39, 2.2, -1.3, 4.8],
  [97, 70, 1.1, -2.4, 2.7],
] as const;

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
  onSelect,
}: {
  options: ApiReasoningEffortOption[];
  currentValue?: string | null;
  onSelect: (effort: string) => Promise<boolean>;
}) {
  const currentIndex = optionIndex(options, currentValue);
  const [draftIndex, setDraftIndex] = useState(currentIndex);
  const persistedValueRef = useRef(options[currentIndex]?.value ?? '');
  const queuedValueRef = useRef<string | null>(null);
  const persistingRef = useRef(false);
  const maxIndex = Math.max(1, options.length - 1);
  const selected = options[clampIndex(draftIndex, options)]!;
  const progress = options.length <= 1 ? 1 : draftIndex / maxIndex;
  const energy = progress >= 0.96 ? 'max' : progress >= 0.7 ? 'high' : progress >= 0.38 ? 'balanced' : 'fast';
  const thumbInset = 22 - 44 * progress;
  const thumbPosition = `calc(${progress * 100}% + ${thumbInset}px)`;
  const fillPosition = progress <= 0 ? '0%' : progress >= 1 ? '100%' : thumbPosition;

  const commit = (value: number) => {
    const next = options[clampIndex(value, options)];
    if (!next) return;
    const normalized = next.value.toLowerCase();
    if (!persistingRef.current && persistedValueRef.current.toLowerCase() === normalized) return;
    if (queuedValueRef.current?.toLowerCase() === normalized) return;
    queuedValueRef.current = next.value;
    if (persistingRef.current) return;
    persistingRef.current = true;
    void (async () => {
      try {
        while (queuedValueRef.current != null) {
          const queued = queuedValueRef.current;
          queuedValueRef.current = null;
          const saved = await onSelect(queued);
          if (saved) {
            persistedValueRef.current = queued;
          } else if (queuedValueRef.current == null) {
            setDraftIndex(optionIndex(options, persistedValueRef.current));
          }
        }
      } finally {
        persistingRef.current = false;
      }
    })();
  };

  return (
    <div class="oh-reasoning-effort-panel" data-energy={energy}>
      <div class="oh-reasoning-effort-heading" aria-hidden="true">
        <span>{t('composer.reasoning.faster', '更快')}</span>
        <span>{t('composer.reasoning.smarter', '更智能')}</span>
      </div>
      <div
        class="oh-reasoning-effort-track-shell"
        style={{
          '--oh-reasoning-progress': `${progress * 100}%`,
          '--oh-reasoning-fill-position': fillPosition,
          '--oh-reasoning-thumb-position': thumbPosition,
        }}
      >
        <div class="oh-reasoning-effort-track" aria-hidden="true">
          <span class="oh-reasoning-effort-fill" />
          <span class="oh-reasoning-effort-sparkles">
            {REASONING_PARTICLES.map(([left, top, size, delay, duration], index) => (
              <i
                key={index}
                style={{
                  left: `${left}%`,
                  top: `${top}%`,
                  width: `${size}px`,
                  height: `${size}px`,
                  animationDelay: `${delay}s`,
                  animationDuration: `${duration}s`,
                }}
              />
            ))}
          </span>
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
      verticalPlacement="above"
      width={360}
      wrapperClassName="oh-composer-reasoning-menu"
      panelClassName="oh-reasoning-effort-popover"
      ariaLabel={t('composer.reasoning.title', '推理强度')}
      content={() => (
        <ReasoningEffortPanel
          options={options}
          currentValue={model?.reasoning_effort}
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
          <span key={label} class="oh-soft-replace">{label}</span>
        </button>
      )}
    />
  );
}
