// Toolbox 相关 API: MCP 服务器 / 已安装技能 / 用户记忆 / 定时任务
// 一律只读, 与服务端 _listMcpServersHandler 等一一对齐。

import { apiRequest, type ApiRequestSignalOptions } from './client';

export interface McpServerSummary {
  name: string;
  type: string;
  enabled: boolean;
  summary: string;
  url?: string;
  command?: string;
  args?: string[];
  tool_count: number;
  template_associations?: TemplateMcpAssociation[];
}

export interface BuiltinToolSummary {
  id: string;
  name: string;
  kind: string;
  enabled: boolean;
  load_strategy: string;
}

interface TemplateMcpAssociation {
  template_id: string;
  label_zh?: string;
  label_en?: string;
  capabilities?: TemplateMcpCapability[];
}

interface TemplateMcpCapability {
  id: string;
  label_zh?: string;
  label_en?: string;
  package_name?: string;
  openhand_managed?: boolean;
}

export interface SkillSummary {
  name: string;
  description: string;
  directory_path: string;
  relative_directory_path: string;
  has_default_prompt: boolean;
  emoji_icon?: string | null;
}

export interface MemoryEntrySummary {
  id: string;
  type: string;
  title: string;
  preview: string;
  tags: string[];
  created_at: string;
  is_user_profile: boolean;
  is_auto_learned: boolean;
}

export interface CronEntrySummary {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  status: string;
  cron_expression: string;
  script_type: string;
  tags: string[];
  last_run_at: string | null;
  next_run_at: string | null;
  last_exit_code: number | null;
  consecutive_failures: number;
}

export interface HookEntrySummary {
  id: string;
  label: string;
  event: string;
  enabled: boolean;
  timeout_seconds: number;
}

export interface KnowledgeSourceSummary {
  id: string;
  title: string;
  kind: string;
  status: string;
  size_bytes: number;
  updated_at: string;
}

export type ResourceUsageKind = 'tool' | 'skill' | 'hook' | 'knowledge' | 'memory' | 'mcp';
export type ResourceUsageLevel = 'session' | 'day' | 'week' | 'month' | 'quarter' | 'year';

interface ResourceUsageTrendPoint {
  bucket: string;
  total: number;
  successes: number;
  failures: number;
}

export interface ResourceUsageResourceSnapshot {
  resource_id: string;
  total: number;
  successes: number;
  failures: number;
  success_rate: number | null;
  average_duration_ms: number;
  duration_sample_count: number;
  max_duration_ms: number;
  session_count: number;
  last_called_at: string | null;
  sub_resources: ResourceUsageResourceSnapshot[];
}

export interface ResourceUsageEvent {
  event_id: string;
  kind: ResourceUsageKind;
  resource_id: string;
  sub_resource_id: string;
  session_id: string;
  tool_call_id: string;
  tool_name: string;
  occurred_at: string;
  status: string;
  succeeded: boolean;
  duration_ms: number;
  arguments_summary: string;
  result_summary: string;
  error_summary: string;
  source: string;
}

export interface ResourceUsageLevelSnapshot {
  level: ResourceUsageLevel;
  bucket: string;
  total: number;
  resource_count: number;
  successes: number;
  failures: number;
  success_rate: number | null;
  average_duration_ms: number;
  duration_sample_count: number;
  max_duration_ms: number;
  p95_duration_ms: number;
  session_count: number;
  counts: Record<string, number>;
  trend: ResourceUsageTrendPoint[];
  resources: ResourceUsageResourceSnapshot[];
  recent_events: ResourceUsageEvent[];
}

export interface ResourceUsageSnapshot {
  kind: ResourceUsageKind;
  generated_at: string;
  levels: Record<ResourceUsageLevel, ResourceUsageLevelSnapshot>;
}

export function listMcpServers(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: McpServerSummary[] }> {
  return apiRequest<{ items: McpServerSummary[] }>('/api/mcp/servers', options);
}
export function listBuiltinTools(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: BuiltinToolSummary[] }> {
  return apiRequest<{ items: BuiltinToolSummary[] }>('/api/tools', options);
}
export function listSkills(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: SkillSummary[]; storage_path: string }> {
  return apiRequest<{ items: SkillSummary[]; storage_path: string }>('/api/skills', options);
}
export function listMemories(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: MemoryEntrySummary[] }> {
  return apiRequest<{ items: MemoryEntrySummary[] }>('/api/memories', options);
}
export function listCrons(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: CronEntrySummary[] }> {
  return apiRequest<{ items: CronEntrySummary[] }>('/api/crons', options);
}

export function listHooks(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: HookEntrySummary[] }> {
  return apiRequest<{ items: HookEntrySummary[] }>('/api/hooks', options);
}

export function listKnowledgeSources(
  options: ApiRequestSignalOptions = {},
): Promise<{ items: KnowledgeSourceSummary[] }> {
  return apiRequest<{ items: KnowledgeSourceSummary[] }>('/api/knowledge/sources', options);
}

export function getResourceUsage(
  kind: ResourceUsageKind,
  options: ApiRequestSignalOptions = {},
): Promise<ResourceUsageSnapshot> {
  return apiRequest<ResourceUsageSnapshot>(`/api/resource-usage?kind=${encodeURIComponent(kind)}`, options);
}
