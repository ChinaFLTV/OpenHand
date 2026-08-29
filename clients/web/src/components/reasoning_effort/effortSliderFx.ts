/**
 * Codex / Claude Code 风格推理强度滑块特效：
 * - 色板两段式：Low 绿 → High 蓝 → MAX 紫（smoothstep）
 * - Canvas2D 像素场（扫过显现 + 流动闪烁）
 * - Canvas2D 流光（WebGL2 不可用时的轻量替代）
 *
 * 像素场与色板派生自 dsh-effort-slider / DSH-Claude-Style-Reasoning-Slider（MIT / BSD-3-Clause）。
 */

export type Rgb = readonly [number, number, number];

export type RgbRange = readonly [number, number];

export interface EffortPalette {
  left: Rgb;
  tones: Rgb[];
  highlight: Rgb;
  peak: Rgb;
  rClamp: RgbRange;
  gClamp: RgbRange;
  bClamp: RgbRange;
  boost: number;
}

export const EFFORT_PURPLE_PALETTE: EffortPalette = {
  left: [210, 206, 214],
  tones: [
    [150, 96, 205], [150, 96, 205], [156, 118, 200], [156, 118, 200],
    [166, 140, 206], [166, 140, 206], [166, 140, 206],
    [170, 154, 206], [170, 154, 206], [182, 168, 206], [194, 182, 206],
  ],
  highlight: [196, 182, 222],
  peak: [212, 198, 234],
  rClamp: [140, 196],
  gClamp: [104, 168],
  bClamp: [182, 216],
  boost: 1,
};

export const EFFORT_BLUE_PALETTE: EffortPalette = {
  left: [212, 218, 226],
  tones: [
    [72, 126, 238], [72, 126, 238], [86, 138, 240], [86, 138, 240],
    [104, 152, 242], [104, 152, 242], [104, 152, 242],
    [124, 166, 243], [124, 166, 243], [146, 182, 244], [172, 200, 246],
  ],
  highlight: [198, 216, 250],
  peak: [222, 232, 252],
  rClamp: [62, 190],
  gClamp: [134, 196],
  bClamp: [215, 255],
  boost: 1,
};

export const EFFORT_GREEN_PALETTE: EffortPalette = {
  left: [214, 224, 212],
  tones: [
    [46, 168, 108], [46, 168, 108], [64, 178, 122], [64, 178, 122],
    [88, 188, 138], [88, 188, 138], [88, 188, 138],
    [116, 198, 154], [116, 198, 154], [150, 210, 174], [184, 220, 194],
  ],
  highlight: [204, 234, 214],
  peak: [226, 244, 232],
  rClamp: [40, 180],
  gClamp: [150, 224],
  bClamp: [100, 210],
  boost: 1,
};

const DARK_GREEN_LEFT: Rgb = [22, 38, 28];
const DARK_BLUE_LEFT: Rgb = [26, 24, 44];
const DARK_PURPLE_LEFT: Rgb = [24, 19, 40];

export const EFFORT_COMMIT_THROTTLE_MS = 16;
export const EFFORT_PIXEL_FRAME_MS = 33;
export const EFFORT_STREAM_FRAME_MS = 33;
/** 主岸线左侧碎裂前导（相对轨长，再乘 softScale）。 */
export const EFFORT_TIDE_SOFT_LEAD = 0.07;
/** 主岸线右侧飞沫漫出。 */
export const EFFORT_TIDE_SOFT_SPILL = 0.04;
/** 底轨/流光掩膜柔边。 */
export const EFFORT_TIDE_UNDERLAY_SOFT = 0.1;
/** 滑块到达末档（满轨实填、关闭潮汐过渡）。 */
export const EFFORT_LAST_TIER_SLIDER = 99.5;
const EFFORT_TIDE_WAVE_AMP = 0.048;
const EFFORT_TIDE_SPRAY_AMP = 0.028;
const EFFORT_TIDE_FOAM_AMP = 0.016;

export function isEffortLastTier(slider100: number): boolean {
  return slider100 >= EFFORT_LAST_TIER_SLIDER;
}

export function clamp(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, value));
}

export function smoothstep(edge0: number, edge1: number, value: number): number {
  const x = clamp((value - edge0) / (edge1 - edge0), 0, 1);
  return x * x * (3 - 2 * x);
}

export function mix(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/** 接近满轨时潮汐柔边收束系数：1=完整潮汐，0=贴拇指实填。 */
export function effortTideSoftScale(maskFrac: number, maxBlend: number): number {
  const settle =
    smoothstep(0.28, 0.97, maxBlend) * smoothstep(0.78, 1, maskFrac);
  return 1 - settle;
}

/**
 * 潮汐前沿：锯齿岸线 + 二元空洞/飞沫。
 * 末档 solidTrack 时整轨实填，不做过渡碎裂。
 */
export function effortTidePresence(input: {
  nX: number;
  maskFrac: number;
  maxBlend: number;
  solidTrack?: boolean;
  row: number;
  column: number;
  base: number;
  phase: number;
  elapsed: number;
}): number {
  if (input.solidTrack) return 1;
  const { nX, maskFrac, maxBlend, row, column, base, phase, elapsed } = input;
  const softScale = effortTideSoftScale(maskFrac, maxBlend);
  if (nX > maskFrac + EFFORT_TIDE_SOFT_SPILL * softScale + 0.015) return 0;
  if (softScale < 0.05) {
    return nX <= maskFrac + 0.002 ? 1 : 0;
  }

  const lead = EFFORT_TIDE_SOFT_LEAD * softScale;
  const spill = EFFORT_TIDE_SOFT_SPILL * softScale;
  const tide = Math.sin(nX * 18 + row * 2.4 + elapsed * 0.0016 + base * 6.283);
  const spray = Math.sin(
    column * 2.41 + row * 5.33 + elapsed * 0.0024 + phase * Math.PI * 2,
  );
  const foam = Math.sin(column * 11.3 + row * 1.7 + base * 9.1 + elapsed * 0.0009);
  // 岸线贴拇指：前导很短，靠锯齿与空洞做出潮水感，避免大段半透明糊边。
  const shore =
    maskFrac -
    lead * 0.4 +
    tide * EFFORT_TIDE_WAVE_AMP * softScale +
    spray * EFFORT_TIDE_SPRAY_AMP * softScale +
    foam * EFFORT_TIDE_FOAM_AMP * softScale;
  const t = (nX - shore) / Math.max(lead * 0.6 + spill, 0.001);
  if (t <= 0) return 1;
  if (t >= 1) return 0;

  const density = Math.pow(1 - clamp(t, 0, 1), 1.85);
  const gate = base * 0.48 + phase * 0.37 + ((column * 19 + row * 29) % 89) / 89 * 0.15;
  if (gate > density) {
    if (t < 0.7 || gate > density + 0.22) return 0;
    return 0.28 + density * 0.22;
  }
  return t < 0.32 ? 1 : clamp(0.62 + density * 0.38, 0.25, 1);
}

function mixRgb(a: Rgb, b: Rgb, t: number): Rgb {
  return [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
}

function mixPalette(a: EffortPalette, b: EffortPalette, t: number): EffortPalette {
  return {
    left: mixRgb(a.left, b.left, t),
    tones: a.tones.map((tone, i) => mixRgb(tone, b.tones[i]!, t)),
    highlight: mixRgb(a.highlight, b.highlight, t),
    peak: mixRgb(a.peak, b.peak, t),
    rClamp: [mix(a.rClamp[0], b.rClamp[0], t), mix(a.rClamp[1], b.rClamp[1], t)],
    gClamp: [mix(a.gClamp[0], b.gClamp[0], t), mix(a.gClamp[1], b.gClamp[1], t)],
    bClamp: [mix(a.bClamp[0], b.bClamp[0], t), mix(a.bClamp[1], b.bClamp[1], t)],
    boost: mix(a.boost, b.boost, t),
  };
}

function rgbCss(color: Rgb): string {
  return `rgb(${Math.round(color[0])} ${Math.round(color[1])} ${Math.round(color[2])})`;
}

export function isDarkEffortTheme(): boolean {
  if (typeof document === 'undefined') return false;
  const root = document.documentElement;
  const attr = root.getAttribute('data-theme')?.toLowerCase();
  if (attr === 'dark') return true;
  if (attr === 'light') return false;
  const surface = getComputedStyle(root).getPropertyValue('--m3-surface').trim();
  const match = surface.match(/rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/i);
  if (match) {
    const r = Number(match[1]);
    const g = Number(match[2]);
    const b = Number(match[3]);
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 128;
  }
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

/** 连续滑块 0..100 → 像素场 / 流光混合系数（与 Flutter 进度曲线对齐）。 */
export function resolveEffortFxBlends(
  slider100: number,
  _optionCount: number,
): {
  pixelStart: number;
  pixelBlend: number;
  lowBlend: number;
  maxBlend: number;
  stream01: number;
} {
  const progress = clamp(slider100 / 100, 0, 1);
  // 与 App 端 _smoothstep 阈值一致：像素场 / 绿→蓝 / 蓝→紫。
  const pixelBlend = smoothstep(0.18, 0.55, progress);
  const lowBlend = smoothstep(0.0, 0.55, progress);
  const maxBlend = smoothstep(0.55, 1.0, progress);
  const stream01 = progress > 0 ? 0.15 + progress * 0.85 : 0;
  return { pixelStart: 1, pixelBlend, lowBlend, maxBlend, stream01 };
}

interface PixelCell {
  x: number;
  y: number;
  row: number;
  column: number;
  nX: number;
  base: number;
  tempo: number;
  phase: number;
  chroma: number;
  purple: number;
  intensity: number;
  depth: number;
}

export interface EffortPixelFieldHandle {
  setParams: (params: {
    active: boolean;
    lowBlend: number;
    maxBlend: number;
    thumb100: number;
    dark: boolean;
    reducedMotion: boolean;
  }) => void;
  /** 弹层动画结束后需重测布局尺寸（勿用 getBoundingClientRect，会吃到 scale）。 */
  resize: () => void;
  destroy: () => void;
}

/** 绑定轨道内像素场画布；返回更新句柄。 */
export function attachEffortPixelField(
  canvas: HTMLCanvasElement,
): EffortPixelFieldHandle {
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    return {
      setParams: () => undefined,
      resize: () => undefined,
      destroy: () => undefined,
    };
  }

  let active = false;
  let lowBlend = 1;
  let maxBlend = 0;
  let thumb100 = 0;
  let dark = false;
  let reduced = false;
  let startedAt = 0;
  let wasActive = false;
  let width = 0;
  let height = 0;
  let ratio = 1;
  let grid: PixelCell[] = [];
  let cellSize = 6;
  let gapBase = 1.1;
  let rafId: number | null = null;
  let loopRunning = false;
  let lastFrame = 0;
  let destroyed = false;
  let resizeDebounce = 0;

  const buildGrid = () => {
    const cell = width < 280 ? 5 : 6;
    const gap = 1.1;
    const columns = Math.ceil(width / cell);
    const rows = Math.ceil(height / cell);
    const cells: PixelCell[] = [];
    for (let row = 0; row < rows; row += 1) {
      for (let column = 0; column < columns; column += 1) {
        const x = column * cell;
        const y = row * cell;
        const nX = (x + cell * 0.5) / Math.max(width, 1);
        cells.push({
          x,
          y,
          row,
          column,
          nX,
          base: Math.abs(Math.sin(column * 12.9898 + row * 78.233) * 43758.5453) % 1,
          tempo: Math.abs(Math.sin(column * 7.13 + row * 19.41) * 19341.731) % 1,
          phase: Math.abs(Math.sin(column * 31.17 + row * 11.93) * 28437.123) % 1,
          chroma: Math.abs(Math.sin(column * 9.47 + row * 67.13) * 15823.917) % 1,
          purple: smoothstep(0.1, 0.88, nX),
          intensity: smoothstep(0.04, 0.38, nX),
          depth: smoothstep(0.35, 0.95, nX),
        });
      }
    }
    grid = cells;
    cellSize = cell;
    gapBase = gap;
  };

  const resize = () => {
    if (destroyed) return;
    // clientWidth 不受弹层 scale transform 影响，避免画布被量成动画中的缩小尺寸。
    const w = canvas.clientWidth || canvas.offsetWidth || 0;
    const h = canvas.clientHeight || canvas.offsetHeight || 0;
    if (w < 2 || h < 2) return;
    const nextRatio = Math.min(window.devicePixelRatio || 1, 2);
    const nextW = Math.round(w * nextRatio);
    const nextH = Math.round(h * nextRatio);
    if (width === w && height === h && ratio === nextRatio && canvas.width === nextW) {
      draw(Date.now());
      return;
    }
    ratio = nextRatio;
    canvas.width = nextW;
    canvas.height = nextH;
    width = w;
    height = h;
    buildGrid();
    draw(Date.now());
  };

  const draw = (time: number) => {
    if (destroyed || !canvas.width || !canvas.height) return;
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, width, height);
    if (!active) return;

    // 末档整轨实填；非末档右缘跟随拇指。不做从右向左扫过显现。
    const solidTrack = isEffortLastTier(thumb100);
    const maskFrac = solidTrack ? 1 : clamp(thumb100 / 100, 0, 1);
    const gap = 0.2 + (gapBase - 0.2) * maxBlend;
    const elapsed = reduced ? 0 : Math.max(0, time - startedAt);

    const greenPal: EffortPalette = {
      ...EFFORT_GREEN_PALETTE,
      left: dark ? DARK_GREEN_LEFT : EFFORT_GREEN_PALETTE.left,
    };
    const bluePal: EffortPalette = {
      ...EFFORT_BLUE_PALETTE,
      left: dark ? DARK_BLUE_LEFT : EFFORT_BLUE_PALETTE.left,
    };
    const purplePal: EffortPalette = {
      ...EFFORT_PURPLE_PALETTE,
      left: dark ? DARK_PURPLE_LEFT : EFFORT_PURPLE_PALETTE.left,
    };
    const pal = mixPalette(
      mixPalette(greenPal, bluePal, lowBlend),
      purplePal,
      maxBlend,
    );

    const flowDuration = 4000;
    const frozenTime = reduced ? 0 : elapsed;
    const rawFlow = frozenTime / flowDuration;
    const flowCycle = Math.floor(rawFlow);
    const easedFlow = flowCycle + smoothstep(0, 1, rawFlow - flowCycle);

    ctx.save();
    ctx.beginPath();
    if (typeof ctx.roundRect === 'function') {
      ctx.roundRect(0, 0, width, height, 10);
    } else {
      ctx.rect(0, 0, width, height);
    }
    ctx.clip();

    for (const c of grid) {
      const tidePresence = effortTidePresence({
        nX: c.nX,
        maskFrac,
        maxBlend,
        solidTrack,
        row: c.row,
        column: c.column,
        base: c.base,
        phase: c.phase,
        elapsed,
      });
      if (tidePresence <= 0.02) continue;
      const nLocal = c.nX / Math.max(maskFrac, 0.001);
      const effIntensity = mix(1, c.intensity, maxBlend);

      const period = 500 + c.tempo * 1500;
      const localTime = elapsed + c.phase * period;
      const cycle = Math.floor(localTime / period);
      const cycleProgress = (localTime % period) / period;
      const cycleHash =
        Math.abs(Math.sin(c.column * 17.17 + c.row * 41.73 + cycle * 13.11) * 24634.6345) % 1;
      const widthHash =
        Math.abs(Math.sin(c.column * 5.37 + c.row * 29.11 + cycle * 7.43) * 17391.443) % 1;
      const pulseCenter = 0.2 + cycleHash * 0.55;
      const pulseWidth = 0.09 + widthHash * 0.08;
      const pulseDistance = (cycleProgress - pulseCenter) / pulseWidth;
      const pulseEnvelope = Math.exp(-pulseDistance * pulseDistance * 1.45);
      const activeCycle = cycleHash > 0.12 ? 1 : 0.26;
      const irregularFlicker = pulseEnvelope * activeCycle;

      const flowCoordinate = (c.nX + easedFlow) * 9;
      const flowIndex = Math.floor(flowCoordinate);
      const flowProgress = smoothstep(0, 1, flowCoordinate - flowIndex);
      const flowHashA =
        Math.abs(Math.sin(flowIndex * 18.31 + c.row * 37.17) * 19283.173) % 1;
      const flowHashB =
        Math.abs(Math.sin((flowIndex + 1) * 18.31 + c.row * 37.17) * 19283.173) % 1;
      const clusterGate = smoothstep(0.46, 0.84, mix(flowHashA, flowHashB, flowProgress));
      const wavePhase = (c.nX + easedFlow + c.row * 0.06 + c.base * 0.02) * Math.PI * 2;
      const directionalWave = Math.pow(0.5 + 0.5 * Math.cos(wavePhase), 5);
      const directionalFlow = Math.max(clusterGate, directionalWave * 0.62);
      const lightAmount = Math.max(
        irregularFlicker * (0.48 + directionalFlow * 0.58),
        directionalFlow * (0.38 + c.base * 0.28),
      );

      const peakHighlight =
        lightAmount > 0.4 &&
        irregularFlicker > 0.16 &&
        cycleHash > 0.26 &&
        clusterGate > 0.04;
      const hottestHighlight =
        lightAmount > 0.68 &&
        irregularFlicker > 0.3 &&
        cycleHash > 0.48 &&
        clusterGate > 0.12;
      const highlightAmount = peakHighlight
        ? 0.97
        : clamp(lightAmount * (0.44 + cycleHash * 0.3), 0, 0.64);

      const deepTone = pal.tones[0]!;
      const bandPurple = clamp(nLocal / 0.7, 0, 1);
      const bandColor = mixRgb(pal.left, deepTone, bandPurple);

      const toneDrift =
        c.base * 0.28 +
        c.depth * 0.28 +
        cycleProgress * 0.38 +
        easedFlow * 0.18 +
        cycleHash * 0.2 +
        Math.sin(elapsed * 0.00135 + c.phase * Math.PI * 2) * 0.14;
      const tonePosition = (((toneDrift % 1) + 1) % 1) * pal.tones.length;
      const toneIndex = Math.floor(tonePosition);
      const toneMix = tonePosition - toneIndex;
      const toneA = pal.tones[toneIndex]!;
      const toneB = pal.tones[(toneIndex + 1) % pal.tones.length]!;
      const cellTone = mixRgb(toneA, toneB, toneMix);
      const chromaNudge = (c.chroma - 0.5) * 10 + c.phase * 12;
      const variedPurple: Rgb = [
        clamp(cellTone[0] + chromaNudge * 0.35 - c.depth * 8, pal.rClamp[0], pal.rClamp[1]),
        clamp(cellTone[1] - c.depth * 16 + (c.base - 0.5) * 8, pal.gClamp[0], pal.gClamp[1]),
        clamp(cellTone[2] + c.depth * 6 + (cycleHash - 0.5) * 6, pal.bClamp[0], pal.bClamp[1]),
      ];
      const maxColor = mixRgb(pal.left, variedPurple, c.purple);
      const blendedColor = mixRgb(bandColor, maxColor, maxBlend);
      const color = hottestHighlight
        ? mixRgb(blendedColor, pal.peak, 0.95)
        : mixRgb(blendedColor, pal.highlight, highlightAmount);

      const baseOpacity = mix(0.82 + c.base * 0.08, 0.7 + c.base * 0.2, maxBlend);
      const cellAlpha =
        (peakHighlight || hottestHighlight
          ? effIntensity
          : effIntensity * clamp(baseOpacity + lightAmount * 0.12, 0, 1)) *
        tidePresence *
        pal.boost;
      if (cellAlpha < 0.02) continue;
      ctx.globalAlpha = cellAlpha;
      ctx.fillStyle = rgbCss(color);
      ctx.fillRect(
        c.x + gap * 0.5,
        c.y + gap * 0.5,
        cellSize - gap,
        cellSize - gap,
      );
    }

    ctx.restore();
    ctx.globalAlpha = 1;
  };

  const ensureLoop = () => {
    if (loopRunning || destroyed || !active) return;
    if (reduced) {
      draw(Date.now());
      return;
    }
    loopRunning = true;
    lastFrame = 0;
    const step = (t: number) => {
      if (!loopRunning || destroyed) return;
      if (!active) {
        loopRunning = false;
        rafId = null;
        draw(Date.now());
        return;
      }
      if (t - lastFrame >= EFFORT_PIXEL_FRAME_MS) {
        lastFrame = t;
        draw(Date.now());
      }
      rafId = window.requestAnimationFrame(step);
    };
    rafId = window.requestAnimationFrame(step);
  };

  const resizeObserver = new ResizeObserver(() => {
    window.clearTimeout(resizeDebounce);
    resizeDebounce = window.setTimeout(resize, 80);
  });
  resizeObserver.observe(canvas);
  resize();

  return {
    setParams: (params) => {
      if (destroyed) return;
      active = params.active;
      lowBlend = params.lowBlend;
      maxBlend = params.maxBlend;
      thumb100 = params.thumb100;
      dark = params.dark;
      reduced = params.reducedMotion;
      if (active && !wasActive) startedAt = Date.now();
      wasActive = active;
      if (active) ensureLoop();
      else if (!loopRunning) draw(Date.now());
    },
    resize,
    destroy: () => {
      destroyed = true;
      if (rafId != null) window.cancelAnimationFrame(rafId);
      rafId = null;
      loopRunning = false;
      resizeObserver.disconnect();
      window.clearTimeout(resizeDebounce);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
    },
  };
}

export interface EffortStreamFieldHandle {
  setParams: (params: {
    intensity: number;
    opacity: number;
    dark: boolean;
    reducedMotion: boolean;
  }) => void;
  resize: () => void;
  destroy: () => void;
}

/** 轻量 Canvas2D 流光：沿轨道向右缘流动的光线与火花。 */
export function attachEffortStreamField(
  canvas: HTMLCanvasElement,
): EffortStreamFieldHandle {
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    return {
      setParams: () => undefined,
      resize: () => undefined,
      destroy: () => undefined,
    };
  }

  let intensity = 0;
  let opacity = 0;
  let dark = false;
  let reduced = false;
  let width = 0;
  let height = 0;
  let ratio = 1;
  let rafId: number | null = null;
  let loopRunning = false;
  let lastFrame = 0;
  let startedAt = performance.now();
  let destroyed = false;
  let resizeDebounce = 0;

  const resize = () => {
    if (destroyed) return;
    const w = canvas.clientWidth || canvas.offsetWidth || 0;
    const h = canvas.clientHeight || canvas.offsetHeight || 0;
    if (w < 2 || h < 2) return;
    const nextRatio = Math.min(window.devicePixelRatio || 1, 2);
    const nextW = Math.round(w * nextRatio);
    const nextH = Math.round(h * nextRatio);
    if (width === w && height === h && ratio === nextRatio && canvas.width === nextW) {
      draw(performance.now());
      return;
    }
    ratio = nextRatio;
    canvas.width = nextW;
    canvas.height = nextH;
    width = w;
    height = h;
    draw(performance.now());
  };

  const draw = (now: number) => {
    if (destroyed || !canvas.width || !canvas.height) return;
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, width, height);
    if (intensity <= 0.001 || opacity <= 0.01) return;

    const t = reduced ? 0 : (now - startedAt) / 1000;
    const edge = intensity;
    const k = smoothstep(0.5, 0.92, intensity);
    const blue: Rgb = [51, 140, 255];
    const purp: Rgb = [166, 89, 255];
    const accent = mixRgb(blue, purp, k);
    const bright = mixRgb(accent, [255, 255, 255], 0.12);
    const es = mix(0.2, 1, clamp(t / 1.1, 0, 1));

    ctx.save();
    ctx.globalAlpha = opacity;
    ctx.beginPath();
    if (typeof ctx.roundRect === 'function') {
      ctx.roundRect(0, 0, width, height, 10);
    } else {
      ctx.rect(0, 0, width, height);
    }
    ctx.clip();

    const frontX = edge * width;
    const glow = ctx.createLinearGradient(0, 0, frontX, 0);
    const c0 = rgbCss(mixRgb(accent, bright, 0.35));
    const c1 = rgbCss(accent);
    glow.addColorStop(0, 'rgba(0,0,0,0)');
    glow.addColorStop(Math.max(0, edge - 0.22), 'rgba(0,0,0,0)');
    glow.addColorStop(Math.max(0, edge - 0.05), c0);
    glow.addColorStop(1, c1);
    ctx.globalCompositeOperation = dark ? 'screen' : 'source-over';
    ctx.fillStyle = glow;
    ctx.globalAlpha = opacity * (0.35 + intensity * 0.45) * es;
    ctx.fillRect(0, 0, frontX, height);

    for (let i = 0; i < 18; i += 1) {
      const seed = i * 17.13;
      const spd = 0.35 + ((seed * 0.13) % 0.55);
      const loop = ((t * spd * 0.28 + seed) % 1 + 1) % 1;
      const head = edge * Math.pow(loop, 0.45);
      const x = head * width;
      const y = height * (0.22 + ((seed * 0.37) % 0.56));
      const twinkle = 0.55 + 0.45 * Math.sin(t * (3.2 + (seed % 2.4)) + seed);
      const radius = 1.1 + (seed % 1.8);
      ctx.globalAlpha = opacity * twinkle * intensity * es * 0.85;
      ctx.fillStyle = rgbCss(mixRgb(accent, bright, (seed % 1) * 0.5));
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha *= 0.45;
      ctx.beginPath();
      ctx.ellipse(x - radius * 3.2, y, radius * 4.5, radius * 0.55, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    const pulse = 0.5 + 0.5 * Math.sin(t * 5);
    ctx.globalAlpha = opacity * (0.45 + pulse * 0.25) * intensity * es;
    const core = ctx.createRadialGradient(frontX, height * 0.5, 0, frontX, height * 0.5, 18);
    core.addColorStop(0, rgbCss(bright));
    core.addColorStop(0.45, rgbCss(accent));
    core.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = core;
    ctx.fillRect(frontX - 22, 0, 36, height);
    ctx.restore();
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
  };

  const ensureLoop = () => {
    if (loopRunning || destroyed) return;
    if (reduced || intensity <= 0.001 || opacity <= 0.01) {
      draw(performance.now());
      return;
    }
    loopRunning = true;
    lastFrame = 0;
    const step = (t: number) => {
      if (!loopRunning || destroyed) return;
      if (intensity <= 0.001 || opacity <= 0.01) {
        loopRunning = false;
        rafId = null;
        draw(t);
        return;
      }
      if (t - lastFrame >= EFFORT_STREAM_FRAME_MS) {
        lastFrame = t;
        draw(t);
      }
      rafId = window.requestAnimationFrame(step);
    };
    rafId = window.requestAnimationFrame(step);
  };

  const resizeObserver = new ResizeObserver(() => {
    window.clearTimeout(resizeDebounce);
    resizeDebounce = window.setTimeout(resize, 80);
  });
  resizeObserver.observe(canvas);
  resize();

  return {
    setParams: (params) => {
      if (destroyed) return;
      const wasOff = intensity <= 0.001;
      intensity = params.intensity;
      opacity = params.opacity;
      dark = params.dark;
      reduced = params.reducedMotion;
      if (wasOff && intensity > 0.001) startedAt = performance.now();
      ensureLoop();
    },
    resize,
    destroy: () => {
      destroyed = true;
      if (rafId != null) window.cancelAnimationFrame(rafId);
      rafId = null;
      loopRunning = false;
      resizeObserver.disconnect();
      window.clearTimeout(resizeDebounce);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
    },
  };
}
