// hook_dom_mutation.js
// 监听整文档 DOM mutation；前缀 __OH_DOM__。
// 仅汇总：被加 / 移 / 属性改的节点 tag + 选择器路径，不带文本，避免 PII。
(() => {
  if (window.__oh_hook_dom_installed) return;
  window.__oh_hook_dom_installed = true;

  const path = (n) => {
    if (!n || n.nodeType !== 1) return null;
    const parts = [];
    let el = n;
    while (el && el.nodeType === 1 && parts.length < 6) {
      let s = el.tagName.toLowerCase();
      if (el.id) s += '#' + el.id;
      else if (el.className && typeof el.className === 'string') s += '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.');
      parts.unshift(s);
      el = el.parentElement;
    }
    return parts.join(' > ');
  };

  const log = (records) => {
    try {
      console.log('__OH_DOM__', JSON.stringify({
        ts: Date.now(),
        records: records.slice(0, 32).map((r) => ({
          type: r.type,
          target: path(r.target),
          attr: r.attributeName || null,
          added: r.addedNodes && r.addedNodes.length ? Array.from(r.addedNodes).slice(0, 4).map((n) => n.tagName ? n.tagName.toLowerCase() : 'text') : null,
          removed: r.removedNodes && r.removedNodes.length ? Array.from(r.removedNodes).slice(0, 4).map((n) => n.tagName ? n.tagName.toLowerCase() : 'text') : null,
        })),
      }));
    } catch (_) { /* ignore */ }
  };

  const mo = new MutationObserver((records) => log(records));
  mo.observe(document, { childList: true, subtree: true, attributes: true, characterData: false });
  window.__oh_dom_observer = mo;
})();
