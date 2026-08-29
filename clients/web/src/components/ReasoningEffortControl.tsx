import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { t } from '../i18n';
import type { ApiMetaModel, ApiReasoningEffortOption } from '../api/meta';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { PopMenu } from './PopMenu';
import {
  attachEffortPixelField,
  attachEffortStreamField,
  clamp,
  EFFORT_SNAP_MS,
  EFFORT_TIDE_UNDERLAY_SOFT,
  effortTideSoftScale,
  isDarkEffortTheme,
  isEffortLastTier,
  resolveEffortFxBlends,
  type EffortPixelFieldHandle,
  type EffortStreamFieldHandle,
} from './reasoning_effort/effortSliderFx';

interface ReasoningEffortControlProps {
  model?: ApiMetaModel;
  disabled?: boolean;
  disabledReason?: string;
  saving?: boolean;
  onSelect: (effort: string) => Promise<boolean>;
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

function indexToSlider100(index: number, optionCount: number): number {
  if (optionCount <= 1) return 100;
  return (index / (optionCount - 1)) * 100;
}

function slider100ToIndex(slider100: number, optionCount: number): number {
  if (optionCount <= 1) return 0;
  return clamp(Math.round((slider100 / 100) * (optionCount - 1)), 0, optionCount - 1);
}

function shortLevelLabel(
  option: ApiReasoningEffortOption,
  index: number,
  total: number,
): string {
  if (index === 0) return t('composer.reasoning.level.off', '关闭');
  if (index === total - 1) return t('composer.reasoning.level.max', '最大');
  return option.label;
}

function ReasoningEffortPanel({
  options,
  currentValue,
  onSelect,
  onClose,
}: {
  options: ApiReasoningEffortOption[];
  currentValue?: string | null;
  onSelect: (effort: string) => Promise<boolean>;
  onClose: () => void;
}) {
  const reducedMotion = useReducedMotion();
  const currentIndex = optionIndex(options, currentValue);
  const [slider100, setSlider100] = useState(() =>
    indexToSlider100(currentIndex, options.length),
  );
  const [dragging, setDragging] = useState(false);
  const [darkTheme, setDarkTheme] = useState(() => isDarkEffortTheme());
  const persistedValueRef = useRef(options[currentIndex]?.value ?? '');
  const queuedValueRef = useRef<string | null>(null);
  const persistingRef = useRef(false);
  const slider100Ref = useRef(slider100);
  const snapRafRef = useRef<number | null>(null);
  const pixelCanvasRef = useRef<HTMLCanvasElement>(null);
  const streamCanvasRef = useRef<HTMLCanvasElement>(null);
  const pixelHandleRef = useRef<EffortPixelFieldHandle | null>(null);
  const streamHandleRef = useRef<EffortStreamFieldHandle | null>(null);

  slider100Ref.current = slider100;

  const cancelSnapAnim = () => {
    if (snapRafRef.current != null) {
      cancelAnimationFrame(snapRafRef.current);
      snapRafRef.current = null;
    }
  };

  const animateSliderTo = (target: number) => {
    cancelSnapAnim();
    const from = slider100Ref.current;
    if (reducedMotion || Math.abs(from - target) < 0.08) {
      setSlider100(target);
      return;
    }
    const start = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / EFFORT_SNAP_MS);
      const eased = 1 - (1 - t) ** 3;
      setSlider100(from + (target - from) * eased);
      if (t < 1) {
        snapRafRef.current = requestAnimationFrame(tick);
        return;
      }
      snapRafRef.current = null;
      setSlider100(target);
    };
    snapRafRef.current = requestAnimationFrame(tick);
  };

  const displayIndex = slider100ToIndex(slider100, options.length);
  const selected = options[displayIndex]!;
  const blends = resolveEffortFxBlends(slider100, options.length);
  const isLastTier = isEffortLastTier(slider100);
  const maskFrac = isLastTier ? 1 : clamp(slider100 / 100, 0, 1);
  const tideSoftScale = isLastTier ? 0 : effortTideSoftScale(maskFrac, blends.maxBlend);
  const isMax = displayIndex === options.length - 1 && options.length > 1;
  const statusClass = isMax
    ? 'is-max'
    : blends.maxBlend > 0.35
      ? 'is-high'
      : blends.pixelBlend > 0.35
        ? 'is-mid'
        : 'is-low';

  useLayoutEffect(() => {
    if (dragging) return;
    const target = indexToSlider100(optionIndex(options, currentValue), options.length);
    if (Math.abs(target - slider100Ref.current) < 0.08) {
      setSlider100(target);
      return;
    }
    animateSliderTo(target);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 仅随外部当前值同步
  }, [currentValue, options, dragging]);

  useEffect(() => () => cancelSnapAnim(), []);

  useEffect(() => {
    const syncTheme = () => setDarkTheme(isDarkEffortTheme());
    syncTheme();
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    media.addEventListener('change', syncTheme);
    const observer = new MutationObserver(syncTheme);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme', 'style', 'class'],
    });
    return () => {
      media.removeEventListener('change', syncTheme);
      observer.disconnect();
    };
  }, []);

  useEffect(() => {
    const pixelCanvas = pixelCanvasRef.current;
    const streamCanvas = streamCanvasRef.current;
    if (!pixelCanvas || !streamCanvas) return;
    const pixel = attachEffortPixelField(pixelCanvas);
    const stream = attachEffortStreamField(streamCanvas);
    pixelHandleRef.current = pixel;
    streamHandleRef.current = stream;
    // 弹层进场 scale 动画结束后再量一次布局尺寸，避免画布偏小。
    const raf = window.requestAnimationFrame(() => {
      pixel.resize();
      stream.resize();
    });
    const timer = window.setTimeout(() => {
      pixel.resize();
      stream.resize();
    }, 360);
    return () => {
      window.cancelAnimationFrame(raf);
      window.clearTimeout(timer);
      pixel.destroy();
      stream.destroy();
      pixelHandleRef.current = null;
      streamHandleRef.current = null;
    };
  }, []);

  useEffect(() => {
    pixelHandleRef.current?.setParams({
      active: blends.pixelBlend > 0.01,
      lowBlend: blends.lowBlend,
      maxBlend: blends.maxBlend,
      // 右缘始终跟随拇指，极高→最大靠补间与 softScale 连续铺满。
      thumb100: slider100,
      dark: darkTheme,
      reducedMotion,
    });
    streamHandleRef.current?.setParams({
      intensity: blends.stream01,
      opacity: Math.max(0, 1 - blends.pixelBlend),
      dark: darkTheme,
      reducedMotion,
    });
  }, [blends, slider100, darkTheme, reducedMotion]);

  const commit = (nextIndex: number) => {
    const next = options[clampIndex(nextIndex, options)];
    if (!next) return;
    const normalized = next.value.toLowerCase();
    if (!persistingRef.current && persistedValueRef.current.toLowerCase() === normalized) {
      return;
    }
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
            // 错误展示由调用方负责，这里只回退到上次已保存值。
          }
          if (saved) {
            persistedValueRef.current = queued;
          } else if (queuedValueRef.current == null) {
            setSlider100(
              indexToSlider100(
                optionIndex(options, persistedValueRef.current),
                options.length,
              ),
            );
          }
        }
      } finally {
        persistingRef.current = false;
      }
    })();
  };

  const snapAndCommit = (raw: number) => {
    const nextIndex = slider100ToIndex(raw, options.length);
    const snapped = indexToSlider100(nextIndex, options.length);
    setDragging(false);
    animateSliderTo(snapped);
    commit(nextIndex);
  };

  const thumbInset = 11 - 22 * (slider100 / 100);
  const thumbPosition = `calc(${slider100}% + ${thumbInset}px)`;
  // 拇指染色：绿 → 蓝 → 紫，与色轨前沿一致。
  const accent =
    blends.maxBlend > 0.01
      ? `color-mix(in srgb, #3b5bd8 ${Math.round((1 - blends.maxBlend) * 100)}%, #9660cd)`
      : blends.lowBlend < 0.99
        ? `color-mix(in srgb, #2ea86c ${Math.round((1 - blends.lowBlend) * 100)}%, #3b5bd8)`
        : '#3b5bd8';
  // 末档满轨实填、关闭潮汐过渡；非末档跟随拇指。
  const fillPct = isLastTier ? 100 : slider100;
  const underlaySoftPct = EFFORT_TIDE_UNDERLAY_SOFT * 100 * tideSoftScale;
  const tideMask =
    isLastTier || tideSoftScale < 0.05
      ? 'none'
      : `linear-gradient(to right, #000 0%, #000 calc(${slider100}% - ${underlaySoftPct}%), rgba(0,0,0,0.35) calc(${slider100}% - ${underlaySoftPct * 0.45}%), transparent calc(${slider100}% - 1%))`;

  return (
    <div
      class="oh-reasoning-effort-panel"
      data-es-theme={darkTheme ? 'dark' : 'light'}
      data-status={statusClass}
      data-dragging={dragging ? '1' : '0'}
      data-max-tier={isLastTier || isMax ? '1' : '0'}
      style={
        {
          '--oh-effort-progress': `${slider100}%`,
          '--oh-effort-fill': `${fillPct}%`,
          '--oh-effort-thumb': thumbPosition,
          '--oh-effort-pixel': `${blends.pixelBlend}`,
          '--oh-effort-max': `${blends.maxBlend}`,
          '--oh-effort-low': `${blends.lowBlend}`,
          '--oh-effort-stream': `${Math.max(0, 1 - blends.pixelBlend)}`,
          '--oh-effort-accent': accent,
        } as Record<string, string>
      }
    >
      <div class="oh-reasoning-effort-inner">
        <div class="oh-reasoning-effort-axis">
          <span>{t('composer.reasoning.faster', '更快')}</span>
          <span
            key={selected.value}
            class={`oh-reasoning-effort-status oh-soft-replace ${statusClass}`}
          >
            {selected.label}
          </span>
          <span>{t('composer.reasoning.smarter', '更智能')}</span>
        </div>

        <div class="oh-reasoning-effort-levels" aria-hidden="true">
          {options.map((option, index) => {
            const last = Math.max(options.length - 1, 1);
            const at = index / last;
            // 与 App Align(-1…1) 一致：首尾贴齐「更快 / 更智能」，中间居中。
            const edge =
              index === 0 ? 'start' : index === options.length - 1 ? 'end' : 'mid';
            return (
              <span
                key={option.value}
                class={`oh-reasoning-effort-level is-${edge} ${
                  index === displayIndex ? 'is-active' : ''
                }`}
                style={{ left: `${at * 100}%` }}
              >
                {shortLevelLabel(option, index, options.length)}
              </span>
            );
          })}
        </div>

        <div class="oh-reasoning-effort-track-shell">
          <div class="oh-reasoning-effort-track" aria-hidden="true">
            <span class="oh-reasoning-effort-track-bg" />
            <span
              class={`oh-reasoning-effort-track-max ${
                blends.maxBlend > 0.02 ? 'is-on' : ''
              }`}
              style={{
                // 仅紫段混合时显现，避免 maxBlend=0 仍被 inline opacity 透出。
                opacity:
                  blends.maxBlend > 0.02
                    ? String(0.35 + blends.maxBlend * 0.65)
                    : '0',
                clipPath: isLastTier
                  ? 'none'
                  : tideSoftScale < 0.05
                    ? `inset(0 ${Math.max(0, 100 - fillPct)}% 0 0)`
                    : `inset(0 ${Math.max(0, 100 - fillPct + underlaySoftPct * 0.35)}% 0 0)`,
                maskImage: tideMask,
                WebkitMaskImage: tideMask,
              }}
            />
            <div
              class="oh-reasoning-effort-dots"
              style={{ opacity: String(1 - blends.pixelBlend) }}
            >
              {options.map((option, index) => {
                const tick = index / Math.max(options.length - 1, 1);
                const inset = 11 - 22 * tick;
                return (
                  <span
                    key={option.value}
                    class={`oh-reasoning-effort-dot ${
                      index <= displayIndex ? 'is-active' : ''
                    }`}
                    style={{
                      left: `calc(${tick * 100}% + ${inset}px)`,
                    }}
                  />
                );
              })}
            </div>
            <canvas
              ref={streamCanvasRef}
              class="oh-reasoning-effort-stream"
              aria-hidden="true"
              style={
                isLastTier || tideSoftScale < 0.05
                  ? undefined
                  : {
                      maskImage: tideMask,
                      WebkitMaskImage: tideMask,
                    }
              }
            />
            <canvas
              ref={pixelCanvasRef}
              class={`oh-reasoning-effort-pixel ${
                blends.pixelBlend > 0.01 ? 'is-on' : ''
              }`}
              aria-hidden="true"
            />
          </div>
          <span class="oh-reasoning-effort-thumb" aria-hidden="true" />
          <input
            class="oh-reasoning-effort-range"
            type="range"
            autoFocus
            min="0"
            max="100"
            step="any"
            value={slider100}
            aria-label={t('composer.reasoning.title', '推理强度')}
            aria-valuetext={selected.label}
            onPointerDown={() => {
              cancelSnapAnim();
              setDragging(true);
            }}
            onInput={(event) => {
              cancelSnapAnim();
              setDragging(true);
              setSlider100(clamp(Number(event.currentTarget.value), 0, 100));
            }}
            onPointerUp={(event) => snapAndCommit(Number(event.currentTarget.value))}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                event.preventDefault();
                snapAndCommit(slider100);
                return;
              }
              if (event.key === 'Escape') {
                event.preventDefault();
                onClose();
                return;
              }
              const next =
                event.key === 'Home'
                  ? 0
                  : event.key === 'End'
                    ? options.length - 1
                    : event.key === 'ArrowLeft' || event.key === 'ArrowDown'
                      ? displayIndex - 1
                      : event.key === 'ArrowRight' || event.key === 'ArrowUp'
                        ? displayIndex + 1
                        : null;
              if (next != null) {
                event.preventDefault();
                animateSliderTo(
                  indexToSlider100(clampIndex(next, options), options.length),
                );
              }
            }}
            onKeyUp={(event) => {
              if (
                event.key === 'ArrowLeft' ||
                event.key === 'ArrowRight' ||
                event.key === 'ArrowUp' ||
                event.key === 'ArrowDown' ||
                event.key === 'Home' ||
                event.key === 'End'
              ) {
                snapAndCommit(slider100);
              }
            }}
            onBlur={(event) => snapAndCommit(Number(event.currentTarget.value))}
          />
        </div>
      </div>
    </div>
  );
}

export function ReasoningEffortControl({
  model,
  disabled = false,
  disabledReason,
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
  const tooltip =
    disabled && disabledReason
      ? disabledReason
      : supported
        ? t('composer.reasoning.adjust', '调整当前模型的推理强度')
        : t('composer.reasoning.disabled', '当前模型未启用或不支持推理强度控制');
  const controlRef = useRef<HTMLButtonElement | null>(null);
  const labelRef = useRef<HTMLSpanElement | null>(null);
  const [controlWidth, setControlWidth] = useState<number>();

  useLayoutEffect(() => {
    const control = controlRef.current;
    const labelElement = labelRef.current;
    if (!control || !labelElement) return;
    const style = getComputedStyle(control);
    const chromeWidth = [
      style.paddingLeft,
      style.paddingRight,
      style.borderLeftWidth,
      style.borderRightWidth,
    ].reduce((total, value) => total + (Number.parseFloat(value) || 0), 0);
    const nextWidth = Math.ceil(labelElement.offsetWidth + chromeWidth);
    setControlWidth((currentWidth) =>
      currentWidth === nextWidth ? currentWidth : nextWidth,
    );
  }, [label]);

  return (
    <PopMenu
      align="left"
      verticalPlacement="above"
      width={300}
      wrapperClassName="oh-composer-reasoning-menu"
      wrapperTitle={disabled && disabledReason ? disabledReason : undefined}
      panelClassName="oh-reasoning-effort-popover"
      ariaLabel={t('composer.reasoning.title', '推理强度')}
      content={({ close }) => (
        <ReasoningEffortPanel
          options={options}
          currentValue={model?.reasoning_effort}
          onSelect={onSelect}
          onClose={close}
        />
      )}
      trigger={({ open, toggle }) => (
        <button
          ref={controlRef}
          type="button"
          onClick={toggle}
          disabled={disabled || saving || !supported}
          class={`oh-composer-control oh-composer-reasoning-control oh-tap-press ${
            supported ? 'is-tonal' : 'is-muted'
          }`}
          style={
            controlWidth == null
              ? undefined
              : { '--oh-reasoning-control-width': `${controlWidth}px` }
          }
          aria-expanded={supported ? open : undefined}
          aria-haspopup={supported ? 'dialog' : undefined}
          title={tooltip}
        >
          <span ref={labelRef} key={label} class="oh-soft-replace">
            {label}
          </span>
        </button>
      )}
    />
  );
}
