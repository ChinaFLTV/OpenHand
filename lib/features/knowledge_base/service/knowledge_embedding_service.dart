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
    _validateDimensions(settings, profile);
    final batchSize = _boundedBatchSize(
      inputs.length,
      settings.batchSize,
      profile.embeddingBatchSize,
      profile.embeddingMaxInputsPerBatch,
    );
    final taskType = _resolvedTaskType(profile, isQuery: isQuery);
    final inputType = _resolvedInputType(profile, isQuery: isQuery);
    final preparedInputs = _applyTextPrefix(
      inputs,
      _resolvedTextPrefix(profile, isQuery: isQuery),
    );
    final vectors = <List<double>>[];
    var start = 0;
    while (start < preparedInputs.length) {
      final end = _boundedBatchEnd(
        preparedInputs,
        start,
        batchSize,
        profile.embeddingMaxTokensPerBatch,
      );
      final batch = preparedInputs.sublist(start, end);
      final result = await _embeddings.createEmbeddings(
        model: embeddingModel,
        input: batch,
        dimensions: profile.embeddingSupportsCustomDimensions
            ? settings.dimensions
            : null,
        encodingFormat: profile.embeddingDefaultEncodingFormat,
        inputType: inputType,
        taskType: taskType,
        outputDType: profile.embeddingDefaultOutputDType,
        truncation: profile.embeddingDefaultTruncation,
        timeout: Duration(seconds: settings.requestTimeoutSeconds),
      );
      if (result.vectors.length != batch.length) {
        throw StateError(
          'Embedding 返回数量 ${result.vectors.length} 与输入数量 ${batch.length} 不一致。',
        );
      }
      vectors.addAll(result.vectors);
      start = end;
    }
    for (final vector in vectors) {
      if (vector.length != settings.dimensions) {
        throw StateError(
          'Embedding 维度 ${vector.length} 与知识库配置 ${settings.dimensions} 不一致。',
        );
      }
    }
    return vectors;
  }

  int _boundedBatchSize(
    int inputCount,
    int settingsBatchSize,
    int? profileBatchSize,
    int? maxInputsPerBatch,
  ) {
    var size = settingsBatchSize > 0 ? settingsBatchSize : inputCount;
    if (profileBatchSize != null && profileBatchSize > 0) {
      size = size < profileBatchSize ? size : profileBatchSize;
    }
    if (maxInputsPerBatch != null && maxInputsPerBatch > 0) {
      size = size < maxInputsPerBatch ? size : maxInputsPerBatch;
    }
    if (size <= 0) return 1;
    return size > inputCount ? inputCount : size;
  }

  int _boundedBatchEnd(
    List<String> inputs,
    int start,
    int batchSize,
    int? maxTokensPerBatch,
  ) {
    final countBound = start + batchSize;
    final hardEnd = countBound > inputs.length ? inputs.length : countBound;
    if (maxTokensPerBatch == null || maxTokensPerBatch <= 0) {
      return hardEnd;
    }
    var tokens = 0;
    for (var index = start; index < hardEnd; index += 1) {
      tokens += _roughTokenCount(inputs[index]);
      if (index > start && tokens > maxTokensPerBatch) {
        return index;
      }
    }
    return hardEnd;
  }

  int _roughTokenCount(String value) {
    final trimmedLength = value.trim().length;
    if (trimmedLength <= 0) return 1;
    return (trimmedLength / 4).ceil();
  }

  void _validateDimensions(
    KnowledgeBaseSettings settings,
    AiModelProfile profile,
  ) {
    final expectedDimensions = profile.embeddingDimensions;
    if (!profile.embeddingSupportsCustomDimensions &&
        expectedDimensions != null &&
        settings.dimensions != expectedDimensions) {
      throw StateError(
        '当前嵌入模型固定输出 $expectedDimensions 维，知识库配置为 ${settings.dimensions} 维。',
      );
    }
    final minDimensions = profile.embeddingMinDimensions;
    if (minDimensions != null && settings.dimensions < minDimensions) {
      throw StateError(
        '当前嵌入模型最小支持 $minDimensions 维，知识库配置为 ${settings.dimensions} 维。',
      );
    }
    final maxDimensions = profile.embeddingMaxDimensions;
    if (maxDimensions != null && settings.dimensions > maxDimensions) {
      throw StateError(
        '当前嵌入模型最大支持 $maxDimensions 维，知识库配置为 ${settings.dimensions} 维。',
      );
    }
  }

  String? _resolvedTaskType(AiModelProfile profile, {required bool isQuery}) {
    final value = isQuery
        ? profile.embeddingDefaultQueryTaskType
        : profile.embeddingDefaultDocumentTaskType;
    return _trimmedOrNull(value) ??
        _trimmedOrNull(profile.embeddingDefaultTaskType);
  }

  String? _resolvedInputType(AiModelProfile profile, {required bool isQuery}) {
    final value = isQuery
        ? profile.embeddingQueryInputType
        : profile.embeddingDocumentInputType;
    return _trimmedOrNull(value) ??
        _trimmedOrNull(profile.embeddingDefaultInputType);
  }

  String? _resolvedTextPrefix(AiModelProfile profile, {required bool isQuery}) {
    final value = isQuery
        ? profile.embeddingQueryTextPrefix
        : profile.embeddingDocumentTextPrefix;
    return _trimmedOrNull(value);
  }

  List<String> _applyTextPrefix(List<String> inputs, String? prefix) {
    final normalizedPrefix = _trimmedOrNull(prefix);
    if (normalizedPrefix == null) return inputs;
    return inputs
        .map((value) => _prefixedText(value, normalizedPrefix))
        .toList(growable: false);
  }

  String _prefixedText(String value, String prefix) {
    final trimmedLeft = value.trimLeft();
    if (trimmedLeft.startsWith(prefix)) return value;
    return '$prefix $value';
  }

  void dispose() => _embeddings.dispose();
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
