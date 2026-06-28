import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/tools/knowledge/ai_knowledge_base_tool.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_message_metadata.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_knowledge_tool_test_',
    );
    await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand.db'),
      useNoIsolateFactory: true,
    );
    await _seedKnowledgeBase();
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
    'compound search ranks the matching chunk instead of source-wide hits',
    () async {
      final result = await AiKnowledgeSearchTool().execute(
        _context(
          toolName: 'KnowledgeSearch',
          args: <String, Object?>{'query': '鞠婧祎 纪录片', 'top_k': 3},
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final decoded = jsonDecode(result.resultText) as Map<String, Object?>;
      final rows = decoded['results'] as List;
      expect(rows, isNotEmpty);
      expect((rows.first as Map)['chunk_id'], 'source-1_chunk_2');
      expect(result.resultText, isNot(contains('/tmp/jjy.md')));

      final kb =
          result.metadata[knowledgeBaseMessageMetadataKey]
              as Map<String, Object?>;
      expect(kb['status'], 'success');
      expect(kb['retrieval'], isA<Map>());
      expect(kb['rerank'], isA<Map>());
    },
  );

  test(
    'source reads return bounded previews and never dump raw row content',
    () async {
      final result = await AiKnowledgeReadTool().execute(
        _context(
          toolName: 'KnowledgeRead',
          args: <String, Object?>{'source_id': 'source-1', 'limit': 50},
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final decoded = jsonDecode(result.resultText) as Map<String, Object?>;
      final rows = decoded['results'] as List;
      expect(rows, hasLength(4));
      expect(
        rows.whereType<Map>().any((row) => row.containsKey('content')),
        isFalse,
      );
      expect(result.resultText, isNot(contains('/tmp/jjy.md')));
      expect(result.resultText, contains('small preview only'));
    },
  );

  test(
    'chunk reads return exact chunk content without exposing source paths',
    () async {
      final result = await AiKnowledgeReadTool().execute(
        _context(
          toolName: 'KnowledgeRead',
          args: <String, Object?>{'chunk_id': 'source-1_chunk_2'},
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final decoded = jsonDecode(result.resultText) as Map<String, Object?>;
      final rows = decoded['results'] as List;
      final row = rows.single as Map;
      expect(row['content'], contains('DOCUMENTARY of SNH48'));
      expect(result.resultText, isNot(contains('/tmp/jjy.md')));
    },
  );
}

AiToolExecutionContext _context({
  required String toolName,
  required Map<String, Object?> args,
}) {
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call-1',
      name: toolName,
      arguments: jsonEncode(args),
    ),
    decodedArguments: args,
    model: const AiModelConfig(
      id: 'model-1',
      baseUrl: 'https://example.invalid',
      authScheme: AiAuthScheme.bearer,
      token: '',
      modelId: 'chat-model',
      protocolType: AiProtocolType.openai,
    ),
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
  );
}

Future<void> _seedKnowledgeBase() async {
  final db = DatabaseService.instance.database;
  final now = DateTime.utc(2026, 6, 28, 12).toIso8601String();
  await db.insert('knowledge_sources', <String, Object?>{
    'id': 'source-1',
    'title': '鞠婧祎公开资料汇总',
    'kind': 'markdown',
    'original_path': '/tmp/jjy.md',
    'stored_path': '/tmp/jjy.md',
    'mime_type': 'text/markdown',
    'size_bytes': 4096,
    'content_hash': 'source-hash',
    'status': 'indexed',
    'error_message': '',
    'document_time': now,
    'imported_at': now,
    'indexed_at': now,
    'created_at': now,
    'updated_at': now,
    'metadata_json': '{}',
  });
  final chunks = <({String heading, String content})>[
    (heading: '鞠婧祎公开资料汇总 > 1. 基本资料', content: '鞠婧祎，中国内地女歌手、演员，公开资料基础信息整理。'),
    (heading: '鞠婧祎公开资料汇总 > 6.1 电视剧', content: '鞠婧祎参演电视剧与网络剧公开资料列表。'),
    (
      heading: '鞠婧祎公开资料汇总 > 6.3 纪录片 / 微纪实',
      content:
          '鞠婧祎纪录片与微纪实：2015-06-22《七分七秒》；2015-06-22《DOCUMENTARY of SNH48 少女的巴别塔》；2016-06-01《DOCUMENTARY of SNH48 比翼齐飞》。',
    ),
    (heading: '鞠婧祎公开资料汇总 > 7. 音乐作品', content: '鞠婧祎音乐作品、单曲与舞台公开资料列表。'),
    (heading: '鞠婧祎公开资料汇总 > 8. 综艺活动', content: '鞠婧祎综艺、活动、晚会公开资料列表。'),
  ];
  for (var index = 0; index < chunks.length; index += 1) {
    final chunk = chunks[index];
    await db.insert('knowledge_chunks', <String, Object?>{
      'id': 'source-1_chunk_$index',
      'source_id': 'source-1',
      'chunk_index': index,
      'parent_chunk_id': null,
      'title': '鞠婧祎公开资料汇总',
      'heading_path': chunk.heading,
      'content': chunk.content,
      'content_hash': 'chunk-$index',
      'char_count': chunk.content.length,
      'token_estimate': 32,
      'start_offset': null,
      'end_offset': null,
      'page_number': null,
      'document_time': now,
      'created_at': now,
      'updated_at': now,
      'metadata_json': '{}',
    });
  }
}
