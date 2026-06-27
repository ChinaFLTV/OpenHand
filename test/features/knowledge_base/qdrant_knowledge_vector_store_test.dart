import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/service/qdrant_knowledge_vector_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('qdrant point id is a stable uuid for chunk ids', () {
    const chunkId = 'f9a59f62-f0c1-431a-8fc5-15d60edae123_chunk_0';

    final first = qdrantPointIdForStableId(chunkId);
    final second = qdrantPointIdForStableId(chunkId);

    expect(first, second);
    expect(first, isA<String>());
    expect(Uuid.isValidUUID(fromString: first as String), isTrue);
  });

  test('qdrant point id preserves existing uuid and unsigned integer ids', () {
    const uuid = 'f9a59f62-f0c1-431a-8fc5-15d60edae123';

    expect(qdrantPointIdForStableId(uuid), uuid);
    expect(qdrantPointIdForStableId('42'), 42);
  });
}
