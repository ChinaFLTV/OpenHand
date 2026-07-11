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

const REASONING_PARTICLE_BASE_COUNT = 18;
const REASONING_PARTICLE_MAX_COUNT = 42;
const REASONING_PARTICLE_FRAME_MS = 1000 / 30;

type ParticleKind = 'dust' | 'spark' | 'flare';

interface ReasoningParticle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  opacity: number;
  age: number;
  life: number;
  kind: ParticleKind;
}

function pickParticleKind(maximum: boolean): ParticleKind {
  const roll = Math.random();
  if (!maximum) return roll < 0.72 ? 'dust' : 'spark';
  if (roll < 0.52) return 'dust';
  if (roll < 0.86) return 'spark';
  return 'flare';
}

function createReasoningParticle(
  initial: boolean,
  maximum: boolean,
): ReasoningParticle {
  const kind = pickParticleKind(maximum);
  const sizeRange =
    kind === 'dust'
      ? [1.1, 2.2]
      : kind === 'spark'
        ? [2.0, 3.6]
        : [3.2, 5.2];
  const lifeRange =
    kind === 'dust'
      ? [1.4, 5.2]
      : kind === 'spark'
        ? [1.1, 3.9]
        : [0.7, 2.3];
  return {
    x: Math.random(),
    y: 0.1 + Math.random() * 0.8,
    vx: (Math.random() - 0.28) * (maximum ? 0.12 : 0.075),
    vy: (Math.random() - 0.5) * (maximum ? 0.16 : 0.11),
    size: sizeRange[0]! + Math.random() * (sizeRange[1]! - sizeRange[0]!),
    opacity: initial ? 0.4 + Math.random() * 0.5 : 0.22 + Math.random() * 0.2,
    age: initial ? 0.35 + Math.random() * 1.3 : 0,
    life: lifeRange[0]! + Math.random() * (lifeRange[1]! - lifeRange[0]!),
    kind,
  };
}

function applyParticleElement(
  element: HTMLElement,
  particle: ReasoningParticle,
) {
  element.dataset.kind = particle.kind;
  element.style.width = `${particle.size}px`;
  element.style.height = `${particle.size}px`;
}

/** Radial fireworks from the max-tier thumb — burst on enter + soft embers. */
function ThumbSparkField({ active }: { active: boolean }) {
  const hostRef = useRef<HTMLSpanElement>(null);
  const reducedMotion = useReducedMotion();

  useEffect(() => {
    const host = hostRef.current;
    if (!host || !active || reducedMotion) return;

    type Spark = {
      el: HTMLElement;
      angle: number;
      dist: number;
      speed: number;
      life: number;
      maxLife: number;
      size: number;
      streak: number;
    };

    const sparks: Spark[] = [];
    let previousTime = performance.now();
    let animationFrame = 0;
    let emberAcc = 0;
    let didBurst = false;

    const spawn = (count: number, speedScale: number) => {
      for (let i = 0; i < count; i += 1) {
        if (sparks.length >= 64) break;
        const el = document.createElement('i');
        el.className = 'oh-reasoning-thumb-spark';
        host.appendChild(el);
        const life = 0.35 + Math.random() * 0.55;
        const size = 1.4 + Math.random() * 2.6;
        el.style.width = `${size}px`;
        el.style.height = `${size}px`;
        sparks.push({
          el,
          angle: Math.random() * Math.PI * 2,
          dist: 12 + Math.random() * 6,
          speed: (95 + Math.random() * 150) * speedScale,
          life,
          maxLife: life,
          size,
          streak: 0.35 + Math.random() * 0.85,
        });
      }
    };

    const update = (time: number) => {
      const elapsed = time - previousTime;
      if (elapsed < REASONING_PARTICLE_FRAME_MS) {
        animationFrame = window.requestAnimationFrame(update);
        return;
      }
      const delta = Math.max(0.001, Math.min(elapsed / 1000, 0.05));
      previousTime = time;

      if (!didBurst) {
        didBurst = true;
        spawn(28, 1.15);
      }

      emberAcc += delta;
      while (emberAcc >= 0.065) {
        emberAcc -= 0.065 + Math.random() * 0.04;
        spawn(1 + Math.floor(Math.random() * 3), 0.45 + Math.random() * 0.35);
      }

      const drag = Math.pow(0.18, delta);
      for (let i = sparks.length - 1; i >= 0; i -= 1) {
        const spark = sparks[i]!;
        spark.life -= delta;
        if (spark.life <= 0 || spark.dist > 58) {
          spark.el.remove();
          sparks.splice(i, 1);
          continue;
        }
        spark.dist += spark.speed * delta;
        spark.speed *= drag;
        spark.angle += (Math.random() - 0.5) * delta * 1.4;
        const lifeT = Math.max(0, Math.min(1, spark.life / spark.maxLife));
        const fade = 1 - (1 - lifeT) * (1 - lifeT); // easeOut-ish
        const x = Math.cos(spark.angle) * spark.dist;
        const y = Math.sin(spark.angle) * spark.dist;
        const trail = spark.size * (2.2 + spark.streak * 3.5) * fade;
        spark.el.style.transform = `translate(-50%, -50%) translate(${x}px, ${y}px)`;
        spark.el.style.opacity = `${0.15 + fade * 0.85}`;
        spark.el.style.boxShadow = `0 0 ${4 + trail * 0.15}px color-mix(in srgb, #38bdf8 70%, transparent)`;
      }

      animationFrame = window.requestAnimationFrame(update);
    };

    animationFrame = window.requestAnimationFrame(update);
    return () => {
      window.cancelAnimationFrame(animationFrame);
      sparks.forEach((spark) => spark.el.remove());
      sparks.length = 0;
    };
  }, [active, reducedMotion]);

  return <span ref={hostRef} class="oh-reasoning-thumb-sparks" aria-hidden="true" />;
}

function OrganicReasoningParticles({
  active,
  maximum = false,
}: {
  active: boolean;
  maximum?: boolean;
}) {
  const hostRef = useRef<HTMLSpanElement>(null);
  const reducedMotion = useReducedMotion();
  const count = maximum ? REASONING_PARTICLE_MAX_COUNT : REASONING_PARTICLE_BASE_COUNT;

  useEffect(() => {
    const host = hostRef.current;
    if (!host || !active || reducedMotion) return;
    const elements = Array.from(host.children).filter(
      (element): element is HTMLElement => element instanceof HTMLElement,
    );
    const particles = elements.map(() => createReasoningParticle(true, maximum));
    particles.forEach((particle, index) => {
      applyParticleElement(elements[index]!, particle);
    });
    let previousTime = performance.now();
    let animationFrame = 0;
    const speedBoost = maximum ? 1.55 : 1.0;
    const flowBias = maximum ? 0.055 : 0.02;
    const maxVx = maximum ? 0.22 : 0.13;
    const maxVy = maximum ? 0.28 : 0.2;

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
          particle.x < -0.1 ||
          particle.x > 1.12 ||
          particle.y < -0.22 ||
          particle.y > 1.22
        ) {
          particle = createReasoningParticle(false, maximum);
          particles[index] = particle;
          applyParticleElement(elements[index]!, particle);
        } else {
          particle.vx += flowBias * delta;
          particle.vx = Math.max(
            -maxVx * 0.45,
            Math.min(
              maxVx,
              particle.vx +
                (Math.random() - 0.5) * (maximum ? 0.55 : 0.32) * delta,
            ),
          );
          particle.vy = Math.max(
            -maxVy,
            Math.min(
              maxVy,
              particle.vy +
                (Math.random() - 0.5) * (maximum ? 0.72 : 0.46) * delta,
            ),
          );
          const damping = Math.pow(maximum ? 0.78 : 0.72, delta);
          particle.vx *= damping;
          particle.vy *= damping;
          particle.x += particle.vx * delta * speedBoost;
          particle.y += particle.vy * delta * speedBoost;
          particle.age += delta;
          const floor = particle.kind === 'dust' ? 0.22 : particle.kind === 'spark' ? 0.38 : 0.5;
          const ceil = particle.kind === 'dust' ? 0.78 : particle.kind === 'spark' ? 0.96 : 1;
          particle.opacity = Math.max(
            floor,
            Math.min(ceil, particle.opacity + (Math.random() - 0.45) * delta * 1.15),
          );
        }
        const fadeIn = Math.min(particle.age / 0.32, 1);
        const fadeOut = Math.min(particle.life / 0.45, 1);
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
  }, [active, maximum, reducedMotion, count]);

  return (
    <span
      ref={hostRef}
      class={`oh-reasoning-effort-sparkles${maximum ? ' is-max' : ''}`}
    >
      {Array.from({ length: count }, (_, index) => (
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
          <OrganicReasoningParticles
            active={energy === 'high' || energy === 'max'}
            maximum={energy === 'max'}
          />
          {options.map((option, index) => (
            <span
              key={option.value}
              class={`oh-reasoning-effort-tick ${index <= draftIndex ? 'is-active' : ''}`}
              style={{ left: `${options.length <= 1 ? 50 : (index / maxIndex) * 100}%` }}
            />
          ))}
          <span class="oh-reasoning-effort-orb" />
          <ThumbSparkField active={energy === 'max'} />
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
