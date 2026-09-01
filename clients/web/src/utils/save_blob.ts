import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';

export interface SaveBlobPickerType {
  description: string;
  accept: Record<string, string[]>;
}

interface SaveBlobResult {
  filename: string;
  picked: boolean;
}

interface FileSystemWritableFileStream {
  write(data: Blob): Promise<void>;
  close(): Promise<void>;
  abort?(): Promise<void>;
}

interface FileSystemFileHandle {
  name: string;
  createWritable(): Promise<FileSystemWritableFileStream>;
}

interface SaveFilePickerOptions {
  suggestedName?: string;
  types?: SaveBlobPickerType[];
}

type SaveFilePicker = (options?: SaveFilePickerOptions) => Promise<FileSystemFileHandle>;

const DEFAULT_OBJECT_URL_REVOKE_DELAY_MS = 5_000;
const MAX_DOWNLOAD_FILENAME_BYTES = 240;
const INVALID_DOWNLOAD_FILENAME_CHARACTERS = /[\u0000-\u001f\u007f<>:"/\\|?*]+/g;
const WINDOWS_RESERVED_FILENAME = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i;

function truncateFilenameUtf8(filename: string): string {
  const encoder = new TextEncoder();
  if (encoder.encode(filename).byteLength <= MAX_DOWNLOAD_FILENAME_BYTES) {
    return filename;
  }
  const extensionIndex = filename.lastIndexOf('.');
  const extension = extensionIndex > 0 && filename.length - extensionIndex <= 20
    ? filename.slice(extensionIndex)
    : '';
  const extensionBytes = encoder.encode(extension).byteLength;
  const baseBudget = Math.max(1, MAX_DOWNLOAD_FILENAME_BYTES - extensionBytes);
  const base = extension ? filename.slice(0, extensionIndex) : filename;
  const retained: string[] = [];
  let retainedBytes = 0;
  for (const character of base) {
    const characterBytes = encoder.encode(character).byteLength;
    if (retainedBytes + characterBytes > baseBudget) break;
    retained.push(character);
    retainedBytes += characterBytes;
  }
  return `${retained.join('')}${extension}`;
}

function normalizeRevokeDelayMs(value: number | undefined): number {
  return normalizeDurationMs(value, {
    fallback: DEFAULT_OBJECT_URL_REVOKE_DELAY_MS,
    max: MAX_BROWSER_TIMEOUT_MS,
  });
}

export function revokeObjectUrlQuietly(url: string | null | undefined): void {
  if (!url) return;
  try {
    URL.revokeObjectURL(url);
  } catch {
    // 对象 URL 清理失败不应中断用户操作。
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
      return sanitizeDownloadFilename(decodeURIComponent(encoded[1]));
    } catch {
      return sanitizeDownloadFilename(encoded[1]);
    }
  }
  const quoted = /filename="([^"]+)"/i.exec(value);
  if (quoted?.[1]) return sanitizeDownloadFilename(quoted[1]);
  const plain = /filename=([^;]+)/i.exec(value);
  return plain?.[1] ? sanitizeDownloadFilename(plain[1]) : null;
}

export function sanitizeDownloadFilename(
  value: string,
  fallback = 'download',
): string {
  let safeFallback = fallback
    .trim()
    .replace(INVALID_DOWNLOAD_FILENAME_CHARACTERS, '_')
    .replace(/[. ]+$/g, '');
  if (!safeFallback || safeFallback === '.' || safeFallback === '..') {
    safeFallback = 'download';
  }
  if (WINDOWS_RESERVED_FILENAME.test(safeFallback)) {
    safeFallback = `_${safeFallback}`;
  }
  let filename = value
    .trim()
    .replace(INVALID_DOWNLOAD_FILENAME_CHARACTERS, '_')
    .replace(/[. ]+$/g, '');
  if (!filename || filename === '.' || filename === '..') {
    filename = safeFallback;
  }
  if (WINDOWS_RESERVED_FILENAME.test(filename)) filename = `_${filename}`;
  filename = truncateFilenameUtf8(filename);
  return filename || safeFallback;
}

export function downloadBlobWithAnchor(
  blob: Blob,
  filename: string,
  revokeDelayMs?: number,
): void {
  const safeFilename = sanitizeDownloadFilename(filename);
  const url = URL.createObjectURL(blob);
  try {
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = safeFilename;
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
  const normalizedFilename = sanitizeDownloadFilename(filename);
  const suggestedName = sanitizeDownloadFilename(
    pickerSuggestedName ?? normalizedFilename,
    normalizedFilename,
  );
  const picker = (window as Window & { showSaveFilePicker?: SaveFilePicker }).showSaveFilePicker;
  if (picker) {
    let writable: FileSystemWritableFileStream | null = null;
    try {
      const handle = await picker({ suggestedName, types });
      writable = await handle.createWritable();
      await writable.write(blob);
      await writable.close();
      return { filename: handle.name.trim() || normalizedFilename, picked: true };
    } catch (error) {
      await abortWritableQuietly(writable);
      throw error;
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
    // 流中止失败不覆盖原始保存错误。
  }
}
