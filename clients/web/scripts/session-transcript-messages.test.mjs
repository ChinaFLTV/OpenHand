/**
 * Run: node --experimental-strip-types clients/web/scripts/session-transcript-messages.test.mjs
 */
import assert from 'node:assert/strict';
import { displayableTranscriptMessages } from '../src/shared/util/session_transcript_messages.ts';

function test(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

function message(partial) {
  return {
    id: partial.id,
    kind: partial.kind ?? 'assistant',
    role: partial.role ?? 'assistant',
    content: partial.content ?? '',
    created_at: partial.created_at ?? '2026-01-01T00:00:00.000Z',
    character_count: partial.content?.length ?? 0,
    metadata: partial.metadata ?? {},
  };
}

test('hides paired tool results behind their tool-call card', () => {
  const messages = displayableTranscriptMessages([
    message({
      id: 'tool-call',
      kind: 'tool_call',
      content: 'Bash({})',
      metadata: { tool_call_id: 'call-1', tool_name: 'Bash', tool_arguments: '{}' },
    }),
    message({
      id: 'tool-result',
      kind: 'tool',
      role: 'tool',
      content: 'status: success\nstdout:\nok',
      metadata: { tool_call_id: 'call-1', tool_name: 'Bash' },
    }),
  ]);

  assert.deepEqual(messages.map((item) => item.id), ['tool-call']);
});

test('hides orphan machine terminal results from partial history windows', () => {
  const messages = displayableTranscriptMessages([
    message({
      id: 'machine-terminal-result',
      kind: 'tool',
      role: 'tool',
      content: [
        'terminal_id: term-2',
        'status: running',
        'timed_out: false',
        'exit_code: 0',
        'duration_ms: 144',
        'output:',
        '[root@host ~]# echo ok',
      ].join('\n'),
      metadata: {
        tool_call_id: 'missing-call',
        tool_name: 'MachineTerminalExec',
        terminal_id: 'term-2',
      },
    }),
    message({ id: 'assistant', content: '继续处理后续步骤。' }),
  ]);

  assert.deepEqual(messages.map((item) => item.id), ['assistant']);
});

test('keeps ordinary orphan tool results for historical context', () => {
  const messages = displayableTranscriptMessages([
    message({
      id: 'ordinary-tool-result',
      kind: 'tool',
      role: 'tool',
      content: 'status: success\nstdout:\nok',
      metadata: { tool_call_id: 'missing-call', tool_name: 'Bash' },
    }),
  ]);

  assert.deepEqual(messages.map((item) => item.id), ['ordinary-tool-result']);
});

if (process.exitCode) {
  console.error('session_transcript_messages tests failed');
  process.exit(process.exitCode);
}
console.log('all session_transcript_messages tests passed');
