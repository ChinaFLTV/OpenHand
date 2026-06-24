// 获取AI摘要标题弹窗：范围滑块选择消息区间 + 标题模型选择 + pending 状态展示。
import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ApiMetaModel } from '../api/meta';
import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { describeApiError, isAbortError } from '../utils/api_error';
import {
  DIALOG_OVERLAY_FOCUSED_Z_INDEX,
  DialogFrame,
  createDialogFrameAppearance,
} from './DialogFrame';
import { ModelPickerDialog } from './ModelPickerDialog';

type Phase = 'loading' | 'config' | 'pending' | 'success' | 'error';
type ErrorMode = 'load' | 'generate';

interface TitleSummaryDialogProps {
  initialMessages?: SessionMessage[];
  loadMessages: (options: { signal: AbortSignal }) => Promise<SessionMessage[]>;
  onGenerate: (
    startIndex: number,
    endIndex: number,
    userMessages: SessionMessage[],
    options: { signal: AbortSignal; modelKey?: string },
  ) => Promise<string>;
  models?: ApiMetaModel[];
  initialModelKey?: string;
  onClose: () => void;
  onTitleUpdated?: (title: string) => void;
}

function truncateContent(content: string, maxLen = 60): string {
  const cleaned = content.replace(/\n/g, ' ').trim();
  return cleaned.length > maxLen ? cleaned.slice(0, maxLen) + '…' : cleaned;
}

export function TitleSummaryDialog({
  initialMessages = [],
  loadMessages,
  onGenerate,
  models = [],
  initialModelKey = '',
  onClose,
  onTitleUpdated,
}: TitleSummaryDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [messages, setMessages] = useState<SessionMessage[]>(initialMessages);

  // 仅用户消息参与选择
  const userMessages = useMemo(
    () => messages.filter((m) => m.role === 'user' && m.content.trim().length > 0),
    [messages],
  );
  const totalMessages = userMessages.length;
  const [startIdx, setStartIdx] = useState(0);
  const [endIdx, setEndIdx] = useState(Math.min(totalMessages - 1, 2));
  const [phase, setPhase] = useState<Phase>('loading');
  const [generatedTitle, setGeneratedTitle] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [errorMode, setErrorMode] = useState<ErrorMode>('generate');
  const [tooltipInfo, setTooltipInfo] = useState<{ text: string; x: number; y: number } | null>(null);
  const [modelKey, setModelKey] = useState(initialModelKey);
  const [modelPickerOpen, setModelPickerOpen] = useState(false);
  const sliderContainerRef = useRef<HTMLDivElement | null>(null);
  const loadControllerRef = useRef<AbortController | null>(null);
  const activeControllerRef = useRef<AbortController | null>(null);
  const generationIdRef = useRef(0);
  const loadIdRef = useRef(0);

  useEffect(() => {
    if (totalMessages > 0 && endIdx >= totalMessages) {
      setEndIdx(totalMessages - 1);
    }
  }, [totalMessages, endIdx]);

  const startLoadingMessages = useCallback(async () => {
    loadControllerRef.current?.abort();
    const controller = new AbortController();
    const loadId = loadIdRef.current + 1;
    loadIdRef.current = loadId;
    loadControllerRef.current = controller;
    setTooltipInfo(null);
    setErrorMessage('');
    setErrorMode('load');
    setPhase('loading');
    try {
      const loaded = await loadMessages({ signal: controller.signal });
      if (loadIdRef.current !== loadId || controller.signal.aborted) {
        return;
      }
      loadControllerRef.current = null;
      const loadedUserCount = loaded.filter((m) => m.role === 'user' && m.content.trim().length > 0).length;
      setMessages(loaded);
      setStartIdx(0);
      setEndIdx(Math.min(Math.max(loadedUserCount - 1, 0), 2));
      setPhase('config');
    } catch (err) {
      if (loadIdRef.current !== loadId || controller.signal.aborted || isAbortError(err)) {
        return;
      }
      loadControllerRef.current = null;
      setErrorMessage(describeApiError(err));
      setErrorMode('load');
      setPhase('error');
    }
  }, [loadMessages]);

  useEffect(() => {
    void startLoadingMessages();
    return () => {
      loadIdRef.current += 1;
      loadControllerRef.current?.abort();
      loadControllerRef.current = null;
    };
  }, [startLoadingMessages]);

  useEffect(() => {
    return () => {
      generationIdRef.current += 1;
      loadIdRef.current += 1;
      loadControllerRef.current?.abort();
      loadControllerRef.current = null;
      activeControllerRef.current?.abort();
      activeControllerRef.current = null;
    };
  }, []);

  const handleGenerate = useCallback(async () => {
    if (totalMessages === 0) return;
    activeControllerRef.current?.abort();
    const controller = new AbortController();
    const generationId = generationIdRef.current + 1;
    generationIdRef.current = generationId;
    activeControllerRef.current = controller;
    setErrorMessage('');
    setErrorMode('generate');
    setPhase('pending');
    try {
      const title = await onGenerate(startIdx, endIdx, userMessages, {
        signal: controller.signal,
        modelKey,
      });
      if (generationIdRef.current !== generationId || controller.signal.aborted) {
        return;
      }
      activeControllerRef.current = null;
      setGeneratedTitle(title);
      setPhase('success');
      onTitleUpdated?.(title);
    } catch (err) {
      if (generationIdRef.current !== generationId || controller.signal.aborted || isAbortError(err)) {
        return;
      }
      activeControllerRef.current = null;
      setErrorMessage(describeApiError(err));
      setErrorMode('generate');
      setPhase('error');
    }
  }, [startIdx, endIdx, modelKey, onGenerate, onTitleUpdated, totalMessages, userMessages]);

  const handleCancelGenerate = useCallback(() => {
    generationIdRef.current += 1;
    activeControllerRef.current?.abort();
    activeControllerRef.current = null;
    requestClose();
  }, [requestClose]);

  const handleCancelLoad = useCallback(() => {
    loadIdRef.current += 1;
    loadControllerRef.current?.abort();
    loadControllerRef.current = null;
    requestClose();
  }, [requestClose]);

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
  const selectedModel = useMemo(
    () => models.find((model) => model.key === modelKey),
    [models, modelKey],
  );

  useEffect(() => {
    if (!initialModelKey) return;
    setModelKey((current) => {
      if (current && models.some((model) => model.key === current)) return current;
      return models.some((model) => model.key === initialModelKey) ? initialModelKey : '';
    });
  }, [initialModelKey, models]);

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      closeOnBackdrop={phase !== 'pending'}
      {...createDialogFrameAppearance({
        overlay: {
          background: 'color-mix(in srgb, black 48%, transparent)',
          blurPx: 6,
          zIndex: DIALOG_OVERLAY_FOCUSED_Z_INDEX,
        },
        panelClassName: 'w-full max-w-md rounded-2xl px-6 py-5',
        panelSurface: {
          boxShadow: 'var(--m3-elev-4)',
          border: 'none',
        },
      })}
      ariaLabel={t('titleSummary.title', '获取 AI 摘要标题')}
    >
      {phase === 'loading' ? (
            <div class="flex flex-col items-center py-6 gap-4">
              <div class="oh-spin" style={{ color: 'var(--m3-primary)' }}>
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
                  <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
                </svg>
              </div>
              <p class="text-sm font-medium">{t('titleSummary.loadingMessages', '正在读取线程消息…')}</p>
              <button
                type="button"
                onClick={handleCancelLoad}
                class="oh-tap-press px-5 py-2 rounded-full text-sm font-medium mt-1"
                style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
              >
                {t('common.cancel', '取消')}
              </button>
            </div>
          ) : phase === 'config' ? (
            <>
              <h3 class="text-base font-semibold mb-1">
                {t('titleSummary.title', '获取 AI 摘要标题')}
              </h3>
              <p class="text-xs mb-4" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('titleSummary.hint', '选择参与标题总结的用户消息区间')}
              </p>

              <div class="mb-4">
                <label class="block text-xs font-medium mb-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
                  {t('titleSummary.model', '标题生成模型')}
                </label>
                <button
                  type="button"
                  onClick={() => models.length > 0 && setModelPickerOpen(true)}
                  disabled={models.length === 0}
                  class="oh-tap-press w-full rounded-2xl px-3 py-2 text-left disabled:opacity-50"
                  style={{
                    border: '1px solid var(--m3-outline-variant)',
                    background: 'var(--m3-surface-container-low)',
                    color: 'var(--m3-on-surface)',
                  }}
                >
                  <span class="block text-sm font-semibold truncate">
                    {selectedModel?.label ?? t('titleSummary.noModel', '无可用模型，将使用文本兜底')}
                  </span>
                  <span class="block text-xs truncate" style={{ color: 'var(--m3-on-surface-variant)' }}>
                    {selectedModel
                      ? `${selectedModel.provider}${selectedModel.protocol ? ` (${selectedModel.protocol})` : ''}`
                      : t('titleSummary.modelHint', '默认按当前线程模型、同提供商默认标题模型、全局默认标题模型依次选择')}
                  </span>
                </button>
              </div>

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
              <button
                type="button"
                onClick={handleCancelGenerate}
                class="oh-tap-press px-5 py-2 rounded-full text-sm font-medium mt-1"
                style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
              >
                {t('common.cancel', '取消')}
              </button>
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
              <p class="text-sm font-medium">
                {errorMode === 'load'
                  ? t('titleSummary.loadFailed', '线程消息读取失败')
                  : t('titleSummary.failed', '标题生成失败')}
              </p>
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
                  onClick={() => {
                    if (errorMode === 'load') {
                      void startLoadingMessages();
                    } else {
                      setPhase('config');
                    }
                  }}
                  class="oh-tap-press px-4 py-2 rounded-full text-sm font-medium"
                  style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
                >
                  {t('common.retry', '重试')}
                </button>
              </div>
            </div>
          )}
      {modelPickerOpen ? (
        <ModelPickerDialog
          models={models}
          selectedKey={modelKey}
          onSelect={(key) => {
            setModelKey(key);
            setModelPickerOpen(false);
          }}
          onClose={() => setModelPickerOpen(false)}
        />
      ) : null}
    </DialogFrame>
  );
}
