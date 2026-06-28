import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/data/knowledge_base_store.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_chunk.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late KnowledgeBaseStore store;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE knowledge_sources (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL DEFAULT '',
              kind TEXT NOT NULL DEFAULT 'note',
              original_path TEXT NOT NULL DEFAULT '',
              stored_path TEXT NOT NULL DEFAULT '',
              mime_type TEXT NOT NULL DEFAULT '',
              size_bytes INTEGER NOT NULL DEFAULT 0,
              content_hash TEXT NOT NULL DEFAULT '',
              status TEXT NOT NULL DEFAULT 'pending',
              error_message TEXT NOT NULL DEFAULT '',
              document_time TEXT,
              imported_at TEXT NOT NULL,
              indexed_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              metadata_json TEXT NOT NULL DEFAULT '{}'
            )
          ''');
          await database.execute('''
            CREATE TABLE knowledge_chunks (
              id TEXT PRIMARY KEY,
              source_id TEXT NOT NULL,
              chunk_index INTEGER NOT NULL DEFAULT 0,
              parent_chunk_id TEXT,
              title TEXT NOT NULL DEFAULT '',
              heading_path TEXT NOT NULL DEFAULT '',
              content TEXT NOT NULL DEFAULT '',
              content_hash TEXT NOT NULL DEFAULT '',
              char_count INTEGER NOT NULL DEFAULT 0,
              token_estimate INTEGER NOT NULL DEFAULT 0,
              start_offset INTEGER,
              end_offset INTEGER,
              page_number INTEGER,
              document_time TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              metadata_json TEXT NOT NULL DEFAULT '{}',
              FOREIGN KEY (source_id) REFERENCES knowledge_sources(id) ON DELETE CASCADE
            )
          ''');
          await database.execute('''
            CREATE TABLE knowledge_embedding_jobs (
              id TEXT PRIMARY KEY,
              chunk_id TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              FOREIGN KEY (chunk_id) REFERENCES knowledge_chunks(id) ON DELETE CASCADE
            )
          ''');
        },
        version: 1,
      ),
    );
    store = KnowledgeBaseStore(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'upsertSource updates source without cascading existing chunks',
    () async {
      final now = DateTime.utc(2026, 6, 28);
      final source = KnowledgeSource(
        id: 'source-1',
        title: 'Doc',
        kind: 'markdown',
        originalPath: '/tmp/doc.md',
        storedPath: '/tmp/doc.md',
        mimeType: 'text/markdown',
        sizeBytes: 42,
        contentHash: 'hash',
        status: 'indexing',
        errorMessage: '',
        importedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      final chunk = KnowledgeChunk(
        id: 'source-1_chunk_0',
        sourceId: source.id,
        chunkIndex: 0,
        title: 'Doc',
        headingPath: 'Doc',
        content: 'Indexed content',
        contentHash: 'chunk-hash',
        charCount: 15,
        tokenEstimate: 3,
        createdAt: now,
        updatedAt: now,
      );

      await store.upsertSource(source);
      await store.replaceChunks(
        sourceId: source.id,
        chunks: <KnowledgeChunk>[chunk],
      );
      await store.upsertSource(
        source.copyWith(
          status: 'indexed',
          indexedAt: now.add(const Duration(seconds: 1)),
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
      );

      final chunks = await store.loadChunksForSource(source.id);
      expect(chunks, hasLength(1));
      expect(chunks.single.id, chunk.id);
      expect((await store.loadStats()).chunkCount, 1);
    },
  );

  test('row models normalize persisted numeric fields', () {
    final source = KnowledgeSource.fromRow(<String, Object?>{
      'id': 'source-1',
      'title': 'Doc',
      'size_bytes': double.infinity,
      'imported_at': '2026-06-28T00:00:00Z',
      'created_at': '2026-06-28T00:00:00Z',
      'updated_at': '2026-06-28T00:00:00Z',
    });
    expect(source.sizeBytes, 0);

    final chunk = KnowledgeChunk.fromRow(<String, Object?>{
      'id': 'chunk-1',
      'source_id': 'source-1',
      'chunk_index': '-1',
      'char_count': '128',
      'token_estimate': double.nan,
      'start_offset': -5,
      'end_offset': '256',
      'page_number': double.infinity,
      'created_at': '2026-06-28T00:00:00Z',
      'updated_at': '2026-06-28T00:00:00Z',
    });
    expect(chunk.chunkIndex, 0);
    expect(chunk.charCount, 128);
    expect(chunk.tokenEstimate, 0);
    expect(chunk.startOffset, isNull);
    expect(chunk.endOffset, 256);
    expect(chunk.pageNumber, isNull);
  });
}
