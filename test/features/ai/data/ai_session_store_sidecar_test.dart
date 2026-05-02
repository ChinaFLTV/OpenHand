import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';

void main() {
  test('writes compact memory sidecar files', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand-sidecar-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = AiSessionStore(sessionsDirectoryPath: root.path);
    final now = DateTime.utc(2026, 5, 3);
    final checkpoint = AiSessionMessage.compressionPoint(
      id: 'checkpoint-1',
      content: '## Summary\nPersisted compact memory.',
      createdAt: now,
      metadata: const <String, Object?>{'source_character_count': 1234},
    );
    final session = AiSession(
      id: 'session-1',
      title: 'Sidecar Test',
      templateId: 'default',
      templateName: 'Default Assistant',
      templateIconName: 'auto_awesome_rounded',
      templateInternalVersion: '1.0.0',
      createdAt: now,
      updatedAt: now,
      messages: <AiSessionMessage>[checkpoint],
      environment: AiSessionEnvironment(
        localeTag: 'zh-Hans',
        platform: 'macos',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        applicationDirectory: root.path,
        homeDirectory: root.path,
        settingsFilePath: '${root.path}/settings.json',
        skillsStoragePath: '${root.path}/skills',
        mcpServersFilePath: '${root.path}/mcp.json',
        userMemoryFilePath: '${root.path}/memory.md',
        sessionsDirectoryPath: root.path,
        compressionThresholdChars: 12000,
      ),
      statistics: AiSessionStatistics.fromMessages(
        <AiSessionMessage>[checkpoint],
        totalPromptCharacters: 0,
        promptBuildCount: 0,
        compressionRunCount: 1,
        totalUsage: const AiTokenUsage(),
        lastPromptSystemMessageCount: 0,
        lastPromptHistoryMessageCount: 0,
      ),
      recentErrors: const <AiSessionErrorRecord>[],
    );

    await store.saveCompressionMemorySidecar(
      session: session,
      checkpoint: checkpoint,
    );

    final markdown = await File(
      store.sessionCompactMemoryMarkdownPath(session.id),
    ).readAsString();
    final metadata =
        jsonDecode(
              await File(
                store.sessionCompactMemoryMetadataPath(session.id),
              ).readAsString(),
            )
            as Map<String, Object?>;

    expect(markdown, contains('# OpenHand Session Compact Memory'));
    expect(markdown, contains('checkpoint_message_id: checkpoint-1'));
    expect(markdown, contains('Persisted compact memory.'));
    expect(metadata['schema'], 'openhand.compact_memory.v1');
    expect(metadata['session_id'], session.id);
    expect(metadata['checkpoint_message_id'], checkpoint.id);
    expect(metadata['checkpoint_character_count'], checkpoint.characterCount);
  });
}
