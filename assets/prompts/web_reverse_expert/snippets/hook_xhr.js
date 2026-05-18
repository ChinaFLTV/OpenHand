// hook_xhr.js
// 拦截 XMLHttpRequest.open/setRequestHeader/send，记录每条请求的
// method/url/headers/body 与 readyState=4 时的 status/timing。
// 前缀 __OH_XHR__；body 限 1KB。
(() => {
  if (window.__oh_hook_xhr_installed) return;
  window.__oh_hook_xhr_installed = true;

  const X = window.XMLHttpRequest;
  if (!X) return;

  const origOpen = X.prototype.open;
  const origSend = X.prototype.send;
  const origSetHeader = X.prototype.setRequestHeader;

  const cap = (v, n = 1024) => {
    if (v == null) return null;
    const t = typeof v === 'string' ? v : String(v);
    return t.length > n ? t.slice(0, n) + '…' : t;
  };

  const log = (payload) => {
    try {
      console.log('__OH_XHR__', JSON.stringify({ ts: Date.now(), ...payload }));
    } catch (_) { /* ignore */ }
  };

  X.prototype.open = function (method, url) {
    this.__oh_xhr = { method, url, headers: {}, start: performance.now() };
    return origOpen.apply(this, arguments);
  };

  X.prototype.setRequestHeader = function (k, v) {
    if (this.__oh_xhr) this.__oh_xhr.headers[k] = v;
    return origSetHeader.apply(this, arguments);
  };

  X.prototype.send = function (body) {
    const meta = this.__oh_xhr || {};
    log({
      phase: 'request',
      method: meta.method,
      url: meta.url,
      headers: meta.headers || {},
      body: body != null ? cap(body) : null,
    });
    this.addEventListener('loadend', () => {
      const elapsed = +(performance.now() - (meta.start || 0)).toFixed(1);
      log({
        phase: 'response',
        method: meta.method,
        url: meta.url,
        status: this.status,
        elapsedMs: elapsed,
        respHeaders: cap(this.getAllResponseHeaders(), 2048),
      });
    });
    return origSend.apply(this, arguments);
  };
})();
