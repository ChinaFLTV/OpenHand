import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/shared/db/database_service.dart';

void main() {
  late Directory tempDir;
  late AiSessionStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_ai_session_store_test_',
    );
    await DatabaseService.initialize(
      databasePath: '${tempDir.path}/openhand.db',
      useNoIsolateFactory: true,
    );
    store = AiSessionStore(sessionsDirectoryPath: '${tempDir.path}/sessions');
  });

  tearDown(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AiSessionStore', () {
    test(
      'loadAll batches messages by session id and preserves order',
      () async {
        final now = DateTime.utc(2026);
        await store.save(
          _session(
            id: 'session-1',
            updatedAt: now.add(const Duration(minutes: 2)),
            messages: <AiSessionMessage>[
              AiSessionMessage.user(id: 's1-u', content: 'one', createdAt: now),
              AiSessionMessage.assistant(
                id: 's1-a',
                content: 'two',
                createdAt: now.add(const Duration(seconds: 1)),
              ),
            ],
          ),
        );
        await store.save(
          _session(
            id: 'session-2',
            updatedAt: now.add(const Duration(minutes: 1)),
            messages: <AiSessionMessage>[
              AiSessionMessage.user(
                id: 's2-u',
                content: 'alpha',
                createdAt: now,
              ),
            ],
          ),
        );

        final result = await store.loadAll();
        final sessionsById = <String, AiSession>{
          for (final session in result.sessions) session.id: session,
        };

        expect(result.issues, isEmpty);
        expect(
          sessionsById['session-1']!.messages.map((message) => message.content),
          <String>['one', 'two'],
        );
        expect(
          sessionsById['session-2']!.messages.map((message) => message.content),
          <String>['alpha'],
        );
      },
    );

    test(
      'loadAllHeaders batches message counts without decoding messages',
      () async {
        final now = DateTime.utc(2026);
        await store.save(
          _session(
            id: 'session-1',
            updatedAt: now,
            messages: <AiSessionMessage>[
              AiSessionMessage.user(id: 's1-u', content: 'one', createdAt: now),
              AiSessionMessage.assistant(
                id: 's1-a',
                content: 'two',
                createdAt: now.add(const Duration(seconds: 1)),
              ),
            ],
          ),
        );

        final result = await store.loadAllHeaders();
        final session = result.sessions.single;

        expect(result.issues, isEmpty);
        expect(session.messages, isEmpty);
        expect(session.messageLoadState, AiSessionMessageLoadState.header);
        expect(session.messageTotalCount, 2);
      },
    );
  });
}

AiSession _session({
  required String id,
  required DateTime updatedAt,
  required List<AiSessionMessage> messages,
}) {
  final createdAt = DateTime.utc(2026);
  return AiSession(
    id: id,
    title: id,
    templateId: 'template',
    templateName: 'Template',
    templateIconName: 'message',
    templateInternalVersion: '1',
    createdAt: createdAt,
    updatedAt: updatedAt,
    messages: messages,
    environment: _testEnvironment,
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
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
