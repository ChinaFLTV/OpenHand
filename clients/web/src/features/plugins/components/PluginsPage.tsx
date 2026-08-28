import { useState } from 'preact/hooks';
import { TopBar } from '../../../components/TopBar';
import { Appear } from '../../../components/Appear';
import { ErrorBanner } from '../../../components/StatusBanner';
import { ConfirmDialog } from '../../../components/ConfirmDialog';
import {
  type PluginSummary,
  type PluginStatus,
  listPlugins,
  installPlugin,
  updatePlugin,
  uninstallPlugin,
  rescanPlugins,
  checkPluginUpdate,
} from '../../../api/plugins';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { t } from '../../../i18n';
import { showSnackbar } from '../../../components/Snackbar';
import { describeApiError } from '../../../utils/api_error';
import {
  STATUS_SUCCESS_COLOR,
  STATUS_SUCCESS_BG,
  STATUS_ACTIVE_BG,
  STATUS_ERROR_BG,
  STATUS_WARNING_COLOR,
  STATUS_WARNING_BG,
  STATUS_NEUTRAL_BG,
  STATUS_NEUTRAL_BG_FAINT,
} from '../../../shared/ui/status_palette';
import { templateAssociationLabel } from '../../../shared/util/template_association';

const PLUGINS_POLL_INTERVAL_MS = 5_000;

function statusBadge(status: PluginStatus): { color: string; bg: string; label: string } {
  switch (status) {
    case 'installed':
      return { color: STATUS_SUCCESS_COLOR, bg: STATUS_SUCCESS_BG, label: t('plugins.status.installed', '已安装') };
    case 'notInstalled':
      return { color: 'var(--m3-on-surface-variant)', bg: STATUS_NEUTRAL_BG, label: t('plugins.status.notInstalled', '未安装') };
    case 'installing':
      return { color: 'var(--m3-primary)', bg: STATUS_ACTIVE_BG, label: t('plugins.status.installing', '安装中…') };
    case 'updating':
      return { color: 'var(--m3-primary)', bg: STATUS_ACTIVE_BG, label: t('plugins.status.updating', '更新中…') };
    case 'uninstalling':
      return { color: STATUS_WARNING_COLOR, bg: STATUS_WARNING_BG, label: t('plugins.status.uninstalling', '卸载中…') };
    case 'error':
      return { color: 'var(--m3-error)', bg: STATUS_ERROR_BG, label: t('plugins.status.error', '错误') };
    default:
      return { color: 'var(--m3-on-surface-variant)', bg: STATUS_NEUTRAL_BG_FAINT, label: status };
  }
}

function pluginIcon(id: string): string {
  switch (id) {
    case 'nodejs': return '⬢';
    case 'playwright': return '🎭';
    case 'python': return 'Py';
    case 'pip': return 'Pkg';
    default: return '🧩';
  }
}

function TemplatePluginSummary(props: { plugins: PluginSummary[] }) {
  const groups = new Map<string, { label: string; total: number; ready: number; disabled: number }>();
  for (const plugin of props.plugins) {
    for (const association of plugin.template_associations ?? []) {
      const key = association.template_id || templateAssociationLabel(association);
      const current = groups.get(key) ?? {
        label: templateAssociationLabel(association),
        total: 0,
        ready: 0,
        disabled: 0,
      };
      current.total += 1;
      if (plugin.status === 'installed' && plugin.enabled !== false) {
        current.ready += 1;
      } else if (plugin.status === 'installed') {
        current.disabled += 1;
      }
      groups.set(key, current);
    }
  }
  const rows = Array.from(groups.values());
  if (rows.length === 0) return null;
  return (
    <div class="oh-toolbox-card mb-4">
      <div class="text-sm font-semibold mb-2 oh-text-body">
        {t('plugins.templateBindings', '线程模板关联插件')}
      </div>
      <div class="flex flex-wrap gap-2">
        {rows.map((row) => (
          <span
            key={row.label}
            class="oh-toolbox-badge"
            style={{ color: 'var(--m3-primary)', background: STATUS_ACTIVE_BG }}
          >
            {row.label} · {row.ready}/{row.total}
            {row.disabled > 0 ? ` · ${t('plugins.disabledCount', '禁用')} ${row.disabled}` : ''}
          </span>
        ))}
      </div>
    </div>
  );
}

export function PluginsPage() {
  const [plugins, setPlugins] = useState<PluginSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [operating, setOperating] = useState<string | null>(null);
  const [checkingUpdate, setCheckingUpdate] = useState<string | null>(null);
  const [confirmAction, setConfirmAction] = useState<{
    pluginId: string;
    pluginName: string;
    action: 'install' | 'update' | 'uninstall';
  } | null>(null);

  const fetchPlugins = async (
    isActive: () => boolean = () => true,
    signal?: AbortSignal,
  ) => {
    try {
      const result = await listPlugins({ signal });
      if (!isActive()) return;
      setPlugins(result.items);
      setError(null);
    } catch (err) {
      if (isActive()) setError(describeApiError(err));
    } finally {
      if (isActive()) setLoading(false);
    }
  };

  useAsyncPolling(fetchPlugins, {
    intervalMs: PLUGINS_POLL_INTERVAL_MS,
    onError: (err) => {
      setError(describeApiError(err));
      setLoading(false);
    },
  });

  const handleAction = async (pluginId: string, action: 'install' | 'update' | 'uninstall') => {
    setOperating(pluginId);
    try {
      const fn = action === 'install' ? installPlugin
        : action === 'update' ? updatePlugin
        : uninstallPlugin;
      const result = await fn(pluginId);
      if (result.success) {
        showSnackbar(result.message || t('plugins.actionSuccess', '操作成功'), { tone: 'success' });
      } else {
        showSnackbar(result.message || t('plugins.actionFailed', '操作失败'), { tone: 'error' });
      }
      await fetchPlugins();
    } catch (err) {
      showSnackbar(describeApiError(err), { tone: 'error' });
    } finally {
      setOperating(null);
    }
  };

  const handleRescan = async () => {
    setLoading(true);
    try {
      const result = await rescanPlugins();
      setPlugins(result.items);
      showSnackbar(t('plugins.rescanDone', '扫描完成'), { tone: 'success' });
    } catch (err) {
      showSnackbar(describeApiError(err), { tone: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleCheckUpdate = async (pluginId: string) => {
    setCheckingUpdate(pluginId);
    try {
      const result = await checkPluginUpdate(pluginId);
      setPlugins((current) => current?.map((plugin) =>
        plugin.id === pluginId ? result.item : plugin,
      ) ?? current);
      if (result.item.has_update && result.item.latest_version) {
        showSnackbar(
          t('plugins.updateFound', `发现新版本：${result.item.latest_version}`),
          { tone: 'success' },
        );
      } else {
        showSnackbar(
          result.message || t('plugins.noUpdate', '未发现新版本'),
          { tone: 'success' },
        );
      }
    } catch (err) {
      showSnackbar(describeApiError(err), { tone: 'error' });
    } finally {
      setCheckingUpdate(null);
    }
  };

  const confirmActionLabel = confirmAction
    ? confirmAction.action === 'install'
      ? t('plugins.confirmInstall', '确认安装')
      : confirmAction.action === 'update'
        ? t('plugins.confirmUpdate', '确认更新')
        : t('plugins.confirmUninstall', '确认卸载')
    : '';

  const confirmActionBody = confirmAction
    ? confirmAction.action === 'install'
      ? t('plugins.confirmInstallBody', `将在本机安装 ${confirmAction.pluginName}，可能需要下载依赖文件。`)
      : confirmAction.action === 'update'
        ? t('plugins.confirmUpdateBody', `将更新 ${confirmAction.pluginName} 到最新版本。`)
        : t('plugins.confirmUninstallBody', `将从本机卸载 ${confirmAction.pluginName}，此操作不可撤销。`)
    : '';

  return (
    <main
      class="min-h-screen"
      style={{ background: 'var(--m3-background)', color: 'var(--m3-on-surface)' }}
    >
      <TopBar
        title={t('plugins.title', '插件服务')}
        subtitle={t('plugins.subtitle', '管理可选插件的安装、更新与卸载')}
      />

      <div class="max-w-4xl mx-auto px-4 py-6">
        <ErrorBanner message={error} />

        <div class="flex items-center justify-between mb-4">
          <p class="text-xs oh-text-muted">
            {t('plugins.scanHint', '自动扫描本机环境，已安装的插件将被识别并显示版本信息。')}
          </p>
          <button
            type="button"
            class="oh-tap-press text-sm px-3 py-1.5 rounded-m3-sm"
            style={{
              border: '1px solid var(--m3-outline-variant)',
              color: 'var(--m3-primary)',
            }}
            onClick={() => void handleRescan()}
            disabled={loading || !!operating}
          >
            {t('plugins.rescan', '重新扫描')}
          </button>
        </div>

        {loading && !plugins ? (
          <p class="text-sm oh-text-muted">
            {t('common.loading', '加载中…')}
          </p>
        ) : null}

        {plugins ? (
          <>
            <TemplatePluginSummary plugins={plugins} />
            <ul class="space-y-3">
              {plugins.map((plugin, idx) => {
                const badge = statusBadge(plugin.status);
                const isChecking = checkingUpdate === plugin.id;
                const isBusy = operating === plugin.id ||
                  isChecking ||
                  plugin.status === 'installing' ||
                  plugin.status === 'updating' ||
                  plugin.status === 'uninstalling';
                return (
                  <Appear key={plugin.id} variant="up" index={idx}>
                    <li class="oh-toolbox-card">
                    <div class="flex items-start justify-between gap-3">
                      <div class="flex items-start gap-3 flex-1 min-w-0">
                        <span style={{ fontSize: 24 }}>{pluginIcon(plugin.id)}</span>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-2 flex-wrap">
                            <h3 class="text-sm font-semibold oh-text-body">
                              {plugin.name}
                            </h3>
                            <span
                              class="oh-toolbox-badge"
                              style={{ color: badge.color, background: badge.bg }}
                            >
                              {badge.label}
                            </span>
                            {plugin.status === 'installed' ? (
                              <span
                                class="oh-toolbox-badge"
                                style={{
                                  color: plugin.enabled === false ? STATUS_WARNING_COLOR : STATUS_SUCCESS_COLOR,
                                  background: plugin.enabled === false ? STATUS_WARNING_BG : STATUS_SUCCESS_BG,
                                }}
                              >
                                {plugin.enabled === false ? t('plugins.disabled', '已禁用') : t('plugins.enabled', '可用')}
                              </span>
                            ) : null}
                            {(plugin.template_associations ?? []).map((association) => (
                              <span
                                key={association.template_id}
                                class="oh-toolbox-badge"
                                style={{ color: 'var(--m3-primary)', background: STATUS_ACTIVE_BG }}
                              >
                                {templateAssociationLabel(association)}
                              </span>
                            ))}
                          </div>
                          <p class="text-xs mt-1 oh-text-muted">
                            {plugin.description}
                          </p>
                          {plugin.installed_version ? (
                            <div class="oh-toolbox-meta-grid mt-2">
                              <div>{t('plugins.version', '版本')}: <code>{plugin.installed_version}</code></div>
                              {plugin.has_update && plugin.latest_version ? (
                                <div style={{ color: STATUS_WARNING_COLOR }}>
                                  {t('plugins.updateAvailable', '可更新到')}: <code>{plugin.latest_version}</code>
                                </div>
                              ) : null}
                              {plugin.install_path ? (
                                <div class="col-span-2">{t('plugins.path', '路径')}: <code>{plugin.install_path}</code></div>
                              ) : null}
                            </div>
                          ) : null}
                          {plugin.dependencies.length > 0 ? (
                            <div class="mt-2 flex items-center gap-1 flex-wrap">
                              <span class="text-[11px] oh-text-muted">
                                {t('plugins.dependsOn', '依赖')}:
                              </span>
                              {plugin.dependencies.map((dep) => {
                                const depPlugin = plugins.find((p) => p.id === dep);
                                const depInstalled = depPlugin?.status === 'installed';
                                return (
                                  <span
                                    key={dep}
                                    class="text-[10px] px-1.5 py-0.5 rounded-m3-xs"
                                    style={{
                                      background: depInstalled ? STATUS_SUCCESS_BG : STATUS_ERROR_BG,
                                      color: depInstalled ? STATUS_SUCCESS_COLOR : 'var(--m3-error)',
                                    }}
                                  >
                                    {depPlugin?.name || dep} {depInstalled ? '✓' : '✗'}
                                  </span>
                                );
                              })}
                            </div>
                          ) : null}
                          {plugin.error_message ? (
                            <p class="text-xs mt-2 oh-text-error">
                              {plugin.error_message}
                            </p>
                          ) : null}
                        </div>
                      </div>
                      <div class="flex items-center gap-2 flex-shrink-0">
                        {plugin.status === 'installed' ? (
                          <button
                            type="button"
                            class="oh-tap-press text-sm px-3 py-1.5 rounded-m3-sm inline-flex items-center gap-2"
                            style={{
                              border: '1px solid var(--m3-outline-variant)',
                              color: 'var(--m3-primary)',
                              opacity: isBusy ? 0.6 : 1,
                            }}
                            disabled={isBusy}
                            onClick={() => void handleCheckUpdate(plugin.id)}
                          >
                            {isChecking ? <span class="animate-spin">↻</span> : null}
                            {t('plugins.checkUpdate', '检查更新')}
                          </button>
                        ) : null}
                        {plugin.status === 'notInstalled' ? (
                          <button
                            type="button"
                            class="oh-tap-press text-sm px-3 py-1.5 rounded-m3-sm"
                            style={{
                              background: 'var(--m3-primary)',
                              color: 'var(--m3-on-primary)',
                              opacity: isBusy ? 0.6 : 1,
                            }}
                            disabled={isBusy}
                            onClick={() => setConfirmAction({
                              pluginId: plugin.id,
                              pluginName: plugin.name,
                              action: 'install',
                            })}
                          >
                            {t('plugins.install', '安装')}
                          </button>
                        ) : plugin.status === 'installed' ? (
                          <>
                            {plugin.has_update ? (
                              <button
                                type="button"
                                class="oh-tap-press text-sm px-3 py-1.5 rounded-m3-sm"
                                style={{
                                  background: 'var(--m3-secondary-container)',
                                  color: 'var(--m3-on-secondary-container)',
                                  opacity: isBusy ? 0.6 : 1,
                                }}
                                disabled={isBusy}
                                onClick={() => setConfirmAction({
                                  pluginId: plugin.id,
                                  pluginName: plugin.name,
                                  action: 'update',
                                })}
                              >
                                {t('plugins.update', '更新')}
                              </button>
                            ) : null}
                            {plugin.supports_uninstall ? (
                              <button
                                type="button"
                                class="oh-tap-press text-sm px-3 py-1.5 rounded-m3-sm"
                                style={{
                                  border: '1px solid var(--m3-outline-variant)',
                                  color: 'var(--m3-error)',
                                  opacity: isBusy ? 0.6 : 1,
                                }}
                                disabled={isBusy}
                                onClick={() => setConfirmAction({
                                  pluginId: plugin.id,
                                  pluginName: plugin.name,
                                  action: 'uninstall',
                                })}
                              >
                                {t('plugins.uninstall', '卸载')}
                              </button>
                            ) : null}
                          </>
                        ) : isBusy ? (
                          <span class="text-xs oh-text-primary">
                            ⏳
                          </span>
                        ) : null}
                      </div>
                    </div>
                    </li>
                  </Appear>
                );
              })}
            </ul>
          </>
        ) : null}
      </div>

      {confirmAction ? (
        <ConfirmDialog
          title={confirmActionLabel}
          body={confirmActionBody}
          confirmLabel={confirmActionLabel}
          danger={confirmAction.action === 'uninstall'}
          onConfirm={() => {
            const { pluginId, action } = confirmAction;
            setConfirmAction(null);
            void handleAction(pluginId, action);
          }}
          onCancel={() => setConfirmAction(null)}
        />
      ) : null}
    </main>
  );
}
