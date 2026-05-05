// 工作区文件浏览/读取/写入/删除。对应 service：
//   GET    /api/workspace/files?path=&q=&type=&extensions=
//   GET    /api/workspace/file?path=
//   PUT    /api/workspace/file body {path, content}    — 创建 / 覆写（受 write_enabled）
//   DELETE /api/workspace/file?path=                    — 删除文件 / 空目录（受 write_enabled）
//
// 设计决定：
// - 列表只返回最多 300 项（由 service 兜底）；前端不再二次截断。
// - 读取被 service 拦截二进制；前端遇到 binary_file_not_supported 时用提示卡退 化。
// - 写入超出 max_file_bytes 时 service 回 content_too_large；前端在 byte 级
//   做一次预判，避免无谓的请求往返。
// - 创建新文件复用 PUT（path 不存在时 service 自动创建父目录 + 写入）。

import { apiRequest } from './client';

export interface WorkspaceItem {
  name: string;
  path: string;
  type: 'file' | 'directory';
  size: number;
  modified_at: string;
  extension?: string;
  editable?: boolean;
}

export interface WorkspaceListResponse {
  root: string;
  path: string;
  items: WorkspaceItem[];
  query: string;
  type: string;
  write_enabled: boolean;
  max_file_bytes: number;
  allowed_extensions: string[];
}

export interface WorkspaceReadResponse {
  path: string;
  content: string;
  size: number;
  modified_at: string;
}

export interface WorkspaceWriteResponse {
  ok: boolean;
  path: string;
  size: number;
  modified_at: string;
}

export interface ListFilesOptions {
  path?: string;
  q?: string;
  type?: 'all' | 'file' | 'directory';
  extensions?: string[];
}

export function listWorkspaceFiles(
  options: ListFilesOptions = {},
): Promise<WorkspaceListResponse> {
  const params = new URLSearchParams();
  if (options.path != null) params.set('path', options.path);
  if (options.q) params.set('q', options.q);
  if (options.type) params.set('type', options.type);
  if (options.extensions && options.extensions.length > 0) {
    params.set('extensions', options.extensions.join(','));
  }
  const qs = params.toString();
  return apiRequest<WorkspaceListResponse>(
    `/api/workspace/files${qs ? `?${qs}` : ''}`,
  );
}

export function readWorkspaceFile(path: string): Promise<WorkspaceReadResponse> {
  return apiRequest<WorkspaceReadResponse>(
    `/api/workspace/file?path=${encodeURIComponent(path)}`,
  );
}

export function writeWorkspaceFile(
  path: string,
  content: string,
): Promise<WorkspaceWriteResponse> {
  return apiRequest<WorkspaceWriteResponse>('/api/workspace/file', {
    method: 'PUT',
    body: { path, content },
  });
}

export interface WorkspaceDeleteResponse {
  ok: boolean;
  path: string;
}

export function deleteWorkspaceFile(path: string): Promise<WorkspaceDeleteResponse> {
  return apiRequest<WorkspaceDeleteResponse>(
    `/api/workspace/file?path=${encodeURIComponent(path)}`,
    { method: 'DELETE' },
  );
}
