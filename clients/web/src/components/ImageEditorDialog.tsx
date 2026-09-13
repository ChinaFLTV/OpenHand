import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { t } from '../i18n';
import { clampNumber, finiteNumberFromText } from '../shared/util/number';
import {
  base64PayloadFromDataUrl,
  readBlobAsDataUrl,
} from '../utils/blob_data_url';
import { copyBlobToClipboard, copyTextToClipboard } from '../utils/clipboard';
import { describeApiError } from '../utils/api_error';
import { downloadBlobWithAnchor } from '../utils/save_blob';
import { runWithTimeout } from '../utils/timed_abort';
import {
  DIALOG_OVERLAY_MEDIA_Z_INDEX,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import { DialogFooterActions } from './DialogChrome';
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
  | 'dot'
  | 'photo'
  | 'crop'
  | 'sliders'
  | 'palette'
  | 'sparkle'
  | 'wand'
  | 'text';

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
    case 'photo':
      return <svg {...common}><rect x="4" y="6" width="16" height="13" rx="2" /><circle cx="12" cy="13" r="3.1" /><path d="M8 6 9.4 4h5.2L16 6" /></svg>;
    case 'crop':
      return <svg {...common}><path d="M6 3v15h15" /><path d="M18 21V9H3" /></svg>;
    case 'sliders':
      return <svg {...common}><path d="M4 7h16" /><path d="M4 12h16" /><path d="M4 17h16" /><circle cx="9" cy="7" r="1.8" fill="currentColor" /><circle cx="15" cy="12" r="1.8" fill="currentColor" /><circle cx="11" cy="17" r="1.8" fill="currentColor" /></svg>;
    case 'palette':
      return <svg {...common}><path d="M12 4a8 8 0 1 0 .2 16h1.5a1.8 1.8 0 0 0 0-3.6H12" /><circle cx="8.2" cy="10" r="1" fill="currentColor" stroke="none" /><circle cx="10.5" cy="7.4" r="1" fill="currentColor" stroke="none" /><circle cx="14.2" cy="7.8" r="1" fill="currentColor" stroke="none" /></svg>;
    case 'sparkle':
      return <svg {...common}><path d="M12 4l1.15 4.7L18 10l-4.85 1.3L12 16l-1.15-4.7L6 10l4.85-1.3z" /><path d="M18.2 15.2l.55 2.1 2.1.55-2.1.55-.55 2.1-.55-2.1-2.1-.55 2.1-.55z" /></svg>;
    case 'wand':
      return <svg {...common}><path d="m4 20 9-9" /><path d="m15 5 1.1.35L16.5 6.5l.35-1.15L18 5l-1.15-.35L16.5 3.5 16.15 4.65z" /><path d="M8 4.5v3" /><path d="M6.5 6h3" /></svg>;
    case 'text':
      return <svg {...common}><path d="M5 7h14" /><path d="M12 7v12" /><path d="M9 19h6" /></svg>;
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

const ASPECTS: readonly CropAspect[] = [
  'free',
  'original',
  '1:1',
  '4:3',
  '3:4',
  '16:9',
  '9:16',
  'circle',
];

const IMAGE_ENCODE_TIMEOUT_MS = 15_000;
const IMAGE_DATA_URL_DECODE_TIMEOUT_MS = 10_000;
const IMAGE_EDITOR_PREVIEW_MAX_WIDTH = 720;
const IMAGE_EDITOR_PREVIEW_MAX_HEIGHT = 420;
const IMAGE_EDITOR_OUTPUT_MAX_LONG_SIDE = 2048;
const IMAGE_EDITOR_JPEG_QUALITY = 0.92;
const IMAGE_EDITOR_MAX_UNDO_ENTRIES = 20;

export function ImageEditorDialog({ input, onCancel, onSave }: ImageEditorDialogProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const imageRef = useRef<HTMLImageElement | null>(null);
  const dragRef = useRef<{ x: number; y: number; panX: number; panY: number } | null>(null);
  const mountedRef = useRef(true);
  const operationBusyRef = useRef(false);
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

  useEffect(() => {
    if (!busy && !closing) return;
    setShowOriginal(false);
  }, [busy, closing]);

  const ratio = useMemo(() => aspectRatio(settings.aspect, naturalSize), [settings.aspect, naturalSize]);
  const previewSize = useMemo(
    () => fitSize(
      ratio,
      IMAGE_EDITOR_PREVIEW_MAX_WIDTH,
      IMAGE_EDITOR_PREVIEW_MAX_HEIGHT,
    ),
    [ratio],
  );

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
    setUndoStack((prev) => [
      ...prev.slice(-(IMAGE_EDITOR_MAX_UNDO_ENTRIES - 1)),
      settings,
    ]);
  }

  function update<K extends keyof EditorSettings>(key: K, value: EditorSettings[K]): void {
    setSettings((prev) => ({ ...prev, [key]: value }));
  }

  async function makeResult(): Promise<{
    result: ImageEditorResult;
    blob: Blob;
  }> {
    await yieldToBrowser();
    const image = imageRef.current;
    if (!image) throw new Error(t('imageEditor.loadFailed', '无法加载所选图片'));
    const outputRatio = aspectRatio(settings.aspect, naturalSize);
    const out = outputSize(
      outputRatio,
      naturalSize,
      IMAGE_EDITOR_OUTPUT_MAX_LONG_SIDE,
    );
    const canvas = document.createElement('canvas');
    renderToCanvas(canvas, image, settings, { width: out.width, height: out.height, preview: false });
    const mime = settings.aspect === 'circle' ? 'image/png' : 'image/jpeg';
    const { dataUrl, dataBase64, size, blob } = await encodeCanvas(
      canvas,
      mime,
      IMAGE_EDITOR_JPEG_QUALITY,
    );
    const ext = mime === 'image/png' ? 'png' : 'jpg';
    const name = replaceExtension(input.name, ext);
    return {
      result: { name, mime, dataUrl, dataBase64, size },
      blob,
    };
  }

  async function runBusyOperation(operation: () => Promise<void>): Promise<void> {
    if (operationBusyRef.current || closing || pendingSaveResultRef.current) return;
    operationBusyRef.current = true;
    setBusy(true);
    setStatus(null);
    setError(null);
    try {
      await operation();
    } catch (err: unknown) {
      if (mountedRef.current) setError(describeApiError(err));
    } finally {
      operationBusyRef.current = false;
      if (mountedRef.current) setBusy(false);
    }
  }

  async function save(): Promise<void> {
    await runBusyOperation(async () => {
      pendingSaveResultRef.current = null;
      const { result } = await makeResult();
      if (!mountedRef.current) return;
      pendingSaveResultRef.current = result;
      requestCloseWithReason('save');
    });
  }

  async function download(): Promise<void> {
    await runBusyOperation(async () => {
      const { result, blob } = await makeResult();
      if (!mountedRef.current) return;
      downloadBlobWithAnchor(blob, result.name);
      setStatus(t('imageEditor.savedLocal', '已另存到本地'));
    });
  }

  async function copyToClipboard(): Promise<void> {
    await runBusyOperation(async () => {
      const { result, blob } = await makeResult();
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
    });
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
            <span class="oh-image-editor-header-icon" aria-hidden="true">
              <ImageEditorIcon name="photo" size={18} />
            </span>
            <div>
              <h2>{t('imageEditor.title', '编辑图片')}</h2>
              <p>{t('imageEditor.hint', '拖动图片调整裁剪位置，并使用下方工具精细调整。')}</p>
            </div>
          </header>

          <div class="oh-image-editor-scroll">
            <section class="oh-image-editor-stage">
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
                {showOriginal ? (
                  <span class="oh-image-editor-original-badge">
                    {t('imageEditor.original', '原图')}
                  </span>
                ) : null}
                <button
                  type="button"
                  class="oh-image-editor-compare oh-tap-press"
                  data-active={showOriginal ? 'true' : 'false'}
                  aria-pressed={showOriginal}
                  aria-label={t('imageEditor.compare', '按住对比')}
                  title={t('imageEditor.compare', '按住对比')}
                  onPointerDown={(event) => {
                    if (busy || closing) return;
                    event.preventDefault();
                    event.currentTarget.setPointerCapture(event.pointerId);
                    setShowOriginal(true);
                  }}
                  onPointerUp={() => setShowOriginal(false)}
                  onPointerCancel={() => setShowOriginal(false)}
                  onLostPointerCapture={() => setShowOriginal(false)}
                  onContextMenu={(event) => event.preventDefault()}
                  onKeyDown={(event) => {
                    if (busy || closing || event.repeat) return;
                    if (event.key !== ' ' && event.key !== 'Enter') return;
                    event.preventDefault();
                    setShowOriginal(true);
                  }}
                  onKeyUp={(event) => {
                    if (event.key !== ' ' && event.key !== 'Enter') return;
                    event.preventDefault();
                    setShowOriginal(false);
                  }}
                  onBlur={() => setShowOriginal(false)}
                  disabled={busy || closing}
                >
                  <ImageEditorIcon name="compare" />
                  {showOriginal ? t('imageEditor.release', '松开返回') : t('imageEditor.compare', '按住对比')}
                </button>
              </div>
            </section>

            <ImageEditorPanel
              tone="compose"
              icon="crop"
              title={t('imageEditor.composition', '构图')}
              hint={t('imageEditor.compositionHint', '比例、旋转与翻转')}
            >
            <div class="oh-image-editor-aspects">
              {ASPECTS.map((aspect) => {
                const active = settings.aspect === aspect;
                return (
                <button
                  key={aspect}
                  type="button"
                  class="oh-tap-press"
                  data-active={active ? 'true' : 'false'}
                  aria-pressed={active}
                  onClick={() => { pushUndo(); setSettings((prev) => ({ ...prev, aspect, panX: 0, panY: 0 })); }}
                >
                  <span class="oh-image-editor-button-icon">
                    {active ? <ImageEditorIcon name="check" size={13} /> : null}
                  </span>
                  {imageEditorAspectLabel(aspect)}
                </button>
                );
              })}
            </div>

            <div class="oh-image-editor-actions">
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); update('rotation', settings.rotation - 90); }}><ImageEditorIcon name="rotateLeft" />{t('imageEditor.rotateLeft', '左转')}</button>
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); update('rotation', settings.rotation + 90); }}><ImageEditorIcon name="rotateRight" />{t('imageEditor.rotateRight', '右转')}</button>
              <button type="button" class="oh-tap-press" data-active={settings.flipH ? 'true' : 'false'} aria-pressed={settings.flipH} onClick={() => { pushUndo(); update('flipH', !settings.flipH); }}><ImageEditorIcon name="flipH" />{t('imageEditor.flipH', '水平翻转')}</button>
              <button type="button" class="oh-tap-press" data-active={settings.flipV ? 'true' : 'false'} aria-pressed={settings.flipV} onClick={() => { pushUndo(); update('flipV', !settings.flipV); }}><ImageEditorIcon name="flipV" />{t('imageEditor.flipV', '垂直翻转')}</button>
              <button type="button" class="oh-tap-press" onClick={() => { pushUndo(); setSettings((prev) => ({ ...DEFAULT_SETTINGS, aspect: prev.aspect })); }}><ImageEditorIcon name="reset" />{t('imageEditor.reset', '重置')}</button>
            </div>
            </ImageEditorPanel>

            <ImageEditorPanel
              tone="adjust"
              icon="sliders"
              title={t('imageEditor.basicAdjust', '基础调整')}
            >
            <section class="oh-image-editor-sliders">
              <EditorSlider label={t('imageEditor.zoom', '缩放')} value={settings.zoom} min={0.6} max={3} step={0.01} onChange={(v) => update('zoom', v)} />
              <EditorSlider label={t('imageEditor.brightness', '亮度')} value={settings.brightness} min={0.5} max={1.5} step={0.01} onChange={(v) => update('brightness', v)} />
              <EditorSlider label={t('imageEditor.contrast', '对比度')} value={settings.contrast} min={0.6} max={1.6} step={0.01} onChange={(v) => update('contrast', v)} />
              <EditorSlider label={t('imageEditor.saturation', '饱和度')} value={settings.saturation} min={0} max={2} step={0.01} onChange={(v) => update('saturation', v)} />
              <EditorSlider label={t('imageEditor.exposure', '曝光')} value={settings.exposure} min={-1} max={1} step={0.01} onChange={(v) => update('exposure', v)} />
              <EditorSlider label={t('imageEditor.hue', '色相')} value={settings.hue} min={-180} max={180} step={1} onChange={(v) => update('hue', v)} />
              <EditorSlider label={t('imageEditor.vignette', '暗角')} value={settings.vignette} min={0} max={1} step={0.01} onChange={(v) => update('vignette', v)} />
              <EditorSlider label={t('imageEditor.fineRotation', '微调旋转（度）')} value={settings.rotation} min={-180} max={180} step={1} onChange={(v) => update('rotation', v)} />
            </section>
            </ImageEditorPanel>

            <p class="oh-image-editor-advanced-hint">{t('imageEditor.advancedHint', '高级调整会在保存时应用到原图。')}</p>
            <ImageEditorPanel
              tone="color"
              icon="palette"
              collapsible
              title={t('imageEditor.sectionColor', '色彩')}
              hint={t('imageEditor.sectionColorHint', '色温、色调、灰度曲线')}
            >
              <EditorSlider label={t('imageEditor.temperature', '色温')} value={settings.temperature} min={-100} max={100} step={1} onChange={(v) => update('temperature', v)} />
              <EditorSlider label={t('imageEditor.tint', '色调偏移')} value={settings.tint} min={-100} max={100} step={1} onChange={(v) => update('tint', v)} />
              <EditorSlider label={t('imageEditor.gamma', '灰度曲线')} value={settings.gamma} min={0.5} max={2} step={0.01} onChange={(v) => update('gamma', v)} />
            </ImageEditorPanel>
            <ImageEditorPanel
              tone="detail"
              icon="sparkle"
              collapsible
              title={t('imageEditor.sectionDetail', '细节')}
              hint={t('imageEditor.sectionDetailHint', '清晰度、锐度、降噪、颗粒')}
            >
              <EditorSlider label={t('imageEditor.clarity', '清晰度')} value={settings.clarity} min={0} max={100} step={1} onChange={(v) => update('clarity', v)} />
              <EditorSlider label={t('imageEditor.sharpness', '锐度')} value={settings.sharpness} min={0} max={100} step={1} onChange={(v) => update('sharpness', v)} />
              <EditorSlider label={t('imageEditor.denoise', '降噪')} value={settings.denoise} min={0} max={100} step={1} onChange={(v) => update('denoise', v)} />
              <EditorSlider label={t('imageEditor.grain', '颗粒')} value={settings.grain} min={0} max={100} step={1} onChange={(v) => update('grain', v)} />
            </ImageEditorPanel>
            <ImageEditorPanel
              tone="effects"
              icon="wand"
              collapsible
              title={t('imageEditor.sectionEffects', '特效')}
              hint={t('imageEditor.sectionEffectsHint', '色散、扭曲、晕影')}
            >
              <EditorSlider label={t('imageEditor.dispersion', '色散')} value={settings.dispersion} min={0} max={20} step={1} onChange={(v) => update('dispersion', v)} />
              <EditorSlider label={t('imageEditor.distort', '扭曲（正值凸出 / 负值拉伸）')} value={settings.distort} min={-100} max={100} step={1} onChange={(v) => update('distort', v)} />
            </ImageEditorPanel>
            <ImageEditorPanel
              tone="watermark"
              icon="text"
              collapsible
              title={t('imageEditor.sectionWatermark', '文字水印')}
              hint={t('imageEditor.sectionWatermarkHint', '叠加文字、位置与颜色')}
            >
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
                  <button
                    type="button"
                    data-active={settings.watermarkPosition === pos ? 'true' : 'false'}
                    aria-pressed={settings.watermarkPosition === pos}
                    onClick={() => update('watermarkPosition', pos)}
                    aria-label={imageEditorWatermarkPositionLabel(pos)}
                  >
                    <ImageEditorIcon name="dot" size={12} />
                  </button>
                ))}
              </div>
            </ImageEditorPanel>

            {status ? <p class="oh-image-editor-status">{status}</p> : null}
            {error ? <p class="oh-image-editor-error">{error}</p> : null}
          </div>

          <DialogFooterActions className="oh-image-editor-footer">
            <button type="button" class="oh-tap-press" disabled={busy} onClick={() => void download()}><ImageEditorIcon name="download" />{t('imageEditor.saveLocal', '另存到本地')}</button>
            <button type="button" class="oh-tap-press" disabled={busy} onClick={() => void copyToClipboard()}><ImageEditorIcon name="copy" />{t('imageEditor.copy', '复制到剪贴板')}</button>
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
          </DialogFooterActions>
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

type ImageEditorPanelTone = 'compose' | 'adjust' | 'color' | 'detail' | 'effects' | 'watermark';

function ImageEditorPanel({
  tone,
  icon,
  title,
  hint,
  collapsible = false,
  children,
}: {
  tone: ImageEditorPanelTone;
  icon: ImageEditorIconName;
  title: string;
  hint?: string;
  collapsible?: boolean;
  children: ComponentChildren;
}) {
  const heading = (
    <>
      <span class="oh-image-editor-panel-icon" aria-hidden="true">
        <ImageEditorIcon name={icon} size={16} />
      </span>
      <span class="oh-image-editor-panel-copy">
        <strong>{title}</strong>
        {hint ? <small>{hint}</small> : null}
      </span>
    </>
  );
  if (collapsible) {
    return (
      <details class={`oh-image-editor-panel is-${tone}`}>
        <summary>{heading}</summary>
        <div class="oh-image-editor-panel-body">{children}</div>
      </details>
    );
  }
  return (
    <section class={`oh-image-editor-panel is-${tone}`}>
      <header class="oh-image-editor-panel-head">{heading}</header>
      <div class="oh-image-editor-panel-body">{children}</div>
    </section>
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

function imageEditorAspectLabel(aspect: CropAspect): string {
  switch (aspect) {
    case 'free':
      return t('imageEditor.aspect.free', '自由');
    case 'original':
      return t('imageEditor.aspect.original', '原始');
    case 'circle':
      return t('imageEditor.aspect.circle', '圆形');
    default:
      return aspect;
  }
}

function imageEditorWatermarkPositionLabel(position: WatermarkPosition): string {
  switch (position) {
    case 'tl':
      return t('imageEditor.watermarkPosition.topLeft', '左上');
    case 'tc':
      return t('imageEditor.watermarkPosition.topCenter', '顶部居中');
    case 'tr':
      return t('imageEditor.watermarkPosition.topRight', '右上');
    case 'ml':
      return t('imageEditor.watermarkPosition.middleLeft', '左侧居中');
    case 'mc':
      return t('imageEditor.watermarkPosition.center', '居中');
    case 'mr':
      return t('imageEditor.watermarkPosition.middleRight', '右侧居中');
    case 'bl':
      return t('imageEditor.watermarkPosition.bottomLeft', '左下');
    case 'bc':
      return t('imageEditor.watermarkPosition.bottomCenter', '底部居中');
    case 'br':
      return t('imageEditor.watermarkPosition.bottomRight', '右下');
  }
}

function fitSize(ratio: number, maxWidth: number, maxHeight: number): { width: number; height: number } {
  const safeRatio = Number.isFinite(ratio) && ratio > 0 ? ratio : 1;
  let width = maxWidth;
  let height = width / safeRatio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * safeRatio;
  }
  return {
    width: Math.max(1, Math.round(width)),
    height: Math.max(1, Math.round(height)),
  };
}

function outputSize(ratio: number, natural: { width: number; height: number }, maxLongSide: number): { width: number; height: number } {
  const safeRatio = Number.isFinite(ratio) && ratio > 0 ? ratio : 1;
  const longSide = Math.max(
    1,
    Math.min(maxLongSide, Math.max(natural.width, natural.height)),
  );
  if (safeRatio >= 1) {
    return {
      width: Math.max(1, Math.round(longSide)),
      height: Math.max(1, Math.round(longSide / safeRatio)),
    };
  }
  return {
    width: Math.max(1, Math.round(longSide * safeRatio)),
    height: Math.max(1, Math.round(longSide)),
  };
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
): Promise<{ dataUrl: string; dataBase64: string; size: number; blob: Blob }> {
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
    if (!dataBase64) throw new Error(t('imageEditor.encodeFailed', '图片编码失败'));
    const fallbackBlob = await runWithTimeout(
      async () => (await fetch(dataUrl)).blob(),
      { timeoutMs: IMAGE_DATA_URL_DECODE_TIMEOUT_MS },
    );
    return {
      dataUrl,
      dataBase64,
      size: fallbackBlob.size,
      blob: fallbackBlob,
    };
  }

  const dataUrl = await readBlobAsDataUrl(blob, {
    timeoutMs: IMAGE_ENCODE_TIMEOUT_MS,
    failureMessage: t('imageEditor.encodeFailed', '图片编码失败'),
    timeoutMessage: t('imageEditor.encodeTimeout', '图片编码超时'),
  });
  const dataBase64 = base64PayloadFromDataUrl(dataUrl) ?? '';
  if (!dataBase64) throw new Error(t('imageEditor.encodeFailed', '图片编码失败'));
  return { dataUrl, dataBase64, size: blob.size, blob };
}

function yieldToBrowser(): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, 0));
}

function clamp255(value: number): number {
  return Math.round(clampNumber(value, 0, 255));
}
