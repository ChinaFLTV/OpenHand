import 'dart:async';
import 'dart:io';

import '../../../shared/net/loopback_hosts.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/exponential_backoff.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart';
import '../model/knowledge_base_settings.dart';
import 'knowledge_indexing_control.dart';

const int _localQwen3EmbeddingDocumentTimeoutSeconds = 180;
const int _localQwen3EmbeddingQueryTimeoutSeconds = 120;
const int _maxRetryBackoffMs = 10000;

class KnowledgeEmbeddingService {
  KnowledgeEmbeddingService({AiEmbeddingsService? embeddings})
    : _embeddings = embeddings ?? AiEmbeddingsService(),
      _ownsEmbeddings = embeddings == null;

  AiEmbeddingsService _embeddings;
  final bool _ownsEmbeddings;

  Future<List<List<double>>> embedBatch({
    required KnowledgeBaseSettings settings,
    required AiModelConfig model,
    required List<String> inputs,
    required bool isQuery,
    KnowledgeIndexingCancelToken? cancelToken,
  }) {
    return AiUsageTraceContext.runDerived(
      source: AiUsageSource.knowledgeBase,
      operation: isQuery ? 'query_embedding' : 'document_embedding',
      metadata: <String, Object?>{'input_count': inputs.length},
      body: () => _embedBatch(
        settings: settings,
        model: model,
        inputs: inputs,
        isQuery: isQuery,
        cancelToken: cancelToken,
      ),
    );
  }

  Future<List<List<double>>> _embedBatch({
    required KnowledgeBaseSettings settings,
    required AiModelConfig model,
    required List<String> inputs,
    required bool isQuery,
    KnowledgeIndexingCancelToken? cancelToken,
  }) async {
    if (inputs.isEmpty) return const <List<double>>[];
    cancelToken?.throwIfCancelled();
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
    final requestModelId = _resolvedModelId(
      profile,
      fallbackModelId: settings.modelId,
      isQuery: isQuery,
    );
    final embeddingModel = _embeddingModelForRequest(
      model,
      profile: profile,
      sourceModelId: settings.modelId,
      requestModelId: requestModelId,
    );
    _validateDimensions(settings, profile);
    var batchSize = _boundedBatchSize(
      inputs.length,
      settings.batchSize,
      profile.embeddingBatchSize,
      profile.embeddingMaxInputsPerBatch,
    );
    if (_usesLocalQwen3Embedding(embeddingModel, profile) && batchSize > 1) {
      batchSize = 1;
    }
    final taskType = _resolvedTaskType(profile, isQuery: isQuery);
    final inputType = _resolvedInputType(profile, isQuery: isQuery);
    final preparedInputs = _applyTextPrefix(
      inputs,
      _resolvedTextPrefix(profile, isQuery: isQuery),
    );
    final timeout = _effectiveTimeout(
      settings,
      model: embeddingModel,
      profile: profile,
      isQuery: isQuery,
    );
    final vectors = <List<double>>[];
    var start = 0;
    while (start < preparedInputs.length) {
      cancelToken?.throwIfCancelled();
      final end = _boundedBatchEnd(
        preparedInputs,
        start,
        batchSize,
        profile.embeddingMaxTokensPerBatch,
      );
      final batch = preparedInputs.sublist(start, end);
      final batchVectors = await _embedPreparedBatch(
        settings: settings,
        model: embeddingModel,
        profile: profile,
        batch: batch,
        isQuery: isQuery,
        startIndex: start,
        totalInputs: preparedInputs.length,
        timeout: timeout,
        taskType: taskType,
        inputType: inputType,
        cancelToken: cancelToken,
      );
      vectors.addAll(batchVectors);
      start = end;
    }
    cancelToken?.throwIfCancelled();
    for (final vector in vectors) {
      if (vector.length != settings.dimensions) {
        throw StateError(
          'Embedding 维度 ${vector.length} 与知识库配置 ${settings.dimensions} 不一致。',
        );
      }
    }
    return vectors;
  }

  Future<List<List<double>>> _embedPreparedBatch({
    required KnowledgeBaseSettings settings,
    required AiModelConfig model,
    required AiModelProfile profile,
    required List<String> batch,
    required bool isQuery,
    required int startIndex,
    required int totalInputs,
    required Duration timeout,
    required String? taskType,
    required String? inputType,
    required KnowledgeIndexingCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    try {
      final result = await _createEmbeddingsWithRetries(
        settings: settings,
        model: model,
        profile: profile,
        batch: batch,
        timeout: timeout,
        taskType: taskType,
        inputType: inputType,
        cancelToken: cancelToken,
      );
      if (result.vectors.length != batch.length) {
        throw StateError(
          'Embedding 返回数量 ${result.vectors.length} 与输入数量 ${batch.length} 不一致。',
        );
      }
      return result.vectors;
    } on TimeoutException catch (error, stackTrace) {
      if (batch.length > 1) {
        final midpoint = batch.length ~/ 2;
        final left = await _embedPreparedBatch(
          settings: settings,
          model: model,
          profile: profile,
          batch: batch.sublist(0, midpoint),
          isQuery: isQuery,
          startIndex: startIndex,
          totalInputs: totalInputs,
          timeout: timeout,
          taskType: taskType,
          inputType: inputType,
          cancelToken: cancelToken,
        );
        final right = await _embedPreparedBatch(
          settings: settings,
          model: model,
          profile: profile,
          batch: batch.sublist(midpoint),
          isQuery: isQuery,
          startIndex: startIndex + midpoint,
          totalInputs: totalInputs,
          timeout: timeout,
          taskType: taskType,
          inputType: inputType,
          cancelToken: cancelToken,
        );
        return <List<double>>[...left, ...right];
      }
      Error.throwWithStackTrace(
        KnowledgeEmbeddingException(
          _timeoutMessage(
            model: model,
            isQuery: isQuery,
            startIndex: startIndex,
            batchLength: batch.length,
            totalInputs: totalInputs,
            timeout: timeout,
          ),
          cause: error,
        ),
        stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        KnowledgeEmbeddingException(
          _networkMessage(model: model, error: error),
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  Future<AiEmbeddingResult> _createEmbeddingsWithRetries({
    required KnowledgeBaseSettings settings,
    required AiModelConfig model,
    required AiModelProfile profile,
    required List<String> batch,
    required Duration timeout,
    required String? taskType,
    required String? inputType,
    required KnowledgeIndexingCancelToken? cancelToken,
  }) async {
    final retryCount = settings.retryCount < 0 ? 0 : settings.retryCount;
    for (var attempt = 0; ; attempt += 1) {
      cancelToken?.throwIfCancelled();
      try {
        return await _awaitEmbeddingOrCancel(
          _embeddings.createEmbeddings(
            model: model,
            input: batch,
            dimensions: profile.embeddingSupportsCustomDimensions
                ? settings.dimensions
                : null,
            encodingFormat: profile.embeddingDefaultEncodingFormat,
            inputType: inputType,
            taskType: taskType,
            outputDType: profile.embeddingDefaultOutputDType,
            truncation: profile.embeddingDefaultTruncation,
            timeout: timeout,
          ),
          cancelToken,
        );
      } catch (error, stackTrace) {
        if (!AiTransportDiagnosticMessages.isRetryableTransportError(error) ||
            attempt >= retryCount) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        await _delayOrCancel(_retryBackoff(settings, attempt), cancelToken);
      }
    }
  }

  Future<T> _awaitEmbeddingOrCancel<T>(
    Future<T> future,
    KnowledgeIndexingCancelToken? cancelToken,
  ) async {
    final result = await awaitWithCancelSignal(
      future,
      cancelSignal: cancelToken?.whenCancelled,
    );
    if (result == null) {
      _abortOwnedEmbeddings();
      throw const KnowledgeIndexingCancelledException();
    }
    return result;
  }

  Future<void> _delayOrCancel(
    Duration duration,
    KnowledgeIndexingCancelToken? cancelToken,
  ) async {
    final cancelled = await delayUntilCancelled(
      duration,
      cancelSignal: cancelToken?.whenCancelled,
    );
    if (cancelled) {
      throw const KnowledgeIndexingCancelledException();
    }
  }

  void _abortOwnedEmbeddings() {
    if (!_ownsEmbeddings) return;
    _embeddings.dispose();
    _embeddings = AiEmbeddingsService();
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
    return nullIfBlank(value) ?? nullIfBlank(profile.embeddingDefaultTaskType);
  }

  String? _resolvedInputType(AiModelProfile profile, {required bool isQuery}) {
    final value = isQuery
        ? profile.embeddingQueryInputType
        : profile.embeddingDocumentInputType;
    return nullIfBlank(value) ?? nullIfBlank(profile.embeddingDefaultInputType);
  }

  String? _resolvedTextPrefix(AiModelProfile profile, {required bool isQuery}) {
    final value = isQuery
        ? profile.embeddingQueryTextPrefix
        : profile.embeddingDocumentTextPrefix;
    return nullIfBlank(value);
  }

  String _resolvedModelId(
    AiModelProfile profile, {
    required String fallbackModelId,
    required bool isQuery,
  }) {
    final value = isQuery
        ? profile.embeddingQueryModelId
        : profile.embeddingDocumentModelId;
    return nullIfBlank(value) ?? fallbackModelId;
  }

  AiModelConfig _embeddingModelForRequest(
    AiModelConfig model, {
    required AiModelProfile profile,
    required String sourceModelId,
    required String requestModelId,
  }) {
    final source = sourceModelId.trim();
    final request = requestModelId.trim();
    final profiles = Map<String, AiModelProfile>.of(model.modelProfiles);
    if (request.isNotEmpty &&
        request != source &&
        !profiles.containsKey(request)) {
      profiles[request] = profile;
    }
    return model.copyWith(
      modelId: request,
      modelProfiles: profiles,
      operationRouting: model.operationRouting.copyWith(
        embeddingModelId: request,
      ),
    );
  }

  Duration _effectiveTimeout(
    KnowledgeBaseSettings settings, {
    required AiModelConfig model,
    required AiModelProfile profile,
    required bool isQuery,
  }) {
    final configuredSeconds = settings.requestTimeoutSeconds > 0
        ? settings.requestTimeoutSeconds
        : 60;
    if (!_usesLocalQwen3Embedding(model, profile)) {
      return Duration(seconds: configuredSeconds);
    }
    final minimumSeconds = isQuery
        ? _localQwen3EmbeddingQueryTimeoutSeconds
        : _localQwen3EmbeddingDocumentTimeoutSeconds;
    return Duration(
      seconds: configuredSeconds < minimumSeconds
          ? minimumSeconds
          : configuredSeconds,
    );
  }

  bool _usesLocalQwen3Embedding(AiModelConfig model, AiModelProfile profile) {
    final modelId = model.modelId.trim().toLowerCase();
    final displayName = (profile.displayName ?? '').trim().toLowerCase();
    final isQwen3Embedding =
        modelId.contains('qwen3-embedding') ||
        displayName.contains('qwen3 embedding') ||
        displayName.contains('qwen3-embedding');
    if (!isQwen3Embedding) return false;
    if (model.protocolType == AiProtocolType.ollama) return true;
    final uri = Uri.tryParse(model.baseUrl.trim());
    final host = uri?.host ?? '';
    return isLoopbackHost(host) || host.trim().toLowerCase().endsWith('.local');
  }

  Duration _retryBackoff(KnowledgeBaseSettings settings, int attempt) {
    final baseMs = settings.retryBackoffMs > 0 ? settings.retryBackoffMs : 800;
    // attempt 从 0 起：首个退避应等于 baseMs，故 attempt+1 对齐 backoff 公式的
    // base * 2^(n-1) 语义。
    return Duration(
      milliseconds: exponentialBackoffMs(
        attempt: attempt + 1,
        baseMs: baseMs,
        capMs: _maxRetryBackoffMs,
      ),
    );
  }

  String _timeoutMessage({
    required AiModelConfig model,
    required bool isQuery,
    required int startIndex,
    required int batchLength,
    required int totalInputs,
    required Duration timeout,
  }) {
    final modelId = _embeddingModelLabel(model);
    final batchEnd = startIndex + batchLength;
    final kind = isQuery ? '查询' : '文档';
    return '知识库 $kind embedding 请求超时：模型 $modelId 在 ${timeout.inSeconds} 秒内未返回。'
        '当前批次 ${startIndex + 1}-$batchEnd/$totalInputs，批量大小 $batchLength。'
        '请确认模型服务已启动并完成预热；本地大模型建议将批量大小调为 1-2，或在知识库配置中提高请求超时。';
  }

  String _networkMessage({
    required AiModelConfig model,
    required SocketException error,
  }) {
    final modelId = _embeddingModelLabel(model);
    return '知识库 embedding 请求网络异常：模型 $modelId 无法连接或连接被中断。'
        '请确认模型服务地址、端口、代理与鉴权配置可用。原始错误：${error.message}';
  }

  List<String> _applyTextPrefix(List<String> inputs, String? prefix) {
    final normalizedPrefix = nullIfBlank(prefix);
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

  void dispose() {
    // 只销毁自己创建的实例。外部注入的 AiEmbeddingsService 由注入方持有，
    // 在这里 dispose 会让共享实例的 HTTP 客户端提前关闭。
    if (_ownsEmbeddings) {
      _embeddings.dispose();
    }
  }
}

class KnowledgeEmbeddingException implements Exception {
  const KnowledgeEmbeddingException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

String _embeddingModelLabel(AiModelConfig model) {
  return nullIfBlank(model.modelId) ?? '嵌入模型';
}
