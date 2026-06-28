import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('catalog marks common reranker model ids as rerank capable', () {
    for (final modelId in const <String>[
      'jina-reranker-v2-base-multilingual',
      'bge-reranker-v2-m3',
      'qwen3-reranker-4b',
      'gte-rerank-v2',
      'cohere-rerank-v3.5',
    ]) {
      final profile = AiModelCatalog.lookup(modelId, AiProtocolType.openai);

      expect(profile, isNotNull, reason: modelId);
      expect(profile!.supportsRerank, isTrue, reason: modelId);
      expect(profile.supportsEmbeddings, isFalse, reason: modelId);
    }
  });

  test('model profile parses rerank capability from storage', () {
    final profile = AiModelProfile.fromJson(const <String, Object?>{
      'capabilities': <String>['rerank'],
    });

    expect(profile.supportsRerank, isTrue);
  });
}
