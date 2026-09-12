// 获取AI摘要标题弹窗：范围滑块选择消息区间 + 标题模型选择 + pending 状态展示。
import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ApiMetaModel } from '../api/meta';
import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { isAbortError } from '../shared/util/errors';
import { describeApiError } from '../utils/api_error';
import { clampNumber, finiteNumberFromText, normalizeInteger } from '../shared/util/number';
import { truncateEndText } from '../shared/util/text';
import {
  DIALOG_OVERLAY_FOCUSED_Z_INDEX,
  DialogActionButton,
  DialogFrame,
  DialogHeader,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import {
  DIALOG_ACCENT,
  DIALOG_FOOTER_VARIANT,
  DialogFooterActions,
  DialogGlyph,
  DialogIconBadge,
  DialogSectionCard,
  DialogTintedPanel,
} from './DialogChrome';
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
  return truncateEndText(cleaned, maxLen);
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
      setEndIdx(clampNumber(loadedUserCount - 1, 0, 2));
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
    const maxIndex = Math.max(0, totalMessages - 1);
    const value = normalizeInteger(finiteNumberFromText(target.value), {
      fallback: which === 'start' ? startIdx : endIdx,
      min: 0,
      max: maxIndex,
    });
    const rect = target.getBoundingClientRect();
    const ratio = maxIndex > 0 ? value / maxIndex : 0;
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

  const headerSubtitle =
    phase === 'config'
      ? t('titleSummary.hint', '选择参与标题总结的用户消息区间')
      : phase === 'loading'
        ? t('titleSummary.loadingMessages', '正在读取线程消息…')
        : phase === 'pending'
          ? t('titleSummary.generating', '正在生成摘要标题…')
          : phase === 'success'
            ? t('titleSummary.success', '标题生成成功')
            : errorMode === 'load'
              ? t('titleSummary.loadFailed', '线程消息读取失败')
              : t('titleSummary.failed', '标题生成失败');
  const headerAccent =
    phase === 'success'
      ? DIALOG_ACCENT.success
      : phase === 'error'
        ? DIALOG_ACCENT.error
        : phase === 'pending'
          ? DIALOG_ACCENT.warning
          : DIALOG_ACCENT.info;

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      closeOnBackdrop={phase !== 'pending'}
      {...createStandardDialogFrameAppearance({
        overlay: {
          background: 'color-mix(in srgb, black 48%, transparent)',
          blurPx: 6,
        },
        overlayZIndex: DIALOG_OVERLAY_FOCUSED_Z_INDEX,
        panelClassName: 'w-full max-w-lg rounded-2xl overflow-hidden flex flex-col',
        panelBorder: 'none',
        panelSurface: {
          boxShadow: 'var(--m3-elev-4)',
        },
      })}
      ariaLabel={t('titleSummary.title', '获取 AI 摘要标题')}
    >
      <DialogHeader
        title={t('titleSummary.title', '获取 AI 摘要标题')}
        subtitle={headerSubtitle}
        icon={
          <DialogIconBadge accent={headerAccent}>
            <DialogGlyph name={phase === 'success' ? 'check' : phase === 'error' ? 'alert' : 'spark'} />
          </DialogIconBadge>
        }
        onClose={phase === 'pending' ? undefined : requestClose}
        closeLabel={t('common.close', '关闭')}
      />
      <div class="min-h-0 space-y-4 overflow-auto px-5 py-4">
        {phase === 'loading' ? (
          <DialogSectionCard
            title={t('titleSummary.loadingMessages', '正在读取线程消息…')}
            accent={DIALOG_ACCENT.info}
            icon={<span class="oh-spin"><DialogGlyph name="spark" /></span>}
          >
            <DialogFooterActions>
              <DialogActionButton tone="secondary" onClick={handleCancelLoad}>
                {t('common.cancel', '取消')}
              </DialogActionButton>
            </DialogFooterActions>
          </DialogSectionCard>
        ) : phase === 'config' ? (
          <>
            <DialogSectionCard
              title={t('titleSummary.model', '标题生成模型')}
              subtitle={
                selectedModel
                  ? `${selectedModel.provider}${selectedModel.protocol ? ` (${selectedModel.protocol})` : ''}`
                  : t('titleSummary.modelHint', '默认按当前线程模型、同提供商默认标题模型、全局默认标题模型依次选择')
              }
              accent={DIALOG_ACCENT.secondary}
              icon={<DialogGlyph name="model" />}
            >
              <button
                type="button"
                onClick={() => models.length > 0 && setModelPickerOpen(true)}
                disabled={models.length === 0}
                class="oh-tap-press w-full text-left disabled:opacity-50"
              >
                <DialogTintedPanel accent={DIALOG_ACCENT.secondary}>
                  <span class="block text-sm font-semibold truncate">
                    {selectedModel?.label ?? t('titleSummary.noModel', '无可用模型，将使用文本兜底')}
                  </span>
                  <span class="mt-1 block text-xs truncate oh-text-muted">
                    {selectedModel
                      ? selectedModel.key
                      : t('titleSummary.modelHint', '默认按当前线程模型、同提供商默认标题模型、全局默认标题模型依次选择')}
                  </span>
                </DialogTintedPanel>
              </button>
            </DialogSectionCard>

            {totalMessages === 0 ? (
              <DialogTintedPanel accent={DIALOG_ACCENT.warning}>
                <p class="text-sm text-center oh-text-muted">
                  {t('titleSummary.noMessages', '暂无用户消息可供总结')}
                </p>
              </DialogTintedPanel>
            ) : (
              <DialogSectionCard
                title={t('titleSummary.hint', '选择参与标题总结的用户消息区间')}
                subtitle={`${t('titleSummary.selected', '已选择')} ${selectedCount} ${t('titleSummary.messagesUnit', '条用户消息')}`}
                accent={DIALOG_ACCENT.info}
                icon={<DialogGlyph name="chat" />}
              >
                <div ref={sliderContainerRef} class="relative space-y-3">
                  <DialogTintedPanel accent={DIALOG_ACCENT.info}>
                    <div class="flex items-center justify-between gap-3">
                      <label class="text-xs font-bold" style={{ color: DIALOG_ACCENT.info }}>
                        {t('titleSummary.startMessage', '起始消息')}
                      </label>
                      <span class="text-sm font-black tabular-nums" style={{ color: DIALOG_ACCENT.info }}>
                        #{startIdx + 1}
                      </span>
                    </div>
                    <input
                      type="range"
                      min={0}
                      max={Math.max(0, totalMessages - 1)}
                      value={startIdx}
                      onInput={(e) => handleSliderInput(e, 'start')}
                      onMouseUp={hideTooltip}
                      onTouchEnd={hideTooltip}
                      class="oh-range-slider oh-dialog-range mt-2 w-full"
                      style={{ accentColor: DIALOG_ACCENT.info }}
                    />
                  </DialogTintedPanel>
                  <DialogTintedPanel accent={DIALOG_ACCENT.tertiary}>
                    <div class="flex items-center justify-between gap-3">
                      <label class="text-xs font-bold" style={{ color: DIALOG_ACCENT.tertiary }}>
                        {t('titleSummary.endMessage', '结束消息')}
                      </label>
                      <span class="text-sm font-black tabular-nums" style={{ color: DIALOG_ACCENT.tertiary }}>
                        #{endIdx + 1}
                      </span>
                    </div>
                    <input
                      type="range"
                      min={0}
                      max={Math.max(0, totalMessages - 1)}
                      value={endIdx}
                      onInput={(e) => handleSliderInput(e, 'end')}
                      onMouseUp={hideTooltip}
                      onTouchEnd={hideTooltip}
                      class="oh-range-slider oh-dialog-range mt-2 w-full"
                      style={{ accentColor: DIALOG_ACCENT.tertiary }}
                    />
                  </DialogTintedPanel>
                  {tooltipInfo ? (
                    <div
                      class="oh-title-summary-tooltip"
                      style={{ left: `${clampNumber(((tooltipInfo.x - (sliderContainerRef.current?.getBoundingClientRect().left ?? 0)) / (sliderContainerRef.current?.getBoundingClientRect().width ?? 300)) * 100, 5, 85)}%` }}
                    >
                      {tooltipInfo.text}
                    </div>
                  ) : null}
                </div>
              </DialogSectionCard>
            )}

            <DialogFooterActions>
              <DialogActionButton tone="secondary" onClick={requestClose}>
                {t('common.cancel', '取消')}
              </DialogActionButton>
              <DialogActionButton tone="primary" onClick={handleGenerate} disabled={totalMessages === 0}>
                {t('titleSummary.generate', '生成标题')}
              </DialogActionButton>
            </DialogFooterActions>
          </>
        ) : phase === 'pending' ? (
          <DialogSectionCard
            title={t('titleSummary.generating', '正在生成摘要标题…')}
            accent={DIALOG_ACCENT.warning}
            icon={<span class="oh-spin"><DialogGlyph name="spark" /></span>}
          >
            <DialogFooterActions>
              <DialogActionButton tone="secondary" onClick={handleCancelGenerate}>
                {t('common.cancel', '取消')}
              </DialogActionButton>
            </DialogFooterActions>
          </DialogSectionCard>
        ) : phase === 'success' ? (
          <DialogSectionCard
            title={t('titleSummary.success', '标题生成成功')}
            accent={DIALOG_ACCENT.success}
            icon={<DialogGlyph name="check" />}
          >
            <DialogTintedPanel accent={DIALOG_ACCENT.success}>
              <p class="text-base font-semibold text-center" style={{ color: DIALOG_ACCENT.success }}>
                {generatedTitle}
              </p>
            </DialogTintedPanel>
            <DialogFooterActions variant={DIALOG_FOOTER_VARIANT.padded}>
              <DialogActionButton tone="primary" onClick={requestClose}>
                {t('common.close', '关闭')}
              </DialogActionButton>
            </DialogFooterActions>
          </DialogSectionCard>
        ) : (
          <DialogSectionCard
            title={
              errorMode === 'load'
                ? t('titleSummary.loadFailed', '线程消息读取失败')
                : t('titleSummary.failed', '标题生成失败')
            }
            subtitle={errorMessage}
            accent={DIALOG_ACCENT.error}
            icon={<DialogGlyph name="alert" />}
          >
            <DialogFooterActions>
              <DialogActionButton tone="secondary" onClick={requestClose}>
                {t('common.close', '关闭')}
              </DialogActionButton>
              <DialogActionButton
                tone="primary"
                onClick={() => {
                  if (errorMode === 'load') {
                    void startLoadingMessages();
                  } else {
                    setPhase('config');
                  }
                }}
              >
                {t('common.retry', '重试')}
              </DialogActionButton>
            </DialogFooterActions>
          </DialogSectionCard>
        )}
      </div>
      {modelPickerOpen ? (
        <ModelPickerDialog
          models={models}
          selectedKey={modelKey}
          onSelect={(key) => {
            setModelKey(key);
          }}
          onClose={() => setModelPickerOpen(false)}
        />
      ) : null}
    </DialogFrame>
  );
}
