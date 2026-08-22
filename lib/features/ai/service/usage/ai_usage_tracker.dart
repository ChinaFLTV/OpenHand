import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/date_time_format.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../../../shared/util/text_clip.dart';
import '../../data/ai_usage_store.dart';
import '../../model/ai_cost_breakdown.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../../model/ai_usage_analytics.dart';
import '../runtime/ai_transport_client.dart';

abstract final class AiUsageSource {
  static const String thread = 'thread';
  static const String knowledgeBase = 'knowledge_base';
  static const String harness = 'harness';
  static const String translation = 'translation';
  static const String textToSpeech = 'text_to_speech';
  static const String selfLearning = 'self_learning';
  static const String agent = 'agent';
  static const String webSearch = 'web_search';
  static const String webFetch = 'web_fetch';
  static const String modelTest = 'model_test';
  static const String modelProxy = 'model_proxy';
  static const String other = 'other';
}

class AiUsageTraceContext {
  AiUsageTraceContext({
    String? traceId,
    this.surface = 'app',
    this.source = AiUsageSource.other,
    this.operation = 'chat',
    this.sessionId,
    this.threadTemplateId,
    this.knowledgeBaseId,
    this.metadata = const <String, Object?>{},
  }) : traceId = traceId ?? _nextUsageId('trace');

  static final Object _zoneKey = Object();

  final String traceId;
  final String surface;
  final String source;
  final String operation;
  final String? sessionId;
  final String? threadTemplateId;
  final String? knowledgeBaseId;
  final Map<String, Object?> metadata;

  static AiUsageTraceContext? get current =>
      Zone.current[_zoneKey] as AiUsageTraceContext?;

  static T run<T>(AiUsageTraceContext context, T Function() body) {
    return runZoned(body, zoneValues: <Object, Object>{_zoneKey: context});
  }

  static T runDerived<T>({
    String? surface,
    String? source,
    String? operation,
    String? sessionId,
    String? threadTemplateId,
    String? knowledgeBaseId,
    Map<String, Object?> metadata = const <String, Object?>{},
    required T Function() body,
  }) {
    final parent = current;
    return run(
      AiUsageTraceContext(
        traceId: parent?.traceId,
        surface: surface ?? parent?.surface ?? 'app',
        source: source ?? parent?.source ?? AiUsageSource.other,
        operation: operation ?? parent?.operation ?? 'chat',
        sessionId: sessionId ?? parent?.sessionId,
        threadTemplateId: threadTemplateId ?? parent?.threadTemplateId,
        knowledgeBaseId: knowledgeBaseId ?? parent?.knowledgeBaseId,
        metadata: <String, Object?>{...?parent?.metadata, ...metadata},
      ),
      body,
    );
  }
}

class AiUsageTracker {
  AiUsageTracker._();

  static final AiUsageTracker instance = AiUsageTracker._();
  static const int _defaultEstimatedCharactersPerToken = 4;
  static const int _pruneInterval = 256;
  static const int _maxErrorMessageCharacters = 8000;
  static const Duration runtimeCleanupTimeout =
      kOpenHandServiceRuntimeCleanupTimeout;

  final AiUsageStore _store = const AiUsageStore();
  final SerialTaskQueue _writes = SerialTaskQueue(maxPendingTasks: 2048);
  final OpenHandAsyncOnce _shutdownOnce = OpenHandAsyncOnce();
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  int _successfulWrites = 0;
  int _estimatedCharactersPerToken = _defaultEstimatedCharactersPerToken;
  bool _shuttingDown = false;

  void updateEstimatedCharactersPerToken(int value) {
    if (value > 0) _estimatedCharactersPerToken = value;
  }

  Future<AiUsageSnapshot> loadSnapshot(AiUsageFilter filter) {
    return _store.loadSnapshot(filter);
  }

  Future<AiUsageSummary> loadSessionSummary({
    required String sessionId,
    required String source,
    DateTime? legacyStartAt,
    DateTime? legacyEndAt,
  }) {
    return _store.loadSessionSummary(
      sessionId: sessionId,
      source: source,
      legacyStartAt: legacyStartAt,
      legacyEndAt: legacyEndAt,
    );
  }

  void recordSuccess({
    required AiModelConfig model,
    required String apiFamily,
    required DateTime startedAt,
    required DateTime endedAt,
    required int inputCharacters,
    required int outputCharacters,
    AiTokenUsage? usage,
    int? firstTokenMs,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    try {
      final effectiveUsage = _normalizedUsage(
        usage,
        inputCharacters: inputCharacters,
        outputCharacters: outputCharacters,
      );
      _record(
        model: model,
        apiFamily: apiFamily,
        startedAt: startedAt,
        endedAt: endedAt,
        firstTokenMs: firstTokenMs,
        status: AiUsageRequestStatus.success,
        usage: effectiveUsage.usage,
        usageEstimated: effectiveUsage.estimated,
        metadata: metadata,
      );
    } catch (error, stack) {
      silentLog('ai_usage_tracker', '构建 AI 成功请求统计', error, stack);
    }
  }

  void recordFailure({
    required AiModelConfig model,
    required String apiFamily,
    required DateTime startedAt,
    required DateTime endedAt,
    required Object error,
    bool cancelled = false,
    Duration? timeout,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    try {
      final failure = _failureDetails(
        error,
        cancelled: cancelled,
        timeout: timeout,
      );
      _record(
        model: model,
        apiFamily: apiFamily,
        startedAt: startedAt,
        endedAt: endedAt,
        status: failure.status,
        errorType: failure.errorType,
        errorMessage: failure.errorMessage,
        httpStatusCode: failure.httpStatusCode,
        timeoutMs: failure.timeoutMs,
        timeoutPhase: failure.timeoutPhase,
        usage: const AiTokenUsage(totalTokens: 0),
        usageEstimated: false,
        metadata: metadata,
      );
    } catch (trackingError, stack) {
      silentLog('ai_usage_tracker', '构建 AI 失败请求统计', trackingError, stack);
    }
  }

  Future<void> clear() {
    if (_shuttingDown) return Future<void>.value();
    return _writes.enqueue(() async {
      await _store.clear();
      if (!_shuttingDown) changes.value += 1;
    });
  }

  Future<void> flush() => _writes.idle;

  Future<void> shutdown() {
    _shuttingDown = true;
    return _shutdownOnce.run(() async {
      try {
        await flush().timeout(runtimeCleanupTimeout);
      } finally {
        changes.dispose();
      }
    });
  }

  void _record({
    required AiModelConfig model,
    required String apiFamily,
    required DateTime startedAt,
    required DateTime endedAt,
    required String status,
    required AiTokenUsage usage,
    required bool usageEstimated,
    int? firstTokenMs,
    String? errorType,
    String? errorMessage,
    int? httpStatusCode,
    int? timeoutMs,
    String? timeoutPhase,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (_shuttingDown) return;
    final trace = AiUsageTraceContext.current ?? AiUsageTraceContext();
    final localStartedAt = startedAt.toLocal();
    final profile = model.profileFor(model.modelId);
    final claudeStyle = model.supportsExplicitPromptCacheControl;
    final cost = status == AiUsageRequestStatus.success
        ? AiCostBreakdown.compute(
            usage: usage,
            profile: profile,
            claudeStyle: claudeStyle,
          )
        : null;
    final record = AiUsageStorageRecord(
      id: _nextUsageId('usage'),
      traceId: trace.traceId,
      startedAt: startedAt,
      endedAt: endedAt,
      localDate: formatYearMonthDay(localStartedAt),
      localHour:
          '${formatYearMonthDay(localStartedAt)}T${twoDigit(localStartedAt.hour)}',
      durationMs: endedAt
          .difference(startedAt)
          .inMilliseconds
          .clamp(0, 1 << 31),
      firstTokenMs: firstTokenMs,
      status: status,
      errorType: errorType,
      errorMessage: errorMessage,
      httpStatusCode: httpStatusCode,
      timeoutMs: timeoutMs,
      timeoutPhase: timeoutPhase,
      surface: trace.surface,
      source: trace.source,
      operation: trace.operation,
      sessionId: trace.sessionId,
      threadTemplateId: trace.threadTemplateId,
      knowledgeBaseId: trace.knowledgeBaseId,
      providerConfigId: model.id,
      providerName: model.providerLabel,
      protocol: model.protocolType.storageValue,
      modelId: model.modelId,
      apiFamily: apiFamily,
      usage: usage,
      cacheInputTokens: computeCacheHitDenominatorTokens(
        promptTokens: usage.promptTokens ?? 0,
        cacheReadTokens: usage.cacheReadTokens ?? 0,
        cacheWriteTokens: usage.cacheCreationTokens ?? 0,
        claudeStyle: claudeStyle,
      ),
      usageEstimated: usageEstimated,
      inputCostUsd: cost?.inputUsd,
      outputCostUsd: cost?.outputUsd,
      cacheReadCostUsd: cost?.cacheReadUsd,
      cacheWriteCostUsd: cost?.cacheWriteUsd,
      totalCostUsd: cost?.totalUsd,
      metadataJson: _encodeMetadata(<String, Object?>{
        ...trace.metadata,
        ...metadata,
      }),
    );
    unawaited(
      _writes
          .enqueue(() async {
            await _store.insert(record);
            _successfulWrites += 1;
            if (_successfulWrites % _pruneInterval == 0) {
              await _store.prune();
            }
            if (!_shuttingDown) changes.value += 1;
          })
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              silentLog('ai_usage_tracker', '写入 AI 使用统计', error, stack);
            },
          ),
    );
  }

  ({AiTokenUsage usage, bool estimated}) _normalizedUsage(
    AiTokenUsage? usage, {
    required int inputCharacters,
    required int outputCharacters,
  }) {
    if (usage != null && !usage.isEmpty) {
      final prompt = usage.promptTokens;
      final completion = usage.completionTokens;
      final total = usage.resolvedTotalTokens ?? 0;
      return (
        usage: AiTokenUsage(
          promptTokens: prompt,
          completionTokens: completion,
          totalTokens: total,
          cacheCreationTokens: usage.cacheCreationTokens,
          cacheReadTokens: usage.cacheReadTokens,
          reasoningTokens: usage.reasoningTokens,
          audioInputTokens: usage.audioInputTokens,
          imageInputTokens: usage.imageInputTokens,
          videoInputTokens: usage.videoInputTokens,
          webSearchToolUsage: usage.webSearchToolUsage,
          webSearchPageUsage: usage.webSearchPageUsage,
        ),
        estimated: false,
      );
    }
    return (
      usage: estimateAiTokenUsage(
        inputCharacters: inputCharacters,
        outputCharacters: outputCharacters,
        charactersPerToken: _estimatedCharactersPerToken,
      ),
      estimated: true,
    );
  }

  ({
    String status,
    String errorType,
    String errorMessage,
    int? httpStatusCode,
    int? timeoutMs,
    String? timeoutPhase,
  })
  _failureDetails(
    Object error, {
    required bool cancelled,
    required Duration? timeout,
  }) {
    final errorType = error.runtimeType.toString();
    final message = _sanitizeErrorMessage('$error', fallback: errorType);
    final normalized = message.toLowerCase();
    final httpStatusCode = _httpStatusCode(error, normalized);
    final wasCancelled =
        cancelled ||
        error is http.RequestAbortedException ||
        errorType.toLowerCase().contains('cancelled') ||
        errorType.toLowerCase().contains('canceled');
    final timedOut = !wasCancelled && _isTimeout(error, normalized);
    final String status;
    if (wasCancelled) {
      status = AiUsageRequestStatus.cancelled;
    } else if (timedOut) {
      status = AiUsageRequestStatus.timeout;
    } else if (httpStatusCode != null) {
      status = AiUsageRequestStatus.failed;
    } else if (_isTransportError(error, normalized)) {
      status = AiUsageRequestStatus.error;
    } else if (_isProviderFailure(normalized)) {
      status = AiUsageRequestStatus.failed;
    } else {
      status = AiUsageRequestStatus.error;
    }
    Duration? effectiveTimeout;
    if (timedOut) {
      effectiveTimeout = timeout;
      if (error is TimeoutException) {
        effectiveTimeout = error.duration ?? effectiveTimeout;
      }
    }
    return (
      status: status,
      errorType: errorType,
      errorMessage: message,
      httpStatusCode: httpStatusCode,
      timeoutMs: effectiveTimeout?.inMilliseconds.clamp(0, 1 << 31),
      timeoutPhase: timedOut ? _timeoutPhase(normalized) : null,
    );
  }

  bool _isTimeout(Object error, String message) {
    if (error is TimeoutException) return true;
    return const <String>[
      'timeout',
      'timed out',
      'time limit',
      '超时',
      '逾时',
    ].any(message.contains);
  }

  int? _httpStatusCode(Object error, String message) {
    if (error is AiTransportResponseException) return error.statusCode;
    final match = RegExp(
      r'(?:http|status(?: code)?|状态码)\s*[:=#-]?\s*(\d{3})',
      caseSensitive: false,
    ).firstMatch(message);
    final value = int.tryParse(match?.group(1) ?? '');
    return value != null && value >= 100 && value <= 599 ? value : null;
  }

  bool _isProviderFailure(String message) {
    // 子串匹配，因此被同表中更短项完全覆盖的条目一律不可达，写进来只是噪音：
    // 'provider request failed' ⊃ 'request failed'，
    // '返回失败' / '请求失败' / '生成失败' / '翻译失败' 均 ⊃ '失败'。
    return const <String>[
      'request failed',
      'response failed',
      'translation failed',
      'generation failed',
      ' failed (',
      ' failed:',
      'rejected',
      'empty response',
      'invalid response',
      '服务端拒绝',
      '返回空',
      '响应无效',
      '失败',
    ].any(message.contains);
  }

  bool _isTransportError(Object error, String message) {
    if (error is http.ClientException) return true;
    return const <String>[
      'network',
      'socket',
      'connection',
      'handshake',
      'tls',
      'dns',
      '网络',
      '连接',
      '握手',
      '证书',
    ].any(message.contains);
  }

  String _timeoutPhase(String message) {
    if (const <String>[
      'stream idle',
      'streaming idle',
      '流式响应',
      '流空闲',
    ].any(message.contains)) {
      return 'stream_idle';
    }
    if (const <String>['response header', '响应头'].any(message.contains)) {
      return 'response_headers';
    }
    if (const <String>[
      'connect',
      'connection',
      'handshake',
      'dns',
      '连接',
      '握手',
    ].any(message.contains)) {
      return 'connection';
    }
    if (const <String>[
      'response body',
      'read response',
      'download',
      '响应体',
      '读取响应',
      '下载',
    ].any(message.contains)) {
      return 'response_body';
    }
    return 'request';
  }

  String _sanitizeErrorMessage(String value, {required String fallback}) {
    var message = value.trim();
    if (message.isEmpty) message = fallback;
    message = message.replaceAllMapped(
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      (match) => '${match.group(1)} [已脱敏]',
    );
    message = message.replaceAllMapped(
      RegExp(
        r'''(["']?(?:api[_-]?key|access[_-]?token|authorization|token)["']?\s*[:=]\s*["']?)[^"'\s,}]+''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[已脱敏]',
    );
    message = message.replaceAllMapped(
      RegExp(
        r'([?&](?:key|api_key|access_token|token)=)[^&\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[已脱敏]',
    );
    return clipTextWithEllipsis(message, _maxErrorMessageCharacters);
  }

  String _encodeMetadata(Map<String, Object?> metadata) {
    if (metadata.isEmpty) return '{}';
    try {
      return jsonEncode(metadata);
    } catch (_) {
      return '{}';
    }
  }
}

int _usageIdCounter = 0;

String _nextUsageId(String prefix) {
  _usageIdCounter = (_usageIdCounter + 1) & 0x7FFFFFFF;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_usageIdCounter';
}
