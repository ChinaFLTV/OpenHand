import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { t } from '../i18n';
import type { ApiMetaModel, ApiReasoningEffortOption } from '../api/meta';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { PopMenu } from './PopMenu';
import {
  attachEffortPixelField,
  attachEffortStreamField,
  clamp,
  isDarkEffortTheme,
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
  const pixelCanvasRef = useRef<HTMLCanvasElement>(null);
  const streamCanvasRef = useRef<HTMLCanvasElement>(null);
  const pixelHandleRef = useRef<EffortPixelFieldHandle | null>(null);
  const streamHandleRef = useRef<EffortStreamFieldHandle | null>(null);

  const displayIndex = slider100ToIndex(slider100, options.length);
  const selected = options[displayIndex]!;
  const blends = resolveEffortFxBlends(slider100, options.length);
  const isMax = displayIndex === options.length - 1 && options.length > 1;
  const statusClass = isMax
    ? 'is-max'
    : blends.maxBlend > 0.35
      ? 'is-high'
      : blends.pixelBlend > 0.35
        ? 'is-mid'
        : 'is-low';

  useLayoutEffect(() => {
    if (!dragging) {
      setSlider100(indexToSlider100(optionIndex(options, currentValue), options.length));
    }
  }, [currentValue, options, dragging]);

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
    return () => {
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
    setSlider100(snapped);
    setDragging(false);
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

  return (
    <div
      class="oh-reasoning-effort-panel"
      data-es-theme={darkTheme ? 'dark' : 'light'}
      data-status={statusClass}
      data-dragging={dragging ? '1' : '0'}
      style={
        {
          '--oh-effort-progress': `${slider100}%`,
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
            const left = 10 + (index / Math.max(options.length - 1, 1)) * 80;
            return (
              <span
                key={option.value}
                class={`oh-reasoning-effort-level ${
                  index === displayIndex ? 'is-active' : ''
                }`}
                style={{ left: `${left}%` }}
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
                opacity: String(0.35 + blends.maxBlend * 0.65),
                clipPath: `inset(0 ${Math.max(0, 100 - slider100)}% 0 0)`,
                maskImage: `linear-gradient(to right, #000 0%, #000 calc(${slider100}% - 14px), transparent ${slider100}%)`,
                WebkitMaskImage: `linear-gradient(to right, #000 0%, #000 calc(${slider100}% - 14px), transparent ${slider100}%)`,
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
              style={{
                maskImage: `linear-gradient(to right, #000 0%, #000 calc(${slider100}% - 14px), transparent ${slider100}%)`,
                WebkitMaskImage: `linear-gradient(to right, #000 0%, #000 calc(${slider100}% - 14px), transparent ${slider100}%)`,
              }}
            />
            <canvas
              ref={pixelCanvasRef}
              class={`oh-reasoning-effort-pixel ${
                blends.pixelBlend > 0.01 ? 'is-on' : ''
              }`}
              aria-hidden="true"
              style={{
                maskImage: `linear-gradient(to right, #000 0%, #000 calc(${slider100}% - 14px), transparent ${slider100}%)`,
                WebkitMaskImage: `linear-gradient(to right, #000 0%, #000 calc(${slider100}% - 14px), transparent ${slider100}%)`,
              }}
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
            onPointerDown={() => setDragging(true)}
            onInput={(event) => {
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
                const snapped = indexToSlider100(
                  clampIndex(next, options),
                  options.length,
                );
                setSlider100(snapped);
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
