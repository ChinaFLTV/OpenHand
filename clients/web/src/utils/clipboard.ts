export async function copyTextToClipboard(text: string): Promise<boolean> {
  if (!text) return false;
  // 关键：浏览器偶发"navigator.clipboard.writeText 静默失败"（permissions
  // policy、focus 丢失、service worker 后台等）—— API resolve 但剪贴板为空。
  // 这里加一道读回校验，写入后立即 read 一次做证据回放。
  if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      if (typeof navigator.clipboard?.readText === 'function') {
        try {
          const readBack = await navigator.clipboard.readText();
          if (readBack === text) return true;
        } catch {
          // read 权限被拒不代表 write 失败，继续信任 write 成功信号。
        }
      }
      // 不可读回时保守：把 write 当作成功（浏览器拒绝重复授权是常见情况）。
      return true;
    } catch (err) {
      console.warn('[clipboard] navigator.writeText 失败，降级 execCommand', err);
    }
  }
  if (typeof document === 'undefined') return false;
  // 兜底：textarea + execCommand('copy')。execCommand 在新浏览器里
  // 仍能 work（虽然 deprecated），且不会因 focus 丢失静默失败。
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
  } catch (err) {
    console.error('[clipboard] execCommand 兜底也失败', err);
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
    console.warn('[clipboard] copyBlobToClipboard: blob 为空');
    return false;
  }
  if ('ClipboardItem' in window && navigator.clipboard?.write) {
    try {
      await navigator.clipboard.write([new ClipboardItem({ [blob.type]: blob })]);
      // 关键：Clipboard API 同样可能静默失败（permissions policy、focus
      // 丢失、blob MIME 不被剪贴板支持等）。这里 read 回校验一次。
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
    } catch (err) {
      console.warn('[clipboard] navigator.write 失败', err);
    }
  }
  return false;
}