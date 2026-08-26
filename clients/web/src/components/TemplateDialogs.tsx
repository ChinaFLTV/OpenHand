import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import type { ApiMetaModel, ApiMetaTemplate } from '../api/meta';
import {
  isGoalModeAllowedForTemplate,
  SESSION_TITLE_MAX_CHARACTERS,
  type SessionMode,
  type SessionSummary,
} from '../api/sessions';
import { MenuSelect } from './MenuSelect';
import { ModelPickerDialog } from './ModelPickerDialog';
import { Appear } from './Appear';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import {
  DIALOG_OVERLAY_CENTER_COMPACT_CLASS,
  DIALOG_OVERLAY_LOW_Z_INDEX,
  DialogActionButton,
  DialogFrame,
  DialogHeader,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

interface DialogShellProps {
  title: string;
  onClose: () => void;
  children: (
    requestClose: (afterClose?: () => void) => void,
  ) => ComponentChildren;
  maxWidth?: number;
  closeDisabled?: boolean;
}

function DialogShell({
  title,
  onClose,
  children,
  maxWidth = 880,
  closeDisabled = false,
}: DialogShellProps) {
  const closeActionRef = useRef<(() => void) | null>(null);
  const closeRequestedRef = useRef(false);
  const closedRef = useRef(false);
  const { closing, requestClose } = useDialogExitMotion(
    () => {
      closedRef.current = true;
      const closeAction = closeActionRef.current;
      closeActionRef.current = null;
      (closeAction ?? onClose)();
    },
    {
      onBeforeClose: () => {
        closeRequestedRef.current = true;
      },
    },
  );
  const requestShellClose = (afterClose?: () => void) => {
    if (closeRequestedRef.current) {
      if (afterClose) {
        if (closedRef.current) afterClose();
        else closeActionRef.current = afterClose;
      }
      return;
    }
    if (closeDisabled) return;
    closeRequestedRef.current = true;
    closeActionRef.current = afterClose ?? null;
    requestClose();
  };

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestShellClose}
      closeOnBackdrop={!closeDisabled && !closing}
      {...createStandardDialogFrameAppearance({
        overlayClassName: DIALOG_OVERLAY_CENTER_COMPACT_CLASS,
        overlayTone: 'strong',
        overlayZIndex: DIALOG_OVERLAY_LOW_Z_INDEX,
        panelClassName: 'rounded-m3-xl w-full overflow-hidden flex flex-col',
        panelBorder: 'none',
        panelSurface: {
          maxWidth: `${maxWidth}px`,
          maxHeight: '88vh',
        },
      })}
      ariaLabel={title}
    >
      <DialogHeader
        title={title}
        onClose={() => requestShellClose()}
        closeDisabled={closeDisabled || closing}
        closeLabel={t('common.close', '关闭')}
        titleClassName="text-lg font-semibold"
        borderColor="var(--m3-outline)"
      />
      <div class="px-6 py-5 overflow-auto" style={{ flex: 1 }}>
        {children(requestShellClose)}
      </div>
    </DialogFrame>
  );
}

function templateIconGlyph(template: ApiMetaTemplate): string {
  const raw = `${template.icon ?? ''} ${template.id} ${template.name}`.toLowerCase();
  if (template.icon && /^[A-Za-z0-9]{1,3}$/.test(template.icon)) {
    return template.icon;
  }
  if (raw.includes('program') || raw.includes('code')) return '</>';
  if (raw.includes('harness') || raw.includes('engineering')) return 'ENG';
  if (
    raw.includes('web_reverse') ||
    raw.includes('web reverse') ||
    raw.includes('web 逆向')
  ) return 'WEB';
  if (raw.includes('android')) return 'AND';
  if (raw.includes('machine') || raw.includes('机器') || raw.includes('機器')) return 'OPS';
  if (raw.includes('hermes') || raw.includes('talk')) return 'MSG';
  if (raw.includes('default') || raw.includes('chat')) return 'AI';
  return 'AI';
}

function templateVersionLabel(template: ApiMetaTemplate): string {
  const version = template.internal_version?.trim();
  return version ? `v${version}` : '';
}

function TemplateIcon({ template }: { template: ApiMetaTemplate }) {
  const glyph = templateIconGlyph(template);
  return (
    <div
      class="w-10 h-10 rounded-m3-sm flex items-center justify-center overflow-hidden text-center"
      style={{
        background: 'var(--m3-primary)',
        color: 'var(--m3-on-primary)',
        fontSize: glyph === '</>' ? '15px' : '18px',
        fontWeight: 700,
        lineHeight: 1,
        letterSpacing: 0,
      }}
      aria-hidden
      title={template.icon ?? template.name}
    >
      {glyph}
    </div>
  );
}

interface TemplatePickerDialogProps {
  templates: ApiMetaTemplate[];
  onPick: (template: ApiMetaTemplate) => void;
  onClose: () => void;
}

export function TemplatePickerDialog({ templates, onPick, onClose }: TemplatePickerDialogProps) {
  return (
    <DialogShell title={t('sessions.templatePicker.title', '选择线程模板')} onClose={onClose}>
      {(requestClose) => (
        <>
          <p class="text-sm mb-4 oh-text-muted">
            {t('sessions.templatePicker.subtitle', '新建线程前，请先从下方内置能力模板中选择一个。')}
          </p>
          {templates.length === 0 ? (
            <p class="text-center py-12 text-sm oh-text-muted">
              {t('sessions.templatePicker.empty', '主控制台尚未导出任何模板。')}
            </p>
          ) : (
            <div class="oh-template-picker-grid grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              {templates.map((tpl, idx) => {
                const versionLabel = templateVersionLabel(tpl);
                return (
                  <Appear key={tpl.id} variant="up" index={idx + 1}>
                    <button
                      type="button"
                      onClick={() => requestClose(() => onPick(tpl))}
                      class="oh-tap-press oh-template-picker-card w-full text-left rounded-m3-md p-4 flex flex-col gap-2 h-full transition-all"
                      style={{
                        background: 'var(--m3-surface)',
                        border: '1px solid var(--m3-outline)',
                        minHeight: '160px',
                      }}
                    >
                      <div class="flex items-start justify-between gap-3">
                        <TemplateIcon template={tpl} />
                        {versionLabel ? (
                          <span
                            class="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold"
                            style={{
                              color: 'var(--m3-on-primary-container)',
                              background: 'var(--m3-primary-container)',
                              fontVariantNumeric: 'tabular-nums',
                            }}
                          >
                            {versionLabel}
                          </span>
                        ) : null}
                      </div>
                      <h3 class="text-base font-semibold oh-text-body">
                        {tpl.name}
                      </h3>
                      {tpl.description ? (
                        <p class="oh-template-picker-card-description text-xs leading-snug oh-text-muted">
                          {tpl.description}
                        </p>
                      ) : null}
                    </button>
                  </Appear>
                );
              })}
            </div>
          )}
        </>
      )}
    </DialogShell>
  );
}

interface TemplateConfigDialogProps {
  template: ApiMetaTemplate;
  models: ApiMetaModel[];
  defaultModelKey?: string;
  planEnabled: boolean;
  busy: boolean;
  error: string | null;
  onSubmit: (params: {
    mode: SessionMode;
    title: string;
    modelKey: string;
  }) => Promise<SessionSummary | null>;
  onCreated: (session: SessionSummary) => void;
  onClose: () => void;
}

export function TemplateConfigDialog(props: TemplateConfigDialogProps) {
  const {
    template,
    models,
    defaultModelKey,
    planEnabled,
    busy,
    error,
    onSubmit,
    onCreated,
    onClose,
  } = props;
  const goalModeAvailable = isGoalModeAllowedForTemplate(template.id);
  const [title, setTitle] = useState<string>('');
  const [mode, setMode] = useState<SessionMode>('chat');
  const [modelKey, setModelKey] = useState<string>(() => resolveDefaultModelKey(models, defaultModelKey));
  const [modelPickerOpen, setModelPickerOpen] = useState(false);
  const titleRef = useRef<HTMLInputElement | null>(null);
  const submitInFlightRef = useRef(false);
  const selectedModel = models.find((model) => model.key === modelKey);

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  useEffect(() => {
    setModelKey((current) => {
      if (current && models.some((model) => model.key === current)) return current;
      return resolveDefaultModelKey(models, defaultModelKey);
    });
  }, [models, defaultModelKey]);

  const submit = async (
    requestClose: (afterClose?: () => void) => void,
    ev?: Event,
  ) => {
    if (ev) ev.preventDefault();
    if (busy || submitInFlightRef.current) return;
    submitInFlightRef.current = true;
    try {
      const session = await onSubmit({
        mode,
        title: title.trim(),
        modelKey,
      });
      if (session != null) {
        requestClose(() => onCreated(session));
      }
    } finally {
      submitInFlightRef.current = false;
    }
  };

  return (
    <DialogShell
      title={t('sessions.templateConfig.title', '模板参数配置').replace(
        '{template}',
        template.name,
      )}
      onClose={onClose}
      maxWidth={620}
      closeDisabled={busy}
    >
      {(requestClose) => (
        <>
          <p class="text-sm mb-4 oh-text-muted">
            {template.description ??
              t('sessions.templateConfig.subtitle', '为新会话指定标题、对话模式与默认模型。')}
          </p>
          <form
            onSubmit={(event) => void submit(requestClose, event)}
            class="flex flex-col gap-4"
          >
            <label class="flex flex-col text-xs gap-1 oh-text-muted">
              {t('sessions.templateConfig.titleField', '会话标题（可选）')}
              <input
                ref={titleRef}
                type="text"
                maxLength={SESSION_TITLE_MAX_CHARACTERS}
                value={title}
                onInput={(e) => setTitle((e.currentTarget as HTMLInputElement).value)}
                disabled={busy}
                placeholder={t('sessions.templateConfig.titlePlaceholder', '例如：紧急生产事故排查')}
                class="px-3 py-2 rounded-m3-sm text-sm"
                style={{
                  background: 'var(--m3-surface)',
                  color: 'var(--m3-on-surface)',
                  border: '1px solid var(--m3-outline)',
                }}
              />
            </label>

            <div class="flex flex-wrap gap-3">
              <label class="flex flex-col text-xs gap-1 flex-1 min-w-[160px] oh-text-muted">
                {t('sessions.create.mode', '模式')}
                <MenuSelect
                  value={mode}
                  onChange={(v) => setMode(v as SessionMode)}
                  disabled={busy}
                  minWidth={140}
                  options={[
                    { value: 'chat', label: t('sessions.mode.chat', '聊天模式') },
                    ...(planEnabled
                      ? [{ value: 'plan', label: t('sessions.mode.plan', '计划模式') }]
                      : []),
                    ...(goalModeAvailable
                      ? [{ value: 'goal', label: t('sessions.mode.goal', '目标模式') }]
                      : []),
                  ]}
                />
              </label>
              <label class="flex flex-col text-xs gap-1 flex-1 min-w-[220px] oh-text-muted">
                {t('composer.model', '模型')}
                <button
                  type="button"
                  onClick={() => setModelPickerOpen(true)}
                  disabled={busy || models.length === 0}
                  class="oh-tap-press text-left px-3 py-2 rounded-m3-sm text-sm disabled:opacity-60"
                  style={{
                    background: 'var(--m3-surface)',
                    color: selectedModel ? 'var(--m3-on-surface)' : 'var(--m3-on-surface-variant)',
                    border: '1px solid var(--m3-outline)',
                  }}
                >
                  {selectedModel?.model_id || t('sessions.templateConfig.modelDefault', '使用模板默认模型')}
                </button>
              </label>
            </div>

            {error ? (
              <p class="text-xs oh-text-error">
                {error}
              </p>
            ) : null}

            <div class="flex items-center justify-end gap-2 pt-2">
              <DialogActionButton
                onClick={() => requestClose()}
                disabled={busy}
                className="oh-tap-press text-sm px-4 py-2 rounded-m3-sm"
              >
                {t('common.cancel', '取消')}
              </DialogActionButton>
              <DialogActionButton
                type="submit"
                tone="primary"
                disabled={busy}
                className="oh-tap-press text-sm font-medium px-4 py-2 rounded-m3-sm disabled:opacity-60"
              >
                {busy
                  ? t('sessions.create.submitting', '正在创建…')
                  : t('sessions.templateConfig.submit', '开始会话')}
              </DialogActionButton>
            </div>
          </form>
          {modelPickerOpen ? (
            <ModelPickerDialog
              models={models}
              selectedKey={modelKey}
              onSelect={setModelKey}
              onClose={() => setModelPickerOpen(false)}
            />
          ) : null}
        </>
      )}
    </DialogShell>
  );
}

function resolveDefaultModelKey(models: ApiMetaModel[], defaultModelKey?: string): string {
  const key = (defaultModelKey ?? '').trim();
  if (key && models.some((model) => model.key === key)) return key;
  return models[0]?.key ?? '';
}
