import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render, waitFor } from '@testing-library/preact';
import {
  isLocalMediaReference,
  Markdown,
  openHtmlInNewTab,
  stripLocalMediaReferences,
} from './Markdown';

describe('Markdown', () => {
  afterEach(() => cleanup());

  it('strips local generated media references before markdown rendering', () => {
    const source = [
      'before',
      '![AI Generated Image](/tmp/openhand_media/image_1.png)',
      '[🎬 AI Generated Video](/tmp/openhand_media/video_1.mp4)',
      '![Remote](https://example.test/remote.png)',
    ].join('\n');

    expect(isLocalMediaReference('/tmp/openhand_media/image_1.png')).toBe(true);
    expect(isLocalMediaReference('https://example.test/remote.png')).toBe(false);
    expect(stripLocalMediaReferences(source)).not.toContain('openhand_media');
    expect(stripLocalMediaReferences(source)).toContain('https://example.test/remote.png');
  });

  it('exports openHtmlInNewTab helper for HTML preview buttons', () => {
    expect(typeof openHtmlInNewTab).toBe('function');
  });

  it('preserves native flex and grid declarations in HTML mode', async () => {
    const source = [
      '<div data-testid="flex-row" style="display:flex;flex-wrap:wrap;gap:8px 12px;column-gap:16px">',
      '<section>定位</section><section>优势</section><section>短板</section>',
      '</div>',
      '<div data-testid="grid-row" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));row-gap:8px;column-gap:12px">',
      '<section>剧情</section><section>人物</section><section>制作</section>',
      '</div>',
    ].join('');

    const { container } = render(<Markdown source={source} format="html" />);

    await waitFor(() => {
      expect(container.querySelector('[data-testid="flex-row"]')).not.toBeNull();
      expect(container.querySelector('[data-testid="grid-row"]')).not.toBeNull();
    });

    const flexRow = container.querySelector<HTMLElement>('[data-testid="flex-row"]')!;
    const gridRow = container.querySelector<HTMLElement>('[data-testid="grid-row"]')!;
    expect(flexRow.style.display).toBe('flex');
    expect(flexRow.style.flexWrap).toBe('wrap');
    expect(flexRow.style.columnGap).toBe('16px');
    expect(gridRow.style.display).toBe('grid');
    expect(gridRow.style.gridTemplateColumns).toContain('repeat(auto-fit,minmax(160px,1fr))');
    expect(gridRow.style.rowGap).toBe('8px');
    expect(gridRow.style.columnGap).toBe('12px');
  });
});