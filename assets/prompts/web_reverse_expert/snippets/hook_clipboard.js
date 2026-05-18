// hook_clipboard.js
// 拦截 navigator.clipboard.writeText/readText + document.execCommand('copy')，
// 把任何剪贴板读写以 __OH_CLIP__ 打 console，便于追踪复制按钮 / 密钥拷贝。
(() => {
  if (window.__oh_hook_clipboard_installed) return;
  window.__oh_hook_clipboard_installed = true;

  const cap = (v, n = 512) => {
    if (v == null) return null;
    const t = typeof v === 'string' ? v : String(v);
    return t.length > n ? t.slice(0, n) + '…' : t;
  };

  const log = (kind, payload) => {
    try {
      console.log('__OH_CLIP__', JSON.stringify({ kind, ts: Date.now(), ...payload }));
    } catch (_) { /* ignore */ }
  };

  const c = navigator && navigator.clipboard;
  if (c) {
    if (typeof c.writeText === 'function') {
      const orig = c.writeText.bind(c);
      c.writeText = function (text) {
        log('writeText', { text: cap(text), length: (text || '').length });
        return orig(text);
      };
    }
    if (typeof c.readText === 'function') {
      const orig = c.readText.bind(c);
      c.readText = function () {
        return orig().then((t) => {
          log('readText', { text: cap(t), length: (t || '').length });
          return t;
        });
      };
    }
    if (typeof c.write === 'function') {
      const orig = c.write.bind(c);
      c.write = function (items) {
        try {
          const types = (items || []).flatMap((it) => Array.from(it.types || []));
          log('write', { types });
        } catch (_) { /* ignore */ }
        return orig(items);
      };
    }
  }

  if (typeof document.execCommand === 'function') {
    const orig = document.execCommand.bind(document);
    document.execCommand = function (cmd) {
      if (cmd === 'copy' || cmd === 'cut' || cmd === 'paste') {
        try {
          const sel = window.getSelection && window.getSelection().toString();
          log('execCommand', { cmd, selection: cap(sel) });
        } catch (_) { /* ignore */ }
      }
      return orig.apply(this, arguments);
    };
  }
})();
