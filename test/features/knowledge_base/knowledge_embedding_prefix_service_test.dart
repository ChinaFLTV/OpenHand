import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_embedding_service.dart';

void main() {
  group('KnowledgeEmbeddingService text prefixes', () {
    test('applies query and document prefixes before embedding', () async {
      final embeddings = _RecordingEmbeddingsService(dimensions: 4);
      final service = KnowledgeEmbeddingService(embeddings: embeddings);
      final model = _model(
        profile: const AiModelProfile(
          capabilities: <AiModelCapability>{
            AiModelCapability.embeddingGeneration,
          },
          embeddingDimensions: 4,
          embeddingQueryTextPrefix: 'query:',
          embeddingDocumentTextPrefix: 'passage:',
        ),
      );

      await service.embedBatch(
        settings: _settings(dimensions: 4),
        model: model,
        inputs: const <String>['find docs', 'query: already tagged'],
        isQuery: true,
      );
      await service.embedBatch(
        settings: _settings(dimensions: 4),
        model: model,
        inputs: const <String>['source chunk'],
        isQuery: false,
      );

      expect(embeddings.calls.first.input, <String>[
        'query: find docs',
        'query: already tagged',
      ]);
      expect(embeddings.calls.last.input, <String>['passage: source chunk']);
    });
  });
}

KnowledgeBaseSettings _settings({required int dimensions}) {
  return KnowledgeBaseSettings(
    providerConfigId: 'provider',
    modelId: 'embedding-model',
    dimensions: dimensions,
    allowDocumentCloudEmbedding: true,
    allowQueryCloudEmbedding: true,
  );
}

AiModelConfig _model({required AiModelProfile profile}) {
  return AiModelConfig(
    id: 'provider',
    baseUrl: 'https://example.com/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'embedding-model',
    protocolType: AiProtocolType.openai,
    modelProfiles: <String, AiModelProfile>{'embedding-model': profile},
  );
}

class _RecordingEmbeddingsService extends AiEmbeddingsService {
  _RecordingEmbeddingsService({required this.dimensions});

  final int dimensions;
  final List<_EmbeddingCall> calls = <_EmbeddingCall>[];

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
    calls.add(_EmbeddingCall(input: input));
    return AiEmbeddingResult(
      vectors: List<List<double>>.generate(
        input.length,
        (_) => List<double>.filled(this.dimensions, 0),
      ),
      rawResponse: '{}',
    );
  }
}

class _EmbeddingCall {
  const _EmbeddingCall({required this.input});

  final List<String> input;
}
