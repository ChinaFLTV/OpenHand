// Toolbox 相关 API: MCP 服务器 / 已安装技能 / 用户记忆 / 定时任务
// 一律只读, 与服务端 _listMcpServersHandler 等一一对齐。

import { apiRequest } from './client';

export interface McpServerSummary {
  name: string;
  type: string;
  enabled: boolean;
  summary: string;
  url?: string;
  command?: string;
  args?: string[];
  tool_count: number;
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

export function listMcpServers(): Promise<{ items: McpServerSummary[] }> {
  return apiRequest<{ items: McpServerSummary[] }>('/api/mcp/servers');
}
export function listSkills(): Promise<{ items: SkillSummary[]; storage_path: string }> {
  return apiRequest<{ items: SkillSummary[]; storage_path: string }>('/api/skills');
}
export function listMemories(): Promise<{ items: MemoryEntrySummary[] }> {
  return apiRequest<{ items: MemoryEntrySummary[] }>('/api/memories');
}
export function listCrons(): Promise<{ items: CronEntrySummary[] }> {
  return apiRequest<{ items: CronEntrySummary[] }>('/api/crons');
}
