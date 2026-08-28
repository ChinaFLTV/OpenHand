import { useState } from 'preact/hooks';
import { TopBar } from '../../../components/TopBar';
import { Appear } from '../../../components/Appear';
import { ErrorBanner } from '../../../components/StatusBanner';
import {
  type HarnessPhaseLogSnapshot,
  type HarnessPhaseStatus,
  type HarnessPhaseValue,
  type HarnessSessionRecord,
  fetchHarnessSession,
} from '../../../api/harness';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { t, tDateTime } from '../../../i18n';
import { describeApiError } from '../../../utils/api_error';
import {
  STATUS_SUCCESS_COLOR,
  STATUS_SUCCESS_BG,
  STATUS_ACTIVE_BG,
  STATUS_ERROR_BG,
  STATUS_WARNING_BG,
  STATUS_NEUTRAL_BG,
  STATUS_NEUTRAL_BG_FAINT,
} from '../../../shared/ui/status_palette';

const HARNESS_POLL_INTERVAL_MS = 5_000;

const PHASE_ORDER: HarnessPhaseValue[] = [
  'meta_collection',
  'reading',
  'planning',
  'implementing',
  'reviewing',
];

const PHASE_NAMES_ZH: Record<HarnessPhaseValue, string> = {
  meta_collection: '元数据采集',
  reading: '调查',
  planning: '规划',
  implementing: '实施',
  reviewing: '验收',
};

function phaseStatusBadge(status: HarnessPhaseStatus): { color: string; bg: string; icon: string } {
  switch (status) {
    case 'running':
      return { color: 'var(--m3-primary)', bg: STATUS_ACTIVE_BG, icon: '⟳' };
    case 'completed':
      return { color: STATUS_SUCCESS_COLOR, bg: STATUS_SUCCESS_BG, icon: '✓' };
    case 'failed':
      return { color: 'var(--m3-error)', bg: STATUS_ERROR_BG, icon: '✕' };
    case 'skipped':
      return { color: 'var(--m3-on-surface-variant)', bg: STATUS_NEUTRAL_BG, icon: '↷' };
    default:
      return { color: 'var(--m3-on-surface-variant)', bg: STATUS_NEUTRAL_BG_FAINT, icon: '○' };
  }
}

function overallStatusLabel(status: string): string {
  const map: Record<string, string> = {
    idle: '空闲',
    running: '运行中',
    completed: '已完成',
    failed: '失败',
    cancelled: '已取消',
  };
  return map[status] ?? status;
}

export function HarnessPage() {
  const [record, setRecord] = useState<HarnessSessionRecord | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);

  useAsyncPolling(async (isActive, signal) => {
    try {
      const res = await fetchHarnessSession({ signal });
      if (!isActive()) return;
      setRecord(res.record);
      setError(null);
    } catch (err) {
      if (isActive()) setError(describeApiError(err));
    }
  }, {
    intervalMs: HARNESS_POLL_INTERVAL_MS,
    onError: (err) => setError(describeApiError(err)),
  });

  return (
    <main
      class="min-h-screen"
      style={{ background: 'var(--m3-background)', color: 'var(--m3-on-surface)' }}
    >
      <TopBar
        title={t('harness.title', 'Harness Engineering')}
        subtitle={t('harness.subtitle', '查看本机最近一次工程化会话快照')}
      />

      <div class="max-w-6xl mx-auto px-4 py-6">
        <ErrorBanner message={error} />

        {record === undefined ? (
          <p class="text-sm oh-text-muted">
            {t('common.loading', '加载中…')}
          </p>
        ) : record === null ? (
          <Appear variant="up">
            <div
              class="rounded-m3-md px-4 py-8 text-sm text-center"
              style={{
                background: 'var(--m3-surface-container-low)',
                color: 'var(--m3-on-surface-variant)',
                border: '1px dashed var(--m3-outline-variant)',
              }}
            >
              {t('harness.empty', '本机尚未运行过 Harness Engineering 会话')}
            </div>
          </Appear>
        ) : (
          <HarnessRecordView record={record} />
        )}
      </div>
    </main>
  );
}

function HarnessRecordView(props: { record: HarnessSessionRecord }) {
  const r = props.record;
  // 把日志按阶段建索引, 便于 5 个标准 phase 都展示, 即便还没跑也展示空卡片。
  const logsByPhase = new Map<HarnessPhaseValue, HarnessPhaseLogSnapshot>();
  for (const log of r.phase_logs) logsByPhase.set(log.phase, log);

  return (
    <>
      <Appear variant="up">
        <header
          class="rounded-m3-md p-4 mb-4"
          style={{
            background: 'var(--m3-surface-container)',
            border: '1px solid var(--m3-outline-variant)',
          }}
        >
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="text-base font-semibold oh-text-body">
              {r.title || r.id}
            </h2>
            <span
              class="text-xs px-2 py-0.5 rounded-m3-xs"
              style={{
                color: r.status === 'failed' ? 'var(--m3-error)' :
                       r.status === 'running' ? 'var(--m3-primary)' :
                       r.status === 'completed' ? STATUS_SUCCESS_COLOR : 'var(--m3-on-surface-variant)',
                background: r.status === 'failed' ? STATUS_ERROR_BG :
                            r.status === 'running' ? STATUS_ACTIVE_BG :
                            r.status === 'completed' ? STATUS_SUCCESS_BG : STATUS_NEUTRAL_BG_FAINT,
              }}
            >
              {overallStatusLabel(r.status)}
            </span>
          </div>
          <div class="mt-2 grid grid-cols-2 gap-2 text-xs oh-text-muted">
            <div>{t('harness.createdAt', '创建于')}: {tDateTime(r.created_at)}</div>
            <div>{t('harness.updatedAt', '更新于')}: {tDateTime(r.updated_at)}</div>
            {r.current_phase ? (
              <div class="col-span-2">
                {t('harness.currentPhase', '当前阶段')}:{' '}
                <code>{PHASE_NAMES_ZH[r.current_phase as HarnessPhaseValue] ?? r.current_phase}</code>
              </div>
            ) : null}
            {r.error_message ? (
              <div class="col-span-2 mt-1 oh-text-error">
                {r.error_message}
              </div>
            ) : null}
          </div>
          {r.manual_phase_input_requested ? (
            <div
              class="mt-2 rounded-m3-sm px-2 py-1.5 text-xs oh-pulse-soft"
              style={{
                background: STATUS_WARNING_BG,
                color: '#d97706',
                border: '1px solid rgba(245,158,11,0.30)',
              }}
            >
              {t('harness.awaitingManualInput', '等待用户在 App 端补充人工反馈以继续')}
            </div>
          ) : null}
        </header>
      </Appear>

      <ol class="space-y-3">
        {PHASE_ORDER.map((phase, idx) => {
          const log = logsByPhase.get(phase);
          return (
            <PhaseCard
              key={phase}
              index={idx}
              phase={phase}
              log={log}
              isCurrent={r.current_phase === phase}
            />
          );
        })}
      </ol>
    </>
  );
}

function PhaseCard(props: {
  index: number;
  phase: HarnessPhaseValue;
  log: HarnessPhaseLogSnapshot | undefined;
  isCurrent: boolean;
}) {
  const { index, phase, log, isCurrent } = props;
  const status: HarnessPhaseStatus = log?.status ?? 'pending';
  const badge = phaseStatusBadge(status);
  const [expanded, setExpanded] = useState(status === 'running' || status === 'failed');

  const ringColor = isCurrent ? 'var(--m3-primary)' : 'var(--m3-outline-variant)';

  return (
    <Appear variant="up" index={index}>
      <li
        class="rounded-m3-md overflow-hidden"
        style={{
          background: 'var(--m3-surface-container)',
          border: `1px solid ${ringColor}`,
        }}
      >
        <button
          type="button"
          class="w-full flex items-center gap-3 px-4 py-3 oh-tap-press"
          style={{ background: 'transparent', textAlign: 'left' }}
          onClick={() => setExpanded((v) => !v)}
        >
          <span
            class="inline-flex items-center justify-center text-xs"
            style={{
              width: 24,
              height: 24,
              borderRadius: '50%',
              background: badge.bg,
              color: badge.color,
              flexShrink: 0,
            }}
          >
            {badge.icon}
          </span>
          <div class="flex-1 min-w-0">
            <div class="flex items-baseline gap-2 flex-wrap">
              <span class="text-sm font-semibold oh-text-body">
                {index + 1}. {PHASE_NAMES_ZH[phase]}
              </span>
              <span class="text-[10px] oh-text-muted">
                <code>{phase}</code>
              </span>
              {log?.exit_code != null ? (
                <span
                  class="text-[10px] px-1.5 py-0.5 rounded-m3-xs"
                  style={{
                    background: log.exit_code === 0 ? STATUS_SUCCESS_BG : STATUS_ERROR_BG,
                    color: log.exit_code === 0 ? STATUS_SUCCESS_COLOR : 'var(--m3-error)',
                  }}
                >
                  exit {log.exit_code}
                </span>
              ) : null}
              {log?.review_verdict_fail ? (
                <span
                  class="text-[10px] px-1.5 py-0.5 rounded-m3-xs"
                  style={{ background: STATUS_ERROR_BG, color: 'var(--m3-error)' }}
                >
                  REVIEW FAIL
                </span>
              ) : null}
            </div>
            {log?.changed_files && log.changed_files.length > 0 ? (
              <div class="text-[11px] mt-0.5 oh-text-muted">
                {t('harness.changedFiles', '改动文件')}: {log.changed_files.length}
              </div>
            ) : null}
          </div>
          <span class="text-xs oh-text-muted">
            {expanded ? '▾' : '▸'}
          </span>
        </button>

        {expanded ? (
          <div
            class="px-4 pb-3 space-y-2 text-xs"
            style={{ borderTop: '1px solid var(--m3-outline-variant)' }}
          >
            {log ? (
              <>
                {log.lines.length > 0 ? (
                  <pre
                    class="rounded-m3-sm p-2 overflow-x-auto"
                    style={{
                      maxHeight: 360,
                      background: 'var(--m3-surface-container-high)',
                      color: 'var(--m3-on-surface)',
                      fontFamily: 'var(--font-mono)',
                      fontSize: 12,
                      lineHeight: '1.45',
                      whiteSpace: 'pre-wrap',
                      wordBreak: 'break-word',
                    }}
                  >
                    {log.lines.join('\n')}
                  </pre>
                ) : (
                  <p class="oh-text-muted">
                    {t('harness.noOutput', '此阶段尚无输出')}
                  </p>
                )}
                {log.changed_files.length > 0 ? (
                  <ul class="space-y-0.5 mt-2">
                    {log.changed_files.map((f) => (
                      <li
                        key={f.relative_path}
                        class="flex items-baseline gap-2 text-[11px] oh-text-muted"
                      >
                        <span
                          style={{
                            color: f.change_type === 'added' ? STATUS_SUCCESS_COLOR :
                                   f.change_type === 'deleted' ? 'var(--m3-error)' : 'var(--m3-primary)',
                            width: 14,
                            display: 'inline-block',
                          }}
                        >
                          {f.change_type === 'added' ? '+' : f.change_type === 'deleted' ? '−' : '±'}
                        </span>
                        <code>{f.relative_path}</code>
                      </li>
                    ))}
                  </ul>
                ) : null}
                {log.saved_log_path ? (
                  <p class="mt-1 text-[11px] oh-text-muted">
                    {t('harness.savedLog', '日志文件')}: <code>{log.saved_log_path}</code>
                  </p>
                ) : null}
              </>
            ) : (
              <p class="oh-text-muted">
                {t('harness.phasePending', '此阶段尚未运行')}
              </p>
            )}
          </div>
        ) : null}
      </li>
    </Appear>
  );
}
