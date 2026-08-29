import { useMemo, useState } from 'preact/hooks';
import { TopBar } from '../../../components/TopBar';
import { Appear } from '../../../components/Appear';
import { ErrorBanner } from '../../../components/StatusBanner';
import {
  type BuiltinToolSummary,
  type CronEntrySummary,
  type HookEntrySummary,
  type KnowledgeSourceSummary,
  type McpServerSummary,
  type MemoryEntrySummary,
  type ResourceUsageKind,
  type SkillSummary,
  listBuiltinTools,
  listCrons,
  listHooks,
  listKnowledgeSources,
  listMcpServers,
  listMemories,
  listSkills,
} from '../../../api/toolbox';
import { ResourceUsageDialog } from '../../../components/ResourceUsageDialog';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { t, tDateTime } from '../../../i18n';
import { describeApiError } from '../../../utils/api_error';
import {
  STATUS_SUCCESS_COLOR,
  STATUS_SUCCESS_BG,
  STATUS_ACTIVE_BG,
  STATUS_ERROR_BG,
  STATUS_NEUTRAL_BG,
  STATUS_NEUTRAL_BG_FAINT,
} from '../../../shared/ui/status_palette';
import { templateAssociationLabel } from '../../../shared/util/template_association';

type TabKey = 'tools' | 'mcp' | 'skills' | 'memories' | 'hooks' | 'knowledge' | 'crons';
const TOOLBOX_POLL_INTERVAL_MS = 5_000;

interface TabSpec {
  key: TabKey;
  label: string;
}

function statusBadge(status: string): { color: string; bg: string; label: string } {
  switch (status) {
    case 'running':
      return { color: 'var(--m3-primary)', bg: STATUS_ACTIVE_BG, label: status };
    case 'success':
    case 'idle':
      return { color: STATUS_SUCCESS_COLOR, bg: STATUS_SUCCESS_BG, label: status };
    case 'failed':
    case 'error':
      return { color: 'var(--m3-error)', bg: STATUS_ERROR_BG, label: status };
    case 'disabled':
      return { color: 'var(--m3-on-surface-variant)', bg: STATUS_NEUTRAL_BG, label: status };
    default:
      return { color: 'var(--m3-on-surface-variant)', bg: STATUS_NEUTRAL_BG_FAINT, label: status };
  }
}

export function ToolboxPage() {
  const [active, setActive] = useState<TabKey>('tools');

  const [tools, setTools] = useState<BuiltinToolSummary[] | null>(null);
  const [mcp, setMcp] = useState<McpServerSummary[] | null>(null);
  const [skills, setSkills] = useState<SkillSummary[] | null>(null);
  const [skillsRoot, setSkillsRoot] = useState<string>('');
  const [memories, setMemories] = useState<MemoryEntrySummary[] | null>(null);
  const [crons, setCrons] = useState<CronEntrySummary[] | null>(null);
  const [hooks, setHooks] = useState<HookEntrySummary[] | null>(null);
  const [knowledge, setKnowledge] = useState<KnowledgeSourceSummary[] | null>(null);
  const [usageKind, setUsageKind] = useState<ResourceUsageKind | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useAsyncPolling(async (isActive, signal) => {
    try {
      const [toolItems, m, s, mem, c, h, k] = await Promise.all([
        listBuiltinTools({ signal }),
        listMcpServers({ signal }),
        listSkills({ signal }),
        listMemories({ signal }),
        listCrons({ signal }),
        listHooks({ signal }),
        listKnowledgeSources({ signal }),
      ]);
      if (!isActive()) return;
      setTools(toolItems.items);
      setMcp(m.items);
      setSkills(s.items);
      setSkillsRoot(s.storage_path);
      setMemories(mem.items);
      setCrons(c.items);
      setHooks(h.items);
      setKnowledge(k.items);
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
      { key: 'tools', label: `${t('toolbox.tools', '工具')} (${tools?.length ?? '—'})` },
      { key: 'mcp', label: `MCP (${mcp?.length ?? '—'})` },
      { key: 'skills', label: `${t('toolbox.skills', '技能')} (${skills?.length ?? '—'})` },
      { key: 'memories', label: `${t('toolbox.memories', '记忆')} (${memories?.length ?? '—'})` },
      { key: 'hooks', label: `Hooks (${hooks?.length ?? '—'})` },
      { key: 'knowledge', label: `${t('toolbox.knowledge', '知识库')} (${knowledge?.length ?? '—'})` },
      { key: 'crons', label: `${t('toolbox.crons', '定时任务')} (${crons?.length ?? '—'})` },
    ],
    [tools, mcp, skills, memories, hooks, knowledge, crons],
  );

  const activeUsageKind: ResourceUsageKind | null = {
    tools: 'tool', mcp: 'mcp', skills: 'skill', memories: 'memory', hooks: 'hook', knowledge: 'knowledge', crons: null,
  }[active] as ResourceUsageKind | null;
  const usageLabels = useMemo<Record<string, string>>(() => {
    if (usageKind === 'tool') return Object.fromEntries((tools ?? []).map((item) => [item.id, item.name]));
    if (usageKind === 'mcp') return Object.fromEntries((mcp ?? []).map((item) => [item.name, item.name]));
    if (usageKind === 'skill') return Object.fromEntries((skills ?? []).flatMap((item) => [[item.relative_directory_path, item.name], [item.name, item.name]]));
    if (usageKind === 'memory') return Object.fromEntries((memories ?? []).map((item) => [item.id, item.title]));
    if (usageKind === 'hook') return Object.fromEntries((hooks ?? []).map((item) => [item.id, item.label]));
    if (usageKind === 'knowledge') return Object.fromEntries((knowledge ?? []).map((item) => [item.id, item.title]));
    return {};
  }, [usageKind, tools, mcp, skills, memories, hooks, knowledge]);

  return (
    <main
      class="min-h-screen"
      style={{ background: 'var(--m3-background)', color: 'var(--m3-on-surface)' }}
    >
      <TopBar
        title={t('home.openToolbox', '工具箱')}
        subtitle={t('toolbox.subtitle', '远程查看本机已加载的工具、MCP、技能、记忆、Hooks 与知识库')}
        actionSlot={activeUsageKind ? (
          <button type="button" class="oh-topbar-action oh-tap-press px-3 py-1.5 rounded-m3-sm text-sm" onClick={() => setUsageKind(activeUsageKind)}>
            {t('resourceUsage.title', '使用统计')}
          </button>
        ) : null}
      />

      <div class="max-w-6xl mx-auto px-4 py-6">
        <ErrorBanner message={error} />

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

        {loading && !tools && !mcp && !skills && !memories && !hooks && !knowledge && !crons ? (
          <p class="text-sm oh-text-muted">
            {t('common.loading', '加载中…')}
          </p>
        ) : null}

        {active === 'tools' && tools ? <ToolsList items={tools} /> : null}
        {active === 'mcp' && mcp ? <McpList items={mcp} /> : null}
        {active === 'skills' && skills ? <SkillsList items={skills} root={skillsRoot} /> : null}
        {active === 'memories' && memories ? <MemoriesList items={memories} /> : null}
        {active === 'hooks' && hooks ? <HooksList items={hooks} /> : null}
        {active === 'knowledge' && knowledge ? <KnowledgeList items={knowledge} /> : null}
        {active === 'crons' && crons ? <CronsList items={crons} /> : null}
      </div>
      {usageKind ? <ResourceUsageDialog kind={usageKind} labels={usageLabels} onClose={() => setUsageKind(null)} /> : null}
    </main>
  );
}

function ToolsList(props: { items: BuiltinToolSummary[] }) {
  if (props.items.length === 0) return emptyHint(t('toolbox.empty.tools', '暂无内建工具配置'));
  return (
    <ul class="space-y-2">
      {props.items.map((item, idx) => (
        <Appear key={item.id} variant="up" index={idx}>
          <li class="oh-toolbox-card">
            <div class="flex items-baseline justify-between gap-3">
              <h3 class="text-sm font-semibold">{item.name}</h3>
              <span class="oh-toolbox-badge" style={{ color: item.enabled ? STATUS_SUCCESS_COLOR : 'var(--m3-on-surface-variant)', background: item.enabled ? STATUS_SUCCESS_BG : STATUS_NEUTRAL_BG }}>
                {item.enabled ? t('common.enabled', '已启用') : t('common.disabled', '未启用')}
              </span>
            </div>
            <div class="oh-toolbox-meta-grid"><div>{t('toolbox.tool.kind', '类型')}: <code>{item.kind}</code></div><div>{t('toolbox.tool.loading', '加载策略')}: <code>{item.load_strategy}</code></div><div class="col-span-2"><code>{item.id}</code></div></div>
          </li>
        </Appear>
      ))}
    </ul>
  );
}

function HooksList(props: { items: HookEntrySummary[] }) {
  if (props.items.length === 0) return emptyHint(t('toolbox.empty.hooks', '尚未配置 Hook'));
  return (
    <ul class="space-y-2">
      {props.items.map((item, idx) => (
        <Appear key={item.id} variant="up" index={idx}>
          <li class="oh-toolbox-card">
            <div class="flex items-baseline justify-between gap-3">
              <h3 class="text-sm font-semibold">{item.label}</h3>
              <span class="oh-toolbox-badge" style={{ color: item.enabled ? STATUS_SUCCESS_COLOR : 'var(--m3-on-surface-variant)', background: item.enabled ? STATUS_SUCCESS_BG : STATUS_NEUTRAL_BG }}>
                {item.enabled ? t('common.enabled', '已启用') : t('common.disabled', '未启用')}
              </span>
            </div>
            <div class="oh-toolbox-meta-grid"><div>{t('toolbox.hook.event', '事件')}: <code>{item.event}</code></div><div>{t('toolbox.hook.timeout', '超时')}: {item.timeout_seconds}s</div></div>
          </li>
        </Appear>
      ))}
    </ul>
  );
}

function KnowledgeList(props: { items: KnowledgeSourceSummary[] }) {
  if (props.items.length === 0) return emptyHint(t('toolbox.empty.knowledge', '知识库中暂无资源'));
  return (
    <ul class="space-y-2">
      {props.items.map((item, idx) => (
        <Appear key={item.id} variant="up" index={idx}>
          <li class="oh-toolbox-card">
            <div class="flex items-baseline justify-between gap-3"><h3 class="text-sm font-semibold">{item.title}</h3><span class="oh-toolbox-badge">{item.status}</span></div>
            <div class="oh-toolbox-meta-grid"><div>{t('toolbox.knowledge.kind', '类型')}: <code>{item.kind}</code></div><div>{t('toolbox.knowledge.updated', '更新时间')}: {tDateTime(item.updated_at)}</div><div class="col-span-2"><code>{item.id}</code></div></div>
          </li>
        </Appear>
      ))}
    </ul>
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
                <h3 class="text-sm font-semibold oh-text-body">
                  {srv.name}
                </h3>
                <div class="flex items-center gap-1.5 flex-wrap justify-end">
                  {(srv.template_associations ?? []).map((association) => (
                    <span
                      key={association.template_id}
                      class="oh-toolbox-badge"
                      style={{ color: 'var(--m3-primary)', background: STATUS_ACTIVE_BG }}
                    >
                      {templateAssociationLabel(association)}
                    </span>
                  ))}
                  <span
                    class="oh-toolbox-badge"
                    style={{ color: badge.color, background: badge.bg }}
                  >
                    {srv.enabled ? t('toolbox.mcp.enabled', '已启用') : t('toolbox.mcp.disabled', '未启用')}
                  </span>
                </div>
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
                {srv.summary ? <div class="col-span-2 mt-1 oh-text-body">{srv.summary}</div> : null}
                {(srv.template_associations ?? []).some((association) => (association.capabilities ?? []).length > 0) ? (
                  <div class="col-span-2 flex flex-wrap gap-1.5 mt-1">
                    {(srv.template_associations ?? []).flatMap((association) =>
                      (association.capabilities ?? []).map((capability) => (
                        <span
                          key={`${association.template_id}:${capability.id}`}
                          class="oh-toolbox-badge"
                          style={{ color: 'var(--m3-on-surface-variant)', background: STATUS_NEUTRAL_BG }}
                        >
                          {capability.label_zh || capability.label_en || capability.id}
                        </span>
                      )),
                    )}
                  </div>
                ) : null}
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
                <h3 class="text-sm font-semibold oh-text-body">{sk.name}</h3>
                {sk.has_default_prompt ? (
                  <span
                    class="text-[10px] px-1.5 py-0.5 rounded-m3-xs"
                    style={{ background: STATUS_ACTIVE_BG, color: 'var(--m3-primary)' }}
                  >
                    {t('toolbox.skills.defaultPrompt', '含默认 prompt')}
                  </span>
                ) : null}
              </div>
              {sk.description ? (
                <p class="text-xs mt-1.5 leading-relaxed oh-text-muted">
                  {sk.description}
                </p>
              ) : null}
              <p class="text-[11px] mt-1.5 oh-text-muted">
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
              <h3 class="text-sm font-semibold oh-text-body">{m.title}</h3>
              <span class="text-[10px] oh-text-muted">
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
                <span class="text-[10px] px-1.5 py-0.5 rounded-m3-xs" style={{ background: STATUS_ACTIVE_BG, color: 'var(--m3-primary)' }}>
                  {t('toolbox.memory.userProfile', '用户画像')}
                </span>
              ) : null}
              {m.is_auto_learned ? (
                <span class="text-[10px] px-1.5 py-0.5 rounded-m3-xs" style={{ background: STATUS_SUCCESS_BG, color: STATUS_SUCCESS_COLOR }}>
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
                <h3 class="text-sm font-semibold oh-text-body">{c.name}</h3>
                <span
                  class="oh-toolbox-badge"
                  style={{ color: badge.color, background: badge.bg }}
                >
                  {badge.label}
                </span>
              </div>
              {c.description ? (
                <p class="text-xs mt-1.5 oh-text-muted">{c.description}</p>
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
