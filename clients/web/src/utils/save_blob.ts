import { normalizeDurationMs } from '../shared/util/number';
import { isAbortError } from './api_error';

export interface SaveBlobPickerType {
  description: string;
  accept: Record<string, string[]>;
}

export interface SaveBlobResult {
  filename: string;
  picked: boolean;
}

interface FileSystemWritableFileStream {
  write(data: Blob): Promise<void>;
  close(): Promise<void>;
  abort?(): Promise<void>;
}

interface FileSystemFileHandle {
  createWritable(): Promise<FileSystemWritableFileStream>;
}

interface SaveFilePickerOptions {
  suggestedName?: string;
  types?: SaveBlobPickerType[];
}

type SaveFilePicker = (options?: SaveFilePickerOptions) => Promise<FileSystemFileHandle>;

const DEFAULT_OBJECT_URL_REVOKE_DELAY_MS = 5_000;

function normalizeRevokeDelayMs(value: number | undefined): number {
  return normalizeDurationMs(value, {
    fallback: DEFAULT_OBJECT_URL_REVOKE_DELAY_MS,
  });
}

export function revokeObjectUrlQuietly(url: string | null | undefined): void {
  if (!url) return;
  try {
    URL.revokeObjectURL(url);
  } catch {
    // Object URL cleanup is best-effort; callers should not fail user actions.
  }
}

export function scheduleObjectUrlRevoke(
  url: string,
  delayMs?: number,
): void {
  const safeDelayMs = normalizeRevokeDelayMs(delayMs);
  if (safeDelayMs <= 0 || typeof window === 'undefined') {
    revokeObjectUrlQuietly(url);
    return;
  }
  window.setTimeout(() => revokeObjectUrlQuietly(url), safeDelayMs);
}

export function filenameFromContentDisposition(value: string | null): string | null {
  if (!value) return null;
  const encoded = /filename\*=UTF-8''([^;]+)/i.exec(value);
  if (encoded?.[1]) {
    try {
      return decodeURIComponent(encoded[1]);
    } catch {
      return encoded[1];
    }
  }
  const quoted = /filename="([^"]+)"/i.exec(value);
  if (quoted?.[1]) return quoted[1];
  const plain = /filename=([^;]+)/i.exec(value);
  return plain?.[1]?.trim() ?? null;
}

export function downloadBlobWithAnchor(
  blob: Blob,
  filename: string,
  revokeDelayMs?: number,
): void {
  const url = URL.createObjectURL(blob);
  try {
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    scheduleObjectUrlRevoke(url, revokeDelayMs);
  }
}

export async function saveBlobWithPicker(
  blob: Blob,
  filename: string,
  types?: SaveBlobPickerType[],
  pickerSuggestedName?: string,
): Promise<SaveBlobResult> {
  const normalizedFilename = filename.trim() || 'download';
  const suggestedName = pickerSuggestedName?.trim() || normalizedFilename;
  const picker = (window as Window & { showSaveFilePicker?: SaveFilePicker }).showSaveFilePicker;
  if (picker) {
    let writable: FileSystemWritableFileStream | null = null;
    try {
      const handle = await picker({ suggestedName, types });
      writable = await handle.createWritable();
      await writable.write(blob);
      await writable.close();
      return { filename: normalizedFilename, picked: true };
    } catch (error) {
      await abortWritableQuietly(writable);
      if (isAbortError(error)) {
        throw error;
      }
    }
  }
  downloadBlobWithAnchor(blob, normalizedFilename);
  return { filename: normalizedFilename, picked: false };
}

async function abortWritableQuietly(
  writable: FileSystemWritableFileStream | null,
): Promise<void> {
  try {
    await writable?.abort?.();
  } catch {
    // Fallback download should still proceed when stream abort cleanup fails.
  }
}
