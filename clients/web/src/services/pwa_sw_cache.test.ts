import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const serviceWorkerPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../public/sw.js',
);

describe('service worker cache strategy', () => {
  const source = readFileSync(serviceWorkerPath, 'utf8');

  it('keeps fixed app shell bundle paths on a network-first strategy', () => {
    expect(source).toContain('APP_SHELL_NETWORK_FIRST');
    expect(source).toContain("'/app.js'");
    expect(source).toContain("'/app.css'");
    expect(source).toContain('event.respondWith(networkFirst(req, \'/\'))');
  });

  it('keeps Vite derived asset folders on a cache-first strategy', () => {
    expect(source).toContain('CACHE_FIRST_PREFIXES');
    expect(source).toContain("'/chunks/'");
    expect(source).toContain("'/assets/'");
    expect(source).toContain('event.respondWith(cacheFirst(req))');
  });
});