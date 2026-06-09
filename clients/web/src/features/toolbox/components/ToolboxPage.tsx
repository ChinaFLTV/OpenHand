// ToolboxPage —— 只读浏览 MCP 服务器 / 已安装技能 / 用户记忆 / 定时任务。
//
// App 端是这些资源的真权威 (新增/修改/删除全在 GUI), Web 端只展示当前
// 已加载的快照, 帮助远程使用者快速确认 MCP 是否在线 / 哪些技能可用 /
// 哪些定时任务正在跑。所有列表 5 秒一次 polling, 出错只在头部红条提示,
// 内容保留旧值, 避免短暂网络抖动让用户 tab 整个清空。

import { useMemo, useState } from 'preact/hooks';
import { TopBar } from '../../../components/TopBar';
import { Appear } from '../../../components/Appear';
import {
  CronEntrySummary,
  McpServerSummary,
  MemoryEntrySummary,
  SkillSummary,
  listCrons,
  listMcpServers,
  listMemories,
  listSkills,
} from '../../../api/toolbox';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { t, tDateTime } from '../../../i18n';
import { describeApiError } from '../../../utils/api_error';

type TabKey = 'mcp' | 'skills' | 'memories' | 'crons';
const TOOLBOX_POLL_INTERVAL_MS = 5_000;

interface TabSpec {
  key: TabKey;
  label: string;
}

function statusBadge(status: string): { color: string; bg: string; label: string } {
  switch (status) {
    case 'running':
      return { color: 'var(--m3-primary)', bg: 'rgba(99,102,241,0.10)', label: status };
    case 'success':
    case 'idle':
      return { color: '#16a34a', bg: 'rgba(22,163,74,0.10)', label: status };
    case 'failed':
    case 'error':
      return { color: 'var(--m3-error)', bg: 'rgba(239,68,68,0.10)', label: status };
    case 'disabled':
      return { color: 'var(--m3-on-surface-variant)', bg: 'rgba(120,120,120,0.10)', label: status };
    default:
      return { color: 'var(--m3-on-surface-variant)', bg: 'rgba(120,120,120,0.06)', label: status };
  }
}

export function ToolboxPage() {
  const [active, setActive] = useState<TabKey>('mcp');

  const [mcp, setMcp] = useState<McpServerSummary[] | null>(null);
  const [skills, setSkills] = useState<SkillSummary[] | null>(null);
  const [skillsRoot, setSkillsRoot] = useState<string>('');
  const [memories, setMemories] = useState<MemoryEntrySummary[] | null>(null);
  const [crons, setCrons] = useState<CronEntrySummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useAsyncPolling(async (isActive, signal) => {
    try {
      const [m, s, mem, c] = await Promise.all([
        listMcpServers({ signal }),
        listSkills({ signal }),
        listMemories({ signal }),
        listCrons({ signal }),
      ]);
      if (!isActive()) return;
      setMcp(m.items);
      setSkills(s.items);
      setSkillsRoot(s.storage_path);
      setMemories(mem.items);
      setCrons(c.items);
      setError(null);
    } catch (err) {
      if (isActive()) setError(describeApiError(err));
    } finally {
      if (isActive()) setLoading(false);
    }
  }, {
    intervalMs: TOOLBOX_POLL_INTERVAL_MS,
    onError: (err) => {
      setError(describeApiError(err));
      setLoading(false);
    },
  });

  const tabs: TabSpec[] = useMemo(
    () => [
      { key: 'mcp', label: `MCP (${mcp?.length ?? '—'})` },
      { key: 'skills', label: `${t('toolbox.skills', '技能')} (${skills?.length ?? '—'})` },
      { key: 'memories', label: `${t('toolbox.memories', '记忆')} (${memories?.length ?? '—'})` },
      { key: 'crons', label: `${t('toolbox.crons', '定时任务')} (${crons?.length ?? '—'})` },
    ],
    [mcp, skills, memories, crons],
  );

  return (
    <main
      class="min-h-screen"
      style={{ background: 'var(--m3-background)', color: 'var(--m3-on-surface)' }}
    >
      <TopBar title={t('home.openToolbox', '工具箱')} subtitle={t('toolbox.subtitle', '远程查看本机已加载的 MCP / 技能 / 记忆 / 定时任务')} />

      <div class="max-w-6xl mx-auto px-4 py-6">
        {error ? (
          <div
            class="rounded-m3-md px-3 py-2 text-sm mb-4"
            style={{
              background: 'rgba(239,68,68,0.08)',
              color: 'var(--m3-error)',
              border: '1px solid rgba(239,68,68,0.30)',
            }}
          >
            {error}
          </div>
        ) : null}

        <div class="oh-toolbox-tabs mb-4" role="tablist" aria-label={t('toolbox.tabs.aria', '工具箱分类')}>
          {tabs.map((tab) => {
            const isActive = active === tab.key;
            return (
              <button
                key={tab.key}
                type="button"
                class={`oh-tap-press oh-toolbox-tab${isActive ? ' is-active' : ''}`}
                role="tab"
                aria-selected={isActive}
                onClick={() => setActive(tab.key)}
              >
                {tab.label}
              </button>
            );
          })}
        </div>

        {loading && !mcp && !skills && !memories && !crons ? (
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {t('common.loading', '加载中…')}
          </p>
        ) : null}

        {active === 'mcp' && mcp ? <McpList items={mcp} /> : null}
        {active === 'skills' && skills ? <SkillsList items={skills} root={skillsRoot} /> : null}
        {active === 'memories' && memories ? <MemoriesList items={memories} /> : null}
        {active === 'crons' && crons ? <CronsList items={crons} /> : null}
      </div>
    </main>
  );
}

function emptyHint(label: string) {
  return (
    <Appear variant="up">
      <p
        class="oh-toolbox-empty"
      >
        {label}
      </p>
    </Appear>
  );
}

function McpList(props: { items: McpServerSummary[] }) {
  if (props.items.length === 0) return emptyHint(t('toolbox.empty.mcp', '当前没有已配置的 MCP 服务器'));
  return (
    <ul class="space-y-2">
      {props.items.map((srv, idx) => {
        const badge = statusBadge(srv.enabled ? 'success' : 'disabled');
        return (
          <Appear key={srv.name} variant="up" index={idx}>
            <li class="oh-toolbox-card">
              <div class="flex items-baseline justify-between gap-3">
                <h3 class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
                  {srv.name}
                </h3>
                <span
                  class="oh-toolbox-badge"
                  style={{ color: badge.color, background: badge.bg }}
                >
                  {srv.enabled ? t('toolbox.mcp.enabled', '已启用') : t('toolbox.mcp.disabled', '未启用')}
                </span>
              </div>
              <div class="oh-toolbox-meta-grid">
                <div>{t('toolbox.mcp.type', '类型')}: <code>{srv.type}</code></div>
                <div>{t('toolbox.mcp.tools', '工具数')}: {srv.tool_count}</div>
                {srv.url ? <div class="col-span-2">URL: <code>{srv.url}</code></div> : null}
                {srv.command ? (
                  <div class="col-span-2">
                    {t('toolbox.mcp.cmd', '命令')}: <code>{srv.command}{srv.args && srv.args.length > 0 ? ' ' + srv.args.join(' ') : ''}</code>
                  </div>
                ) : null}
                {srv.summary ? <div class="col-span-2 mt-1" style={{ color: 'var(--m3-on-surface)' }}>{srv.summary}</div> : null}
              </div>
            </li>
          </Appear>
        );
      })}
    </ul>
  );
}

function SkillsList(props: { items: SkillSummary[]; root: string }) {
  if (props.items.length === 0) return emptyHint(t('toolbox.empty.skills', '尚未安装本地技能'));
  return (
    <>
      {props.root ? (
        <p class="oh-toolbox-section-note">
          {t('toolbox.skills.root', '存储位置')}: <code>{props.root}</code>
        </p>
      ) : null}
      <ul class="space-y-2">
        {props.items.map((sk, idx) => (
          <Appear key={sk.name} variant="up" index={idx}>
            <li class="oh-toolbox-card">
              <div class="flex items-baseline gap-2">
                {sk.emoji_icon ? <span style={{ fontSize: 16 }}>{sk.emoji_icon}</span> : null}
                <h3 class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface)' }}>{sk.name}</h3>
                {sk.has_default_prompt ? (
                  <span
                    class="text-[10px] px-1.5 py-0.5 rounded-m3-xs"
                    style={{ background: 'rgba(99,102,241,0.10)', color: 'var(--m3-primary)' }}
                  >
                    {t('toolbox.skills.defaultPrompt', '含默认 prompt')}
                  </span>
                ) : null}
              </div>
              {sk.description ? (
                <p class="text-xs mt-1.5 leading-relaxed" style={{ color: 'var(--m3-on-surface-variant)' }}>
                  {sk.description}
                </p>
              ) : null}
              <p class="text-[11px] mt-1.5" style={{ color: 'var(--m3-on-surface-variant)' }}>
                <code>{sk.relative_directory_path || sk.directory_path}</code>
              </p>
            </li>
          </Appear>
        ))}
      </ul>
    </>
  );
}

function MemoriesList(props: { items: MemoryEntrySummary[] }) {
  if (props.items.length === 0) return emptyHint(t('toolbox.empty.memories', '尚未保存任何记忆'));
  return (
    <ul class="space-y-2">
      {props.items.map((m, idx) => (
        <Appear key={m.id} variant="up" index={idx}>
          <li class="oh-toolbox-card">
            <div class="flex items-baseline justify-between gap-3">
              <h3 class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface)' }}>{m.title}</h3>
              <span class="text-[10px]" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {tDateTime(m.created_at)}
              </span>
            </div>
            <p
              class="text-xs mt-1.5 leading-relaxed"
              style={{ color: 'var(--m3-on-surface-variant)', whiteSpace: 'pre-wrap' }}
            >
              {m.preview}
            </p>
            <div class="mt-1.5 flex flex-wrap gap-1">
              {m.is_user_profile ? (
                <span class="text-[10px] px-1.5 py-0.5 rounded-m3-xs" style={{ background: 'rgba(99,102,241,0.10)', color: 'var(--m3-primary)' }}>
                  {t('toolbox.memory.userProfile', '用户画像')}
                </span>
              ) : null}
              {m.is_auto_learned ? (
                <span class="text-[10px] px-1.5 py-0.5 rounded-m3-xs" style={{ background: 'rgba(22,163,74,0.10)', color: '#16a34a' }}>
                  {t('toolbox.memory.autoLearned', '自动学习')}
                </span>
              ) : null}
              {m.tags.map((tg) => (
                <span
                  key={tg}
                  class="text-[10px] px-1.5 py-0.5 rounded-m3-xs"
                  style={{ background: 'var(--m3-surface-container-high)', color: 'var(--m3-on-surface-variant)' }}
                >
                  #{tg}
                </span>
              ))}
            </div>
          </li>
        </Appear>
      ))}
    </ul>
  );
}

function CronsList(props: { items: CronEntrySummary[] }) {
  if (props.items.length === 0) return emptyHint(t('toolbox.empty.crons', '尚未配置定时任务'));
  return (
    <ul class="space-y-2">
      {props.items.map((c, idx) => {
        const badge = statusBadge(c.enabled ? c.status : 'disabled');
        return (
          <Appear key={c.id} variant="up" index={idx}>
            <li class="oh-toolbox-card">
              <div class="flex items-baseline justify-between gap-3">
                <h3 class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface)' }}>{c.name}</h3>
                <span
                  class="oh-toolbox-badge"
                  style={{ color: badge.color, background: badge.bg }}
                >
                  {badge.label}
                </span>
              </div>
              {c.description ? (
                <p class="text-xs mt-1.5" style={{ color: 'var(--m3-on-surface-variant)' }}>{c.description}</p>
              ) : null}
              <div class="oh-toolbox-meta-grid">
                <div>{t('toolbox.cron.expr', '表达式')}: <code>{c.cron_expression}</code></div>
                <div>{t('toolbox.cron.scriptType', '脚本类型')}: <code>{c.script_type}</code></div>
                <div>
                  {t('toolbox.cron.lastRun', '最近运行')}:{' '}
                  {c.last_run_at ? tDateTime(c.last_run_at) : '—'}
                </div>
                <div>
                  {t('toolbox.cron.nextRun', '下次运行')}:{' '}
                  {c.next_run_at ? tDateTime(c.next_run_at) : '—'}
                </div>
                <div>{t('toolbox.cron.lastExit', '最近退出码')}: {c.last_exit_code ?? '—'}</div>
                <div>
                  {t('toolbox.cron.failures', '连续失败')}:{' '}
                  <span style={{ color: c.consecutive_failures > 0 ? 'var(--m3-error)' : 'inherit' }}>
                    {c.consecutive_failures}
                  </span>
                </div>
              </div>
            </li>
          </Appear>
        );
      })}
    </ul>
  );
}
