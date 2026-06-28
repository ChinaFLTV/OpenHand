import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late AiSessionStore store;

  setUp(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_ai_session_store_parsing_test_',
    );
    await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand.db'),
      useNoIsolateFactory: true,
    );
    store = AiSessionStore(sessionsDirectoryPath: tempDir.path);
  });

  tearDown(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads loose sqlite numeric flags and json maps safely', () async {
    final now = DateTime.utc(2026, 6, 28, 12);
    final session = _session(
      now: now,
      metadata: <String, Object?>{'saved': true},
    );
    await store.save(session);

    final db = DatabaseService.instance.database;
    await db.update(
      'sessions',
      <String, Object?>{
        'pinned': '1',
        'archived': 'yes',
        'is_title_manually_edited': '1',
        'awaiting_plan_approval': 'enabled',
        'full_access_permission': 'true',
        'metadata_json': '{"numeric_key":7,"9":"string-keyed"}',
        'todo_items_json': jsonEncode(<Object?>[
          <Object?, Object?>{
            'id': 1,
            'content': ' write tests ',
            'status': 'completed',
          },
          'ignored',
        ]),
      },
      where: 'id = ?',
      whereArgs: <Object?>[session.id],
    );
    await db.update(
      'messages',
      <String, Object?>{
        'character_count': '42',
        'is_deleted': 'true',
        'usage_json': jsonEncode(<Object?, Object?>{
          'prompt_tokens': 11,
          'completion_tokens': 7,
          'total_tokens': 18,
        }),
        'metadata_json': '{"5":"message-meta"}',
      },
      where: 'id = ?',
      whereArgs: const <Object?>['message-1'],
    );

    final flags = await store.loadSessionFlags();
    expect(flags[session.id]?.pinned, isTrue);
    expect(flags[session.id]?.archived, isTrue);

    final loaded = await store.loadAll(includeArchived: true);
    expect(loaded.issues, isEmpty);
    final loadedSession = loaded.sessions.single;
    expect(loadedSession.isTitleManuallyEdited, isTrue);
    expect(loadedSession.awaitingPlanApproval, isTrue);
    expect(loadedSession.fullAccessPermission, isTrue);
    expect(loadedSession.metadata['numeric_key'], 7);
    expect(loadedSession.metadata['9'], 'string-keyed');
    expect(loadedSession.todoItems.single.id, '1');
    expect(loadedSession.todoItems.single.content, ' write tests ');

    final message = loadedSession.messages.single;
    expect(message.characterCount, 42);
    expect(message.isDeleted, isTrue);
    expect(message.metadata['5'], 'message-meta');
    expect(message.usage?.promptTokens, 11);
    expect(message.usage?.completionTokens, 7);
    expect(message.usage?.totalTokens, 18);
  });
}

AiSession _session({
  required DateTime now,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return AiSession(
    id: 'session-1',
    title: 'Parsing session',
    templateId: 'chat',
    templateName: 'Chat',
    templateIconName: 'chat',
    templateInternalVersion: '1',
    createdAt: now,
    updatedAt: now,
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'test',
      appVersion: 'test',
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
    messages: <AiSessionMessage>[
      AiSessionMessage.user(id: 'message-1', content: 'hello', createdAt: now),
    ],
    metadata: metadata,
  );
}
