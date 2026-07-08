import { ApiError } from '../api/client';
import { OperationTimeoutError } from './timed_abort';
import {
  nonBlankStringFromUnknown,
  recordOrNullFromUnknown,
} from '../shared/util/value';
export { isAbortError } from '../shared/util/errors';

interface ApiErrorBody {
  error?: unknown;
  message?: unknown;
  detail?: unknown;
}

function apiFieldMessage(value: unknown): string | null {
  return nonBlankStringFromUnknown(value, { coerce: false });
}

function apiBodyMessage(body: unknown): string | null {
  if (typeof body === 'string') return nonBlankStringFromUnknown(body);
  const typed = recordOrNullFromUnknown(body) as ApiErrorBody | null;
  if (typed == null) return null;
  return (
    apiFieldMessage(typed.message) ??
    apiFieldMessage(typed.error) ??
    apiFieldMessage(typed.detail)
  );
}

export function describeApiError(error: unknown): string {
  if (error instanceof OperationTimeoutError) {
    return `请求超时（${Math.round(error.timeoutMs / 1000)} 秒）`;
  }
  if (error instanceof ApiError) {
    const message = apiBodyMessage(error.body);
    return `HTTP ${error.status}${message == null ? '' : ` (${message})`}`;
  }
  if (error instanceof Error) {
    return nonBlankStringFromUnknown(error.message) ?? error.name;
  }
  return String(error);
}
