import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import type { ApiMetaModel, ApiMetaTemplate } from '../api/meta';
import { isGoalModeAllowedForTemplate, type SessionMode } from '../api/sessions';
import { MenuSelect } from './MenuSelect';
import { ModelPickerDialog, pushRecentModel } from './ModelPickerDialog';
import { Appear } from './Appear';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import {
  DIALOG_OVERLAY_CENTER_COMPACT_CLASS,
  DIALOG_OVERLAY_LOW_Z_INDEX,
  DialogFrame,
  DialogHeader,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

interface DialogShellProps {
  title: string;
  onClose: () => void;
  children: ComponentChildren;
  maxWidth?: number;
}

function DialogShell({ title, onClose, children, maxWidth = 880 }: DialogShellProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
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
        onClose={requestClose}
        closeLabel={t('common.close', '关闭')}
        titleClassName="text-lg font-semibold"
        borderColor="var(--m3-outline)"
      />
      <div class="px-6 py-5 overflow-auto" style={{ flex: 1 }}>
        {children}
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
  if (raw.includes('machine') || raw.includes('expert')) return 'OPS';
  if (raw.includes('harness') || raw.includes('engineering')) return 'ENG';
  if (raw.includes('hermes') || raw.includes('talk')) return 'MSG';
  if (raw.includes('default') || raw.includes('chat')) return 'AI';
  return 'AI';
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

export interface TemplatePickerDialogProps {
  templates: ApiMetaTemplate[];
  onPick: (template: ApiMetaTemplate) => void;
  onClose: () => void;
}

export function TemplatePickerDialog({ templates, onPick, onClose }: TemplatePickerDialogProps) {
  return (
    <DialogShell title={t('sessions.templatePicker.title', '选择线程模板')} onClose={onClose}>
      <p class="text-sm mb-4" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {t('sessions.templatePicker.subtitle', '新建线程前，请先从下方内置能力模板中选择一个。')}
      </p>
      {templates.length === 0 ? (
        <p
          class="text-center py-12 text-sm"
          style={{ color: 'var(--m3-on-surface-variant)' }}
        >
          {t('sessions.templatePicker.empty', '主控制台尚未导出任何模板。')}
        </p>
      ) : (
        <div class="oh-template-picker-grid grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {templates.map((tpl, idx) => (
            <Appear key={tpl.id} variant="up" index={idx + 1}>
              <button
                type="button"
                onClick={() => onPick(tpl)}
                class="oh-tap-press oh-template-picker-card w-full text-left rounded-m3-md p-4 flex flex-col gap-2 h-full transition-all"
                style={{
                  background: 'var(--m3-surface)',
                  border: '1px solid var(--m3-outline)',
                  minHeight: '160px',
                }}
              >
                <TemplateIcon template={tpl} />
                <h3 class="text-base font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
                  {tpl.name}
                </h3>
                {tpl.description ? (
                  <p
                    class="oh-template-picker-card-description text-xs leading-snug"
                    style={{ color: 'var(--m3-on-surface-variant)' }}
                  >
                    {tpl.description}
                  </p>
                ) : null}
              </button>
            </Appear>
          ))}
        </div>
      )}
    </DialogShell>
  );
}

export interface TemplateConfigDialogProps {
  template: ApiMetaTemplate;
  models: ApiMetaModel[];
  defaultModelKey?: string;
  allowedModes: string[];
  planEnabled: boolean;
  busy: boolean;
  error: string | null;
  onSubmit: (params: { mode: SessionMode; title: string; modelKey: string }) => void;
  onClose: () => void;
}

export function TemplateConfigDialog(props: TemplateConfigDialogProps) {
  const { template, models, defaultModelKey, planEnabled, busy, error, onSubmit, onClose } = props;
  const [title, setTitle] = useState<string>('');
  const [mode, setMode] = useState<SessionMode>('chat');
  const [modelKey, setModelKey] = useState<string>(() => resolveDefaultModelKey(models, defaultModelKey));
  const [modelPickerOpen, setModelPickerOpen] = useState(false);
  const titleRef = useRef<HTMLInputElement | null>(null);
  const selectedModel = models.find((model) => model.key === modelKey);
  const goalModeAvailable = isGoalModeAllowedForTemplate(template.id);

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  useEffect(() => {
    setModelKey((current) => {
      if (current && models.some((model) => model.key === current)) return current;
      return resolveDefaultModelKey(models, defaultModelKey);
    });
  }, [models, defaultModelKey]);

  const submit = (ev?: Event) => {
    if (ev) ev.preventDefault();
    if (busy) return;
    onSubmit({ mode, title: title.trim(), modelKey });
  };

  return (
    <DialogShell
      title={t('sessions.templateConfig.title', '模板参数配置').replace(
        '{template}',
        template.name,
      )}
      onClose={onClose}
      maxWidth={620}
    >
      <p class="text-sm mb-4" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {template.description ??
          t('sessions.templateConfig.subtitle', '为新会话指定标题、对话模式与默认模型。')}
      </p>
      <form onSubmit={submit} class="flex flex-col gap-4">
        <label class="flex flex-col text-xs gap-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
          {t('sessions.templateConfig.titleField', '会话标题（可选）')}
          <input
            ref={titleRef}
            type="text"
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
          <label class="flex flex-col text-xs gap-1 flex-1 min-w-[160px]" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
          <label class="flex flex-col text-xs gap-1 flex-1 min-w-[220px]" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
          <p class="text-xs" style={{ color: 'var(--m3-error)' }}>
            {error}
          </p>
        ) : null}

        <div class="flex items-center justify-end gap-2 pt-2">
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            class="oh-tap-press text-sm px-4 py-2 rounded-m3-sm"
            style={{
              border: '1px solid var(--m3-outline)',
              color: 'var(--m3-on-surface)',
            }}
          >
            {t('common.cancel', '取消')}
          </button>
          <button
            type="submit"
            disabled={busy}
            class="oh-tap-press text-sm font-medium px-4 py-2 rounded-m3-sm disabled:opacity-60"
            style={{
              background: 'var(--m3-primary)',
              color: 'var(--m3-on-primary)',
            }}
          >
            {busy
              ? t('sessions.create.submitting', '正在创建…')
              : t('sessions.templateConfig.submit', '开始会话')}
          </button>
        </div>
      </form>
      {modelPickerOpen ? (
        <ModelPickerDialog
          models={models}
          selectedKey={modelKey}
          onSelect={(key) => {
            setModelKey(key);
            pushRecentModel(key);
          }}
          onClose={() => setModelPickerOpen(false)}
        />
      ) : null}
    </DialogShell>
  );
}

function resolveDefaultModelKey(models: ApiMetaModel[], defaultModelKey?: string): string {
  const key = (defaultModelKey ?? '').trim();
  if (key && models.some((model) => model.key === key)) return key;
  return models[0]?.key ?? '';
}
