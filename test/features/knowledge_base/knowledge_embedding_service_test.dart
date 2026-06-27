import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_embedding_service.dart';

void main() {
  group('KnowledgeEmbeddingService', () {
    test(
      'passes document embedding profile parameters and bounds batches',
      () async {
        final embeddings = _RecordingEmbeddingsService(dimensions: 4);
        final service = KnowledgeEmbeddingService(embeddings: embeddings);

        final vectors = await service.embedBatch(
          settings: _settings(dimensions: 4, batchSize: 8),
          model: _model(
            profile: const AiModelProfile(
              capabilities: <AiModelCapability>{
                AiModelCapability.embeddingGeneration,
              },
              embeddingDimensions: 4,
              embeddingSupportsCustomDimensions: true,
              embeddingBatchSize: 4,
              embeddingMaxInputsPerBatch: 2,
              embeddingDefaultEncodingFormat: 'float',
              embeddingDefaultOutputDType: 'int8',
              embeddingDefaultTruncation: 'END',
              embeddingDefaultDocumentTaskType: 'retrieval.passage',
              embeddingDefaultQueryTaskType: 'retrieval.query',
              embeddingDocumentInputType: 'search_document',
              embeddingQueryInputType: 'search_query',
            ),
          ),
          inputs: const <String>['doc one', 'doc two', 'doc three'],
          isQuery: false,
        );

        expect(vectors, hasLength(3));
        expect(embeddings.calls, hasLength(2));
        expect(embeddings.calls.first.input, <String>['doc one', 'doc two']);
        expect(embeddings.calls.first.dimensions, 4);
        expect(embeddings.calls.first.encodingFormat, 'float');
        expect(embeddings.calls.first.outputDType, 'int8');
        expect(embeddings.calls.first.truncation, 'END');
        expect(embeddings.calls.first.taskType, 'retrieval.passage');
        expect(embeddings.calls.first.inputType, 'search_document');
      },
    );

    test('passes query-specific embedding parameters', () async {
      final embeddings = _RecordingEmbeddingsService(dimensions: 4);
      final service = KnowledgeEmbeddingService(embeddings: embeddings);

      await service.embedBatch(
        settings: _settings(dimensions: 4),
        model: _model(
          profile: const AiModelProfile(
            capabilities: <AiModelCapability>{
              AiModelCapability.embeddingGeneration,
            },
            embeddingDimensions: 4,
            embeddingSupportsCustomDimensions: true,
            embeddingDefaultDocumentTaskType: 'retrieval.passage',
            embeddingDefaultQueryTaskType: 'retrieval.query',
            embeddingDocumentInputType: 'search_document',
            embeddingQueryInputType: 'search_query',
          ),
        ),
        inputs: const <String>['find docs'],
        isQuery: true,
      );

      expect(embeddings.calls.single.taskType, 'retrieval.query');
      expect(embeddings.calls.single.inputType, 'search_query');
    });

    test(
      'rejects fixed-dimension profile mismatches before embedding',
      () async {
        final embeddings = _RecordingEmbeddingsService(dimensions: 8);
        final service = KnowledgeEmbeddingService(embeddings: embeddings);

        await expectLater(
          service.embedBatch(
            settings: _settings(dimensions: 4),
            model: _model(
              profile: const AiModelProfile(
                capabilities: <AiModelCapability>{
                  AiModelCapability.embeddingGeneration,
                },
                embeddingDimensions: 8,
              ),
            ),
            inputs: const <String>['doc'],
            isQuery: false,
          ),
          throwsStateError,
        );
        expect(embeddings.calls, isEmpty);
      },
    );
  });
}

KnowledgeBaseSettings _settings({required int dimensions, int batchSize = 16}) {
  return KnowledgeBaseSettings(
    providerConfigId: 'provider',
    modelId: 'embedding-model',
    dimensions: dimensions,
    batchSize: batchSize,
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
    calls.add(
      _EmbeddingCall(
        input: input,
        dimensions: dimensions,
        encodingFormat: encodingFormat,
        inputType: inputType,
        taskType: taskType,
        outputDType: outputDType,
        truncation: truncation,
      ),
    );
    return AiEmbeddingResult(
      vectors: List<List<double>>.generate(
        input.length,
        (_) => List<double>.filled(this.dimensions, 1),
        growable: false,
      ),
      rawResponse: '{}',
    );
  }
}

class _EmbeddingCall {
  const _EmbeddingCall({
    required this.input,
    this.dimensions,
    this.encodingFormat,
    this.inputType,
    this.taskType,
    this.outputDType,
    this.truncation,
  });

  final List<String> input;
  final int? dimensions;
  final String? encodingFormat;
  final String? inputType;
  final String? taskType;
  final String? outputDType;
  final String? truncation;
}
