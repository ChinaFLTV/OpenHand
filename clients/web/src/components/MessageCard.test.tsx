import { cleanup, fireEvent, render, screen, within } from '@testing-library/preact';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { useState } from 'preact/hooks';
import { MessageCard } from './MessageCard';
import type { SessionMessage } from '../api/sessions';

const copyName = /^(复制|Copy)$/;
const deleteName = /^(删除|Delete)$/;

vi.mock('./Markdown', () => ({
  Markdown: ({ source }: { source: string }) => <div>{source}</div>,
}));

vi.mock('./MessageMedia', () => ({
  MessageMedia: () => null,
}));

vi.mock('./MessageToolMeta', () => ({
  MessageToolMeta: () => null,
}));

function makeMessage(id: string, content: string, metadata?: Record<string, unknown>): SessionMessage {
  return {
    id,
    kind: 'text',
    role: 'user',
    content,
    created_at: '2026-05-06T00:00:00.000Z',
    character_count: content.length,
    metadata,
  };
}

function MessageListHarness() {
  const [activeMessageId, setActiveMessageId] = useState<string | null>(null);
  const messages = [makeMessage('first', '第一条内容'), makeMessage('second', '第二条内容')];
  return (
    <ul>
      {messages.map((message) => (
        <li key={message.id}>
          <MessageCard
            message={message}
            active={activeMessageId === message.id}
            onActiveChange={(nextMessage, active) => {
              setActiveMessageId(active ? nextMessage.id : null);
            }}
            onCopy={vi.fn()}
            onEdit={vi.fn()}
            onAudit={vi.fn()}
            onDelete={vi.fn()}
            onDeleteAfter={vi.fn()}
          />
        </li>
      ))}
    </ul>
  );
}

describe('MessageCard actions', () => {
  afterEach(() => cleanup());

  it('shows actions only for the clicked card without focus outline or danger-colored delete actions', () => {
    const { container } = render(<MessageListHarness />);
    const cards = Array.from(container.querySelectorAll('article')) as HTMLElement[];
    expect(cards).toHaveLength(2);
    expect(screen.queryByRole('button', { name: copyName })).toBeNull();

    fireEvent.click(screen.getByText('第一条内容'));
    expect(within(cards[0]!).getByRole('button', { name: copyName })).not.toBeNull();
    expect(within(cards[0]!).getByRole('button', { name: deleteName }).getAttribute('style') ?? '').toContain('color: current');
    expect(cards[0]!.getAttribute('style') ?? '').not.toContain('outline');
    expect(within(cards[1]!).queryByRole('button', { name: copyName })).toBeNull();

    fireEvent.click(screen.getByText('第二条内容'));
    expect(within(cards[0]!).queryByRole('button', { name: copyName })).toBeNull();
    expect(within(cards[1]!).getByRole('button', { name: copyName })).not.toBeNull();
    expect(cards[1]!.getAttribute('style') ?? '').not.toContain('outline');
  });

  it('renders user message context capsules for creation mode, skill and attachment kinds', () => {
    render(
      <MessageCard
        message={makeMessage('rich', '生成一张火星照片', {
          creation_request: {
            mode: 'image',
            options: { aspect_ratio: '16:9', count: 2 },
          },
          user_skill_selection: { name: '摄影构图', emoji: '📷' },
          attachments: [
            { id: 'a1', name: 'reference.png', storage_path: '/tmp/reference.png', kind: 'image' },
            { id: 'a2', name: 'brief.pdf', storage_path: '/tmp/brief.pdf', kind: 'pdf' },
          ],
        })}
      />,
    );

    expect(screen.getByText(/(图片生成|Image generation).*16:9.*x2/)).not.toBeNull();
    expect(screen.getByText(/(技能|Skill).*摄影构图/)).not.toBeNull();
    expect(screen.getByText(/(图片附件|Image attachment)/)).not.toBeNull();
    expect(screen.getByText(/(PDF 附件|PDF attachment)/)).not.toBeNull();
  });
});
