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

  it('keeps the collapsed composer shell tight around the expand button', () => {
    const toolbarBlock = source.match(/\.oh-composer-toolbar\[data-collapsed='true'\] \{[\s\S]*?\n\}/)?.[0] ?? '';
    const shellBlock = source.match(/\.oh-session-composer\[data-collapsed='true'\] \{[\s\S]*?\n\}/)?.[0] ?? '';

    expect(shellBlock).toContain('padding: 0 !important');
    expect(shellBlock).toContain('background: transparent !important');
    expect(shellBlock).toContain('box-shadow: none !important');
    expect(toolbarBlock).toContain('display: inline-flex');
    expect(toolbarBlock).toContain('width: auto');
    expect(source).toContain(".oh-session-composer[data-collapsed='true'] .oh-composer-body,");
    expect(source).toContain(".oh-session-composer[data-collapsed='true'] .oh-composer-footer");
    expect(source).toContain('visibility: hidden');
  });

  it('uses shared dialog motion settings for popup menus', () => {
    expect(source).toContain('animation: oh-dialog-fade-scale-in var(--oh-dialog-duration) var(--oh-dialog-curve) both');
    expect(source).toContain('animation: oh-dialog-fade-scale-out var(--oh-dialog-duration) var(--oh-dialog-exit-curve) both');
    expect(source).toContain("[data-dialog-enter='elastic'] .oh-popmenu-pop");
    expect(source).toContain("[data-dialog-exit='spring_scale'] .oh-menu-pop-out");
    expect(source).toContain("[data-dialog-enter='none'] .oh-popmenu-pop");
    expect(source).toContain("[data-dialog-exit='none'] .oh-menu-pop-out");
  });
});