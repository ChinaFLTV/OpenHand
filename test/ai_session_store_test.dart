import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  test('AiSessionStore persists and reloads session json files', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_ai_session_store_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final store = AiSessionStore(sessionsDirectoryPath: tempDirectory.path);
    final session = AiSession(
      id: 'session-1',
      title: 'Need a deployment checklist',
      templateId: 'default',
      templateName: 'Default Assistant',
      templateIconName: 'auto_awesome_rounded',
      templateInternalVersion: '1.0.0',
      createdAt: DateTime.utc(2026, 3, 22, 9, 0, 0),
      updatedAt: DateTime.utc(2026, 3, 22, 9, 5, 0),
      messages: <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-1',
          content: 'Help me prepare a deployment checklist.',
          createdAt: DateTime.utc(2026, 3, 22, 9, 0, 0),
        ),
      ],
      environment: const AiSessionEnvironment(
        localeTag: 'en-US',
        platform: 'macos',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        applicationDirectory: '/workspace/openhand',
        homeDirectory: '/Users/example',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath:
            '/workspace/openhand/.openhand/memory/user-memory.json',
        sessionsDirectoryPath: '/Users/example/.openhand/sessions',
        compressionThresholdChars: 12000,
      ),
      statistics: const AiSessionStatistics.initial(),
      recentErrors: const <AiSessionErrorRecord>[],
    );

    await store.save(session);

    final reloaded = await store.loadAll();

    expect(reloaded.issues, isEmpty);
    expect(reloaded.sessions, hasLength(1));
    expect(reloaded.sessions.single.id, 'session-1');
    expect(
      reloaded.sessions.single.messages.single.content,
      contains('deployment'),
    );
    expect(
      File(p.join(tempDirectory.path, 'session-session-1.json')).existsSync(),
      isTrue,
    );
  });

  test('AiSessionStore preserves presented session errors', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_ai_session_error_store_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final store = AiSessionStore(sessionsDirectoryPath: tempDirectory.path);
    final session = AiSession(
      id: 'session-error',
      title: 'Need error persistence',
      templateId: 'default',
      templateName: 'Default Assistant',
      templateIconName: 'auto_awesome_rounded',
      templateInternalVersion: '1.0.0',
      createdAt: DateTime.utc(2026, 3, 22, 10, 0, 0),
      updatedAt: DateTime.utc(2026, 3, 22, 10, 5, 0),
      messages: const <AiSessionMessage>[],
      environment: const AiSessionEnvironment(
        localeTag: 'en-US',
        platform: 'macos',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        applicationDirectory: '/workspace/openhand',
        homeDirectory: '/Users/example',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath:
            '/workspace/openhand/.openhand/memory/user-memory.json',
        sessionsDirectoryPath: '/Users/example/.openhand/sessions',
        compressionThresholdChars: 12000,
      ),
      statistics: const AiSessionStatistics.initial(),
      recentErrors: <AiSessionErrorRecord>[
        AiSessionErrorRecord(
          id: 'error-1',
          createdAt: DateTime.utc(2026, 3, 22, 10, 5, 0),
          stage: 'chat_request',
          message: 'Request failed',
          detail: 'Request failed',
          presentedAt: DateTime.utc(2026, 3, 22, 10, 6, 0),
        ),
      ],
    );

    await store.save(session);

    final reloaded = await store.loadAll();

    expect(reloaded.sessions, hasLength(1));
    expect(reloaded.sessions.single.recentErrors, hasLength(1));
    expect(
      reloaded.sessions.single.recentErrors.single.hasBeenPresented,
      isTrue,
    );
    expect(
      reloaded.sessions.single.recentErrors.single.presentedAt,
      DateTime.utc(2026, 3, 22, 10, 6, 0),
    );
  });

  test('AiSessionStore backs up invalid session files on load', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_ai_session_invalid_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final invalidFile = File(p.join(tempDirectory.path, 'session-broken.json'));
    await invalidFile.writeAsString('{broken', flush: true);
    final store = AiSessionStore(sessionsDirectoryPath: tempDirectory.path);

    final loadResult = await store.loadAll();

    expect(loadResult.sessions, isEmpty);
    expect(loadResult.issues, hasLength(1));
    expect(
      loadResult.issues.single.kind,
      AiSessionPersistenceIssueKind.recoveredInvalidFile,
    );
    final backupFiles = tempDirectory
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).contains('.invalid-'))
        .toList();
    expect(backupFiles, isNotEmpty);
  });

  test(
    'AiSessionStore delete removes the session attachment subtree',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_ai_session_delete_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final store = AiSessionStore(sessionsDirectoryPath: tempDirectory.path);
      final session = AiSession(
        id: 'session-delete',
        title: 'Need attachment cleanup',
        templateId: 'default',
        templateName: 'Default Assistant',
        templateIconName: 'auto_awesome_rounded',
        templateInternalVersion: '1.0.0',
        createdAt: DateTime.utc(2026, 3, 25, 10, 0, 0),
        updatedAt: DateTime.utc(2026, 3, 25, 10, 5, 0),
        messages: const <AiSessionMessage>[],
        environment: const AiSessionEnvironment(
          localeTag: 'en-US',
          platform: 'macos',
          appVersion: '0.1.0',
          appBuildNumber: '1',
          applicationDirectory: '/workspace/openhand',
          homeDirectory: '/Users/example',
          settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
          skillsStoragePath: '/Users/example/.openhand/skills',
          mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
          userMemoryFilePath:
              '/workspace/openhand/.openhand/memory/user-memory.json',
          sessionsDirectoryPath: '/Users/example/.openhand/sessions',
          compressionThresholdChars: 12000,
        ),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );
      await store.save(session);
      final attachmentDirectory = Directory(
        store.sessionAttachmentsDirectoryPath('session-delete/message-1'),
      );
      await attachmentDirectory.create(recursive: true);
      await File(
        p.join(attachmentDirectory.path, 'attachment.txt'),
      ).writeAsString('attachment', flush: true);

      await store.delete('session-delete');

      expect(
        File(store.sessionFilePath('session-delete')).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          store.sessionAttachmentsDirectoryPath('session-delete'),
        ).existsSync(),
        isFalse,
      );
    },
  );
}
