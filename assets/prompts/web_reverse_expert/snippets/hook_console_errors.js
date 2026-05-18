// hook_console_errors.js
// 抓 window.onerror / unhandledrejection / console.error 的归一化签名。
// 配合「Console 错误聚类」面板。前缀 __OH_ERR__。
(() => {
  if (window.__oh_hook_err_installed) return;
  window.__oh_hook_err_installed = true;

  const normalize = (s) => String(s ?? '')
    .replace(/https?:\/\/\S+?:\d+:\d+/g, '<url:line:col>')
    .replace(/\b[0-9a-f]{8,}\b/gi, '<hash>')
    .replace(/\b\d{10,}\b/g, '<id>')
    .replace(/\s+/g, ' ')
    .slice(0, 512);

  const log = (kind, payload) => {
    try {
      console.log('__OH_ERR__', JSON.stringify({
        kind,
        ts: Date.now(),
        sig: normalize(payload.message || payload.reason || ''),
        ...payload,
      }));
    } catch (_) { /* ignore */ }
  };

  window.addEventListener('error', (ev) => log('error', {
    message: ev.message,
    source: ev.filename,
    lineno: ev.lineno,
    colno: ev.colno,
    stack: ev.error && ev.error.stack ? String(ev.error.stack).split('\n').slice(0, 6).join('\n') : null,
  }), true);

  window.addEventListener('unhandledrejection', (ev) => log('rejection', {
    reason: ev.reason && (ev.reason.message || String(ev.reason)),
    stack: ev.reason && ev.reason.stack ? String(ev.reason.stack).split('\n').slice(0, 6).join('\n') : null,
  }), true);

  const origErr = console.error.bind(console);
  console.error = function (...args) {
    log('console', { message: args.map((a) => typeof a === 'string' ? a : (a && a.message) || JSON.stringify(a)).join(' ') });
    return origErr(...args);
  };
})();
