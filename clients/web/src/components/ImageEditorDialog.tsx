import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { t } from '../i18n';
import { clampNumber, finiteNumberFromText } from '../shared/util/number';
import {
  base64PayloadFromDataUrl,
  readBlobAsDataUrl,
} from '../utils/blob_data_url';
import { copyBlobToClipboard, copyTextToClipboard } from '../utils/clipboard';
import { describeApiError } from '../utils/api_error';
import { runWithTimeout } from '../utils/timed_abort';
import {
  DIALOG_OVERLAY_MEDIA_Z_INDEX,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import { svgIconProps } from '../shared/ui/svg_icon';

export interface ImageEditorInput {
  name: string;
  mime: string;
  dataUrl: string;
  size: number;
}

export interface ImageEditorResult {
  name: string;
  mime: string;
  dataUrl: string;
  dataBase64: string;
  size: number;
}

interface ImageEditorDialogProps {
  input: ImageEditorInput;
  onCancel: () => void;
  onSave: (result: ImageEditorResult) => void;
}

type CropAspect = 'free' | 'original' | '1:1' | '4:3' | '3:4' | '16:9' | '9:16' | 'circle';
type WatermarkPosition = 'tl' | 'tc' | 'tr' | 'ml' | 'mc' | 'mr' | 'bl' | 'bc' | 'br';

type ImageEditorIconName =
  | 'compare'
  | 'check'
  | 'rotateLeft'
  | 'rotateRight'
  | 'flipH'
  | 'flipV'
  | 'reset'
  | 'download'
  | 'copy'
  | 'undo'
  | 'dot';

function ImageEditorIcon({ name, size = 15 }: { name: ImageEditorIconName; size?: number }) {
  const common = svgIconProps({ size });
  switch (name) {
    case 'compare':
      return <svg {...common}><circle cx="12" cy="12" r="8" /><path d="M12 4v16" /></svg>;
    case 'check':
      return <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
    case 'rotateLeft':
      return <svg {...common}><path d="M8 7H4V3" /><path d="M4 7a8 8 0 1 1 2.3 5.7" /></svg>;
    case 'rotateRight':
      return <svg {...common}><path d="M16 7h4V3" /><path d="M20 7a8 8 0 1 0-2.3 5.7" /></svg>;
    case 'flipH':
      return <svg {...common}><path d="M4 5v14" /><path d="M20 5v14" /><path d="m8 8 4 4-4 4z" /><path d="m16 8-4 4 4 4z" /></svg>;
    case 'flipV':
      return <svg {...common}><path d="M5 4h14" /><path d="M5 20h14" /><path d="m8 8 4 4 4-4z" /><path d="m8 16 4-4 4 4z" /></svg>;
    case 'reset':
      return <svg {...common}><path d="M4 12a8 8 0 0 1 13.4-5.9" /><path d="M17 3v4h-4" /><path d="M20 12a8 8 0 0 1-13.4 5.9" /><path d="M7 21v-4h4" /></svg>;
    case 'download':
      return <svg {...common}><path d="M12 4v10" /><path d="m8 10 4 4 4-4" /><path d="M5 19h14" /></svg>;
    case 'copy':
      return <svg {...common}><rect x="8" y="8" width="11" height="11" rx="2" /><path d="M5 15V7a2 2 0 0 1 2-2h8" /></svg>;
    case 'undo':
      return <svg {...common}><path d="M9 7H4v5" /><path d="M4 12a8 8 0 1 0 2.3-5.7" /></svg>;
    case 'dot':
      return <svg {...common}><circle cx="12" cy="12" r="3.3" fill="currentColor" stroke="none" /></svg>;
  }
}

interface EditorSettings {
  aspect: CropAspect;
  zoom: number;
  panX: number;
  panY: number;
  rotation: number;
  flipH: boolean;
  flipV: boolean;
  brightness: number;
  contrast: number;
  saturation: number;
  exposure: number;
  hue: number;
  vignette: number;
  temperature: number;
  tint: number;
  gamma: number;
  clarity: number;
  sharpness: number;
  denoise: number;
  grain: number;
  dispersion: number;
  distort: number;
  watermarkText: string;
  watermarkSize: number;
  watermarkOpacity: number;
  watermarkPosition: WatermarkPosition;
  watermarkHue: number;
  watermarkSaturation: number;
  watermarkLightness: number;
}

const DEFAULT_SETTINGS: EditorSettings = {
  aspect: 'free',
  zoom: 1,
  panX: 0,
  panY: 0,
  rotation: 0,
  flipH: false,
  flipV: false,
  brightness: 1,
  contrast: 1,
  saturation: 1,
  exposure: 0,
  hue: 0,
  vignette: 0,
  temperature: 0,
  tint: 0,
  gamma: 1,
  clarity: 0,
  sharpness: 0,
  denoise: 0,
  grain: 0,
  dispersion: 0,
  distort: 0,
  watermarkText: '',
  watermarkSize: 48,
  watermarkOpacity: 0.85,
  watermarkPosition: 'br',
  watermarkHue: 0,
  watermarkSaturation: 0,
  watermarkLightness: 0.94,
};

const ASPECTS: { key: CropAspect; label: string }[] = [
  { key: 'free', label: '自由' },
  { key: 'original', label: '原始' },
  { key: '1:1', label: '1:1' },
  { key: '4:3', label: '4:3' },
  { key: '3:4', label: '3:4' },
  { key: '16:9', label: '16:9' },
  { key: '9:16', label: '9:16' },
  { key: 'circle', label: '圆形' },
];

const IMAGE_ENCODE_TIMEOUT_MS = 15_000;
const IMAGE_CLIPBOARD_FETCH_TIMEOUT_MS = 10_000;

export function ImageEditorDialog({ input, onCancel, onSave }: ImageEditorDialogProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const imageRef = useRef<HTMLImageElement | null>(null);
  const dragRef = useRef<{ x: number; y: number; panX: number; panY: number } | null>(null);
  const mountedRef = useRef(true);
  const [settings, setSettings] = useState<EditorSettings>(DEFAULT_SETTINGS);
  const [naturalSize, setNaturalSize] = useState({ width: 0, height: 0 });
  const [busy, setBusy] = useState(false);
  const pendingSaveResultRef = useRef<ImageEditorResult | null>(null);
  const { closing, requestClose, requestCloseWithReason } = useDialogExitMotion<
    'cancel' | 'save'
  >(
    (reason) => {
      const result = pendingSaveResultRef.current;
      pendingSaveResultRef.current = null;
      if (reason === 'save' && result) {
        onSave(result);
        return;
      }
      onCancel();
    },
  );
  const [showOriginal, setShowOriginal] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [undoStack, setUndoStack] = useState<EditorSettings[]>([]);

  useEffect(() => () => {
    mountedRef.current = false;
  }, []);

  const ratio = useMemo(() => aspectRatio(settings.aspect, naturalSize), [settings.aspect, naturalSize]);
  const previewSize = useMemo(() => fitSize(ratio, 720, 420), [ratio]);

  useEffect(() => {
    let cancelled = false;
    const image = new Image();
    image.decoding = 'async';
    image.onload = () => {
      if (cancelled) return;
      imageRef.current = image;
      setNaturalSize({ width: image.naturalWidth || 1, height: image.naturalHeight || 1 });
      setError(null);
    };
    image.onerror = () => {
      if (!cancelled) setError(t('imageEditor.loadFailed', '无法加载所选图片'));
    };
    image.src = input.dataUrl;
    return () => {
      cancelled = true;
      image.onload = null;
      image.onerror = null;
    };
  }, [input.dataUrl]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const image = imageRef.current;
    if (!canvas || !image || naturalSize.width <= 0 || naturalSize.height <= 0) return;
    const frame = requestAnimationFrame(() => {
      renderToCanvas(canvas, image, showOriginal ? { ...DEFAULT_SETTINGS, aspect: settings.aspect } : settings, {
        width: previewSize.width,
        height: previewSize.height,
        preview: true,
      });
    });
    return () => cancelAnimationFrame(frame);
  }, [settings, showOriginal, previewSize.width, previewSize.height, naturalSize.width, naturalSize.height]);

  function pushUndo(): void {
    setUndoStack((prev) => [...prev.slice(-19), settings]);
  }

  function update<K extends keyof EditorSettings>(key: K, value: EditorSettings[K]): void {
    setSettings((prev) => ({ ...prev, [key]: value }));
  }

  async function makeResult(download = false): Promise<ImageEditorResult> {
    await yieldToBrowser();
    const image = imageRef.current;
    if (!image) throw new Error(t('imageEditor.loadFailed', '无法加载所选图片'));
    const outputRatio = aspectRatio(settings.aspect, naturalSize);
    const out = outputSize(outputRatio, naturalSize, 2048);
    const canvas = document.createElement('canvas');
    renderToCanvas(canvas, image, settings, { width: out.width, height: out.height, preview: false });
    const mime = settings.aspect === 'circle' ? 'image/png' : 'image/jpeg';
    const { dataUrl, dataBase64, size } = await encodeCanvas(canvas, mime, 0.92);
    const ext = mime === 'image/png' ? 'png' : 'jpg';
    const name = replaceExtension(input.name, ext);
    if (download) {
      const link = document.createElement('a');
      link.href = dataUrl;
      link.download = name;
      link.click();
    }
    return { name, mime, dataUrl, dataBase64, size };
  }

  async function save(): Promise<void> {
    if (busy || closing) return;
    setBusy(true);
    setError(null);
    try {
      pendingSaveResultRef.current = await makeResult(false);
      if (!mountedRef.current) return;
      requestCloseWithReason('save');
    } catch (err: unknown) {
      pendingSaveResultRef.current = null;
      if (mountedRef.current) setError(describeApiError(err));
    } finally {
      if (mountedRef.current) setBusy(false);
    }
  }

  async function download(): Promise<void> {
    setBusy(true);
    setStatus(null);
    setError(null);
    try {
      await makeResult(true);
      if (mountedRef.current) setStatus(t('imageEditor.savedLocal', '已另存到本地'));
    } catch (err: unknown) {
      if (mountedRef.current) setError(describeApiError(err));
    } finally {
      if (mountedRef.current) setBusy(false);
    }
  }

  async function copyToClipboard(): Promise<void> {
    setBusy(true);
    setStatus(null);
    setError(null);
    try {
      const result = await makeResult(false);
      const blob = await runWithTimeout(
        async () => (await fetch(result.dataUrl)).blob(),
        { timeoutMs: IMAGE_CLIPBOARD_FETCH_TIMEOUT_MS },
      );
      if (!mountedRef.current) return;
      if (await copyBlobToClipboard(blob)) {
        if (!mountedRef.current) return;
        setStatus(t('imageEditor.copiedBitmap', '已复制图片到剪贴板'));
      } else if (await copyTextToClipboard(result.dataUrl)) {
        if (!mountedRef.current) return;
        setStatus(t('imageEditor.copiedDataUrl', '无法写入位图，已复制图片 data URL'));
      } else {
        setError(t('imageEditor.copyFailed', '复制图片失败，请检查浏览器剪贴板权限'));
      }
    } catch (err: unknown) {
      if (mountedRef.current) setError(describeApiError(err));
    } finally {
      if (mountedRef.current) setBusy(false);
    }
  }

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      closeOnBackdrop={!busy && !closing}
      {...createStandardDialogFrameAppearance({
        overlayClassName:
          'fixed inset-0 flex items-center justify-center p-3 sm:p-5',
        overlayZIndex: DIALOG_OVERLAY_MEDIA_Z_INDEX,
        panelClassName: 'oh-image-editor-dialog',
        panelStyle: {},
      })}
      ariaLabel={t('imageEditor.title', '编辑图片')}
    >
      <div class="oh-image-editor-body">
          <header class="oh-image-editor-header">
            <h2>{t('imageEditor.title', '编辑图片')}</h2>
            <p>{t('imageEditor.hint', '拖动方框调整裁剪区域，可继续缩放、旋转、翻转，展开下方面板可使用 HSL、色调分离、清晰度、颗粒、降噪、色散、扭曲、水印等高级调整（高级调整在保存时应用）。')}</p>
          </header>

          <div class="oh-image-editor-scroll">
            <section class="oh-image-editor-preview-row">
              <div class="oh-image-editor-preview-shell" style={{ width: '100%', maxWidth: `${previewSize.width}px` }}>
                <canvas
                  ref={canvasRef}
                  width={previewSize.width}
                  height={previewSize.height}
                  class="oh-image-editor-canvas"
                  onPointerDown={(event) => {
                    (event.currentTarget as HTMLCanvasElement).setPointerCapture(event.pointerId);
                    dragRef.current = { x: event.clientX, y: event.clientY, panX: settings.panX, panY: settings.panY };
                  }}
                  onPointerMove={(event) => {
                    const drag = dragRef.current;
                    if (!drag) return;
                    update(
                      'panX',
                      clampNumber(
                        drag.panX + (event.clientX - drag.x) / previewSize.width,
                        -1.5,
                        1.5,
                      ),
                    );
                    update(
                      'panY',
                      clampNumber(
                        drag.panY + (event.clientY - drag.y) / previewSize.height,
                        -1.5,
                        1.5,
                      ),
                    );
                  }}
                  onPointerUp={() => { dragRef.current = null; }}
                  onPointerCancel={() => { dragRef.current = null; }}
                />
              </div>
              <button
                type="button"
                class="oh-image-editor-compare oh-tap-press"
                onPointerDown={() => setShowOriginal(true)}
                onPointerUp={() => setShowOriginal(false)}
                onPointerLeave={() => setShowOriginal(false)}
                disabled={busy}
              >
                <ImageEditorIcon name="compare" />
                {showOriginal ? t('imageEditor.release', '松开') : t('imageEditor.compare', '按住对比')}
              </button>
            </section>

            <div class="oh-image-editor-aspects">
              {ASPECTS.map((item) => {
                const active = settings.aspect === item.key;
                return (
                <button
                  key={item.key}
                  type="button"
                  class="oh-tap-press"
                  data-active={active ? 'true' : 'false'}
                  onClick={() => { pushUndo(); setSettings((prev) => ({ ...prev, aspect: item.key, panX: 0, panY: 0 })); }}
                >
                  <span class="oh-image-editor-button-icon">
                    {active ? <ImageEditorIcon name="check" size={13} /> : null}
                  </span>
                  {item.label}
                </button>
                );
              })}
            </div>

            <div class="oh-image-editor-actions">
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); update('rotation', settings.rotation - 90); }}><ImageEditorIcon name="rotateLeft" />{t('imageEditor.rotateLeft', '左转')}</button>
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); update('rotation', settings.rotation + 90); }}><ImageEditorIcon name="rotateRight" />{t('imageEditor.rotateRight', '右转')}</button>
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); update('flipH', !settings.flipH); }}><ImageEditorIcon name="flipH" />{t('imageEditor.flipH', '水平翻转')}</button>
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); update('flipV', !settings.flipV); }}><ImageEditorIcon name="flipV" />{t('imageEditor.flipV', '垂直翻转')}</button>
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); setSettings((prev) => ({ ...DEFAULT_SETTINGS, aspect: prev.aspect })); }}><ImageEditorIcon name="reset" />{t('imageEditor.reset', '重置')}</button>
            </div>

            <section class="oh-image-editor-sliders">
              <EditorSlider label={t('imageEditor.zoom', '缩放')} value={settings.zoom} min={0.6} max={3} step={0.01} onChange={(v) => update('zoom', v)} />
              <EditorSlider label={t('imageEditor.brightness', '亮度')} value={settings.brightness} min={0.5} max={1.5} step={0.01} onChange={(v) => update('brightness', v)} />
              <EditorSlider label={t('imageEditor.contrast', '对比度')} value={settings.contrast} min={0.6} max={1.6} step={0.01} onChange={(v) => update('contrast', v)} />
              <EditorSlider label={t('imageEditor.saturation', '饱和度')} value={settings.saturation} min={0} max={2} step={0.01} onChange={(v) => update('saturation', v)} />
              <EditorSlider label={t('imageEditor.exposure', '曝光')} value={settings.exposure} min={-1} max={1} step={0.01} onChange={(v) => update('exposure', v)} />
              <EditorSlider label={t('imageEditor.hue', '色相')} value={settings.hue} min={-180} max={180} step={1} onChange={(v) => update('hue', v)} />
              <EditorSlider label={t('imageEditor.vignette', '暗角')} value={settings.vignette} min={0} max={1} step={0.01} onChange={(v) => update('vignette', v)} />
              <EditorSlider label={t('imageEditor.fineRotation', '微调旋转 (°)')} value={settings.rotation} min={-180} max={180} step={1} onChange={(v) => update('rotation', v)} />
            </section>

            <p class="oh-image-editor-advanced-hint">{t('imageEditor.advancedHint', '展开面板中的调整会在“保存”时一次性应用到原图。')}</p>
            <details class="oh-image-editor-section">
              <summary>{t('imageEditor.sectionColor', '色彩（色温 / 色调 / 伽马）')}</summary>
              <EditorSlider label={t('imageEditor.temperature', '色温')} value={settings.temperature} min={-100} max={100} step={1} onChange={(v) => update('temperature', v)} />
              <EditorSlider label={t('imageEditor.tint', '色调偏移')} value={settings.tint} min={-100} max={100} step={1} onChange={(v) => update('tint', v)} />
              <EditorSlider label={t('imageEditor.gamma', '伽马（曲线）')} value={settings.gamma} min={0.5} max={2} step={0.01} onChange={(v) => update('gamma', v)} />
            </details>
            <details class="oh-image-editor-section">
              <summary>{t('imageEditor.sectionDetail', '细节（清晰度 / 锐度 / 降噪 / 颗粒）')}</summary>
              <EditorSlider label={t('imageEditor.clarity', '清晰度')} value={settings.clarity} min={0} max={100} step={1} onChange={(v) => update('clarity', v)} />
              <EditorSlider label={t('imageEditor.sharpness', '锐度')} value={settings.sharpness} min={0} max={100} step={1} onChange={(v) => update('sharpness', v)} />
              <EditorSlider label={t('imageEditor.denoise', '降噪')} value={settings.denoise} min={0} max={100} step={1} onChange={(v) => update('denoise', v)} />
              <EditorSlider label={t('imageEditor.grain', '颗粒')} value={settings.grain} min={0} max={100} step={1} onChange={(v) => update('grain', v)} />
            </details>
            <details class="oh-image-editor-section">
              <summary>{t('imageEditor.sectionEffects', '特效（色散 / 扭曲 / 晕影）')}</summary>
              <EditorSlider label={t('imageEditor.dispersion', '色散')} value={settings.dispersion} min={0} max={20} step={1} onChange={(v) => update('dispersion', v)} />
              <EditorSlider label={t('imageEditor.distort', '扭曲（正值凸出 / 负值拉伸）')} value={settings.distort} min={-100} max={100} step={1} onChange={(v) => update('distort', v)} />
            </details>
            <details class="oh-image-editor-section">
              <summary>{t('imageEditor.sectionWatermark', '文字水印 / 标记')}</summary>
              <label class="oh-image-editor-text-field">
                <span>{t('imageEditor.watermarkText', '水印文字')}</span>
                <input value={settings.watermarkText} maxLength={120} placeholder={t('imageEditor.watermarkHint', '输入要叠加的文字（留空则不添加）')} onInput={(e) => update('watermarkText', (e.currentTarget as HTMLInputElement).value)} />
              </label>
              <EditorSlider label={t('imageEditor.watermarkSize', '文字大小')} value={settings.watermarkSize} min={12} max={160} step={1} onChange={(v) => update('watermarkSize', v)} />
              <EditorSlider label={t('imageEditor.watermarkOpacity', '透明度')} value={settings.watermarkOpacity} min={0.1} max={1} step={0.01} onChange={(v) => update('watermarkOpacity', v)} />
              <EditorSlider label={t('imageEditor.watermarkHue', '文字色相')} value={settings.watermarkHue} min={0} max={360} step={1} onChange={(v) => update('watermarkHue', v)} />
              <EditorSlider label={t('imageEditor.watermarkSaturation', '文字饱和度')} value={settings.watermarkSaturation} min={0} max={1} step={0.01} onChange={(v) => update('watermarkSaturation', v)} />
              <EditorSlider label={t('imageEditor.watermarkLightness', '文字明度')} value={settings.watermarkLightness} min={0} max={1} step={0.01} onChange={(v) => update('watermarkLightness', v)} />
              <div class="oh-image-editor-position-grid">
                {(['tl', 'tc', 'tr', 'ml', 'mc', 'mr', 'bl', 'bc', 'br'] as WatermarkPosition[]).map((pos) => (
                  <button type="button" data-active={settings.watermarkPosition === pos ? 'true' : 'false'} onClick={() => update('watermarkPosition', pos)} aria-label={pos}><ImageEditorIcon name="dot" size={12} /></button>
                ))}
              </div>
            </details>

            {status ? <p class="oh-image-editor-status">{status}</p> : null}
            {error ? <p class="oh-image-editor-error">{error}</p> : null}
          </div>

          <footer class="oh-image-editor-footer">
            <button type="button" class="oh-tap-press" disabled={busy} onClick={() => void download()}><ImageEditorIcon name="download" />{t('imageEditor.saveLocal', '另存到本地')}</button>
            <button type="button" class="oh-tap-press" disabled={busy} onClick={() => void copyToClipboard()}><ImageEditorIcon name="copy" />{t('imageEditor.copy', '复制到剪贴板')}</button>
            <span class="flex-1" />
            <button type="button" class="oh-tap-press" disabled={busy} onClick={() => { pushUndo(); setStatus(t('imageEditor.applied', '调整已应用')); }}><ImageEditorIcon name="check" />{t('imageEditor.apply', '应用')}</button>
            <button type="button" class="oh-tap-press" disabled={busy || undoStack.length === 0} onClick={() => {
              const previous = undoStack[undoStack.length - 1];
              if (!previous) return;
              setSettings(previous);
              setUndoStack((prev) => prev.slice(0, -1));
            }}><ImageEditorIcon name="undo" />{t('imageEditor.undo', '回退')}</button>
            <button type="button" class="oh-tap-press" disabled={busy} onClick={() => { pushUndo(); setSettings(DEFAULT_SETTINGS); }}><ImageEditorIcon name="reset" />{t('imageEditor.resetAll', '重置全部')}</button>
            <button type="button" class="oh-tap-press" disabled={busy || closing} onClick={requestClose}>{t('common.cancel', '取消')}</button>
            <button type="button" class="oh-tap-press is-primary" disabled={busy || closing || Boolean(error)} onClick={() => void save()}>{busy ? t('common.processing', '处理中…') : t('common.save', '保存')}</button>
          </footer>
        </div>
    </DialogFrame>
  );
}

function EditorSlider({ label, value, min, max, step, onChange }: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (value: number) => void;
}) {
  return (
    <label class="oh-image-editor-slider">
      <span>{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onInput={(event) => {
          const next = finiteNumberFromText((event.currentTarget as HTMLInputElement).value);
          if (next == null) return;
          onChange(clampNumber(next, min, max));
        }}
      />
      <output>{value.toFixed(step >= 1 ? 0 : 2)}</output>
    </label>
  );
}

function aspectRatio(aspect: CropAspect, size: { width: number; height: number }): number {
  const original = size.width > 0 && size.height > 0 ? size.width / size.height : 1;
  switch (aspect) {
    case '1:1':
    case 'circle':
      return 1;
    case '4:3':
      return 4 / 3;
    case '3:4':
      return 3 / 4;
    case '16:9':
      return 16 / 9;
    case '9:16':
      return 9 / 16;
    case 'free':
    case 'original':
    default:
      return original;
  }
}

function fitSize(ratio: number, maxWidth: number, maxHeight: number): { width: number; height: number } {
  let width = maxWidth;
  let height = Math.round(width / ratio);
  if (height > maxHeight) {
    height = maxHeight;
    width = Math.round(height * ratio);
  }
  return { width: Math.max(180, width), height: Math.max(180, height) };
}

function outputSize(ratio: number, natural: { width: number; height: number }, maxLongSide: number): { width: number; height: number } {
  const longSide = Math.min(maxLongSide, Math.max(natural.width, natural.height));
  if (ratio >= 1) return { width: Math.round(longSide), height: Math.round(longSide / ratio) };
  return { width: Math.round(longSide * ratio), height: Math.round(longSide) };
}

function renderToCanvas(
  canvas: HTMLCanvasElement,
  image: HTMLImageElement,
  settings: EditorSettings,
  size: { width: number; height: number; preview: boolean },
): void {
  canvas.width = size.width;
  canvas.height = size.height;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return;
  ctx.clearRect(0, 0, size.width, size.height);
  if (settings.aspect !== 'circle') {
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, size.width, size.height);
  }
  if (settings.aspect === 'circle') {
    ctx.save();
    ctx.beginPath();
    ctx.arc(size.width / 2, size.height / 2, Math.min(size.width, size.height) / 2, 0, Math.PI * 2);
    ctx.clip();
  }
  const drawScale = Math.max(size.width / image.naturalWidth, size.height / image.naturalHeight) * settings.zoom;
  const rotation = (settings.rotation * Math.PI) / 180;
  ctx.save();
  ctx.filter = `brightness(${Math.max(0.05, settings.brightness + settings.exposure * 0.32)}) contrast(${settings.contrast}) saturate(${settings.saturation}) hue-rotate(${settings.hue}deg)`;
  ctx.translate(size.width / 2 + settings.panX * size.width * 0.5, size.height / 2 + settings.panY * size.height * 0.5);
  ctx.rotate(rotation);
  ctx.scale(settings.flipH ? -1 : 1, settings.flipV ? -1 : 1);
  const distortion = 1 + settings.distort / 700;
  ctx.scale(distortion, 1 / distortion);
  ctx.drawImage(image, -image.naturalWidth * drawScale / 2, -image.naturalHeight * drawScale / 2, image.naturalWidth * drawScale, image.naturalHeight * drawScale);
  ctx.restore();
  if (settings.aspect === 'circle') ctx.restore();
  applyPixelTone(ctx, size.width, size.height, settings, size.preview);
  applyOverlays(ctx, size.width, size.height, settings);
}

function applyPixelTone(ctx: CanvasRenderingContext2D, width: number, height: number, settings: EditorSettings, preview: boolean): void {
  if (
    settings.temperature === 0 && settings.tint === 0 && settings.gamma === 1 &&
    settings.clarity === 0 && settings.sharpness === 0 && settings.denoise === 0 &&
    settings.grain === 0 && settings.dispersion === 0
  ) return;
  const data = ctx.getImageData(0, 0, width, height);
  const pixels = data.data;
  const temp = settings.temperature * 0.45;
  const tint = settings.tint * 0.32;
  const clarity = (settings.clarity + settings.sharpness) / 260;
  const denoise = preview ? 0 : settings.denoise / 400;
  const gamma = Math.max(0.1, settings.gamma);
  for (let i = 0; i < pixels.length; i += 4) {
    const grain = settings.grain > 0 ? (Math.random() - 0.5) * settings.grain * 0.9 : 0;
    let r = pixels[i] + temp + grain;
    let g = pixels[i + 1] + tint + grain;
    let b = pixels[i + 2] - temp * 0.55 + grain;
    const avg = (r + g + b) / 3;
    r = avg + (r - avg) * (1 + clarity);
    g = avg + (g - avg) * (1 + clarity);
    b = avg + (b - avg) * (1 + clarity);
    if (denoise > 0) {
      r = r * (1 - denoise) + avg * denoise;
      g = g * (1 - denoise) + avg * denoise;
      b = b * (1 - denoise) + avg * denoise;
    }
    pixels[i] = clamp255(
      255 * Math.pow(clampNumber(r, 0, 255) / 255, 1 / gamma),
    );
    pixels[i + 1] = clamp255(
      255 * Math.pow(clampNumber(g, 0, 255) / 255, 1 / gamma),
    );
    pixels[i + 2] = clamp255(
      255 * Math.pow(clampNumber(b, 0, 255) / 255, 1 / gamma),
    );
  }
  ctx.putImageData(data, 0, 0);
  if (settings.dispersion > 0) {
    const shift = settings.dispersion * (preview ? 0.4 : 1);
    const copy = document.createElement('canvas');
    copy.width = width;
    copy.height = height;
    copy.getContext('2d')?.drawImage(ctx.canvas, 0, 0);
    ctx.globalCompositeOperation = 'screen';
    ctx.globalAlpha = 0.08;
    ctx.drawImage(copy, shift, 0);
    ctx.drawImage(copy, -shift, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
  }
}

function applyOverlays(ctx: CanvasRenderingContext2D, width: number, height: number, settings: EditorSettings): void {
  if (settings.vignette > 0) {
    const gradient = ctx.createRadialGradient(width / 2, height / 2, Math.min(width, height) * 0.18, width / 2, height / 2, Math.max(width, height) * 0.62);
    gradient.addColorStop(0, 'rgba(0,0,0,0)');
    gradient.addColorStop(1, `rgba(0,0,0,${0.58 * settings.vignette})`);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
  }
  const text = settings.watermarkText.trim();
  if (!text) return;
  const margin = Math.max(16, Math.min(width, height) * 0.04);
  const xMap = { l: margin, c: width / 2, r: width - margin };
  const yMap = { t: margin, m: height / 2, b: height - margin };
  const horizontal = settings.watermarkPosition[1] as 'l' | 'c' | 'r';
  const vertical = settings.watermarkPosition[0] as 't' | 'm' | 'b';
  ctx.save();
  ctx.globalAlpha = settings.watermarkOpacity;
  ctx.fillStyle = `hsl(${settings.watermarkHue} ${settings.watermarkSaturation * 100}% ${settings.watermarkLightness * 100}%)`;
  ctx.font = `700 ${settings.watermarkSize}px system-ui, -apple-system, BlinkMacSystemFont, sans-serif`;
  ctx.textAlign = horizontal === 'l' ? 'left' : horizontal === 'r' ? 'right' : 'center';
  ctx.textBaseline = vertical === 't' ? 'top' : vertical === 'b' ? 'bottom' : 'middle';
  ctx.shadowColor = 'rgba(0,0,0,0.35)';
  ctx.shadowBlur = 8;
  ctx.fillText(text, xMap[horizontal], yMap[vertical], width - margin * 2);
  ctx.restore();
}

function replaceExtension(name: string, ext: string): string {
  const clean = name.trim() || 'image';
  return clean.replace(/\.[^.]+$/, '') + `.${ext}`;
}

async function encodeCanvas(
  canvas: HTMLCanvasElement,
  mime: string,
  quality: number,
): Promise<{ dataUrl: string; dataBase64: string; size: number }> {
  const blob = await new Promise<Blob | null>((resolve) => {
    let settled = false;
    const finish = (value: Blob | null) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      resolve(value);
    };
    const timer = window.setTimeout(() => finish(null), IMAGE_ENCODE_TIMEOUT_MS);
    try {
      canvas.toBlob(finish, mime, quality);
    } catch {
      finish(null);
    }
  });
  if (blob == null) {
    const dataUrl = canvas.toDataURL(mime, quality);
    const dataBase64 = base64PayloadFromDataUrl(dataUrl) ?? '';
    if (!dataBase64) throw new Error('图片编码失败');
    return {
      dataUrl,
      dataBase64,
      size: Math.ceil((dataBase64.length * 3) / 4),
    };
  }

  const dataUrl = await readBlobAsDataUrl(blob, {
    timeoutMs: IMAGE_ENCODE_TIMEOUT_MS,
    failureMessage: '图片编码失败',
    timeoutMessage: '图片编码超时',
  });
  const dataBase64 = base64PayloadFromDataUrl(dataUrl) ?? '';
  if (!dataBase64) throw new Error('图片编码失败');
  return { dataUrl, dataBase64, size: blob.size };
}

function yieldToBrowser(): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, 0));
}

function clamp255(value: number): number {
  return Math.round(clampNumber(value, 0, 255));
}
