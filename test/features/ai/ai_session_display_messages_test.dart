import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  group('AiSession.displayMessages', () {
    test('hides paired tool results behind their tool-call card', () {
      final session = _session(<AiSessionMessage>[
        _toolCall(id: 'call-card', toolCallId: 'call-1', toolName: 'Bash'),
        _toolResult(
          id: 'tool-result',
          content: 'status: success\nstdout:\nok',
          metadata: <String, Object?>{
            'tool_call_id': 'call-1',
            'tool_name': 'Bash',
          },
        ),
      ]);

      expect(session.displayMessages.map((item) => item.id), <String>[
        'call-card',
      ]);
    });

    test(
      'hides orphan machine terminal tool results from windowed history',
      () {
        final session = _session(<AiSessionMessage>[
          _toolResult(
            id: 'machine-terminal-result',
            content:
                'terminal_id: term-2\n'
                'status: running\n'
                'timed_out: false\n'
                'exit_code: 0\n'
                'duration_ms: 144\n'
                'output:\n'
                '[root@host ~]# echo ok',
            metadata: <String, Object?>{
              'tool_call_id': 'missing-call',
              'tool_name': 'MachineTerminalExec',
              'terminal_id': 'term-2',
            },
          ),
          AiSessionMessage.assistant(
            id: 'assistant',
            content: '继续处理后续步骤。',
            createdAt: _time(1),
          ),
        ]);

        expect(session.displayMessages.map((item) => item.id), <String>[
          'assistant',
        ]);
      },
    );

    test('keeps ordinary orphan tool results so history still has context', () {
      final session = _session(<AiSessionMessage>[
        _toolResult(
          id: 'ordinary-tool-result',
          content: 'status: success\nstdout:\nok',
          metadata: <String, Object?>{
            'tool_call_id': 'missing-call',
            'tool_name': 'Bash',
          },
        ),
      ]);

      expect(session.displayMessages.single.id, 'ordinary-tool-result');
    });
  });
}

AiSession _session(List<AiSessionMessage> messages) {
  return AiSession(
    id: 'session-test',
    title: 'Session test',
    templateId: 'machine_expert',
    templateName: 'Machine expert',
    templateIconName: 'terminal',
    templateInternalVersion: '1',
    createdAt: _time(0),
    updatedAt: _time(messages.length + 1),
    messages: messages,
    environment: _environment(),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

AiSessionEnvironment _environment() {
  return AiSessionEnvironment(
    localeTag: 'zh-CN',
    platform: 'test',
    appVersion: '0.0.0',
    appBuildNumber: '0',
    applicationDirectory: '/',
    homeDirectory: '/',
    settingsFilePath: '/settings.json',
    skillsStoragePath: '/skills',
    mcpServersFilePath: '/mcp.json',
    userMemoryFilePath: '/memory.md',
    sessionsDirectoryPath: '/sessions',
    compressionThresholdChars: 0,
  );
}

AiSessionMessage _toolCall({
  required String id,
  required String toolCallId,
  required String toolName,
}) {
  return AiSessionMessage.toolCall(
    id: id,
    content: '$toolName({})',
    createdAt: _time(0),
    metadata: <String, Object?>{
      'tool_call_id': toolCallId,
      'tool_name': toolName,
      'tool_arguments': '{}',
    },
  );
}

AiSessionMessage _toolResult({
  required String id,
  required String content,
  required Map<String, Object?> metadata,
}) {
  return AiSessionMessage.toolResult(
    id: id,
    content: content,
    createdAt: _time(0),
    metadata: metadata,
  );
}

DateTime _time(int seconds) => DateTime.utc(2026, 1, 1, 0, 0, seconds);
