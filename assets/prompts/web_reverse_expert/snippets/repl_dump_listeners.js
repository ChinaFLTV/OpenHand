// repl_dump_listeners.js
// 粘贴到 REPL：扫描 DOM 找出"曾经监听过事件"的节点。
// 注意：原生 Element 不暴露 listener 列表 —— 本片段只对
// （a）通过 onXxx 属性绑定 和（b）DevTools 提供的 getEventListeners 可用。
(() => {
  const has = typeof getEventListeners === 'function';
  const nodes = document.querySelectorAll('*');
  const onAttrs = [
    'onclick','onchange','oninput','onsubmit','onkeydown','onkeyup','onkeypress',
    'onmousedown','onmouseup','onmousemove','onmouseover','onmouseout',
    'onfocus','onblur','onload','onerror','onbeforeunload',
  ];

  const path = (el) => {
    const seg = [];
    let n = el;
    while (n && n.nodeType === 1 && seg.length < 6) {
      const id = n.id ? `#${n.id}` : '';
      const cls = n.classList && n.classList.length
        ? '.' + Array.from(n.classList).slice(0, 2).join('.')
        : '';
      seg.unshift(n.tagName.toLowerCase() + id + cls);
      n = n.parentElement;
    }
    return seg.join(' > ');
  };

  const hits = [];
  nodes.forEach((el) => {
    const found = [];
    for (const attr of onAttrs) {
      if (typeof el[attr] === 'function') found.push(attr.slice(2));
    }
    if (has) {
      try {
        const ls = getEventListeners(el);
        Object.keys(ls).forEach((k) => { if (!found.includes(k)) found.push(k); });
      } catch (_) { /* not in DevTools */ }
    }
    if (found.length) hits.push({ path: path(el), events: found });
  });

  return {
    devtoolsMode: has,
    scanned: nodes.length,
    matched: hits.length,
    sample: hits.slice(0, 50),
  };
})();
