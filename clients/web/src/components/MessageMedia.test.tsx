import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/preact';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MessageMedia } from './MessageMedia';
import type { SessionMessage } from '../api/sessions';

function makeMessage(
  content: string,
  metadata?: Record<string, unknown>,
  role: SessionMessage['role'] = 'assistant',
): SessionMessage {
  return {
    id: 'm1',
    kind: 'assistant',
    role,
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
    vi.restoreAllMocks();
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
    expect(document.querySelector('video')?.getAttribute('preload')).toBe('none');
    expect(document.querySelector('audio')?.getAttribute('preload')).toBe('none');
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
              storage_path: '/tmp/session/upload-cache/a1',
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

  it('renders user image attachments as compact attachment rows instead of inline previews', () => {
    render(
      <MessageMedia
        sessionId="session-3"
        message={makeMessage('请看附件', {
          attachments: [
            {
              name: 'photo.png',
              mime_type: 'image/png',
              storage_path: '/tmp/session/upload-cache/a1',
            },
          ],
        }, 'user')}
      />,
    );

    expect(screen.getByText('photo.png')).not.toBeNull();
    expect(screen.getByText(/(附件|Attachment).*(图片|Image)/)).not.toBeNull();
    expect(screen.queryByAltText('photo.png')).toBeNull();
  });

  it('aborts an in-flight media save when the preview dialog closes', async () => {
    let saveSignal: AbortSignal | undefined;
    vi.stubGlobal('fetch', vi.fn((_url: string | URL | Request, init?: RequestInit) => {
      saveSignal = init?.signal ?? undefined;
      return new Promise<Response>(() => undefined);
    }));

    render(
      <MessageMedia
        sessionId="session-save"
        message={makeMessage('', {
          attachments: [
            {
              name: 'photo.png',
              kind: 'image',
              storage_path: '/tmp/session/upload-cache/photo.png',
            },
          ],
        })}
      />,
    );

    fireEvent.click(screen.getByTitle('photo.png'));
    await screen.findByRole('dialog', { name: 'photo.png' });

    fireEvent.click(screen.getByRole('button', { name: /保存|Save/ }));
    await waitFor(() => expect(saveSignal).toBeDefined());
    expect(saveSignal?.aborted).toBe(false);

    fireEvent.click(screen.getByRole('button', { name: /关闭|Close/ }));

    expect(saveSignal?.aborted).toBe(true);
  });
});