import { recordOrNullFromUnknown } from './value';

export function isAbortError(error: unknown): boolean {
  if (error instanceof Error && error.name === 'AbortError') return true;
  return recordOrNullFromUnknown(error)?.name === 'AbortError';
}
