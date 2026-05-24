import { afterEach, describe, expect, it } from 'vitest';
import { cleanup } from '@testing-library/preact';
import {
  isLocalMediaReference,
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
});