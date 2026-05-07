import { cleanup, render, screen } from '@testing-library/preact';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { MessageMedia } from './MessageMedia';
import type { SessionMessage } from '../api/sessions';

function makeMessage(content: string, metadata?: Record<string, unknown>): SessionMessage {
  return {
    id: 'm1',
    kind: 'assistant',
    role: 'assistant',
    content,
    created_at: '2026-05-07T00:00:00.000Z',
    character_count: content.length,
    metadata,
  };
}

describe('MessageMedia', () => {
  beforeEach(() => {
    localStorage.setItem('openhand.web.device_id', 'device-1');
  });

  afterEach(() => {
    cleanup();
    localStorage.clear();
  });

  it('renders generated local markdown media through the protected session asset endpoint', () => {
    render(
      <MessageMedia
        sessionId="session-1"
        message={makeMessage([
          '![AI Generated Image](/tmp/openhand_media/image_1.png)',
          '[🎬 AI Generated Video](/tmp/openhand_media/video_1.mp4)',
          '[🔊 AI Generated Audio](/tmp/openhand_media/audio_1.mp3)',
        ].join('\n'))}
      />,
    );

    const image = screen.getByAltText('image_1.png');
    expect(image.getAttribute('src')).toContain('/api/sessions/session-1/asset?');
    expect(image.getAttribute('src')).toContain('path=%2Ftmp%2Fopenhand_media%2Fimage_1.png');
    expect(image.getAttribute('src')).toContain('device_id=device-1');
    expect(image.getAttribute('src')).toContain('source=WEB_PC');
    expect(document.querySelector('video')?.getAttribute('src')).toContain('video_1.mp4');
    expect(document.querySelector('audio')?.getAttribute('src')).toContain('audio_1.mp3');
  });

  it('renders metadata attachment assets with the same browser-safe identity query', () => {
    render(
      <MessageMedia
        sessionId="session-2"
        message={makeMessage('', {
          attachments: [
            {
              name: 'photo.png',
              kind: 'image',
              storage_path: '/tmp/session/photo.png',
            },
          ],
        })}
      />,
    );

    const image = screen.getByAltText('photo.png');
    expect(image.getAttribute('src')).toContain('/api/sessions/session-2/asset?');
    expect(image.getAttribute('src')).toContain('device_id=device-1');
    expect(image.getAttribute('src')).toContain('source=WEB_PC');
  });
});