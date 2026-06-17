// Plugin Service API: 查询插件状态、触发安装/更新/卸载操作。
// 与服务端 _listPluginsHandler / _pluginActionHandler 对齐。

import {
  LONG_API_REQUEST_TIMEOUT_MS,
  apiRequest,
  type ApiRequestSignalOptions,
} from './client';

export type PluginStatus =
  | 'notInstalled'
  | 'installed'
  | 'installing'
  | 'updating'
  | 'uninstalling'
  | 'error';

export interface PluginSummary {
  id: string;
  name: string;
  description: string;
  status: PluginStatus;
  installed_version: string | null;
  latest_version: string | null;
  install_path: string | null;
  dependencies: string[];
  dependents: string[];
  supports_uninstall: boolean;
  error_message: string | null;
  has_update: boolean;
}

export interface PluginActionResult {
  success: boolean;
  message: string | null;
  new_version: string | null;
}

export interface PluginCheckUpdateResult {
  success: boolean;
  message: string | null;
  item: PluginSummary;
}

export function listPlugins(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: PluginSummary[] }> {
  return apiRequest<{ items: PluginSummary[] }>('/api/plugins', options);
}

export function installPlugin(pluginId: string): Promise<PluginActionResult> {
  return apiRequest<PluginActionResult>('/api/plugins/install', {
    method: 'POST',
    body: { plugin_id: pluginId },
    timeoutMs: LONG_API_REQUEST_TIMEOUT_MS,
  });
}

export function updatePlugin(pluginId: string): Promise<PluginActionResult> {
  return apiRequest<PluginActionResult>('/api/plugins/update', {
    method: 'POST',
    body: { plugin_id: pluginId },
    timeoutMs: LONG_API_REQUEST_TIMEOUT_MS,
  });
}

export function uninstallPlugin(pluginId: string): Promise<PluginActionResult> {
  return apiRequest<PluginActionResult>('/api/plugins/uninstall', {
    method: 'POST',
    body: { plugin_id: pluginId },
  });
}

export function rescanPlugins(): Promise<{ items: PluginSummary[] }> {
  return apiRequest<{ items: PluginSummary[] }>('/api/plugins/rescan', {
    method: 'POST',
    timeoutMs: LONG_API_REQUEST_TIMEOUT_MS,
  });
}

export function checkPluginUpdate(pluginId: string): Promise<PluginCheckUpdateResult> {
  return apiRequest<PluginCheckUpdateResult>('/api/plugins/check-update', {
    method: 'POST',
    body: { plugin_id: pluginId },
  });
}
