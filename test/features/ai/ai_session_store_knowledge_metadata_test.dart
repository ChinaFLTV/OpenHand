import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_message_metadata.dart';
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
      'openhand_ai_session_store_test_',
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

  test(
    'loadMessages carries previous user knowledge references into leading assistant window',
    () async {
      final now = DateTime.utc(2026, 6, 28, 12);
      final knowledgeBaseMetadata = <String, Object?>{
        'enabled': true,
        'status': 'success',
        'query': 'OpenHand knowledge base',
        'results': <Object?>[
          <String, Object?>{
            'source_id': 'source-1',
            'chunk_id': 'chunk-1',
            'title': 'OpenHand Knowledge Base',
            'content': 'Chunk content',
          },
        ],
        'prompt_append': <String, Object?>{
          'chunk_count': 1,
          'token_estimate': 24,
          'content_hash': 'hash',
        },
        knowledgeBasePromptAppendMetadataKey: 'Prompt-only retrieved content',
      };
      final session = AiSession(
        id: 'session-kb-window',
        title: 'Knowledge window',
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
          AiSessionMessage.user(
            id: 'user-1',
            content: 'Summarize this document',
            createdAt: now,
            metadata: <String, Object?>{
              knowledgeBaseMessageMetadataKey: knowledgeBaseMetadata,
            },
          ),
          AiSessionMessage.assistant(
            id: 'assistant-1',
            content: 'Here is the summary.',
            createdAt: now.add(const Duration(seconds: 1)),
          ),
        ],
      );

      await store.save(session);
      final page = await store.loadMessages(session.id, limit: 1, offset: 1);

      expect(page.messages, hasLength(1));
      final assistant = page.messages.single;
      final assistantKnowledgeBaseMetadata =
          KnowledgeMessageMetadata.fromMessageMetadata(assistant.metadata);
      expect(assistantKnowledgeBaseMetadata, isNotNull);
      expect(
        KnowledgeMessageMetadata.hasReferences(assistantKnowledgeBaseMetadata!),
        isTrue,
      );
      expect(
        assistantKnowledgeBaseMetadata.containsKey(
          knowledgeBasePromptAppendMetadataKey,
        ),
        isFalse,
      );
    },
  );
}
