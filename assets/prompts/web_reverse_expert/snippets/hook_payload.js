// hook_payload.js
// 拦截 fetch / XMLHttpRequest / WebSocket 的发送与接收，把入参原文和调用堆栈打到 console。
// 通过 __OH_FETCH__ / __OH_XHR__ / __OH_WS_SEND__ / __OH_WS_RECV__ 前缀方便 grep 提取。
//
// 使用方式：
//   1) 通过工具目录里的 init-script 能力在页面下次导航前注入；或
//   2) 通过工具目录里的 evaluate 能力在已加载页面立即执行（首屏请求会漏掉，仅适合用户操作触发的请求）。
//
// 设计要点：
// - 仅修改 window.fetch / XMLHttpRequest.prototype.send / WebSocket，不污染原型链上的其他成员。
// - 异常吞掉只为不破坏页面运行；console 上仍会打 __OH_HOOK_ERROR__ 提示。
// - body 字段对二进制类型只打 [binary length=N]，避免日志爆炸。
(() => {
  if (window.__oh_hook_payload_installed) return;
  window.__oh_hook_payload_installed = true;

  const safeStringify = (value) => {
    try {
      if (value == null) return null;
      if (typeof value === 'string') return value.length > 8192 ? value.slice(0, 8192) + '…[truncated]' : value;
      if (value instanceof FormData) {
        const out = {};
        for (const [k, v] of value.entries()) out[k] = typeof v === 'string' ? v : '[file]';
        return JSON.stringify(out);
      }
      if (value instanceof URLSearchParams) return value.toString();
      if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return `[binary length=${value.byteLength}]`;
      return JSON.stringify(value);
    } catch (e) {
      return `[unserializable: ${e && e.message}]`;
    }
  };

  // ── fetch ────────────────────────────────────────────────────────────
  const origFetch = window.fetch;
  window.fetch = function (input, init) {
    try {
      const url = typeof input === 'string' ? input : input && input.url;
      const method = (init && init.method) || (input && input.method) || 'GET';
      const headers = init && init.headers ? Object.fromEntries(new Headers(init.headers).entries()) : null;
      const body = init && init.body ? safeStringify(init.body) : null;
      console.log('__OH_FETCH__', JSON.stringify({
        url, method, headers, body,
        stack: (new Error().stack || '').split('\n').slice(1, 9).map((s) => s.trim()),
      }));
    } catch (e) {
      console.log('__OH_HOOK_ERROR__', JSON.stringify({ where: 'fetch', error: e && e.message }));
    }
    return origFetch.apply(this, arguments);
  };

  // ── XMLHttpRequest ───────────────────────────────────────────────────
  const OrigXHR = window.XMLHttpRequest;
  function PatchedXHR() {
    const xhr = new OrigXHR();
    let _meta = { method: 'GET', url: '', headers: {} };
    const origOpen = xhr.open;
    const origSend = xhr.send;
    const origSetHeader = xhr.setRequestHeader;
    xhr.open = function (m, u) {
      _meta.method = m; _meta.url = u; _meta.headers = {};
      return origOpen.apply(xhr, arguments);
    };
    xhr.setRequestHeader = function (k, v) {
      try { _meta.headers[k] = v; } catch (_) { /* ignore */ }
      return origSetHeader.apply(xhr, arguments);
    };
    xhr.send = function (body) {
      try {
        console.log('__OH_XHR__', JSON.stringify({
          ..._meta,
          body: safeStringify(body),
          stack: (new Error().stack || '').split('\n').slice(1, 9).map((s) => s.trim()),
        }));
      } catch (e) {
        console.log('__OH_HOOK_ERROR__', JSON.stringify({ where: 'xhr', error: e && e.message }));
      }
      return origSend.apply(xhr, arguments);
    };
    return xhr;
  }
  PatchedXHR.prototype = OrigXHR.prototype;
  window.XMLHttpRequest = PatchedXHR;

  // ── WebSocket ────────────────────────────────────────────────────────
  const OrigWS = window.WebSocket;
  function PatchedWS(url, protocols) {
    const ws = protocols ? new OrigWS(url, protocols) : new OrigWS(url);
    const origSend = ws.send;
    ws.send = function (data) {
      try {
        console.log('__OH_WS_SEND__', JSON.stringify({ url, data: safeStringify(data) }));
      } catch (e) { /* ignore */ }
      return origSend.apply(ws, arguments);
    };
    ws.addEventListener('message', (ev) => {
      try {
        console.log('__OH_WS_RECV__', JSON.stringify({ url, data: safeStringify(ev.data) }));
      } catch (_) { /* ignore */ }
    });
    return ws;
  }
  PatchedWS.prototype = OrigWS.prototype;
  Object.setPrototypeOf(PatchedWS, OrigWS);
  window.WebSocket = PatchedWS;
})();
