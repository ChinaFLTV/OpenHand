import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  test('AiSession clamps negative message window indexes', () {
    final session = _session(
      messageWindowStartIndex: -8,
      messageTotalCount: -3,
    );

    expect(session.messageWindowStartIndex, 0);
    expect(session.messageTotalCount, 0);
  });

  test('AiSession keeps total message count at least loaded count', () {
    final now = DateTime.utc(2026);
    final session = _session(
      messages: <AiSessionMessage>[
        AiSessionMessage.user(id: 'user-1', content: 'Hi', createdAt: now),
        AiSessionMessage.assistant(
          id: 'assistant-1',
          content: 'Hello',
          createdAt: now,
        ),
      ],
      messageTotalCount: 1,
    );

    expect(session.messageTotalCount, 2);
  });
}

AiSession _session({
  List<AiSessionMessage> messages = const <AiSessionMessage>[],
  int? messageWindowStartIndex,
  int? messageTotalCount,
}) {
  final now = DateTime.utc(2026);
  return AiSession(
    id: 'session-1',
    title: 'Session',
    templateId: 'template',
    templateName: 'Template',
    templateIconName: 'message',
    templateInternalVersion: '1',
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: _testEnvironment,
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    messageWindowStartIndex: messageWindowStartIndex,
    messageTotalCount: messageTotalCount,
  );
}

const AiSessionEnvironment _testEnvironment = AiSessionEnvironment(
  localeTag: 'en',
  platform: 'test',
  appVersion: '1.0.0',
  appBuildNumber: '1',
  applicationDirectory: '',
  homeDirectory: '',
  settingsFilePath: '',
  skillsStoragePath: '',
  mcpServersFilePath: '',
  userMemoryFilePath: '',
  sessionsDirectoryPath: '',
  compressionThresholdChars: 0,
);
