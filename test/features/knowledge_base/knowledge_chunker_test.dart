import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_source.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_chunker.dart';

void main() {
  test('uses markdown headings as parent paths for default strategy', () {
    final chunks = const KnowledgeChunker().chunk(
      source: _source(),
      text: '# Alpha\n\nAlpha body.\n\n## Beta\n\nBeta body.',
      settings: const KnowledgeBaseSettings(
        targetTokens: 50,
        hardMaxTokens: 80,
      ),
    );

    expect(chunks, hasLength(2));
    expect(chunks.first.headingPath, 'Alpha');
    expect(chunks.last.headingPath, 'Alpha > Beta');
    expect(chunks.last.startOffset, greaterThan(chunks.first.startOffset!));
    expect(
      chunks.every(
        (chunk) =>
            chunk.metadata['strategy'] ==
            KnowledgeChunkStrategy.markdownHeadingRecursive,
      ),
      isTrue,
    );
  });

  test('fixed token strategy splits long text without stalling', () {
    final chunks = const KnowledgeChunker().chunk(
      source: _source(),
      text: List<String>.generate(24, (index) => 'segment$index').join(' '),
      settings: const KnowledgeBaseSettings(
        chunkStrategy: KnowledgeChunkStrategy.fixedTokenWindow,
        targetTokens: 6,
        hardMaxTokens: 8,
        overlapTokens: 2,
      ),
    );

    expect(chunks.length, greaterThan(2));
    expect(chunks.map((chunk) => chunk.id).toSet(), hasLength(chunks.length));
    expect(
      chunks.every(
        (chunk) =>
            chunk.metadata['strategy'] ==
            KnowledgeChunkStrategy.fixedTokenWindow,
      ),
      isTrue,
    );
  });

  test('paragraph strategy ignores markdown hierarchy', () {
    final chunks = const KnowledgeChunker().chunk(
      source: _source(),
      text: '# Title\n\nFirst paragraph.\n\nSecond paragraph.',
      settings: const KnowledgeBaseSettings(
        chunkStrategy: KnowledgeChunkStrategy.paragraphWindow,
        targetTokens: 8,
        hardMaxTokens: 12,
        overlapTokens: 0,
      ),
    );

    expect(chunks, isNotEmpty);
    expect(chunks.every((chunk) => chunk.headingPath.isEmpty), isTrue);
    expect(chunks.first.title, 'Source Title');
  });
}

KnowledgeSource _source() {
  final now = DateTime.utc(2026);
  return KnowledgeSource(
    id: 'source_1',
    title: 'Source Title',
    kind: 'markdown',
    originalPath: '/tmp/source.md',
    storedPath: '/tmp/source.md',
    mimeType: 'text/markdown',
    sizeBytes: 128,
    contentHash: 'hash',
    status: 'indexed',
    errorMessage: '',
    importedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}
