// hook_fetch.js
// 包裹 window.fetch，把 url/method/headers/body 与响应概要打 console。
// 前缀 __OH_FETCH__ 便于 grep；只截前 1KB body 避免炸日志。
(() => {
  if (window.__oh_hook_fetch_installed) return;
  window.__oh_hook_fetch_installed = true;

  const origFetch = window.fetch;
  if (typeof origFetch !== 'function') return;

  const cap = (s, n = 1024) => {
    if (s == null) return null;
    const t = typeof s === 'string' ? s : String(s);
    return t.length > n ? t.slice(0, n) + '…' : t;
  };

  const headersToObj = (h) => {
    if (!h) return {};
    if (h instanceof Headers) {
      const out = {};
      h.forEach((v, k) => { out[k] = v; });
      return out;
    }
    if (Array.isArray(h)) {
      const out = {};
      for (const [k, v] of h) out[k] = v;
      return out;
    }
    return { ...h };
  };

  const log = (payload) => {
    try {
      console.log('__OH_FETCH__', JSON.stringify({ ts: Date.now(), ...payload }));
    } catch (_) { /* ignore */ }
  };

  window.fetch = function (input, init) {
    const start = performance.now();
    const url = typeof input === 'string'
      ? input
      : (input && input.url) || String(input);
    const method = (init && init.method) || (input && input.method) || 'GET';
    const reqHeaders = headersToObj((init && init.headers) || (input && input.headers));
    const reqBody = init && init.body != null ? cap(init.body) : null;

    log({ phase: 'request', url, method, headers: reqHeaders, body: reqBody });

    return origFetch.apply(this, arguments).then((resp) => {
      const elapsed = +(performance.now() - start).toFixed(1);
      const respHeaders = headersToObj(resp.headers);
      log({
        phase: 'response',
        url,
        method,
        status: resp.status,
        ok: resp.ok,
        elapsedMs: elapsed,
        headers: respHeaders,
      });
      return resp;
    }, (err) => {
      const elapsed = +(performance.now() - start).toFixed(1);
      log({ phase: 'error', url, method, elapsedMs: elapsed, error: String(err) });
      throw err;
    });
  };
})();
