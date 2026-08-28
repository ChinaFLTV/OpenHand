export async function copyTextToClipboard(text: string): Promise<boolean> {
  if (!text) {
    return false;
  }
  // 写入后尽量读回校验，无法校验或写入失败时使用兼容路径。
  if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      if (typeof navigator.clipboard?.readText === 'function') {
        try {
          const readBack = await navigator.clipboard.readText();
          if (readBack === text) {
            return true;
          }
          return false;
        } catch {
          // 无法校验时继续尝试兼容路径。
        }
      } else {
        return false;
      }
    } catch {
      // 降级到兼容路径。
    }
  }
  if (typeof document === 'undefined') return false;
  // 兼容不支持 Clipboard API 或权限受限的浏览器。
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
    if (ok) {
      try {
        if (typeof navigator.clipboard?.readText === 'function') {
          const readBack2 = await navigator.clipboard.readText();
          if (readBack2 === text) return true;
          return false;
        }
      } catch {
        // 无法读回时使用 execCommand 的返回值。
      }
    }
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
    } catch {
      return false;
    }
  }
  return false;
}
