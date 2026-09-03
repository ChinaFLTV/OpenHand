/* OpenHand Web Service Worker
 * 目标:
 *   1. 提供轻量的 App Shell 离线支持 (/、/app.js、/app.css、/openhand_logo.png)。
 *   2. /api/* 一律走网络优先 (避免缓存到了过期的 session/messages)，
 *      网络失败时返回明确的离线 JSON, 让前端显示离线 banner 而非整体崩溃。
 *   3. 内容哈希静态资源 (chunks/* 与 assets/*) 走 cache-first, 失败回退网络。
 *
 * app.js / app.css 使用确定性文件名, 所以 App Shell 必须网络优先，避免发布后
 * 已安装过 Service Worker 的浏览器继续吃旧 bundle。Vite 派生 chunk/assets 使用
 * 内容 hash 文件名, 可安全 cache-first。
 */
const SHELL_CACHE_PREFIX = 'openhand-shell-';
const CACHE_VERSION = `${SHELL_CACHE_PREFIX}aec7d3973e5eee66`;
const NETWORK_TIMEOUT_MS = 12_000;
const APP_SHELL_PRECACHE = [
  '/',
  '/app.js',
  '/app.css',
  '/openhand_logo.png',
  '/manifest.webmanifest',
];
const APP_SHELL_ROUTE_FALLBACK = new Set([
  '/',
  '/threads',
  '/thread',
  '/login',
]);
const APP_SHELL_NETWORK_FIRST = new Set([
  ...APP_SHELL_PRECACHE,
  '/threads/app.js',
  '/threads/app.css',
  '/threads/openhand_logo.png',
  '/threads/manifest.webmanifest',
  '/sw.js',
]);
const CACHE_FIRST_PREFIXES = [
  '/chunks/',
  '/assets/',
  '/threads/chunks/',
  '/threads/assets/',
];

async function cacheResponse(req, res) {
  if (res && res.status === 200 && res.type === 'basic') {
    try {
      const cache = await caches.open(CACHE_VERSION);
      await cache.put(req, res.clone());
    } catch {
      // 缓存配额或存储异常不能覆盖已成功取得的网络响应。
    }
  }
  return res;
}

async function fetchBounded(req) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), NETWORK_TIMEOUT_MS);
  try {
    return await fetch(req, { signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function networkFirst(req, { fallbackUrl, writeCache = false } = {}) {
  try {
    const response = await fetchBounded(req);
    return writeCache ? cacheResponse(req, response) : response;
  } catch {
    const cached = await caches.match(req);
    if (cached) return cached;
    if (fallbackUrl) {
      const fallback = await caches.match(fallbackUrl);
      if (fallback) return fallback;
    }
    throw new Error('offline');
  }
}

async function cacheFirst(req) {
  const cached = await caches.match(req);
  if (cached) return cached;
  return cacheResponse(req, await fetchBounded(req));
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_VERSION);
      await Promise.allSettled(APP_SHELL_PRECACHE.map((url) => cache.add(url)));
      await self.skipWaiting();
    })().catch(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key.startsWith(SHELL_CACHE_PREFIX) && key !== CACHE_VERSION)
          .map((key) => caches.delete(key)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return; // 只处理 GET; POST/PUT/DELETE 全部直通网络
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // 跨域不拦

  // /api/* 网络优先; 失败给一个统一的离线 JSON
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(req).catch(
        () =>
          new Response(
            JSON.stringify({ error: 'offline', message: '网络不可用' }),
            {
              status: 503,
              headers: { 'content-type': 'application/json; charset=utf-8' },
            },
          ),
      ),
    );
    return;
  }

  // SPA 路由: 网络优先, 离线时回退 HTML shell。
  if (req.mode === 'navigate' || APP_SHELL_ROUTE_FALLBACK.has(url.pathname)) {
    event.respondWith(networkFirst(req, { fallbackUrl: '/' }));
    return;
  }

  // 固定文件名 bundle: 网络优先, 离线只回退同一路径缓存, 避免把 HTML 当 JS/CSS 返回。
  if (APP_SHELL_NETWORK_FIRST.has(url.pathname)) {
    event.respondWith(networkFirst(req, { writeCache: url.search === '' }));
    return;
  }

  // Vite 派生静态资源: 文件名含内容 hash, 可 cache-first；入口 app.js/css 仍在上方网络优先。
  if (CACHE_FIRST_PREFIXES.some((prefix) => url.pathname.startsWith(prefix))) {
    event.respondWith(url.search === '' ? cacheFirst(req) : fetchBounded(req));
    return;
  }

  // 未声明为壳资源的普通请求不缓存，也不使用 HTML 兜底。
  event.respondWith(fetchBounded(req));
});

// 来自页面 postMessage 的「新消息桌面通知」请求。
// 页面只在 document.hidden 时才发, SW 这里再叠一层权限校验。
self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || data.type !== 'openhand-notify') return;
  const { title, body, tag, sessionId } = data;
  if (typeof title !== 'string' || title.length === 0) return;
  event.waitUntil(
    self.registration.showNotification(title, {
      body: typeof body === 'string' ? body : '',
      icon: '/openhand_logo.png',
      badge: '/openhand_logo.png',
      tag: typeof tag === 'string' ? tag : 'openhand-message',
      data: { sessionId },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const rawSessionId = event.notification.data && event.notification.data.sessionId;
  const sessionId = typeof rawSessionId === 'string' ? rawSessionId.trim() : '';
  const target = sessionId ? `/threads/${encodeURIComponent(sessionId)}` : '/threads';
  event.waitUntil(
    (async () => {
      const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const c of all) {
        try {
          await c.focus();
          if ('navigate' in c && typeof c.navigate === 'function') {
            await c.navigate(target);
          }
          return;
        } catch {
          // 继续尝试下一个 client
        }
      }
      await self.clients.openWindow(target);
    })(),
  );
});
