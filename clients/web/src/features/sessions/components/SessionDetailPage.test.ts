import { describe, expect, it } from 'vitest';
import type { SessionMessage } from '../../../api/sessions';
import {
  composerCollapsedSummaryParts,
  messageFollowSignature,
  messagesInDisplayOrder,
  mergeServerWindow,
  mergeServerWindowResult,
  shouldApplySessionAsyncResult,
  shouldApplyPollingMessageWindow,
} from './SessionDetailPage';

function message(
  id: string,
  role: string,
  content: string,
  metadata?: Record<string, unknown>,
): SessionMessage {
  return {
    id,
    kind: 'text',
    role,
    content,
    created_at: '2026-05-06T00:00:00.000Z',
    character_count: content.length,
    ...(metadata ? { metadata } : {}),
  };
}

describe('mergeServerWindow', () => {
  it('preserves a local streaming assistant tail when a running poll lags behind persistence', () => {
    const user = message('user-1', 'user', '继续');
    const assistant = message('assistant-1', 'assistant', '正在分析第一段内容');

    const merged = mergeServerWindow(
      [user, assistant],
      [message('user-1', 'user', '继续')],
      0,
      0,
      { preserveLocalStreamingTail: true },
    );

    expect(merged.map((item) => item.id)).toEqual(['user-1', 'assistant-1']);
    expect(merged[1]).toBe(assistant);
  });

  it('does not regress same-id streaming content to a shorter persisted version', () => {
    const user = message('user-1', 'user', '继续');
    const assistant = message('assistant-1', 'assistant', '已经流式输出到更长的一段内容');

    const merged = mergeServerWindow(
      [user, assistant],
      [
        message('user-1', 'user', '继续'),
        message('assistant-1', 'assistant', '已经流式'),
      ],
      0,
      0,
      { preserveLocalStreamingTail: true },
    );

    expect(merged[1]).toBe(assistant);
    expect(merged[1]!.content).toBe('已经流式输出到更长的一段内容');
  });

  it('accepts an authoritative replacement after the last shared user message', () => {
    const user = message('user-1', 'user', '继续');
    const liveAssistant = message('assistant-live', 'assistant', '临时流式内容');
    const finalAssistant = message('assistant-final', 'assistant', '最终落盘内容');

    const merged = mergeServerWindow(
      [user, liveAssistant],
      [message('user-1', 'user', '继续'), finalAssistant],
      0,
      0,
      { preserveLocalStreamingTail: true },
    );

    expect(merged.map((item) => item.id)).toEqual(['user-1', 'assistant-final']);
    expect(merged[1]).toBe(finalAssistant);
  });

  it('keeps the local window when a running poll returns an empty stale window', () => {
    const user = message('user-1', 'user', '继续');
    const assistant = message('assistant-1', 'assistant', '正在分析第一段内容');

    const merged = mergeServerWindow(
      [user, assistant],
      [],
      0,
      0,
      { preserveLocalStreamingTail: true },
    );

    expect(merged.map((item) => item.id)).toEqual(['user-1', 'assistant-1']);
    expect(merged[1]).toBe(assistant);
  });

  it('keeps the local window when a running poll offset regresses without overlap', () => {
    const user = message('user-80', 'user', '继续');
    const assistant = message('assistant-81', 'assistant', '正在分析第一段内容');

    const merged = mergeServerWindow(
      [user, assistant],
      [message('old-1', 'user', '更早的消息')],
      80,
      0,
      { preserveLocalStreamingTail: true },
    );

    expect(merged.map((item) => item.id)).toEqual(['user-80', 'assistant-81']);
  });

  it('keeps the current offset when preserving a stale empty streaming window', () => {
    const user = message('user-80', 'user', '继续');
    const assistant = message('assistant-81', 'assistant', '正在分析第一段内容');

    const merged = mergeServerWindowResult(
      [user, assistant],
      [],
      80,
      0,
      { preserveLocalStreamingTail: true },
    );

    expect(merged.items.map((item) => item.id)).toEqual(['user-80', 'assistant-81']);
    expect(merged.offset).toBe(80);
  });

  it('does not drop a local streaming tail when an advanced window has no suffix overlap', () => {
    const old = message('old-1', 'user', '上一条');
    const user = message('user-2', 'user', '继续');
    const assistant = message('assistant-live', 'assistant', '正在分析第一段内容');

    const merged = mergeServerWindowResult(
      [old, user, assistant],
      [message('stale-other', 'assistant', '较旧落盘片段')],
      0,
      2,
      { preserveLocalStreamingTail: true },
    );

    expect(merged.items.map((item) => item.id)).toEqual(['old-1', 'user-2', 'assistant-live']);
    expect(merged.offset).toBe(0);
  });

  it('keeps normal non-streaming replacement behavior by default', () => {
    const user = message('user-1', 'user', '继续');
    const assistant = message('assistant-1', 'assistant', '正在分析第一段内容');

    const merged = mergeServerWindow(
      [user, assistant],
      [message('user-1', 'user', '继续')],
      0,
      0,
    );

    expect(merged.map((item) => item.id)).toEqual(['user-1']);
  });

  it('preserves references when metadata is structurally unchanged', () => {
    const tool = message('tool-1', 'tool', 'done', {
      status: 'success',
      attachments: [{ name: 'photo.png', storage_path: '/tmp/upload-cache/a1' }],
    });

    const merged = mergeServerWindow(
      [tool],
      [message('tool-1', 'tool', 'done', {
        status: 'success',
        attachments: [{ name: 'photo.png', storage_path: '/tmp/upload-cache/a1' }],
      })],
      0,
      0,
    );

    expect(merged[0]).toBe(tool);
  });

  it('replaces messages when nested metadata changes', () => {
    const tool = message('tool-1', 'tool', 'done', {
      status: 'running',
      usage: { output_tokens: 10 },
    });
    const updated = message('tool-1', 'tool', 'done', {
      status: 'success',
      usage: { output_tokens: 10 },
    });

    const merged = mergeServerWindow([tool], [updated], 0, 0);

    expect(merged[0]).toBe(updated);
  });
});

describe('composerCollapsedSummaryParts', () => {
  const labels = {
    draft: '草稿',
    charUnit: '字符',
    attachments: '附件',
    queue: '队列',
    editing: '编辑中',
    running: '回复中',
  };

  it('surfaces hidden composer state while the composer body is collapsed', () => {
    expect(composerCollapsedSummaryParts({
      textLength: 12,
      attachmentCount: 2,
      queuedCount: 3,
      editing: true,
      responseRunning: true,
    }, labels)).toEqual([
      '编辑中',
      '回复中',
      '队列 3',
      '附件 2',
      '草稿 12 字符',
    ]);
  });

  it('returns no parts for an empty collapsed composer', () => {
    expect(composerCollapsedSummaryParts({
      textLength: 0,
      attachmentCount: 0,
      queuedCount: 0,
      editing: false,
      responseRunning: false,
    }, labels)).toEqual([]);
  });
});

describe('messageFollowSignature', () => {
  it('changes when streaming tool output grows in metadata only', () => {
    const before = message('tool-1', 'tool', '', {
      tool_execution_stdout: 'line 1',
      tool_execution_status: 'running',
    });
    const after = message('tool-1', 'tool', '', {
      tool_execution_stdout: 'line 1\nline 2',
      tool_execution_status: 'running',
    });

    expect(messageFollowSignature(after)).not.toBe(messageFollowSignature(before));
  });
});

describe('messagesInDisplayOrder', () => {
  it('keeps the newest assistant text as the display tail when a tool message arrives out of order', () => {
    const tool = {
      ...message('tool-1', 'tool', 'tool output'),
      kind: 'tool',
      created_at: '2026-05-24T20:16:20.000Z',
    } satisfies SessionMessage;
    const assistant = {
      ...message('assistant-1', 'assistant', 'final answer'),
      kind: 'assistant',
      created_at: '2026-05-24T20:16:42.000Z',
    } satisfies SessionMessage;

    const ordered = messagesInDisplayOrder([assistant, tool]);

    expect(ordered.map((item) => item.id)).toEqual(['tool-1', 'assistant-1']);
    expect(ordered.at(-1)?.id).toBe('assistant-1');
  });
});

describe('shouldApplySessionAsyncResult', () => {
  it('allows applying a result only to the session that started the request', () => {
    expect(shouldApplySessionAsyncResult('session-a', 'session-a')).toBe(true);
    expect(shouldApplySessionAsyncResult('session-b', 'session-a')).toBe(false);
    expect(shouldApplySessionAsyncResult('', 'session-a')).toBe(false);
    expect(shouldApplySessionAsyncResult('session-a', '')).toBe(false);
  });

  it('treats an empty request session as stale', () => {
    expect(shouldApplySessionAsyncResult('', '')).toBe(false);
  });

  it('blocks results after the owning component has unmounted', () => {
    expect(shouldApplySessionAsyncResult('session-a', 'session-a', false)).toBe(false);
  });
});

describe('shouldApplyPollingMessageWindow', () => {
  it('skips running phase-guard windows while SSE is live', () => {
    expect(shouldApplyPollingMessageWindow(true, 'responding')).toBe(false);
    expect(shouldApplyPollingMessageWindow(true, 'toolCalling')).toBe(false);
  });

  it('allows the idle fallback frame and all non-SSE polling windows', () => {
    expect(shouldApplyPollingMessageWindow(true, 'idle')).toBe(true);
    expect(shouldApplyPollingMessageWindow(false, 'responding')).toBe(true);
  });
});
