// repl_dump_storage.js
// 一次性导出 cookies / localStorage / sessionStorage / IndexedDB 概览。
// 配合「存储管理器」面板做快速对照。返回 JSON 字符串。
(async () => {
  const out = { ts: Date.now(), origin: location.origin };
  out.cookies = document.cookie.split(/;\s*/).filter(Boolean).map((p) => {
    const i = p.indexOf('=');
    return i < 0 ? { name: p, value: '' } : { name: p.slice(0, i), value: p.slice(i + 1) };
  });
  out.local = {};
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    out.local[k] = localStorage.getItem(k);
  }
  out.session = {};
  for (let i = 0; i < sessionStorage.length; i++) {
    const k = sessionStorage.key(i);
    out.session[k] = sessionStorage.getItem(k);
  }
  out.idb = [];
  if (indexedDB && indexedDB.databases) {
    try {
      const dbs = await indexedDB.databases();
      for (const d of dbs) out.idb.push({ name: d.name, version: d.version });
    } catch (e) { out.idbError = String(e); }
  }
  return JSON.stringify(out, null, 2);
})();
