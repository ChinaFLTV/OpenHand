// repl_perf_now.js
// 粘贴到 REPL：一次性 dump performance.now()、performance.memory（仅 Chromium）、
// performance.timing 与最近 20 条 PerformanceEntry。
(() => {
  const out = {
    now: +performance.now().toFixed(2),
    timeOrigin: performance.timeOrigin,
  };

  if (performance.memory) {
    out.memory = {
      jsHeapSizeLimit: performance.memory.jsHeapSizeLimit,
      totalJSHeapSize: performance.memory.totalJSHeapSize,
      usedJSHeapSize: performance.memory.usedJSHeapSize,
    };
  }

  try {
    const nav = performance.getEntriesByType('navigation')[0];
    if (nav) {
      out.navigation = {
        type: nav.type,
        domInteractive: +nav.domInteractive.toFixed(1),
        domComplete: +nav.domComplete.toFixed(1),
        loadEventEnd: +nav.loadEventEnd.toFixed(1),
        transferSize: nav.transferSize,
      };
    }
  } catch (_) { /* legacy timing */ }

  try {
    out.recentEntries = performance.getEntries().slice(-20).map((e) => ({
      type: e.entryType,
      name: (e.name || '').length > 120 ? e.name.slice(0, 120) + '…' : e.name,
      start: +e.startTime.toFixed(1),
      duration: +e.duration.toFixed(1),
    }));
  } catch (_) { /* ignore */ }

  return out;
})();
