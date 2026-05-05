// 单会话页专用 TopBar (1:1 对齐 OpenHand App 端 home page 顶部条):
// - 标题区: 返回按钮 + 可点击重命名的标题 + 模板/计数副标题
// - 工具区:
//     模式 chip (普通/Plan/图像/视频/音频)
//     模型 chip (点击弹出 ModelPickerDialog)
//     权限 chip (默认 ask, App 端 normal/auto/ask 等)
//     停止按钮 (sendPhase != idle 时高亮)
//     More 菜单 (重命名 / 删除 / 导出 / 复制 ID)
// - 实时通道 badge (实时/轮询) 已在状态条; 此处不重复

import { useEffect, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import type { ApiMetaModel } from '../api/meta';
import { t } from '../i18n';
import { ModelPickerDialog } from './ModelPickerDialog';

export interface SessionToolbarCapsule {
  key: string;
  icon: string;
  label: string;
  title?: string;
  tone?: 'neutral' | 'primary' | 'warning' | 'success';
  onClick?: () => void;
}

export interface SessionTopBarProps {
  title: string;
  subtitle?: string;
  onBack?: () => void;
  // 标题点击 → 进入重命名;
  onRename?: (next: string) => Promise<void> | void;

  // 模式
  modes: string[]; // ['normal','plan','image','video','audio']
  mode: string;
  onModeChange(next: string): void;

  // 模型
  models: ApiMetaModel[];
  modelKey: string;
  onModelChange(next: string): void;

  // App 端 fullAccessPermission：默认权限 / 完全访问权限。
  fullAccessPermission: boolean;
  onFullAccessPermissionChange(next: boolean): void;

  // 状态
  sendPhase: string;
  canStop: boolean;
  stopping: boolean;
  onStop?: () => void;

  // 操作
  onDelete?: () => void;
  onExport?: () => void;
  sessionId?: string;
  capsules?: SessionToolbarCapsule[];

  trailing?: ComponentChildren;
}

function modeLabel(m: string): string {
  switch (m) {
    case 'chat': return t('sessions.mode.chat', '对话');
    case 'normal': return t('composer.mode.normal', '普通');
    case 'plan': return t('composer.mode.plan', 'Plan');
    case 'image': return t('composer.mode.image', '图像');
    case 'video': return t('composer.mode.video', '视频');
    case 'audio': return t('composer.mode.audio', '音频');
    default: return m;
  }
}

function modeIcon(m: string): string {
  switch (m) {
    case 'chat': return '💬';
    case 'normal': return '💬';
    case 'plan': return '📋';
    case 'image': return '🖼';
    case 'video': return '🎬';
    case 'audio': return '🎙';
    default: return '·';
  }
}

function permissionLabel(fullAccess: boolean): string {
  return fullAccess
    ? t('topbar.perm.full', '完全访问权限')
    : t('topbar.perm.default', '默认权限');
}

function permissionIcon(fullAccess: boolean): string {
  return fullAccess ? '⚠' : '🛡';
}

export function SessionTopBar(props: SessionTopBarProps) {
  const {
    title,
    subtitle,
    onBack,
    onRename,
    modes,
    mode,
    onModeChange,
    models,
    modelKey,
    onModelChange,
    fullAccessPermission,
    onFullAccessPermissionChange,
    sendPhase,
    canStop,
    stopping,
    onStop,
    onDelete,
    onExport,
    sessionId,
    capsules = [],
    trailing,
  } = props;

  const [editing, setEditing] = useState(false);
  const [draftTitle, setDraftTitle] = useState(title);
  const titleInputRef = useRef<HTMLInputElement | null>(null);
  const [showModelPicker, setShowModelPicker] = useState(false);
  const [showModeMenu, setShowModeMenu] = useState(false);
  const [showPermMenu, setShowPermMenu] = useState(false);
  const [showMore, setShowMore] = useState(false);

  useEffect(() => {
    if (!editing) setDraftTitle(title);
  }, [title, editing]);

  useEffect(() => {
    if (editing) titleInputRef.current?.focus();
  }, [editing]);

  // 任意菜单打开时, 点击外部关闭
  useEffect(() => {
    if (!showModeMenu && !showPermMenu && !showMore) return;
    function close(e: MouseEvent) {
      const t = e.target as HTMLElement;
      if (!t.closest('[data-topbar-menu]')) {
        setShowModeMenu(false);
        setShowPermMenu(false);
        setShowMore(false);
      }
    }
    window.addEventListener('mousedown', close);
    return () => window.removeEventListener('mousedown', close);
  }, [showModeMenu, showPermMenu, showMore]);

  function commitRename() {
    setEditing(false);
    const next = draftTitle.trim();
    if (next && next !== title && onRename) {
      void onRename(next);
    } else {
      setDraftTitle(title);
    }
  }

  const isRunning = sendPhase !== 'idle' && sendPhase !== '';

  const selectedModel = models.find((m) => m.key === modelKey);
  const modelLabel = selectedModel
    ? `${selectedModel.label || selectedModel.key}`
    : t('composer.model', '模型');

  return (
    <header
      class="rounded-xl px-3 py-2 flex items-center gap-2 flex-wrap"
      style={{
        background: 'var(--m3-surface-container)',
        boxShadow: 'var(--m3-elev-1)',
      }}
    >
      {onBack ? (
        <button
          type="button"
          onClick={onBack}
          class="oh-tap-press text-xs px-2 py-1 rounded-m3-sm flex-none"
          style={{
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
          }}
          title={t('detail.backToList', '返回会话列表')}
        >
          ←
        </button>
      ) : null}

      <div class="flex-1 min-w-0">
        {editing ? (
          <input
            ref={titleInputRef}
            value={draftTitle}
            onInput={(e) => setDraftTitle((e.currentTarget as HTMLInputElement).value)}
            onBlur={commitRename}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commitRename();
              if (e.key === 'Escape') {
                setEditing(false);
                setDraftTitle(title);
              }
            }}
            class="w-full text-sm font-semibold px-2 py-1 rounded-md"
            style={{
              background: 'var(--m3-surface)',
              color: 'var(--m3-on-surface)',
              border: '1px solid var(--m3-primary)',
            }}
          />
        ) : (
          <button
            type="button"
            onClick={() => onRename && setEditing(true)}
            class="block w-full text-left truncate"
            disabled={!onRename}
            title={onRename ? t('topbar.renameHint', '点击重命名') : undefined}
          >
            <span
              class="text-sm font-semibold"
              style={{ color: 'var(--m3-on-surface)' }}
            >
              {title}
            </span>
          </button>
        )}
        {capsules.length > 0 ? (
          <div class="mt-1 flex items-center gap-1.5 overflow-x-auto pb-0.5">
            {capsules.map((item) => (
              <ToolbarCapsule key={item.key} capsule={item} />
            ))}
          </div>
        ) : subtitle ? (
          <p
            class="text-xs truncate"
            style={{ color: 'var(--m3-on-surface-variant)' }}
          >
            {subtitle}
          </p>
        ) : null}
      </div>

      {/* Mode chip */}
      <div class="relative" data-topbar-menu>
        <Chip
          icon={modeIcon(mode)}
          label={modeLabel(mode)}
          tone="primary"
          onClick={() => {
            setShowModeMenu((v) => !v);
            setShowPermMenu(false);
            setShowMore(false);
          }}
          disabled={isRunning}
          title={t('topbar.mode.title', '会话模式')}
        />
        {showModeMenu ? (
          <Menu>
            {modes.map((m) => (
              <MenuItem
                key={m}
                active={m === mode}
                onClick={() => {
                  onModeChange(m);
                  setShowModeMenu(false);
                }}
              >
                <span class="mr-2" aria-hidden>{modeIcon(m)}</span>
                {modeLabel(m)}
              </MenuItem>
            ))}
          </Menu>
        ) : null}
      </div>

      {/* Model chip */}
      <Chip
        icon="✦"
        label={modelLabel}
        tone="neutral"
        onClick={() => setShowModelPicker(true)}
        disabled={isRunning || models.length === 0}
        title={t('topbar.model.title', '点击选择模型')}
      />

      {/* Permission chip */}
      <div class="relative" data-topbar-menu>
        <Chip
          icon={permissionIcon(fullAccessPermission)}
          label={permissionLabel(fullAccessPermission)}
          tone="neutral"
          onClick={() => {
            setShowPermMenu((v) => !v);
            setShowModeMenu(false);
            setShowMore(false);
          }}
          title={t('topbar.perm.title', '权限模式')}
        />
        {showPermMenu ? (
          <Menu>
            {[false, true].map((value) => (
              <MenuItem
                key={value ? 'full' : 'default'}
                active={value === fullAccessPermission}
                onClick={() => {
                  onFullAccessPermissionChange(value);
                  setShowPermMenu(false);
                }}
              >
                <span class="mr-2" aria-hidden>{permissionIcon(value)}</span>
                {permissionLabel(value)}
              </MenuItem>
            ))}
          </Menu>
        ) : null}
      </div>

      {isRunning && canStop && onStop ? (
        <button
          type="button"
          onClick={onStop}
          disabled={stopping}
          class="oh-tap-press text-xs px-2.5 py-1 rounded-m3-sm flex-none flex items-center gap-1.5 disabled:opacity-50"
          style={{
            border: '1px solid var(--m3-error)',
            color: 'var(--m3-error)',
          }}
          title={t('composer.stop', '停止响应')}
        >
          <span
            class="oh-pulse-soft inline-block"
            aria-hidden
            style={{
              width: 6,
              height: 6,
              borderRadius: '50%',
              background: 'var(--m3-error)',
            }}
          />
          {stopping ? t('composer.stopping', '正在停止…') : t('composer.stop', '停止')}
        </button>
      ) : null}

      <div class="relative" data-topbar-menu>
        <button
          type="button"
          onClick={() => {
            setShowMore((v) => !v);
            setShowModeMenu(false);
            setShowPermMenu(false);
          }}
          class="oh-tap-press text-xs px-2 py-1 rounded-m3-sm"
          style={{
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
          }}
          title={t('topbar.more', '更多')}
        >
          ⋯
        </button>
        {showMore ? (
          <Menu>
            {onRename ? (
              <MenuItem onClick={() => { setShowMore(false); setEditing(true); }}>
                ✎ {t('topbar.rename', '重命名')}
              </MenuItem>
            ) : null}
            {onExport ? (
              <MenuItem onClick={() => { setShowMore(false); onExport(); }}>
                ⬇ {t('topbar.export', '导出 JSON')}
              </MenuItem>
            ) : null}
            {sessionId ? (
              <MenuItem
                onClick={async () => {
                  setShowMore(false);
                  try {
                    await navigator.clipboard.writeText(sessionId);
                  } catch {
                    // ignore
                  }
                }}
              >
                ⎘ {t('topbar.copyId', '复制会话 ID')}
              </MenuItem>
            ) : null}
            {onDelete ? (
              <MenuItem
                tone="danger"
                onClick={() => { setShowMore(false); onDelete(); }}
              >
                🗑 {t('topbar.delete', '删除会话')}
              </MenuItem>
            ) : null}
          </Menu>
        ) : null}
      </div>

      {trailing}

      {showModelPicker ? (
        <ModelPickerDialog
          models={models}
          selectedKey={modelKey}
          onSelect={(k) => onModelChange(k)}
          onClose={() => setShowModelPicker(false)}
        />
      ) : null}
    </header>
  );
}

function ToolbarCapsule({ capsule }: { capsule: SessionToolbarCapsule }) {
  const toneColor = capsule.tone === 'primary'
    ? 'var(--m3-primary)'
    : capsule.tone === 'warning'
      ? '#b45309'
      : capsule.tone === 'success'
        ? '#15803d'
        : 'var(--m3-on-surface-variant)';
  const content = (
    <span
      class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] flex-none max-w-[240px]"
      style={{
        background: 'var(--m3-surface)',
        color: toneColor,
        border: `1px solid color-mix(in srgb, ${toneColor} 28%, transparent)`,
        fontWeight: 600,
      }}
      title={capsule.title ?? capsule.label}
    >
      <span aria-hidden>{capsule.icon}</span>
      <span class="truncate">{capsule.label}</span>
    </span>
  );
  if (!capsule.onClick) return content;
  return (
    <button
      type="button"
      class="oh-tap-press flex-none"
      style={{ background: 'transparent', border: 'none', padding: 0 }}
      onClick={capsule.onClick}
      title={capsule.title ?? capsule.label}
    >
      {content}
    </button>
  );
}

function Chip({
  icon,
  label,
  tone,
  onClick,
  disabled,
  title,
}: {
  icon: string;
  label: string;
  tone: 'primary' | 'neutral';
  onClick: () => void;
  disabled?: boolean;
  title?: string;
}) {
  const isPrimary = tone === 'primary';
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={title}
      class="oh-tap-press text-xs px-2.5 py-1 rounded-m3-sm flex items-center gap-1.5 disabled:opacity-50 disabled:cursor-not-allowed flex-none"
      style={{
        background: isPrimary
          ? 'color-mix(in srgb, var(--m3-primary) 12%, transparent)'
          : 'transparent',
        color: isPrimary ? 'var(--m3-primary)' : 'var(--m3-on-surface)',
        border: `1px solid ${isPrimary
          ? 'color-mix(in srgb, var(--m3-primary) 35%, transparent)'
          : 'var(--m3-outline)'}`,
        maxWidth: '220px',
      }}
    >
      <span aria-hidden>{icon}</span>
      <span class="truncate">{label}</span>
    </button>
  );
}

function Menu({ children }: { children: ComponentChildren }) {
  return (
    <div
      class="absolute right-0 mt-1 z-40 rounded-m3-sm py-1 oh-appear-up"
      style={{
        background: 'var(--m3-surface)',
        boxShadow: 'var(--m3-elev-2)',
        border: '1px solid var(--m3-outline)',
        minWidth: '180px',
      }}
    >
      {children}
    </div>
  );
}

function MenuItem({
  children,
  onClick,
  active,
  tone,
}: {
  children: ComponentChildren;
  onClick: () => void;
  active?: boolean;
  tone?: 'danger';
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      class="w-full text-left text-xs px-3 py-1.5 oh-tap-press flex items-center gap-1"
      style={{
        background: active
          ? 'color-mix(in srgb, var(--m3-primary) 10%, transparent)'
          : 'transparent',
        color: tone === 'danger'
          ? 'var(--m3-error)'
          : active
            ? 'var(--m3-primary)'
            : 'var(--m3-on-surface)',
        fontWeight: active ? 600 : 400,
      }}
    >
      {children}
      {active ? <span class="ml-auto">✓</span> : null}
    </button>
  );
}
