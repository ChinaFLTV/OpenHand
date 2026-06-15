// 多媒体生成选项弹窗：对齐 APP 端 _CreationOptionsSheet 的功能与视觉。
// 支持图片（宽高比 + 数量）、视频（宽高比 + 时长 + 数量）、音频（时长 + 数量）。
import { useRef, useState } from 'preact/hooks';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { normalizeInteger } from '../shared/util/number';
import {
  DIALOG_OVERLAY_PRIORITY_Z_INDEX,
  DialogFrame,
  createDialogOverlayStyle,
} from './DialogFrame';

export interface CreationOptions {
  aspectRatio?: string;
  durationSeconds?: number;
  count?: number;
}

interface CreationOptionsDialogProps {
  mode: 'image' | 'video' | 'audio';
  initial?: CreationOptions;
  onConfirm: (options: CreationOptions) => void;
  onCancel: () => void;
}

const IMAGE_RATIOS = ['1:1', '16:9', '9:16', '4:3', '3:4'];
const VIDEO_RATIOS = ['16:9', '9:16', '1:1', '4:3'];
const VIDEO_DURATIONS = [3, 5, 8, 10];
const AUDIO_DURATIONS = [5, 10, 20, 30, 60];
const MIN_CREATION_COUNT = 1;
const MAX_CREATION_COUNT = 4;

function clampCreationCount(value: number | undefined): number {
  return normalizeInteger(value, {
    fallback: MIN_CREATION_COUNT,
    min: MIN_CREATION_COUNT,
    max: MAX_CREATION_COUNT,
  });
}

function modeTitle(mode: string): string {
  switch (mode) {
    case 'image': return t('creation.options.imageTitle', '图像生成选项');
    case 'video': return t('creation.options.videoTitle', '视频生成选项');
    case 'audio': return t('creation.options.audioTitle', '音频生成选项');
    default: return '';
  }
}

export function CreationOptionsDialog({ mode, initial, onConfirm, onCancel }: CreationOptionsDialogProps) {
  const closeActionRef = useRef<'cancel' | 'confirm'>('cancel');
  const selectedOptionsRef = useRef<CreationOptions>({});
  const [aspectRatio, setAspectRatio] = useState(
    initial?.aspectRatio ?? (mode === 'image' ? '1:1' : mode === 'video' ? '16:9' : undefined),
  );
  const [durationSeconds, setDurationSeconds] = useState(
    initial?.durationSeconds ?? (mode === 'video' ? 5 : mode === 'audio' ? 10 : undefined),
  );
  const [count, setCount] = useState(clampCreationCount(initial?.count));

  const selectedOptions = (): CreationOptions => ({
    aspectRatio: mode !== 'audio' ? aspectRatio : undefined,
    durationSeconds: mode !== 'image' ? durationSeconds : undefined,
    count,
  });

  const { closing, requestClose } = useDialogExitMotion(() => {
    const action = closeActionRef.current;
    closeActionRef.current = 'cancel';
    if (action === 'confirm') {
      onConfirm(selectedOptionsRef.current);
      return;
    }
    onCancel();
  });

  const requestCancel = () => {
    closeActionRef.current = 'cancel';
    requestClose();
  };

  const requestConfirm = () => {
    selectedOptionsRef.current = selectedOptions();
    closeActionRef.current = 'confirm';
    requestClose();
  };

  const ratios = mode === 'image' ? IMAGE_RATIOS : mode === 'video' ? VIDEO_RATIOS : [];
  const durations = mode === 'video' ? VIDEO_DURATIONS : mode === 'audio' ? AUDIO_DURATIONS : [];

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestCancel}
      closeOnBackdrop={!closing}
      overlayClassName="fixed inset-0 flex items-end justify-center"
      overlayStyle={createDialogOverlayStyle({
        background: 'color-mix(in srgb, black 32%, transparent)',
        blurPx: 0,
        zIndex: DIALOG_OVERLAY_PRIORITY_Z_INDEX,
      })}
      panelAnimation="slideUp"
      panelClassName="w-full max-w-2xl rounded-t-2xl px-6 py-5"
      panelStyle={{
        background: 'var(--m3-surface-container-low)',
        color: 'var(--m3-on-surface)',
        boxShadow: 'var(--m3-elev-3)',
      }}
      ariaLabel={modeTitle(mode)}
    >
      <h3 class="text-base font-semibold mb-4">{modeTitle(mode)}</h3>

          {/* 宽高比 */}
          {ratios.length > 0 ? (
            <div class="mb-4">
              <p class="text-xs font-medium mb-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('creation.options.aspectRatio', '宽高比')}
              </p>
              <div class="flex flex-wrap gap-2">
                {ratios.map((r) => (
                  <button
                    key={r}
                    type="button"
                    onClick={() => setAspectRatio(r)}
                    class={`oh-tap-press px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
                      aspectRatio === r
                        ? 'oh-creation-chip-active'
                        : 'oh-creation-chip'
                    }`}
                  >
                    {aspectRatio === r ? `✓ ${r}` : r}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {/* 时长 */}
          {durations.length > 0 ? (
            <div class="mb-4">
              <p class="text-xs font-medium mb-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('creation.options.duration', '时长（秒）')}
              </p>
              <div class="flex flex-wrap gap-2">
                {durations.map((d) => (
                  <button
                    key={d}
                    type="button"
                    onClick={() => setDurationSeconds(d)}
                    class={`oh-tap-press px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
                      durationSeconds === d
                        ? 'oh-creation-chip-active'
                        : 'oh-creation-chip'
                    }`}
                  >
                    {durationSeconds === d ? `✓ ${d}s` : `${d}s`}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {/* 数量 */}
          <div class="mb-5">
            <p class="text-xs font-medium mb-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('creation.options.count', '数量')}
            </p>
            <div class="flex items-center gap-3">
              <button
                type="button"
                onClick={() => setCount((current) => clampCreationCount(current - 1))}
                disabled={closing || count <= MIN_CREATION_COUNT}
                class="oh-tap-press w-8 h-8 rounded-full flex items-center justify-center text-lg disabled:opacity-30"
                style={{ border: '1px solid var(--m3-outline-variant)' }}
              >
                −
              </button>
              <span class="text-base font-semibold w-6 text-center">{count}</span>
              <button
                type="button"
                onClick={() => setCount((current) => clampCreationCount(current + 1))}
                disabled={closing || count >= MAX_CREATION_COUNT}
                class="oh-tap-press w-8 h-8 rounded-full flex items-center justify-center text-lg disabled:opacity-30"
                style={{ border: '1px solid var(--m3-outline-variant)' }}
              >
                +
              </button>
            </div>
          </div>

          {/* 操作按钮 */}
          <div class="flex justify-end gap-3">
            <button
              type="button"
              onClick={requestCancel}
              disabled={closing}
              class="oh-tap-press px-5 py-2.5 rounded-full text-sm font-medium"
              style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
            >
              {t('common.cancel', '取消')}
            </button>
            <button
              type="button"
              onClick={requestConfirm}
              disabled={closing}
              class="oh-tap-press px-5 py-2.5 rounded-full text-sm font-medium disabled:opacity-60"
              style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
            >
              {t('common.confirm', '确认')}
            </button>
          </div>
    </DialogFrame>
  );
}
