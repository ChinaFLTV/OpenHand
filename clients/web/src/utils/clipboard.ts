import { runWithTimeout } from './timed_abort';

const DEFAULT_COPY_TEXT_TIMEOUT_MS = 2500;
const DEFAULT_COPY_BLOB_TIMEOUT_MS = 5000;

export async function copyTextToClipboard(
  text: string,
  timeoutMs = DEFAULT_COPY_TEXT_TIMEOUT_MS,
): Promise<boolean> {
  if (!text) return false;
  try {
    return await runWithTimeout(() => copyTextToClipboardNow(text), {
      timeoutMs,
    });
  } catch {
    return false;
  }
}

async function copyTextToClipboardNow(text: string): Promise<boolean> {
  if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      // 权限被拒或 API 不可用时继续尝试兼容路径。
    }
  }
  return copyTextViaExecCommand(text);
}

function copyTextViaExecCommand(text: string): boolean {
  if (typeof document === 'undefined') return false;
  try {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', 'true');
    textarea.style.position = 'fixed';
    textarea.style.top = '0';
    textarea.style.left = '0';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    const previousFocus = document.activeElement as HTMLElement | null;
    textarea.focus();
    textarea.select();
    let ok = false;
    try {
      ok = document.execCommand('copy');
    } catch {
      ok = false;
    }
    textarea.remove();
    previousFocus?.focus?.();
    return ok;
  } catch {
    return false;
  }
}

/// 在明确时限内把 blob 写到系统剪贴板。
export async function copyBlobToClipboard(
  blob: Blob,
  timeoutMs = DEFAULT_COPY_BLOB_TIMEOUT_MS,
): Promise<boolean> {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') {
    return false;
  }
  if (!(blob instanceof Blob) || blob.size === 0) {
    return false;
  }
  if ('ClipboardItem' in window && navigator.clipboard?.write) {
    try {
      return await runWithTimeout(
        async () => {
          await navigator.clipboard.write([
            new ClipboardItem({ [blob.type]: blob }),
          ]);
          return true;
        },
        { timeoutMs },
      );
    } catch {
      return false;
    }
  }
  return false;
}
