// repl_dump_frames.js
// 直接在 REPL 粘贴执行，dump 当前页 iframe 树（同源访问受 SOP 限制时给出占位）。
// 输出 JSON，便于配合「Frame 树查看器」对照真实 frame target。
((root) => {
  const out = [];
  const walk = (win, depth, parentUrl) => {
    let url;
    try { url = win.location.href; } catch (_) { url = '<cross-origin>'; }
    const node = { depth, url, parent: parentUrl };
    out.push(node);
    let frames;
    try { frames = Array.from(win.frames); } catch (_) { frames = []; }
    for (const f of frames) walk(f, depth + 1, url);
  };
  walk(root, 0, null);
  return JSON.stringify(out, null, 2);
})(window);
