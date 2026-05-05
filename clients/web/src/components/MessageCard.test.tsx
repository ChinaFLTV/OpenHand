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

function makeMessage(id: string, content: string): SessionMessage {
  return {
    id,
    kind: 'text',
    role: 'user',
    content,
    created_at: '2026-05-06T00:00:00.000Z',
    character_count: content.length,
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
});
