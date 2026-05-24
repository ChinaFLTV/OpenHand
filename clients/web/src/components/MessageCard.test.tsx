import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/preact';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
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
  stripCollectedNetworkMedia: (content: string) => content,
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

function makeAssistantMessage(id: string, content: string): SessionMessage {
  return {
    ...makeMessage(id, content),
    role: 'assistant',
  };
}

function domRect(height: number): DOMRect {
  return {
    x: 0,
    y: 0,
    width: 320,
    height,
    top: 0,
    right: 320,
    bottom: height,
    left: 0,
    toJSON: () => ({}),
  } as DOMRect;
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
  beforeEach(() => {
    class ImmediateIntersectionObserver implements IntersectionObserver {
      readonly root = null;
      readonly rootMargin = '0px';
      readonly thresholds = [0];

      constructor(private readonly callback: IntersectionObserverCallback) {}

      observe(target: Element): void {
        this.callback([
          {
            boundingClientRect: {} as DOMRectReadOnly,
            intersectionRatio: 1,
            intersectionRect: {} as DOMRectReadOnly,
            isIntersecting: true,
            rootBounds: null,
            target,
            time: 0,
          },
        ], this);
      }

      disconnect(): void {}
      takeRecords(): IntersectionObserverEntry[] { return []; }
      unobserve(): void {}
    }

    vi.stubGlobal('IntersectionObserver', ImmediateIntersectionObserver);
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

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

    expect(screen.getByText(/(模式|Mode).*(图片生成|Image generation).*16:9.*x2/)).not.toBeNull();
    expect(screen.getByText(/(技能|Skill).*摄影构图/)).not.toBeNull();
    expect(screen.getByText(/(附件|Attachment).*(图片|Image)/)).not.toBeNull();
    expect(screen.getByText(/(附件|Attachment).*PDF/)).not.toBeNull();
  });

  it('animates assistant card height when streamed content grows', async () => {
    const animateDescriptor = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'animate');
    const animate = vi.fn(function animateMock(
      _keyframes?: Keyframe[] | PropertyIndexedKeyframes | null,
      _options?: number | KeyframeAnimationOptions,
    ) {
      return {
        cancel: vi.fn(),
        finished: Promise.resolve({} as Animation),
      } as unknown as Animation;
    });
    Object.defineProperty(HTMLElement.prototype, 'animate', {
      configurable: true,
      value: animate,
    });
    const rectSpy = vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect')
      .mockImplementation(function getRect(this: HTMLElement) {
        return domRect((this.textContent ?? '').includes('第二行') ? 120 : 80);
      });

    try {
      const { rerender } = render(
        <MessageCard message={makeAssistantMessage('assistant-1', '第一行')} />,
      );
      await waitFor(() => expect(rectSpy).toHaveBeenCalledTimes(1));
      expect(animate).not.toHaveBeenCalled();

      rerender(
        <MessageCard message={makeAssistantMessage('assistant-1', '第一行\n第二行')} />,
      );

      await waitFor(() => expect(animate).toHaveBeenCalledTimes(1));
      const [keyframes, options] = animate.mock.calls[0] as [Keyframe[], KeyframeAnimationOptions];
      expect((keyframes as Keyframe[])[0]!.height).toBe('80px');
      expect((keyframes as Keyframe[]).at(-1)!.height).toBe('120px');
      expect((options as KeyframeAnimationOptions).duration).toBeGreaterThanOrEqual(300);
    } finally {
      rectSpy.mockRestore();
      if (animateDescriptor) {
        Object.defineProperty(HTMLElement.prototype, 'animate', animateDescriptor);
      } else {
        delete (HTMLElement.prototype as unknown as { animate?: unknown }).animate;
      }
    }
  });

  it('keeps previous assistant text underneath while streamed diff fades in', () => {
    const rafDescriptor = Object.getOwnPropertyDescriptor(window, 'requestAnimationFrame');
    const cancelDescriptor = Object.getOwnPropertyDescriptor(window, 'cancelAnimationFrame');
    const frames: FrameRequestCallback[] = [];
    Object.defineProperty(window, 'requestAnimationFrame', {
      configurable: true,
      value: vi.fn((callback: FrameRequestCallback) => {
        frames.push(callback);
        return frames.length;
      }),
    });
    Object.defineProperty(window, 'cancelAnimationFrame', {
      configurable: true,
      value: vi.fn(),
    });

    try {
      const { container, rerender } = render(
        <MessageCard message={makeAssistantMessage('assistant-stream', '第一段')} streaming />,
      );

      rerender(
        <MessageCard message={makeAssistantMessage('assistant-stream', '第一段继续增长')} streaming />,
      );

      const underlay = container.querySelector<HTMLElement>('.oh-streaming-diff-underlay');
      const current = container.querySelector<HTMLElement>('.oh-streaming-diff-current');
      expect(underlay).not.toBeNull();
      expect(current).not.toBeNull();
      expect(underlay!.getAttribute('aria-hidden')).toBe('true');
      expect(underlay!.textContent).toContain('第一段');
      expect(current!.textContent).toContain('第一段继续增长');
      expect(window.requestAnimationFrame).toHaveBeenCalled();
      frames[0]?.(16);
      expect(current!.style.maskImage).toContain('linear-gradient');
    } finally {
      if (rafDescriptor) {
        Object.defineProperty(window, 'requestAnimationFrame', rafDescriptor);
      } else {
        delete (window as unknown as { requestAnimationFrame?: unknown }).requestAnimationFrame;
      }
      if (cancelDescriptor) {
        Object.defineProperty(window, 'cancelAnimationFrame', cancelDescriptor);
      } else {
        delete (window as unknown as { cancelAnimationFrame?: unknown }).cancelAnimationFrame;
      }
    }
  });

  it('skips assistant height measurement for tiny same-line streaming deltas', async () => {
    const animateDescriptor = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'animate');
    const animate = vi.fn(function animateMock(
      _keyframes?: Keyframe[] | PropertyIndexedKeyframes | null,
      _options?: number | KeyframeAnimationOptions,
    ) {
      return {
        cancel: vi.fn(),
        finished: Promise.resolve({} as Animation),
      } as unknown as Animation;
    });
    Object.defineProperty(HTMLElement.prototype, 'animate', {
      configurable: true,
      value: animate,
    });
    const rectSpy = vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect')
      .mockReturnValue(domRect(80));

    try {
      const { rerender } = render(
        <MessageCard message={makeAssistantMessage('assistant-1', '短句')} />,
      );
      await waitFor(() => expect(rectSpy).toHaveBeenCalledTimes(1));

      rerender(
        <MessageCard message={makeAssistantMessage('assistant-1', '短句继续补几个字')} />,
      );

      expect(rectSpy).toHaveBeenCalledTimes(1);
      expect(animate).not.toHaveBeenCalled();
    } finally {
      rectSpy.mockRestore();
      if (animateDescriptor) {
        Object.defineProperty(HTMLElement.prototype, 'animate', animateDescriptor);
      } else {
        delete (HTMLElement.prototype as unknown as { animate?: unknown }).animate;
      }
    }
  });

  it('keeps long assistant text expanded while streaming and collapses after completion', () => {
    const tail = 'UNIQUE_TAIL_AFTER_COLLAPSE';
    const longText = `${'A'.repeat(1280)}${tail}`;
    const { rerender } = render(
      <MessageCard message={makeAssistantMessage('assistant-long', longText)} streaming />,
    );

    expect(screen.queryByRole('button', { name: /^(展开全部|Expand all)/ })).toBeNull();
    expect(screen.getByText(longText)).not.toBeNull();

    rerender(<MessageCard message={makeAssistantMessage('assistant-long', longText)} />);

    const expand = screen.getByRole('button', { name: /^(展开全部|Expand all)/ });
    expect(expand).not.toBeNull();
    expect(document.body.textContent ?? '').not.toContain(tail);

    fireEvent.click(expand);

    expect(screen.getByRole('button', { name: /^(折叠|Collapse)/ })).not.toBeNull();
    expect(document.body.textContent ?? '').toContain(tail);
  });

  it('auto-collapses long reasoning body once streaming completes', () => {
    const reasoningText = ['第一行', '第二行', '第三行', '第四行', '第五行', '第六行', '第七行', 'TAIL_REASONING']
      .join('\n');
    const message: SessionMessage = {
      id: 'reasoning-1',
      kind: 'reasoning',
      role: 'assistant',
      content: reasoningText,
      created_at: '2026-05-09T00:00:00.000Z',
      character_count: reasoningText.length,
    };

    // 流式期间 → 胶囊展开 (aria-expanded=true)
    const { rerender, container } = render(
      <MessageCard message={message} streaming />,
    );
    const badgeStreaming = container.querySelector<HTMLElement>(
      '.oh-message-badge-toggle',
    );
    expect(badgeStreaming).not.toBeNull();
    expect(badgeStreaming!.getAttribute('aria-expanded')).toBe('true');

    // 流式结束 → 自动折叠胶囊 (aria-expanded=false)；正文容器以
    // data-collapsed='true' 渲染为前 5-6 行预览（非完全隐藏）。
    rerender(<MessageCard message={message} />);
    const badgeDone = container.querySelector<HTMLElement>(
      '.oh-message-badge-toggle',
    );
    expect(badgeDone!.getAttribute('aria-expanded')).toBe('false');
    const body = container.querySelector<HTMLElement>(
      '.oh-reasoning-collapsible-body',
    );
    expect(body).not.toBeNull();
    expect(body!.getAttribute('data-collapsed')).toBe('true');
    // 预览态保留前若干行文字（可被选中 / 复制），渐隐由 mask-image 完成。
    expect(document.body.textContent ?? '').toContain('第一行');
    expect(body!.style.maxHeight).toMatch(/^\d+px$/);
    expect(body!.style.overflow).toBe('hidden');
  });

  it('toggles reasoning badge overrides default collapsed state', () => {
    const reasoningText = Array.from({ length: 10 }, (_, i) => `段落 ${i + 1}`).join('\n');
    const message: SessionMessage = {
      id: 'reasoning-2',
      kind: 'reasoning',
      role: 'assistant',
      content: reasoningText,
      created_at: '2026-05-09T00:00:00.000Z',
      character_count: reasoningText.length,
    };
    const { container } = render(<MessageCard message={message} />);
    const badge = container.querySelector<HTMLElement>(
      '.oh-message-badge-toggle',
    )!;
    const body = container.querySelector<HTMLElement>(
      '.oh-reasoning-collapsible-body',
    )!;

    // 默认折叠：data-collapsed='true'，max-height 被设定。
    expect(badge.getAttribute('aria-expanded')).toBe('false');
    expect(body.getAttribute('data-collapsed')).toBe('true');
    expect(body.style.maxHeight).toMatch(/^\d+px$/);

    // 点击展开：data-collapsed='false'，内联样式清空。
    fireEvent.click(badge);
    expect(badge.getAttribute('aria-expanded')).toBe('true');
    expect(body.getAttribute('data-collapsed')).toBe('false');
    expect(body.style.maxHeight).toBe('');

    // 再次点击恢复折叠。
    fireEvent.click(badge);
    expect(badge.getAttribute('aria-expanded')).toBe('false');
    expect(body.getAttribute('data-collapsed')).toBe('true');
  });

  it('keeps short reasoning messages expanded by default', () => {
    const shortReasoning = '短短的一句思考';
    const message: SessionMessage = {
      id: 'reasoning-short',
      kind: 'reasoning',
      role: 'assistant',
      content: shortReasoning,
      created_at: '2026-05-09T00:00:00.000Z',
      character_count: shortReasoning.length,
    };
    const { container } = render(<MessageCard message={message} />);
    const badge = container.querySelector<HTMLElement>(
      '.oh-message-badge-toggle',
    )!;
    const body = container.querySelector<HTMLElement>(
      '.oh-reasoning-collapsible-body',
    )!;
    expect(badge.getAttribute('aria-expanded')).toBe('true');
    expect(body.getAttribute('data-collapsed')).toBe('false');
  });
});
