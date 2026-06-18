// 获取AI摘要标题弹窗：范围滑块选择消息区间 + pending 状态展示。
import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_FOCUSED_Z_INDEX,
  DialogFrame,
  createDialogOverlayStyle,
} from './DialogFrame';

type Phase = 'config' | 'pending' | 'success' | 'error';

interface TitleSummaryDialogProps {
  messages: SessionMessage[];
  onGenerate: (startIndex: number, endIndex: number) => Promise<string>;
  onClose: () => void;
  onTitleUpdated?: (title: string) => void;
}

function truncateContent(content: string, maxLen = 60): string {
  const cleaned = content.replace(/\n/g, ' ').trim();
  return cleaned.length > maxLen ? cleaned.slice(0, maxLen) + '…' : cleaned;
}

export function TitleSummaryDialog({
  messages,
  onGenerate,
  onClose,
  onTitleUpdated,
}: TitleSummaryDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);

  // 仅用户消息参与选择
  const userMessages = useMemo(
    () => messages.filter((m) => m.role === 'user' && m.content.trim().length > 0),
    [messages],
  );
  const totalMessages = userMessages.length;
  const [startIdx, setStartIdx] = useState(0);
  const [endIdx, setEndIdx] = useState(Math.min(totalMessages - 1, 2));
  const [phase, setPhase] = useState<Phase>('config');
  const [generatedTitle, setGeneratedTitle] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [tooltipInfo, setTooltipInfo] = useState<{ text: string; x: number; y: number } | null>(null);
  const sliderContainerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (totalMessages > 0 && endIdx >= totalMessages) {
      setEndIdx(totalMessages - 1);
    }
  }, [totalMessages, endIdx]);

  const handleGenerate = useCallback(async () => {
    setPhase('pending');
    try {
      const title = await onGenerate(startIdx, endIdx);
      setGeneratedTitle(title);
      setPhase('success');
      onTitleUpdated?.(title);
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : String(err));
      setPhase('error');
    }
  }, [startIdx, endIdx, onGenerate, onTitleUpdated]);

  const showTooltipForIndex = (idx: number, clientX: number) => {
    if (idx < 0 || idx >= userMessages.length) {
      setTooltipInfo(null);
      return;
    }
    const msg = userMessages[idx];
    setTooltipInfo({
      text: truncateContent(msg.content),
      x: clientX,
      y: 0,
    });
  };

  const handleSliderInput = (e: Event, which: 'start' | 'end') => {
    const target = e.currentTarget as HTMLInputElement;
    const value = parseInt(target.value, 10);
    const rect = target.getBoundingClientRect();
    const ratio = (value / Math.max(1, totalMessages - 1));
    const clientX = rect.left + ratio * rect.width;
    if (which === 'start') {
      const clamped = Math.min(value, endIdx);
      setStartIdx(clamped);
      showTooltipForIndex(clamped, clientX);
    } else {
      const clamped = Math.max(value, startIdx);
      setEndIdx(clamped);
      showTooltipForIndex(clamped, clientX);
    }
  };

  const hideTooltip = () => setTooltipInfo(null);

  const selectedCount = endIdx - startIdx + 1;

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      closeOnBackdrop={phase !== 'pending'}
      overlayClassName={DIALOG_OVERLAY_CENTER_CLASS}
      overlayStyle={createDialogOverlayStyle({
        background: 'color-mix(in srgb, black 48%, transparent)',
        blurPx: 6,
        zIndex: DIALOG_OVERLAY_FOCUSED_Z_INDEX,
      })}
      panelClassName="w-full max-w-md rounded-2xl px-6 py-5"
      panelStyle={{
        background: 'var(--m3-surface-container)',
        color: 'var(--m3-on-surface)',
        boxShadow: 'var(--m3-elev-4)',
      }}
      ariaLabel={t('titleSummary.title', '获取 AI 摘要标题')}
    >
      {phase === 'config' ? (
            <>
              <h3 class="text-base font-semibold mb-1">
                {t('titleSummary.title', '获取 AI 摘要标题')}
              </h3>
              <p class="text-xs mb-4" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('titleSummary.hint', '选择参与标题总结的用户消息区间')}
              </p>

              {totalMessages === 0 ? (
                <p class="text-sm py-4 text-center" style={{ color: 'var(--m3-on-surface-variant)' }}>
                  {t('titleSummary.noMessages', '暂无用户消息可供总结')}
                </p>
              ) : (
                <div ref={sliderContainerRef} class="mb-4 relative">
                  <div class="flex justify-between text-xs mb-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
                    <span>{t('titleSummary.from', '起始')}: #{startIdx + 1}</span>
                    <span>{t('titleSummary.to', '结束')}: #{endIdx + 1}</span>
                  </div>

                  {/* 起始滑块 */}
                  <div class="mb-2">
                    <label class="text-xs font-medium" style={{ color: 'var(--m3-on-surface-variant)' }}>
                      {t('titleSummary.startMessage', '起始消息')}
                    </label>
                    <input
                      type="range"
                      min={0}
                      max={Math.max(0, totalMessages - 1)}
                      value={startIdx}
                      onInput={(e) => handleSliderInput(e, 'start')}
                      onMouseUp={hideTooltip}
                      onTouchEnd={hideTooltip}
                      class="w-full oh-range-slider"
                      style={{ accentColor: 'var(--m3-primary)' }}
                    />
                  </div>

                  {/* 结束滑块 */}
                  <div class="mb-3">
                    <label class="text-xs font-medium" style={{ color: 'var(--m3-on-surface-variant)' }}>
                      {t('titleSummary.endMessage', '结束消息')}
                    </label>
                    <input
                      type="range"
                      min={0}
                      max={Math.max(0, totalMessages - 1)}
                      value={endIdx}
                      onInput={(e) => handleSliderInput(e, 'end')}
                      onMouseUp={hideTooltip}
                      onTouchEnd={hideTooltip}
                      class="w-full oh-range-slider"
                      style={{ accentColor: 'var(--m3-primary)' }}
                    />
                  </div>

                  <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
                    {t('titleSummary.selected', '已选择')} {selectedCount} {t('titleSummary.messagesUnit', '条用户消息')}
                  </p>

                  {/* Tooltip */}
                  {tooltipInfo ? (
                    <div
                      class="oh-title-summary-tooltip"
                      style={{ left: `${Math.min(85, Math.max(5, ((tooltipInfo.x - (sliderContainerRef.current?.getBoundingClientRect().left ?? 0)) / (sliderContainerRef.current?.getBoundingClientRect().width ?? 300)) * 100))}%` }}
                    >
                      {tooltipInfo.text}
                    </div>
                  ) : null}
                </div>
              )}

              <div class="flex justify-end gap-3 mt-2">
                <button
                  type="button"
                  onClick={requestClose}
                  class="oh-tap-press px-4 py-2 rounded-full text-sm"
                  style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
                >
                  {t('common.cancel', '取消')}
                </button>
                <button
                  type="button"
                  onClick={handleGenerate}
                  disabled={totalMessages === 0}
                  class="oh-tap-press px-4 py-2 rounded-full text-sm font-medium disabled:opacity-40"
                  style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
                >
                  {t('titleSummary.generate', '生成标题')}
                </button>
              </div>
            </>
          ) : phase === 'pending' ? (
            <div class="flex flex-col items-center py-6 gap-4">
              <div class="oh-spin" style={{ color: 'var(--m3-primary)' }}>
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
                  <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
                </svg>
              </div>
              <p class="text-sm font-medium">{t('titleSummary.generating', '正在生成摘要标题…')}</p>
            </div>
          ) : phase === 'success' ? (
            <div class="flex flex-col items-center py-4 gap-3">
              <div style={{ color: 'var(--m3-primary)' }}>
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                  <polyline points="22 4 12 14.01 9 11.01" />
                </svg>
              </div>
              <p class="text-sm font-medium">{t('titleSummary.success', '标题生成成功')}</p>
              <p class="text-base font-semibold text-center px-4" style={{ color: 'var(--m3-primary)' }}>
                {generatedTitle}
              </p>
              <button
                type="button"
                onClick={requestClose}
                class="oh-tap-press px-5 py-2 rounded-full text-sm font-medium mt-2"
                style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
              >
                {t('common.close', '关闭')}
              </button>
            </div>
          ) : (
            <div class="flex flex-col items-center py-4 gap-3">
              <div style={{ color: 'var(--m3-error)' }}>
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <circle cx="12" cy="12" r="10" />
                  <line x1="15" y1="9" x2="9" y2="15" />
                  <line x1="9" y1="9" x2="15" y2="15" />
                </svg>
              </div>
              <p class="text-sm font-medium">{t('titleSummary.failed', '标题生成失败')}</p>
              <p class="text-xs text-center px-4" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {errorMessage}
              </p>
              <div class="flex gap-3 mt-2">
                <button
                  type="button"
                  onClick={requestClose}
                  class="oh-tap-press px-4 py-2 rounded-full text-sm"
                  style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
                >
                  {t('common.close', '关闭')}
                </button>
                <button
                  type="button"
                  onClick={() => setPhase('config')}
                  class="oh-tap-press px-4 py-2 rounded-full text-sm font-medium"
                  style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
                >
                  {t('common.retry', '重试')}
                </button>
              </div>
            </div>
          )}
    </DialogFrame>
  );
}
