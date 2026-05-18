// hook_history.js
// 包裹 history.pushState / replaceState + 监听 popstate / hashchange，
// 把 SPA 路由跳变以 __OH_HIST__ 前缀打 console。
(() => {
  if (window.__oh_hook_history_installed) return;
  window.__oh_hook_history_installed = true;

  const h = window.history;
  if (!h) return;

  const log = (kind, payload) => {
    try {
      console.log('__OH_HIST__', JSON.stringify({
        kind,
        ts: Date.now(),
        url: location.href,
        ...payload,
      }));
    } catch (_) { /* ignore */ }
  };

  const wrap = (name) => {
    const orig = h[name];
    if (typeof orig !== 'function') return;
    h[name] = function (state, title, url) {
      log(name, { state: safe(state), title, target: url || null });
      return orig.apply(this, arguments);
    };
  };

  const safe = (s) => {
    try {
      const t = JSON.stringify(s);
      return t && t.length > 512 ? t.slice(0, 512) + '…' : s;
    } catch (_) {
      return '[unserializable]';
    }
  };

  wrap('pushState');
  wrap('replaceState');

  window.addEventListener('popstate', (e) => log('popstate', { state: safe(e.state) }));
  window.addEventListener('hashchange', (e) => log('hashchange', {
    oldURL: e.oldURL,
    newURL: e.newURL,
  }));
})();
