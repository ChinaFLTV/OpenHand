import '../../ai/index.dart';
import '../model/knowledge_base_settings.dart';

class KnowledgeEmbeddingService {
  KnowledgeEmbeddingService({AiEmbeddingsService? embeddings})
    : _embeddings = embeddings ?? AiEmbeddingsService();

  final AiEmbeddingsService _embeddings;

  Future<List<List<double>>> embedBatch({
    required KnowledgeBaseSettings settings,
    required AiModelConfig model,
    required List<String> inputs,
    required bool isQuery,
  }) async {
    if (inputs.isEmpty) return const <List<double>>[];
    final profile = model.profileFor(settings.modelId);
    if (!profile.supportsEmbeddings) {
      throw StateError('模型 ${settings.modelId} 未开启“嵌入生成”能力。');
    }
    if (isQuery && !settings.allowQueryCloudEmbedding) {
      throw StateError('知识库隐私设置禁止将用户 query 发送到云端 embedding API。');
    }
    if (!isQuery && !settings.allowDocumentCloudEmbedding) {
      throw StateError('知识库隐私设置禁止将文档内容发送到云端 embedding API。');
    }
    final embeddingModel = model.copyWith(
      modelId: settings.modelId,
      operationRouting: model.operationRouting.copyWith(
        embeddingModelId: settings.modelId,
      ),
    );
    final result = await _embeddings.createEmbeddings(
      model: embeddingModel,
      input: inputs,
      dimensions: profile.embeddingSupportsCustomDimensions
          ? settings.dimensions
          : null,
      timeout: Duration(seconds: settings.requestTimeoutSeconds),
    );
    if (result.vectors.length != inputs.length) {
      throw StateError(
        'Embedding 返回数量 ${result.vectors.length} 与输入数量 ${inputs.length} 不一致。',
      );
    }
    for (final vector in result.vectors) {
      if (vector.length != settings.dimensions) {
        throw StateError(
          'Embedding 维度 ${vector.length} 与知识库配置 ${settings.dimensions} 不一致。',
        );
      }
    }
    return result.vectors;
  }

  void dispose() => _embeddings.dispose();
}
