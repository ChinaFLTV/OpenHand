import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/date_time_format.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../data/ai_usage_store.dart';
import '../../model/ai_cost_breakdown.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../../model/ai_usage_analytics.dart';

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

  final AiUsageStore _store = const AiUsageStore();
  final SerialTaskQueue _writes = SerialTaskQueue(maxPendingTasks: 2048);
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  int _successfulWrites = 0;
  int _estimatedCharactersPerToken = _defaultEstimatedCharactersPerToken;

  void updateEstimatedCharactersPerToken(int value) {
    if (value > 0) _estimatedCharactersPerToken = value;
  }

  Future<AiUsageSnapshot> loadSnapshot(AiUsageFilter filter) {
    return _store.loadSnapshot(filter);
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
        status: 'success',
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
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    try {
      _record(
        model: model,
        apiFamily: apiFamily,
        startedAt: startedAt,
        endedAt: endedAt,
        status: cancelled ? 'cancelled' : 'failed',
        errorType: error.runtimeType.toString(),
        usage: const AiTokenUsage(totalTokens: 0),
        usageEstimated: false,
        metadata: metadata,
      );
    } catch (trackingError, stack) {
      silentLog('ai_usage_tracker', '构建 AI 失败请求统计', trackingError, stack);
    }
  }

  Future<void> clear() {
    return _writes.enqueue(() async {
      await _store.clear();
      changes.value += 1;
    });
  }

  Future<void> flush() => _writes.enqueue(() async {});

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
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final trace = AiUsageTraceContext.current ?? AiUsageTraceContext();
    final localStartedAt = startedAt.toLocal();
    final profile = model.profileFor(model.modelId);
    final cost = status == 'success'
        ? AiCostBreakdown.compute(
            usage: usage,
            profile: profile,
            claudeStyle:
                model.protocolType == AiProtocolType.claude ||
                model.apiDialect.storageValue.contains('anthropic'),
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
            changes.value += 1;
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
      final total = usage.totalTokens ?? (prompt ?? 0) + (completion ?? 0);
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
    final promptTokens = _estimateTokens(inputCharacters);
    final completionTokens = _estimateTokens(outputCharacters);
    return (
      usage: AiTokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: promptTokens + completionTokens,
      ),
      estimated: true,
    );
  }

  int _estimateTokens(int characters) {
    if (characters <= 0) return 0;
    return (characters / _estimatedCharactersPerToken).ceil();
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
