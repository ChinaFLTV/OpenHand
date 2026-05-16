// hook_storage.js
// 拦截 localStorage / sessionStorage / cookie 写入，便于定位 token / session 注入点。
// 通过 __OH_STORAGE__ 前缀方便 grep 提取。
(() => {
  if (window.__oh_hook_storage_installed) return;
  window.__oh_hook_storage_installed = true;

  const log = (kind, op, key, value) => {
    try {
      console.log('__OH_STORAGE__', JSON.stringify({
        kind, op, key,
        value: typeof value === 'string' && value.length > 512 ? value.slice(0, 512) + '…' : value,
        stack: (new Error().stack || '').split('\n').slice(1, 7).map((s) => s.trim()),
      }));
    } catch (_) { /* ignore */ }
  };

  ['localStorage', 'sessionStorage'].forEach((store) => {
    try {
      const target = window[store];
      const origSet = target.setItem.bind(target);
      const origRemove = target.removeItem.bind(target);
      target.setItem = function (k, v) { log(store, 'set', k, v); return origSet(k, v); };
      target.removeItem = function (k) { log(store, 'remove', k, null); return origRemove(k); };
    } catch (_) { /* SecurityError on cross-origin */ }
  });

  // document.cookie setter
  try {
    const desc = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie');
    if (desc && desc.set) {
      Object.defineProperty(document, 'cookie', {
        configurable: true,
        get: desc.get,
        set(v) { log('cookie', 'set', null, v); return desc.set.call(document, v); },
      });
    }
  } catch (_) { /* ignore */ }
})();
