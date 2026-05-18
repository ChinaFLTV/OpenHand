// hook_websocket.js
// 包裹 WebSocket 构造器，把 open/send/message/close 全部打 console。
// 配合「WebSocket 帧查看/重放」面板使用 — 前缀 __OH_WS__ 便于 grep。
(() => {
  if (window.__oh_hook_ws_installed) return;
  window.__oh_hook_ws_installed = true;

  const N = window.WebSocket;
  if (!N) return;

  const log = (kind, payload) => {
    try {
      console.log('__OH_WS__', JSON.stringify({
        kind,
        ts: Date.now(),
        ...payload,
      }));
    } catch (_) { /* ignore */ }
  };

  const summarize = (data) => {
    if (data == null) return null;
    if (typeof data === 'string') {
      return data.length > 512 ? data.slice(0, 512) + '…' : data;
    }
    if (data instanceof ArrayBuffer) return `[ArrayBuffer ${data.byteLength}B]`;
    if (ArrayBuffer.isView(data)) return `[${data.constructor.name} ${data.byteLength}B]`;
    if (data instanceof Blob) return `[Blob ${data.size}B type=${data.type}]`;
    return String(data);
  };

  window.WebSocket = function (url, protocols) {
    const ws = protocols === undefined ? new N(url) : new N(url, protocols);
    const id = (window.__oh_ws_seq = (window.__oh_ws_seq || 0) + 1);
    log('open', { id, url: String(url), protocols });

    const origSend = ws.send.bind(ws);
    ws.send = function (data) {
      log('send', { id, payload: summarize(data) });
      return origSend(data);
    };
    ws.addEventListener('message', (ev) => log('message', { id, payload: summarize(ev.data) }));
    ws.addEventListener('close', (ev) => log('close', { id, code: ev.code, reason: ev.reason, clean: ev.wasClean }));
    ws.addEventListener('error', () => log('error', { id }));
    return ws;
  };
  window.WebSocket.prototype = N.prototype;
  Object.defineProperty(window.WebSocket, 'CONNECTING', { value: N.CONNECTING });
  Object.defineProperty(window.WebSocket, 'OPEN', { value: N.OPEN });
  Object.defineProperty(window.WebSocket, 'CLOSING', { value: N.CLOSING });
  Object.defineProperty(window.WebSocket, 'CLOSED', { value: N.CLOSED });
})();
