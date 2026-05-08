import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const globalCssPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  './global.css',
);

describe('mobile session layout CSS', () => {
  const source = readFileSync(globalCssPath, 'utf8');

  it('keeps the mobile session shell inside viewport safe areas', () => {
    const mobileBlock = source.match(/@media \(max-width: 720px\) \{[\s\S]*?@media \(max-width: 480px\)/)?.[0] ?? '';

    expect(mobileBlock).toContain('height: 100dvh');
    expect(mobileBlock).toContain('env(safe-area-inset-top, 0px)');
    expect(mobileBlock).toContain('env(safe-area-inset-right, 0px)');
    expect(mobileBlock).toContain('env(safe-area-inset-bottom, 0px)');
    expect(mobileBlock).toContain('env(safe-area-inset-left, 0px)');
  });
});