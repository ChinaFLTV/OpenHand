import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/data/knowledge_base_store.dart';
import 'package:openhand/shared/db/database_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_knowledge_base_store_test_',
    );
    await DatabaseService.initialize(
      databasePath: '${tempDir.path}/openhand.db',
      useNoIsolateFactory: true,
    );
    await _insertFixture();
  });

  tearDown(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('KnowledgeBaseStore', () {
    test('loadSourcesByIds normalizes duplicate and blank ids', () async {
      final store = KnowledgeBaseStore();

      final sources = await store.loadSourcesByIds(<String>[
        'source-1',
        '',
        ' source-1 ',
        'missing',
      ]);

      expect(sources.keys, <String>{'source-1'});
      expect(sources['source-1']!.title, 'Release notes');
    });

    test('loadChunksByIds normalizes duplicate and blank ids', () async {
      final store = KnowledgeBaseStore();

      final chunks = await store.loadChunksByIds(<String>[
        'chunk-1',
        'chunk-2',
        ' chunk-1 ',
        '',
      ]);

      expect(chunks.keys, <String>{'chunk-1', 'chunk-2'});
      expect(chunks['chunk-1']!.content, 'alpha');
      expect(chunks['chunk-2']!.content, 'beta');
    });

    test('loadChunksByIds returns an empty map for empty ids', () async {
      final store = KnowledgeBaseStore();

      expect(await store.loadChunksByIds(const <String>[]), isEmpty);
    });
  });
}

Future<void> _insertFixture() async {
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
  await db.insert('knowledge_chunks', <String, Object?>{
    'id': 'chunk-1',
    'source_id': 'source-1',
    'chunk_index': 0,
    'content': 'alpha',
    'content_hash': 'chunk-hash-1',
    'char_count': 5,
    'token_estimate': 1,
    'created_at': now,
    'updated_at': now,
    'metadata_json': '{}',
  });
  await db.insert('knowledge_chunks', <String, Object?>{
    'id': 'chunk-2',
    'source_id': 'source-1',
    'chunk_index': 1,
    'content': 'beta',
    'content_hash': 'chunk-hash-2',
    'char_count': 4,
    'token_estimate': 1,
    'created_at': now,
    'updated_at': now,
    'metadata_json': '{}',
  });
}
