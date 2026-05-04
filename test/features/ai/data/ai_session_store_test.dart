import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AiSessionStore store;

  setUp(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_session_store_test_',
    );
    await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand.db'),
      useNoIsolateFactory: true,
    );
    store = AiSessionStore(
      sessionsDirectoryPath: p.join(tempDir.path, 'sessions'),
    );
  });

  tearDown(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save preserves session management columns', () async {
    final createdAt = DateTime.utc(2026, 1, 1, 12);
    final firstSession = _session(
      title: 'First title',
      updatedAt: createdAt,
      messages: <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-1',
          content: 'hello',
          createdAt: createdAt,
        ),
      ],
    );

    await store.save(firstSession);
    await DatabaseService.instance.database.update(
      'sessions',
      <String, Object?>{'display_order': 7, 'pinned': 1, 'archived': 1},
      where: 'id = ?',
      whereArgs: <Object?>[firstSession.id],
    );

    await store.save(
      firstSession.copyWith(
        title: 'Updated title',
        updatedAt: createdAt.add(const Duration(minutes: 1)),
        messages: <AiSessionMessage>[
          ...firstSession.messages,
          AiSessionMessage.user(
            id: 'message-2',
            content: 'world',
            createdAt: createdAt.add(const Duration(minutes: 1)),
          ),
        ],
      ),
    );

    final rows = await DatabaseService.instance.database.query(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object?>[firstSession.id],
      limit: 1,
    );
    expect(rows.single['title'], 'Updated title');
    expect(rows.single['display_order'], 7);
    expect(rows.single['pinned'], 1);
    expect(rows.single['archived'], 1);

    final loaded = await store.loadSession(firstSession.id);
    expect(loaded?.messages.map((message) => message.id), <String>[
      'message-1',
      'message-2',
    ]);
  });
}

AiSession _session({
  required String title,
  required DateTime updatedAt,
  required List<AiSessionMessage> messages,
}) {
  return AiSession(
    id: 'session-1',
    title: title,
    templateId: 'default',
    templateName: 'Default',
    templateIconName: 'chat',
    templateInternalVersion: '1',
    createdAt: DateTime.utc(2026, 1, 1, 12),
    updatedAt: updatedAt,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'en',
      platform: 'test',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}
