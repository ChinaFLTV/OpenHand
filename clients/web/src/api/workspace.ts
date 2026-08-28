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
  operations_enabled?: boolean;
  write_enabled: boolean;
  max_file_bytes: number;
  allowed_extensions: string[];
}

interface WorkspaceReadResponse {
  path: string;
  content: string;
  size: number;
  modified_at: string;
}

interface WorkspaceWriteResponse {
  ok: boolean;
  path: string;
  size: number;
  modified_at: string;
}

interface WorkspaceDirectoryResponse {
  ok: boolean;
  path: string;
  modified_at: string;
}

interface ListFilesOptions {
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

export function createWorkspaceDirectory(path: string): Promise<WorkspaceDirectoryResponse> {
  return apiRequest<WorkspaceDirectoryResponse>('/api/workspace/directory', {
    method: 'POST',
    body: { path },
  });
}

interface WorkspaceDeleteResponse {
  ok: boolean;
  path: string;
}

export function deleteWorkspaceFile(path: string): Promise<WorkspaceDeleteResponse> {
  return apiRequest<WorkspaceDeleteResponse>(
    `/api/workspace/file?path=${encodeURIComponent(path)}`,
    { method: 'DELETE' },
  );
}
