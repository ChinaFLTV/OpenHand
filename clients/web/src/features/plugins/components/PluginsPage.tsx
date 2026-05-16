// PluginsPage —— 插件服务管理页面。
//
// 展示可选插件（NodeJS / Playwright）的安装状态，支持安装、更新、卸载操作。
// 5 秒轮询刷新状态，操作期间实时反馈进度。UI 风格与 ToolboxPage 保持一致。

import { useEffect, useState } from 'preact/hooks';
import { TopBar } from '../../../components/TopBar';
import { Appear } from '../../../components/Appear';
import { ConfirmDialog } from '../../../components/ConfirmDialog';
import {
  PluginSummary,
  PluginStatus,
  listPlugins,
  installPlugin,
  updatePlugin,
  uninstallPlugin,
  rescanPlugins,
} from '../../../api/plugins';
import { t } from '../../../i18n';
import { showSnackbar } from '../../../components/Snackbar';

function statusBadge(status: PluginStatus): { color: string; bg: string; label: string } {
  switch (status) {
    case 'installed':
      return { color: '#16a34a', bg: 'rgba(22,163,74,0.10)', label: t('plugins.status.installed', '已安装') };
    case 'notInstalled':
      return { color: 'var(--m3-on-surface-variant)', bg: 'rgba(120,120,120,0.10)', label: t('plugins.status.notInstalled', '未安装') };
    case 'installing':
      return { color: 'var(--m3-primary)', bg: 'rgba(99,102,241,0.10)', label: t('plugins.status.installing', '安装中…') };
    case 'updating':
      return { color: 'var(--m3-primary)', bg: 'rgba(99,102,241,0.10)', label: t('plugins.status.updating', '更新中…') };
    case 'uninstalling':
      return { color: '#f59e0b', bg: 'rgba(245,158,11,0.10)', label: t('plugins.status.uninstalling', '卸载中…') };
    case 'error':
      return { color: 'var(--m3-error)', bg: 'rgba(239,68,68,0.10)', label: t('plugins.status.error', '错误') };
    default:
      return { color: 'var(--m3-on-surface-variant)', bg: 'rgba(120,120,120,0.06)', label: status };
  }
}

function pluginIcon(id: string): string {
  switch (id) {
    case 'nodejs': return '⬢';
    case 'playwright': return '🎭';
    default: return '🧩';
  }
}

export function PluginsPage() {
  const [plugins, setPlugins] = useState<PluginSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [operating, setOperating] = useState<string | null>(null);
  const [confirmAction, setConfirmAction] = useState<{
    pluginId: string;
    pluginName: string;
    action: 'install' | 'update' | 'uninstall';
  } | null>(null);

  const fetchPlugins = async () => {
    try {
      const result = await listPlugins();
      setPlugins(result.items);
      setError(null);
    } catch (err) {
      if (!plugins) setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let stop = false;
    let timer: ReturnType<typeof setTimeout> | null = null;

    const tick = async () => {
      await fetchPlugins();
      if (!stop) timer = setTimeout(tick, 5000);
    };
    void tick();

    return () => {
      stop = true;
      if (timer) clearTimeout(timer);
    };
  }, []);

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
      showSnackbar(err instanceof Error ? err.message : String(err), { tone: 'error' });
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
      showSnackbar(err instanceof Error ? err.message : String(err), { tone: 'error' });
    } finally {
      setLoading(false);
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

        {/* 操作栏 */}
        <div class="flex items-center justify-between mb-4">
          <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {t('common.loading', '加载中…')}
          </p>
        ) : null}

        {plugins ? (
          <ul class="space-y-3">
            {plugins.map((plugin, idx) => {
              const badge = statusBadge(plugin.status);
              const isBusy = operating === plugin.id ||
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
                            <h3 class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
                              {plugin.name}
                            </h3>
                            <span
                              class="oh-toolbox-badge"
                              style={{ color: badge.color, background: badge.bg }}
                            >
                              {badge.label}
                            </span>
                          </div>
                          <p class="text-xs mt-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
                            {plugin.description}
                          </p>
                          {/* 版本信息 */}
                          {plugin.installed_version ? (
                            <div class="oh-toolbox-meta-grid mt-2">
                              <div>{t('plugins.version', '版本')}: <code>{plugin.installed_version}</code></div>
                              {plugin.has_update && plugin.latest_version ? (
                                <div style={{ color: '#f59e0b' }}>
                                  {t('plugins.updateAvailable', '可更新到')}: <code>{plugin.latest_version}</code>
                                </div>
                              ) : null}
                              {plugin.install_path ? (
                                <div class="col-span-2">{t('plugins.path', '路径')}: <code>{plugin.install_path}</code></div>
                              ) : null}
                            </div>
                          ) : null}
                          {/* 依赖信息 */}
                          {plugin.dependencies.length > 0 ? (
                            <div class="mt-2 flex items-center gap-1 flex-wrap">
                              <span class="text-[11px]" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
                                      background: depInstalled ? 'rgba(22,163,74,0.10)' : 'rgba(239,68,68,0.10)',
                                      color: depInstalled ? '#16a34a' : 'var(--m3-error)',
                                    }}
                                  >
                                    {depPlugin?.name || dep} {depInstalled ? '✓' : '✗'}
                                  </span>
                                );
                              })}
                            </div>
                          ) : null}
                          {/* 错误信息 */}
                          {plugin.error_message ? (
                            <p class="text-xs mt-2" style={{ color: 'var(--m3-error)' }}>
                              {plugin.error_message}
                            </p>
                          ) : null}
                        </div>
                      </div>
                      {/* 操作按钮 */}
                      <div class="flex items-center gap-2 flex-shrink-0">
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
                          </>
                        ) : isBusy ? (
                          <span class="text-xs" style={{ color: 'var(--m3-primary)' }}>
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
        ) : null}
      </div>

      {/* 确认弹窗 */}
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
