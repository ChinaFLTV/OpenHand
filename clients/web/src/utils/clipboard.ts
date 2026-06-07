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
          // 读回严格相等 → 写成功。
          if (readBack === text) return true;
          // 读回是空串或与原文不匹配 → 写静默失败（permissions
          // policy、focus 丢失等）。直接返 false 让上层出"复制失败"提示。
          console.warn(
            '[clipboard] write 读回不一致：readBack=' +
              JSON.stringify(readBack.slice(0, 64)) +
              ', expected=' +
              JSON.stringify(text.slice(0, 64)) +
              ' (lengths: ' +
              readBack.length +
              ' vs ' +
              text.length +
              ')',
          );
          return false;
        } catch {
          // read 权限被拒 → 无法校验，但 write resolve 了。
          // 保守信任 write 信号，但需要 execCommand 兜底再尝试一次
          // （read 拒权常常伴随 write 也被静默吞，必须用 textarea 兜）。
        }
      } else {
        // 浏览器没有 readText API（极少数隐私模式），走兜底。
        return false;
      }
    } catch (err) {
      console.warn('[clipboard] navigator.writeText 失败，降级 execCommand', err);
      // writeText 直接抛错：降级到 execCommand。
    }
  }
  if (typeof document === 'undefined') return false;
  // 兜底：textarea + execCommand('copy')。execCommand 在新浏览器里
  // 仍能 work（虽然 deprecated），且不会因 focus 丢失静默失败。
  // 关键：之前 navigator.clipboard.writeText 失败或读回不一致时，必须
  // 走这条路径才有机会真正写入剪贴板。
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
      // 再次校验 execCommand 是否真的写入了（macOS 偶发 execCommand
      // 返 true 但剪贴板仍是空）。
      try {
        if (typeof navigator.clipboard?.readText === 'function') {
          const readBack2 = await navigator.clipboard.readText();
          if (readBack2 === text) return true;
          console.warn(
            '[clipboard] execCommand 读回不一致：readBack=' +
              JSON.stringify(readBack2.slice(0, 64)),
          );
          return false;
        }
      } catch {
        // read 拒权时无法校验，保守返 true（execCommand 自身返 true）。
      }
    }
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