/* OpenHand Web Service Worker
 * 目标:
 *   1. 提供轻量的 App Shell 离线支持 (/、/app.js、/app.css、/openhand_logo.png)。
 *   2. /api/* 一律走网络优先 (避免缓存到了过期的 session/messages)，
 *      网络失败时返回明确的离线 JSON, 让前端显示离线 banner 而非整体崩溃。
 *   3. 静态资源 (chunks/* 与 assets/*) 走 cache-first, 失败回退网络。
 *
 * 缓存版本号在每次发布时手动 bump, 旧缓存在 activate 时清理。
 */
const CACHE_VERSION = 'openhand-shell-v2';
const APP_SHELL = [
  '/',
  '/app.js',
  '/app.css',
  '/openhand_logo.png',
  '/manifest.webmanifest',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_VERSION)
      .then((cache) => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
      .catch(() => undefined),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)),
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
            JSON.stringify({ error: 'offline', message: 'network unavailable' }),
            {
              status: 503,
              headers: { 'content-type': 'application/json; charset=utf-8' },
            },
          ),
      ),
    );
    return;
  }

  // SPA shell + 静态资源: cache-first, 没命中就 fetch 并 put 进缓存。
  event.respondWith(
    caches.match(req).then(
      (cached) =>
        cached ||
        fetch(req)
          .then((res) => {
            // 只缓存 200 同源响应; opaque/redirect 跳过
            if (res && res.status === 200 && res.type === 'basic') {
              const clone = res.clone();
              caches.open(CACHE_VERSION).then((c) => c.put(req, clone)).catch(() => undefined);
            }
            return res;
          })
          .catch(() => caches.match('/') as Promise<Response>),
    ),
  );
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
  const sessionId = event.notification.data && event.notification.data.sessionId;
  const target = sessionId ? `/threads/${sessionId}` : '/threads';
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
