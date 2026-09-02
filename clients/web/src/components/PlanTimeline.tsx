import { useMemo, useState } from 'preact/hooks';
import { type SendMessageInput, type SessionSummary, type SessionTodoItem, sendMessage } from '../api/sessions';
import { t } from '../i18n';
import { showSnackbar } from './Snackbar';
import { svgIconProps } from '../shared/ui/svg_icon';

type StepState = 'completed' | 'in_progress' | 'failed' | 'pending';

type PlanIconName = 'check' | 'x' | 'running' | 'chevronDown' | 'chevronUp';

function PlanIcon({ name, size = 15 }: { name: PlanIconName; size?: number }) {
  const common = svgIconProps({ size });
  switch (name) {
    case 'check':
      return <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
    case 'x':
      return <svg {...common}><path d="M7 7l10 10M17 7 7 17" /></svg>;
    case 'running':
      return <svg {...common}><path d="M4 12a8 8 0 0 1 13.4-5.9" /><path d="M17 3v4h-4" /><path d="M20 12a8 8 0 0 1-13.4 5.9" /><path d="M7 21v-4h4" /></svg>;
    case 'chevronDown':
      return <svg {...common}><path d="m7 10 5 5 5-5" /></svg>;
    case 'chevronUp':
      return <svg {...common}><path d="m7 14 5-5 5 5" /></svg>;
  }
}

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

function statusVisual(s: StepState): { color: string; icon?: PlanIconName; bg: string } {
  switch (s) {
    case 'completed':
      return { color: 'var(--m3-secondary)', icon: 'check', bg: 'var(--m3-secondary-container)' };
    case 'in_progress':
      return {
        color: 'var(--m3-primary)',
        icon: 'running',
        bg: 'color-mix(in srgb, var(--m3-primary) 14%, transparent)',
      };
    case 'failed':
      return {
        color: 'var(--m3-error)',
        icon: 'x',
        bg: 'color-mix(in srgb, var(--m3-error) 14%, transparent)',
      };
    case 'pending':
      return {
        color: 'var(--m3-on-surface-variant)',
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
      const message = t('detail.plan.noModel', '未选择模型');
      setError(message);
      showSnackbar(message, { tone: 'error' });
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const payload: SendMessageInput = { content: '好', modelKey, mode: 'normal' };
      await sendMessage(session.id, payload);
      onApproved?.();
      showSnackbar(t('detail.plan.approve.ok', '已批准计划'), { tone: 'success' });
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      setError(message);
      showSnackbar(`${t('detail.plan.approve.failed', '批准计划失败')}：${message}`, { tone: 'error' });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <section
      class="oh-plan-timeline oh-appear-up rounded-m3-lg p-3 mb-3"
      style={{
        border: awaitingApproval
          ? '1px solid color-mix(in srgb, var(--m3-tertiary) 50%, transparent)'
          : '1px solid var(--m3-outline)',
        background: awaitingApproval
          ? 'color-mix(in srgb, var(--m3-tertiary-container) 42%, var(--m3-surface))'
          : 'var(--m3-surface-container-low)',
      }}
    >
      <header class="oh-plan-timeline-header flex items-center gap-2 mb-2">
        <span class="oh-plan-timeline-title" style={{ fontWeight: 600, color: 'var(--m3-on-surface)' }}>
          {t('detail.plan.title', 'Plan 步骤时间线')}
        </span>
        <span
          class="oh-plan-timeline-count text-xs px-1.5 py-0.5 rounded-m3-sm"
          style={{
            background: 'var(--m3-surface)',
            color: 'var(--m3-on-surface-variant)',
          }}
        >
          {completedCount} / {total}
        </span>
        {awaitingApproval ? (
          <span
            class="oh-plan-timeline-state text-xs px-1.5 py-0.5 rounded-m3-sm"
            style={{
              background: 'var(--m3-tertiary-container)',
              color: 'var(--m3-on-tertiary-container)',
              fontWeight: 600,
            }}
          >
            {t('detail.plan.awaiting', '等待批准')}
          </span>
        ) : allDone ? (
          <span
            class="oh-plan-timeline-state text-xs px-1.5 py-0.5 rounded-m3-sm inline-flex items-center gap-1"
            style={{
              background: 'var(--m3-secondary-container)',
              color: 'var(--m3-on-secondary-container)',
              fontWeight: 600,
            }}
          >
            <PlanIcon name="check" size={13} />
            {t('detail.plan.completed', '已完成')}
          </span>
        ) : null}
        <button
          type="button"
          class="oh-tap-press oh-plan-collapse-button text-xs px-2 py-0.5 rounded-m3-sm ml-auto inline-flex items-center gap-1"
          style={{
            background: 'var(--m3-surface)',
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
          }}
          onClick={() => setCollapsed((v) => !v)}
        >
          <PlanIcon name={collapsed ? 'chevronDown' : 'chevronUp'} size={13} />
          {collapsed ? t('detail.plan.expand', '展开') : t('detail.plan.collapse', '折叠')}
        </button>
      </header>
      {!collapsed && (
        <ol class="oh-plan-step-list flex flex-col gap-1.5">
          {steps.map((step, idx) => {
            const v = statusVisual(step.state);
            return (
              <li
                key={step.id}
                class="oh-plan-step-row flex items-start gap-2 px-2 py-1.5 rounded-m3-sm"
                style={{ background: v.bg }}
              >
                <span
                  class={
                    'oh-plan-step-icon inline-flex items-center justify-center w-6 h-6 rounded-full text-xs flex-shrink-0' +
                    (step.state === 'in_progress' ? ' oh-pulse-soft' : '')
                  }
                  style={{
                    background: v.color,
                    color: 'white',
                    fontWeight: 600,
                  }}
                  aria-hidden
                >
                  {v.icon ? <PlanIcon name={v.icon} size={14} /> : idx + 1}
                </span>
                <span
                  class="oh-plan-step-label text-sm leading-relaxed"
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
        <footer class="oh-plan-timeline-footer flex items-center gap-2 mt-3">
          <button
            type="button"
            disabled={submitting}
            onClick={handleApprove}
            class="oh-tap-press oh-plan-approve-button px-3 py-1.5 rounded-m3-sm text-sm font-semibold disabled:opacity-60 inline-flex items-center gap-1.5"
            style={{
              background: 'var(--m3-primary)',
              color: 'var(--m3-on-primary)',
            }}
          >
            {submitting
              ? t('detail.plan.approving', '批准中…')
              : (
                <>
                  <PlanIcon name="check" />
                  {t('detail.plan.approve', '批准计划')}
                </>
              )}
          </button>
          <span class="oh-plan-approve-hint text-xs oh-text-muted">
            {t('detail.plan.approveHint', '或在输入框回复任意文本继续讨论')}
          </span>
          {error && (
            <span class="oh-plan-approve-error text-xs ml-auto oh-text-error">
              {error}
            </span>
          )}
        </footer>
      )}
    </section>
  );
}
