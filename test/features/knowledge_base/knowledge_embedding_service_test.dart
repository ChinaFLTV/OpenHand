import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_embedding_service.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_indexing_control.dart';

void main() {
  test('local qwen3 embedding uses safe single-item batches', () async {
    final embeddings = _RecordingEmbeddingsService();
    final service = KnowledgeEmbeddingService(embeddings: embeddings);

    final vectors = await service.embedBatch(
      settings: const KnowledgeBaseSettings(
        modelId: 'qwen3-embedding:8b',
        dimensions: 4096,
        batchSize: 32,
        requestTimeoutSeconds: 30,
        allowDocumentCloudEmbedding: true,
      ),
      model: const AiModelConfig(
        id: 'ollama',
        baseUrl: 'http://127.0.0.1:11434/v1',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'qwen3-embedding:8b',
        protocolType: AiProtocolType.ollama,
      ),
      inputs: const <String>['alpha', 'beta', 'gamma'],
      isQuery: false,
    );

    expect(vectors, hasLength(3));
    expect(embeddings.batchLengths, <int>[1, 1, 1]);
    expect(
      embeddings.timeouts.map((timeout) => timeout.inSeconds).toList(),
      <int>[180, 180, 180],
    );
  });

  test(
    'embedding cancellation stops before scheduling remaining batches',
    () async {
      final cancelToken = KnowledgeIndexingCancelToken();
      final embeddings = _RecordingEmbeddingsService(
        onCreateEmbeddings: () => cancelToken.cancel(),
      );
      final service = KnowledgeEmbeddingService(embeddings: embeddings);

      await expectLater(
        service.embedBatch(
          settings: const KnowledgeBaseSettings(
            modelId: 'qwen3-embedding:8b',
            dimensions: 4096,
            batchSize: 32,
            requestTimeoutSeconds: 30,
            allowDocumentCloudEmbedding: true,
          ),
          model: const AiModelConfig(
            id: 'ollama',
            baseUrl: 'http://127.0.0.1:11434/v1',
            authScheme: AiAuthScheme.none,
            token: '',
            modelId: 'qwen3-embedding:8b',
            protocolType: AiProtocolType.ollama,
          ),
          inputs: const <String>['alpha', 'beta', 'gamma'],
          isQuery: false,
          cancelToken: cancelToken,
        ),
        throwsA(isA<KnowledgeIndexingCancelledException>()),
      );

      expect(embeddings.batchLengths, <int>[1]);
    },
  );
}

class _RecordingEmbeddingsService extends AiEmbeddingsService {
  _RecordingEmbeddingsService({this.onCreateEmbeddings});

  final void Function()? onCreateEmbeddings;
  final List<int> batchLengths = <int>[];
  final List<Duration> timeouts = <Duration>[];

  @override
  Future<AiEmbeddingResult> createEmbeddings({
    required AiModelConfig model,
    required List<String> input,
    Duration timeout = const Duration(seconds: 60),
    int? dimensions,
    String? encodingFormat,
    String? inputType,
    String? taskType,
    String? title,
    String? outputDType,
    String? truncation,
    String? user,
  }) async {
    batchLengths.add(input.length);
    timeouts.add(timeout);
    onCreateEmbeddings?.call();
    final vectorSize = dimensions ?? 4096;
    return AiEmbeddingResult(
      vectors: List<List<double>>.generate(
        input.length,
        (_) => List<double>.filled(vectorSize, 0.1),
        growable: false,
      ),
      rawResponse: '{}',
    );
  }

  @override
  void dispose() {}
}
