// 多媒体生成选项弹窗：对齐 APP 端 _CreationOptionsSheet 的功能与视觉。
// 支持图片（宽高比 + 数量）、视频（宽高比 + 时长 + 数量）、音频（时长 + 数量）。
import { useState } from 'preact/hooks';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
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

function modeTitle(mode: string): string {
  switch (mode) {
    case 'image': return t('creation.options.imageTitle', '图像生成选项');
    case 'video': return t('creation.options.videoTitle', '视频生成选项');
    case 'audio': return t('creation.options.audioTitle', '音频生成选项');
    default: return '';
  }
}

export function CreationOptionsDialog({ mode, initial, onConfirm, onCancel }: CreationOptionsDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onCancel);
  const [aspectRatio, setAspectRatio] = useState(
    initial?.aspectRatio ?? (mode === 'image' ? '1:1' : mode === 'video' ? '16:9' : undefined),
  );
  const [durationSeconds, setDurationSeconds] = useState(
    initial?.durationSeconds ?? (mode === 'video' ? 5 : mode === 'audio' ? 10 : undefined),
  );
  const [count, setCount] = useState(initial?.count ?? 1);

  const handleConfirm = () => {
    onConfirm({
      aspectRatio: mode !== 'audio' ? aspectRatio : undefined,
      durationSeconds: mode !== 'image' ? durationSeconds : undefined,
      count,
    });
  };

  const ratios = mode === 'image' ? IMAGE_RATIOS : mode === 'video' ? VIDEO_RATIOS : [];
  const durations = mode === 'video' ? VIDEO_DURATIONS : mode === 'audio' ? AUDIO_DURATIONS : [];

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
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
                onClick={() => setCount(Math.max(1, count - 1))}
                disabled={count <= 1}
                class="oh-tap-press w-8 h-8 rounded-full flex items-center justify-center text-lg disabled:opacity-30"
                style={{ border: '1px solid var(--m3-outline-variant)' }}
              >
                −
              </button>
              <span class="text-base font-semibold w-6 text-center">{count}</span>
              <button
                type="button"
                onClick={() => setCount(Math.min(4, count + 1))}
                disabled={count >= 4}
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
              onClick={requestClose}
              class="oh-tap-press px-5 py-2.5 rounded-full text-sm font-medium"
              style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
            >
              {t('common.cancel', '取消')}
            </button>
            <button
              type="button"
              onClick={handleConfirm}
              class="oh-tap-press px-5 py-2.5 rounded-full text-sm font-medium"
              style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
            >
              {t('common.confirm', '确认')}
            </button>
          </div>
    </DialogFrame>
  );
}
