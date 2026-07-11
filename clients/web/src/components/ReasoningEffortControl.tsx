import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { t } from '../i18n';
import type { ApiMetaModel, ApiReasoningEffortOption } from '../api/meta';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { PopMenu } from './PopMenu';

export interface ReasoningEffortControlProps {
  model?: ApiMetaModel;
  disabled?: boolean;
  saving?: boolean;
  onSelect: (effort: string) => Promise<boolean>;
}

const REASONING_PARTICLE_COUNT = 20;
const REASONING_PARTICLE_FRAME_MS = 1000 / 30;

interface ReasoningParticle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  opacity: number;
  age: number;
  life: number;
}

function createReasoningParticle(initial: boolean): ReasoningParticle {
  return {
    x: Math.random(),
    y: 0.14 + Math.random() * 0.72,
    vx: (Math.random() - 0.42) * 0.075,
    vy: (Math.random() - 0.5) * 0.11,
    size: 1.4 + Math.random() * 2.4,
    opacity: initial ? 0.36 + Math.random() * 0.55 : 0.28,
    age: initial ? 0.4 + Math.random() * 1.2 : 0,
    life: 1.8 + Math.random() * 4.6,
  };
}

function OrganicReasoningParticles({ active }: { active: boolean }) {
  const hostRef = useRef<HTMLSpanElement>(null);
  const reducedMotion = useReducedMotion();

  useEffect(() => {
    const host = hostRef.current;
    if (!host || !active || reducedMotion) return;
    const elements = Array.from(host.children).filter(
      (element): element is HTMLElement => element instanceof HTMLElement,
    );
    const particles = elements.map(() => createReasoningParticle(true));
    particles.forEach((particle, index) => {
      const element = elements[index]!;
      element.style.width = `${particle.size}px`;
      element.style.height = `${particle.size}px`;
    });
    let previousTime = performance.now();
    let animationFrame = 0;

    const update = (time: number) => {
      const elapsed = time - previousTime;
      if (elapsed < REASONING_PARTICLE_FRAME_MS) {
        animationFrame = window.requestAnimationFrame(update);
        return;
      }
      const delta = Math.max(0.001, Math.min(elapsed / 1000, 0.05));
      previousTime = time;
      for (let index = 0; index < particles.length; index += 1) {
        let particle = particles[index]!;
        particle.life -= delta;
        if (
          particle.life <= 0 ||
          particle.x < -0.08 ||
          particle.x > 1.08 ||
          particle.y < -0.18 ||
          particle.y > 1.18
        ) {
          particle = createReasoningParticle(false);
          particles[index] = particle;
          const element = elements[index]!;
          element.style.width = `${particle.size}px`;
          element.style.height = `${particle.size}px`;
        } else {
          particle.vx = Math.max(
            -0.13,
            Math.min(0.13, particle.vx + (Math.random() - 0.5) * 0.32 * delta),
          );
          particle.vy = Math.max(
            -0.2,
            Math.min(0.2, particle.vy + (Math.random() - 0.5) * 0.46 * delta),
          );
          const damping = Math.pow(0.72, delta);
          particle.vx *= damping;
          particle.vy *= damping;
          particle.x += particle.vx * delta;
          particle.y += particle.vy * delta;
          particle.age += delta;
          particle.opacity = Math.max(
            0.28,
            Math.min(0.96, particle.opacity + (Math.random() - 0.48) * delta * 0.9),
          );
        }
        const fadeIn = Math.min(particle.age / 0.38, 1);
        const fadeOut = Math.min(particle.life / 0.5, 1);
        const element = elements[index]!;
        element.style.left = `${particle.x * 100}%`;
        element.style.top = `${particle.y * 100}%`;
        element.style.opacity = `${particle.opacity * fadeIn * fadeOut}`;
      }
      animationFrame = window.requestAnimationFrame(update);
    };

    animationFrame = window.requestAnimationFrame(update);
    return () => {
      window.cancelAnimationFrame(animationFrame);
      elements.forEach((element) => {
        element.style.opacity = '0';
      });
    };
  }, [active, reducedMotion]);

  return (
    <span ref={hostRef} class="oh-reasoning-effort-sparkles">
      {Array.from({ length: REASONING_PARTICLE_COUNT }, (_, index) => (
        <i key={index} />
      ))}
    </span>
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
          let saved = false;
          try {
            saved = await onSelect(queued);
          } catch {
            // The caller owns user-facing error reporting; keep this control
            // mounted and roll back to the last persisted value.
          }
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
          <OrganicReasoningParticles active={energy === 'high' || energy === 'max'} />
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
