// hook_postmessage.js
// 监听跨窗口 postMessage 并打 __OH_PM__。
// 同时拦截 window.postMessage / MessagePort.postMessage 的入参。
(() => {
  if (window.__oh_hook_pm_installed) return;
  window.__oh_hook_pm_installed = true;

  const summarize = (data) => {
    try {
      if (typeof data === 'string') return data.length > 512 ? data.slice(0, 512) + '…' : data;
      return JSON.parse(JSON.stringify(data));
    } catch (_) { return String(data); }
  };

  const log = (dir, payload) => {
    try {
      console.log('__OH_PM__', JSON.stringify({ dir, ts: Date.now(), ...payload }));
    } catch (_) { /* ignore */ }
  };

  window.addEventListener('message', (ev) => {
    log('recv', {
      origin: ev.origin,
      source: ev.source === window ? 'self' : (ev.source && ev.source.location ? ev.source.location.href : 'unknown'),
      data: summarize(ev.data),
    });
  }, true);

  const origWin = window.postMessage.bind(window);
  window.postMessage = function (msg, target, transfer) {
    log('send', { target: String(target), data: summarize(msg) });
    return transfer === undefined ? origWin(msg, target) : origWin(msg, target, transfer);
  };

  if (window.MessagePort && MessagePort.prototype.postMessage) {
    const origPort = MessagePort.prototype.postMessage;
    MessagePort.prototype.postMessage = function (msg, transfer) {
      log('port-send', { data: summarize(msg) });
      return transfer === undefined ? origPort.call(this, msg) : origPort.call(this, msg, transfer);
    };
  }
})();
