// PlanTimeline —— Plan 模式会话顶部的步骤时间线
//
// 数据来源（与 App 端 _PlanTimelineData 一致的优先级）:
//   1) session.todo_items (已批准、执行中)
//   2) session.pending_plan (按 1./2. 行号 / "-" / "•" 切分)
//
// 状态图:
//   completed     绿色  ✓
//   in_progress   主色  ⟳ + 呼吸动效
//   failed/blocked/cancelled  m3-error  ✕
//   pending       灰    ·
//
// 交互:
//   - awaiting_plan_approval=true 时, 渲染「✓ 批准计划」+「✕ 取消」按钮
//     批准 = 发送一条 normal 消息 "好"（后端 _looksLikePlanApproval 接住）
//   - 折叠/展开 (本地 state, 默认展开)

import { useMemo, useState } from 'preact/hooks';
import { SendMessageInput, SessionSummary, SessionTodoItem, sendMessage } from '../api/sessions';
import { t } from '../i18n';

type StepState = 'completed' | 'in_progress' | 'failed' | 'pending';

interface Step {
  id: string;
  label: string;
  state: StepState;
}

const PLAN_STEP_PREFIX = /^\s*(?:\d+[\.\)、:]?|[-*•·])\s*/;

function parsePendingPlan(raw: string): string[] {
  return raw
    .split(/\r?\n/)
    .map((line) => line.replace(PLAN_STEP_PREFIX, '').trim())
    .filter((line) => line.length > 0);
}

function mapTodoStatus(status: string): StepState {
  const s = status.trim().toLowerCase();
  if (s === 'completed') return 'completed';
  if (s === 'in_progress') return 'in_progress';
  if (s === 'failed' || s === 'blocked' || s === 'cancelled') return 'failed';
  return 'pending';
}

function buildSteps(session: SessionSummary): {
  steps: Step[];
  awaitingApproval: boolean;
} {
  const awaiting = session.awaiting_plan_approval === true;
  const todos: SessionTodoItem[] = session.todo_items ?? [];
  if (todos.length > 0) {
    return {
      awaitingApproval: awaiting,
      steps: todos
        .filter((item) => item.content.trim().length > 0)
        .map((item) => ({
          id: item.id,
          label: item.content.trim(),
          state: mapTodoStatus(item.status),
        })),
    };
  }
  const pending = session.pending_plan ?? '';
  const labels = parsePendingPlan(pending);
  if (labels.length === 0) return { steps: [], awaitingApproval: awaiting };
  return {
    awaitingApproval: awaiting,
    steps: labels.map((label, idx) => ({
      id: `plan-${idx}`,
      label,
      state: awaiting ? 'pending' : idx === 0 ? 'in_progress' : 'pending',
    })),
  };
}

function statusVisual(s: StepState) {
  switch (s) {
    case 'completed':
      return { color: '#16a34a', icon: '✓', bg: 'color-mix(in srgb, #16a34a 12%, transparent)' };
    case 'in_progress':
      return {
        color: 'var(--m3-primary)',
        icon: '⟳',
        bg: 'color-mix(in srgb, var(--m3-primary) 14%, transparent)',
      };
    case 'failed':
      return {
        color: 'var(--m3-error)',
        icon: '✕',
        bg: 'color-mix(in srgb, var(--m3-error) 14%, transparent)',
      };
    case 'pending':
      return {
        color: 'var(--m3-on-surface-variant)',
        icon: '·',
        bg: 'var(--m3-surface)',
      };
  }
}

interface PlanTimelineProps {
  session: SessionSummary;
  modelKey: string;
  onApproved?(): void;
}

export function PlanTimeline({ session, modelKey, onApproved }: PlanTimelineProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { steps, awaitingApproval } = useMemo(() => buildSteps(session), [session]);
  if (session.mode !== 'plan' || steps.length === 0) return null;

  const completedCount = steps.filter((s) => s.state === 'completed').length;
  const total = steps.length;
  const allDone = completedCount === total;

  const handleApprove = async () => {
    if (submitting) return;
    if (!modelKey) {
      setError(t('detail.plan.noModel', '未选择模型'));
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const payload: SendMessageInput = { content: '好', modelKey, mode: 'normal' };
      await sendMessage(session.id, payload);
      onApproved?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <section
      class="oh-appear-up rounded-m3-lg p-3 mb-3"
      style={{
        border: awaitingApproval
          ? '1px solid color-mix(in srgb, #f59e0b 50%, transparent)'
          : '1px solid var(--m3-outline)',
        background: awaitingApproval
          ? 'color-mix(in srgb, #f59e0b 7%, var(--m3-surface))'
          : 'var(--m3-surface-container-low)',
      }}
    >
      <header class="flex items-center gap-2 mb-2">
        <span style={{ fontWeight: 600, color: 'var(--m3-on-surface)' }}>
          {t('detail.plan.title', 'Plan 步骤时间线')}
        </span>
        <span
          class="text-xs px-1.5 py-0.5 rounded-m3-sm"
          style={{
            background: 'var(--m3-surface)',
            color: 'var(--m3-on-surface-variant)',
          }}
        >
          {completedCount} / {total}
        </span>
        {awaitingApproval ? (
          <span
            class="text-xs px-1.5 py-0.5 rounded-m3-sm"
            style={{
              background: 'color-mix(in srgb, #f59e0b 22%, transparent)',
              color: '#b45309',
              fontWeight: 600,
            }}
          >
            {t('detail.plan.awaiting', '⚠ 等待批准')}
          </span>
        ) : allDone ? (
          <span
            class="text-xs px-1.5 py-0.5 rounded-m3-sm"
            style={{
              background: 'color-mix(in srgb, #16a34a 18%, transparent)',
              color: '#15803d',
              fontWeight: 600,
            }}
          >
            {t('detail.plan.completed', '✓ 已完成')}
          </span>
        ) : null}
        <button
          type="button"
          class="text-xs px-2 py-0.5 rounded-m3-sm ml-auto"
          style={{
            background: 'var(--m3-surface)',
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
          }}
          onClick={() => setCollapsed((v) => !v)}
        >
          {collapsed ? t('detail.plan.expand', '展开') : t('detail.plan.collapse', '折叠')}
        </button>
      </header>
      {!collapsed && (
        <ol class="flex flex-col gap-1.5">
          {steps.map((step, idx) => {
            const v = statusVisual(step.state);
            return (
              <li
                key={step.id}
                class="flex items-start gap-2 px-2 py-1.5 rounded-m3-sm"
                style={{ background: v.bg }}
              >
                <span
                  class={
                    'inline-flex items-center justify-center w-6 h-6 rounded-full text-xs flex-shrink-0' +
                    (step.state === 'in_progress' ? ' oh-pulse-soft' : '')
                  }
                  style={{
                    background: v.color,
                    color: 'white',
                    fontWeight: 600,
                  }}
                  aria-hidden
                >
                  {step.state === 'completed' || step.state === 'failed' ? v.icon : idx + 1}
                </span>
                <span
                  class="text-sm leading-relaxed"
                  style={{
                    color: 'var(--m3-on-surface)',
                    textDecoration: step.state === 'completed' ? 'line-through' : 'none',
                    opacity: step.state === 'completed' ? 0.7 : 1,
                  }}
                >
                  {step.label}
                </span>
              </li>
            );
          })}
        </ol>
      )}
      {awaitingApproval && (
        <footer class="flex items-center gap-2 mt-3">
          <button
            type="button"
            disabled={submitting}
            onClick={handleApprove}
            class="px-3 py-1.5 rounded-m3-sm text-sm font-semibold disabled:opacity-60"
            style={{
              background: 'var(--m3-primary)',
              color: 'var(--m3-on-primary)',
            }}
          >
            {submitting
              ? t('detail.plan.approving', '批准中…')
              : t('detail.plan.approve', '✓ 批准计划')}
          </button>
          <span class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {t('detail.plan.approveHint', '或在输入框回复任意文本继续讨论')}
          </span>
          {error && (
            <span class="text-xs ml-auto" style={{ color: 'var(--m3-error)' }}>
              {error}
            </span>
          )}
        </footer>
      )}
    </section>
  );
}
