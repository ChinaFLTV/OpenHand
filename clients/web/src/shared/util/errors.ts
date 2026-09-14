import { recordOrNullFromUnknown } from './value';

export function isAbortError(error: unknown): boolean {
  if (error instanceof Error && error.name === 'AbortError') return true;
  return recordOrNullFromUnknown(error)?.name === 'AbortError';
}

export function ignoreError(_error?: unknown): void {}

export function runIgnoringErrors(action: () => void): boolean {
  try {
    action();
    return true;
  } catch {
    return false;
  }
}
