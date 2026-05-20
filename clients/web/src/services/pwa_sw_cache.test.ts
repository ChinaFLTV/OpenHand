import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const serviceWorkerPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../public/sw.js',
);
const viteConfigPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../vite.config.ts',
);

describe('service worker cache strategy', () => {
  const source = readFileSync(serviceWorkerPath, 'utf8');
  const viteConfig = readFileSync(viteConfigPath, 'utf8');

  it('keeps fixed app shell bundle paths on a network-first strategy', () => {
    expect(source).toContain('APP_SHELL_NETWORK_FIRST');
    expect(source).toContain("'/app.js'");
    expect(source).toContain("'/app.css'");
    expect(source).toMatch(/if \(APP_SHELL_NETWORK_FIRST\.has\(url\.pathname\)\) \{\s*event\.respondWith\(networkFirst\(req\)\);/);
  });

  it('only falls back SPA route requests to the HTML shell', () => {
    expect(source).toContain('APP_SHELL_ROUTE_FALLBACK');
    expect(source).toMatch(/if \(req\.mode === 'navigate' \|\| APP_SHELL_ROUTE_FALLBACK\.has\(url\.pathname\)\) \{\s*event\.respondWith\(networkFirst\(req, '\/'\)\);/);
  });

  it('keeps service worker activation resilient to single precache failures', () => {
    expect(source).toContain('Promise.allSettled');
    expect(source).toContain('cache.add(url)');
    expect(source).toContain('self.skipWaiting()');
  });

  it('only cache-firsts content-hashed Vite derived asset folders', () => {
    expect(viteConfig).toContain("chunkFileNames: 'chunks/[name]-[hash].js'");
    expect(viteConfig).toContain("return 'assets/[name]-[hash][extname]'");
    expect(source).toContain('CACHE_FIRST_PREFIXES');
    expect(source).toContain("'/chunks/'");
    expect(source).toContain("'/assets/'");
    expect(source).toContain('event.respondWith(cacheFirst(req))');
  });
});