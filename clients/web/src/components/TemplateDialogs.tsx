// 会话模板选择 / 配置弹窗组合，对齐 OpenHand APP 端"先选模板 → 再填参数 → 创建"流程。
//
// 设计要点：
// - TemplatePickerDialog：grid 渲染所有 meta.templates；点击某项后回调 `onPick(template)`，
//   不内嵌后续 step，便于上层根据 template.id 决定走 ConfigDialog 还是直接创建。
// - TemplateConfigDialog：通用表单（标题 + mode + 模型）。机器专家/编程专家/Hardness 等
//   带额外参数的模板，受限于服务端契约只接受 {template_id, mode, title?}，先走"通用表单"
//   保持与服务端契约一致；后续服务端开放 extra_params 时再分模板渲染专属表单。
//
// 两个弹窗都使用 portal-less 全屏遮罩 + 中央卡片 + ESC 关闭 + 点击遮罩关闭。

import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import type { ApiMetaModel, ApiMetaTemplate } from '../api/meta';
import { MenuSelect } from './MenuSelect';
import { ModelPickerDialog, pushRecentModel } from './ModelPickerDialog';
import { Appear } from './Appear';
import { t } from '../i18n';

interface DialogShellProps {
  title: string;
  onClose: () => void;
  children: ComponentChildren;
  maxWidth?: number;
}

function DialogShell({ title, onClose, children, maxWidth = 880 }: DialogShellProps) {
  // ESC 关闭：在 dialog 挂载时挂全局键监听，卸载时清理。
  useEffect(() => {
    const handler = (ev: KeyboardEvent) => {
      if (ev.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);
  return (
    <div
      class="fixed inset-0 z-50 flex items-center justify-center px-4 oh-dialog-fade-in"
      style={{
        background: 'rgba(0,0,0,0.40)',
        backdropFilter: 'blur(2px)',
      }}
      onClick={(ev) => {
        if (ev.target === ev.currentTarget) onClose();
      }}
      role="dialog"
      aria-modal="true"
      aria-label={title}
    >
      <section
        class="oh-dialog-pop-in rounded-m3-xl w-full overflow-hidden flex flex-col"
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          maxWidth: `${maxWidth}px`,
          maxHeight: '88vh',
        }}
      >
        <header
          class="px-6 py-4 flex items-center justify-between gap-4"
          style={{ borderBottom: '1px solid var(--m3-outline)' }}
        >
          <h2 class="text-lg font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
            {title}
          </h2>
          <button
            type="button"
            onClick={onClose}
            class="oh-tap-press text-sm px-2 py-1 rounded-m3-sm"
            style={{ color: 'var(--m3-on-surface-variant)' }}
            aria-label="close"
          >
            ✕
          </button>
        </header>
        <div class="px-6 py-5 overflow-auto" style={{ flex: 1 }}>
          {children}
        </div>
      </section>
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
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {templates.map((tpl, idx) => (
            <Appear key={tpl.id} variant="up" index={idx + 1}>
              <button
                type="button"
                onClick={() => onPick(tpl)}
                class="oh-tap-press w-full text-left rounded-m3-md p-4 flex flex-col gap-2 h-full transition-all"
                style={{
                  background: 'var(--m3-surface)',
                  border: '1px solid var(--m3-outline)',
                  minHeight: '160px',
                }}
              >
                <div
                  class="w-10 h-10 rounded-m3-sm flex items-center justify-center text-lg"
                  style={{
                    background: 'var(--m3-primary)',
                    color: 'var(--m3-on-primary)',
                  }}
                  aria-hidden
                >
                  {tpl.icon ?? '✦'}
                </div>
                <h3 class="text-base font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
                  {tpl.name}
                </h3>
                {tpl.description ? (
                  <p
                    class="text-xs leading-snug"
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
  allowedModes: string[];
  planEnabled: boolean;
  busy: boolean;
  error: string | null;
  onSubmit: (params: { mode: 'chat' | 'plan'; title: string; modelKey: string }) => void;
  onClose: () => void;
}

export function TemplateConfigDialog(props: TemplateConfigDialogProps) {
  const { template, models, planEnabled, busy, error, onSubmit, onClose } = props;
  const [title, setTitle] = useState<string>('');
  const [mode, setMode] = useState<'chat' | 'plan'>('chat');
  const [modelKey, setModelKey] = useState<string>(models[0]?.key ?? '');
  const [modelPickerOpen, setModelPickerOpen] = useState(false);
  const titleRef = useRef<HTMLInputElement | null>(null);
  const selectedModel = models.find((model) => model.key === modelKey);

  // 自动 focus 到标题输入框，键盘流畅创建。
  useEffect(() => {
    titleRef.current?.focus();
  }, []);

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
              onChange={(v) => setMode(v as 'chat' | 'plan')}
              disabled={busy}
              minWidth={140}
              options={[
                { value: 'chat', label: t('sessions.mode.chat', '对话') },
                ...(planEnabled
                  ? [{ value: 'plan', label: t('sessions.mode.plan', 'Plan') }]
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
