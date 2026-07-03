import { ApiError } from '../api/client';

interface ApiErrorBody {
  error?: unknown;
  message?: unknown;
  detail?: unknown;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null;
}

function nonBlankText(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return text.length > 0 ? text : null;
}

function apiBodyMessage(body: unknown): string | null {
  if (typeof body === 'string') return nonBlankText(body);
  if (!isRecord(body)) return null;
  const typed = body as ApiErrorBody;
  return (
    nonBlankText(typed.message) ??
    nonBlankText(typed.error) ??
    nonBlankText(typed.detail)
  );
}

export function describeApiError(error: unknown): string {
  if (error instanceof ApiError) {
    const message = apiBodyMessage(error.body);
    return `HTTP ${error.status}${message == null ? '' : ` (${message})`}`;
  }
  if (error instanceof Error) {
    return nonBlankText(error.message) ?? error.name;
  }
  return String(error);
}

export function isAbortError(error: unknown): boolean {
  if (error instanceof Error && error.name === 'AbortError') return true;
  if (!isRecord(error)) return false;
  return error.name === 'AbortError';
}
