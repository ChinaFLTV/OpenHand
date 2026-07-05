import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/knowledge/ai_knowledge_base_tool.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_message_metadata.dart';
import 'package:openhand/shared/db/database_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_knowledge_tool_test_',
    );
    await DatabaseService.initialize(
      databasePath: '${tempDir.path}/openhand.db',
      useNoIsolateFactory: true,
    );
    await _insertKnowledgeFixture();
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
    'KnowledgeSearch reports non-negative discarded count after topK cap',
    () async {
      final result = await AiKnowledgeSearchTool().execute(
        _contextForKnowledgeSearch(<String, Object?>{
          'query': 'alpha beta',
          'top_k': 2,
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final knowledgeBase =
          result.metadata[knowledgeBaseMessageMetadataKey]
              as Map<String, Object?>;
      final rerank = knowledgeBase['rerank'] as Map<String, Object?>;
      final results = knowledgeBase['results'] as List<Object?>;

      expect(results, hasLength(2));
      expect(rerank['candidate_count'], 3);
      expect(rerank['rerank_input_count'], 3);
      expect(rerank['rerank_output_count'], 2);
      expect(rerank['kept_count'], 2);
      expect(rerank['discarded_count'], 1);
    },
  );
}

AiToolExecutionContext _contextForKnowledgeSearch(
  Map<String, Object?> arguments,
) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: const AiToolCall(
      id: 'tool-call-1',
      name: 'KnowledgeSearch',
      arguments: '{}',
    ),
    decodedArguments: arguments,
    model: const AiModelConfig(
      id: 'test-model',
      baseUrl: 'http://localhost',
      authScheme: AiAuthScheme.none,
      token: '',
      modelId: 'test-model',
      protocolType: AiProtocolType.openai,
    ),
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
  );
}

Future<void> _insertKnowledgeFixture() async {
  final db = DatabaseService.instance.database;
  final now = DateTime.utc(2026, 1, 1, 12).toIso8601String();
  await db.insert('knowledge_sources', <String, Object?>{
    'id': 'source-1',
    'title': 'Release notes',
    'kind': 'note',
    'original_path': '',
    'stored_path': '',
    'mime_type': 'text/plain',
    'size_bytes': 128,
    'content_hash': 'source-hash',
    'status': 'indexed',
    'imported_at': now,
    'created_at': now,
    'updated_at': now,
    'metadata_json': '{}',
  });

  final contents = <String>[
    'alpha beta release plan',
    'alpha beta design note',
    'alpha beta stability checklist',
  ];
  for (var i = 0; i < contents.length; i += 1) {
    final content = contents[i];
    await db.insert('knowledge_chunks', <String, Object?>{
      'id': 'chunk-$i',
      'source_id': 'source-1',
      'chunk_index': i,
      'title': 'Chunk $i',
      'heading_path': 'Section $i',
      'content': content,
      'content_hash': 'chunk-hash-$i',
      'char_count': content.length,
      'token_estimate': 16,
      'created_at': now,
      'updated_at': now,
      'metadata_json': '{}',
    });
  }
}
