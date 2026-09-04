import { runWithTimeout } from './timed_abort';

export const DEFAULT_COPY_TEXT_TIMEOUT_MS = 2500;

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
  let modernWriteSucceeded = false;
  if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      modernWriteSucceeded = true;
      if (typeof navigator.clipboard.readText === 'function') {
        try {
          if ((await navigator.clipboard.readText()) === text) return true;
          modernWriteSucceeded = false;
        } catch {
          // 无法校验时继续尝试兼容路径。
        }
      }
    } catch {
      modernWriteSucceeded = false;
    }
  }
  const fallbackOk = copyTextViaExecCommand(text);
  if (fallbackOk) return true;
  return modernWriteSucceeded;
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

/// 把任意 blob 写到系统剪贴板（image/png / image/svg+xml 等）。
/// 优先走 navigator.clipboard.write（剪贴板富媒体）；旧浏览器或
/// 权限拒绝时回退为纯文本提示。
export async function copyBlobToClipboard(blob: Blob): Promise<boolean> {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') {
    return false;
  }
  if (!(blob instanceof Blob) || blob.size === 0) {
    return false;
  }
  if ('ClipboardItem' in window && navigator.clipboard?.write) {
    try {
      await navigator.clipboard.write([new ClipboardItem({ [blob.type]: blob })]);
      if (typeof navigator.clipboard?.read === 'function') {
        try {
          const items = await navigator.clipboard.read();
          for (const item of items) {
            for (const type of item.types) {
              if (type === blob.type) {
                const readBack = await item.getType(type);
                if (readBack.size === blob.size) return true;
              }
            }
          }
        } catch {
          // read 权限被拒不代表 write 失败。
        }
      }
      return true;
    } catch {
      return false;
    }
  }
  return false;
}
