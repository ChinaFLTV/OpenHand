import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../../../shared/util/async_concurrency.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_session_message.dart';
import '../../model/ai_web_search_settings.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/chat/ai_transport_diagnostic_messages.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/usage/ai_usage_tracker.dart';
import '../../service/web_engine/web_engine_concurrency.dart';
import '../../service/web_engine/web_engine_health_alert_tracker.dart';
import '../../service/web_engine/web_engine_quality.dart';
import '../../service/web_engine/web_engine_telemetry_store_base.dart';
import '../../service/web_search/web_search_cache_store.dart';
import '../../service/web_search/web_search_orchestrator.dart';
import '../../service/web_search/web_search_telemetry_store.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../web_reverse_cdp_first_guard.dart';

/// WebSearch 子代理：按配置调度搜索引擎，再由总结模型生成最终回答。
/// 旧配置缺失时使用默认引擎。
class AiWebSearchTool extends AiTool {
  AiWebSearchTool({
    required this._backgroundChatClient,
    required this._httpClient,
  });

  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  static const String _summaryTemplateAsset =
      'assets/prompts/common/web_search_summary.md';
  final OpenHandRetryableAsyncCache<String> _summaryTemplateCache =
      OpenHandRetryableAsyncCache<String>(
        () => rootBundle.loadString(_summaryTemplateAsset, cache: false),
      );

  /// 运行时注入的模型清单，供固定总结模型和搜索引擎复用配置。
  List<AiModelConfig> availableModels = const <AiModelConfig>[];

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.webSearch;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final stopwatch = Stopwatch()..start();
    final query = AiToolUtils.readString(args['query']);
    if (query.length < 2) {
      return AiToolUtils.invalidResult(
        'WebSearch',
        'WebSearch 的查询内容至少需要 2 个字符。',
      );
    }
    final allowedDomains = AiToolUtils.normalizeStringList(
      args['allowed_domains'],
    );
    final blockedDomains = AiToolUtils.normalizeStringList(
      args['blocked_domains'],
    );
    final cdpFirstDecision = WebReverseCdpFirstGuard.evaluateTextReference(
      text: <String>[
        query,
        if (allowedDomains.isNotEmpty) allowedDomains.join(' '),
      ].join(' '),
      metadata: context.metadata,
    );
    if (cdpFirstDecision != null) {
      final message = cdpFirstDecision.blockedMessage('WebSearch');
      return AiToolUtils.invalidResult(
        'WebSearch $query',
        message,
        stdout: cdpFirstDecision.diagnosticText(),
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: <String, Object?>{
          'web_reverse_websearch_blocked_query_char_count': query.length,
          ...cdpFirstDecision.metadata(
            requestedUrl: cdpFirstDecision.requestedUri.toString(),
            blockedFlag: 'web_reverse_websearch_blocked_for_cdp_first',
          ),
        },
      );
    }

    final command = 'WebSearch $query';
    final workingDirectory = AiToolUtils.defaultWorkingDirectory();

    final resolved = context.catalog.find(context.toolCall.name);
    final settings =
        resolved?.builtinConfig?.webSearchSettings ??
        AiWebSearchSettings.defaults();
    final cooldownConfig = WebEngineCooldownConfig.fromResilience(
      settings.resilience,
    );

    final progress = StringBuffer()
      ..writeln('query: $query')
      ..writeln('engines_active: ${_engineLabels(settings)}');
    if (allowedDomains.isNotEmpty) {
      progress.writeln('allowed_domains: ${allowedDomains.join(', ')}');
    }
    if (blockedDomains.isNotEmpty) {
      progress.writeln('blocked_domains: ${blockedDomains.join(', ')}');
    }
    progress.writeln(
      settings.parallel
          ? 'mode: parallel (workers=${settings.parallelWorkers})'
          : 'mode: serial',
    );
    final progressReporter = AiToolProgressReporter(
      progress: progress,
      command: command,
      workingDirectory: workingDirectory,
      stopwatch: stopwatch,
      onUpdate: context.onBashUpdate,
    );

    Map<String, Object?> meta({
      int? resultCount,
      List<String>? engines,
      bool? fallbackUsed,
    }) {
      return <String, Object?>{
        'websearch_query': query,
        'websearch_allowed_domains': allowedDomains,
        'websearch_blocked_domains': blockedDomains,
        if (resultCount != null) 'websearch_result_count': resultCount,
        if (engines != null) 'websearch_engines': engines,
        if (fallbackUsed != null) 'websearch_fallback_used': fallbackUsed,
      };
    }

    // 异步记录完整调用；存储层自行处理失败，不阻塞搜索流程。
    void recordTelemetry({
      required String cacheStatus,
      required bool success,
      required int summaryChars,
      WebSearchOrchestrationResult? orchestration,
      AiModelConfig? summaryModel,
      String? errorMessage,
    }) {
      final perEngine = <WebSearchPerEngineLog>[];
      if (orchestration != null) {
        for (final r in orchestration.engineRuns) {
          if (isSkippedWebEngineDiagnostic(r.error)) continue;
          perEngine.add(
            WebSearchPerEngineLog(
              kind: r.kind,
              success: r.error == null,
              hitCount: r.hits.length,
              elapsedMs: r.elapsedMs,
              error: r.error,
            ),
          );
        }
      }
      // 缓存命中没有引擎明细；成功率仅统计实际调度过的引擎。
      unawaited(
        WebSearchTelemetryStore.instance
            .recordCall(
              WebSearchCallLog(
                timestampMs: DateTime.now().millisecondsSinceEpoch,
                query: query,
                cacheStatus: cacheStatus,
                success: success,
                totalDurationMs: stopwatch.elapsedMilliseconds,
                mergedHitCount: orchestration?.merged.length ?? 0,
                fallbackUsed: orchestration?.fallbackUsed ?? false,
                summaryChars: summaryChars,
                errorMessage: errorMessage,
                modelProtocol: summaryModel?.protocolType.name,
                modelId: summaryModel?.modelId,
                perEngine: perEngine,
              ),
              cooldownConfig: cooldownConfig,
            )
            .then((_) => _maybeFireHealthAlerts(settings)),
      );
    }

    AiToolExecutionResult errorResult(
      BashToolExecutionStatus status,
      String message, {
      Map<String, Object?>? metadata,
    }) => progressReporter.errorResult(
      status: status,
      message: message,
      metadata: metadata ?? meta(),
    );

    progressReporter.emit('searching', '正在调度已启用的搜索引擎。');

    final summaryModel = _resolveSummaryModel(
      settings: settings,
      sessionModel: context.model,
    );

    // 优先复用有效期内的同查询、同配置缓存。
    final cacheKey = WebSearchCacheStore.computeKey(
      query: query,
      settings: settings,
      allowedDomains: allowedDomains,
      blockedDomains: blockedDomains,
      localeTag: Platform.localeName,
      modelProtocol: summaryModel.protocolType.name,
      modelId: summaryModel.modelId,
      modelConfigId: summaryModel.id,
    );
    final cached = await WebSearchCacheStore.instance.lookup(
      key: cacheKey,
      settings: settings,
    );
    if (cached != null) {
      progressReporter.emit(
        'cache.hit',
        '已复用缓存摘要（${cached.summary.length} 个字符，'
            '过期时间：${cached.expiresAt.toIso8601String()}）。',
      );
      recordTelemetry(
        cacheStatus: 'hit',
        success: true,
        summaryChars: cached.summary.length,
      );
      return AiToolUtils.progressSuccessResult(
        command: command,
        workingDirectory: workingDirectory,
        progress: progress,
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: cached.summary,
        metadata: <String, Object?>{
          ...meta(),
          'websearch_cache': 'hit',
          'websearch_cache_key': cacheKey,
          'websearch_cache_cached_at': cached.cachedAt.toIso8601String(),
          'websearch_cache_expires_at': cached.expiresAt.toIso8601String(),
          ...cached.metadata,
        },
      );
    }

    final orchestrator = WebSearchOrchestrator(
      settings: settings,
      httpClient: _httpClient,
      availableModels: availableModels,
    );

    final WebSearchOrchestrationResult orchestrationResult;
    try {
      orchestrationResult = await orchestrator.run(
        query: query,
        allowedDomains: allowedDomains,
        blockedDomains: blockedDomains,
        cancelSignal: context.cancelSignal,
        onProgress: (p) {
          progressReporter.emit(
            'engine.${p.kind.name}.${p.stage.name}',
            p.message ??
                (p.stage == WebSearchProgressStage.succeeded
                    ? '在 ${p.elapsedMs} 毫秒内命中 ${p.hitCount} 条结果'
                    : ''),
          );
        },
      );
    } on TimeoutException {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        summaryChars: 0,
        errorMessage: 'orchestrator_timeout',
      );
      return errorResult(
        BashToolExecutionStatus.timedOut,
        'WebSearch 连接搜索引擎超时。',
      );
    } catch (error) {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        summaryChars: 0,
        errorMessage: '$error',
      );
      return errorResult(
        BashToolExecutionStatus.failed,
        AiTransportDiagnosticMessages.friendlyTransportError(
          error,
          contextLabel: 'WebSearch',
        ),
      );
    }

    final merged = orchestrationResult.merged;
    if (merged.isEmpty) {
      final engineDiagnostics = orchestrationResult.engineRuns
          .map((r) => '${r.kind.name}:${r.error ?? "ok"}')
          .toList(growable: false);
      final allFailed = orchestrationResult.engineRuns.every(
        (r) => r.error != null,
      );
      final detail = allFailed
          ? '所有已启用的搜索引擎均执行失败，请稍后重试或检查 WebSearch 引擎配置。'
          : '搜索引擎执行完成，但没有符合当前筛选条件的结果。';
      progressReporter.emit(allFailed ? 'failed' : 'completed', detail);
      recordTelemetry(
        cacheStatus: allFailed
            ? 'bypass'
            : settings.cacheEnabled
            ? 'miss-empty'
            : 'disabled',
        success: !allFailed,
        summaryChars: 0,
        orchestration: orchestrationResult,
      );
      final metadata = meta(
        resultCount: 0,
        engines: engineDiagnostics,
        fallbackUsed: orchestrationResult.fallbackUsed,
      );
      if (allFailed) {
        return errorResult(
          BashToolExecutionStatus.failed,
          detail,
          metadata: metadata,
        );
      }
      return AiToolUtils.progressSuccessResult(
        command: command,
        workingDirectory: workingDirectory,
        progress: progress,
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: detail,
        metadata: metadata,
      );
    }

    progressReporter.emit('summarizing', '正在请求总结模型生成最终回答。');

    final prompt = await _composeSummaryPrompt(settings, query, merged);

    late final AiChatCompletion completion;
    try {
      final maybe = await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
        AiUsageTraceContext.runDerived(
          source: AiUsageSource.webSearch,
          operation: 'result_summary',
          metadata: <String, Object?>{'result_count': merged.length},
          body: () => _backgroundChatClient.sendMessage(
            model: summaryModel,
            messages: <AiChatTurn>[
              AiChatTurn(role: AiChatRole.system, content: prompt.system),
              AiChatTurn(role: AiChatRole.user, content: prompt.user),
            ],
            cancelSignal: context.cancelSignal,
          ),
        ),
        cancelSignal: context.cancelSignal,
      );
      if (maybe == null) {
        return AiToolUtils.cancelledResult(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          metadata: meta(
            resultCount: merged.length,
            fallbackUsed: orchestrationResult.fallbackUsed,
          ),
        );
      }
      completion = maybe;
    } on TimeoutException {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        summaryChars: 0,
        orchestration: orchestrationResult,
        summaryModel: summaryModel,
        errorMessage: 'summary_timeout',
      );
      return errorResult(
        BashToolExecutionStatus.timedOut,
        'WebSearch 总结搜索结果超时。',
      );
    } on AiChatException catch (error) {
      final msg = error.message.trim();
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        summaryChars: 0,
        orchestration: orchestrationResult,
        summaryModel: summaryModel,
        errorMessage: msg,
      );
      return AiToolUtils.looksLikeTimeoutMessage(msg)
          ? errorResult(BashToolExecutionStatus.timedOut, 'WebSearch 总结搜索结果超时。')
          : errorResult(
              BashToolExecutionStatus.failed,
              'WebSearch 总结搜索结果失败：$msg',
            );
    } catch (error) {
      final msg = '$error';
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        summaryChars: 0,
        orchestration: orchestrationResult,
        summaryModel: summaryModel,
        errorMessage: msg,
      );
      return AiToolUtils.looksLikeTimeoutMessage(msg)
          ? errorResult(BashToolExecutionStatus.timedOut, 'WebSearch 总结搜索结果超时。')
          : errorResult(
              BashToolExecutionStatus.failed,
              AiTransportDiagnosticMessages.friendlyTransportError(
                error,
                contextLabel: 'WebSearch',
              ),
            );
    }

    final summary = completion.reply.trim();
    final body = summary.isEmpty ? prompt.rawHits : summary;

    progressReporter.emit('completed', '搜索摘要已生成。');

    final engineSummaries = orchestrationResult.engineRuns
        .map(
          (r) =>
              '${r.kind.name}:${r.isSuccess ? "ok(${r.hits.length})" : (r.error ?? "fail")}',
        )
        .toList(growable: false);

    // 写入本地持久化缓存（异步等待但失败时静默吞掉以不阻塞主流程）。
    if (settings.cacheEnabled && body.trim().isNotEmpty) {
      await WebSearchCacheStore.instance.store(
        key: cacheKey,
        settings: settings,
        query: query,
        summary: body,
        metadata: <String, Object?>{
          'session_id': context.sessionId,
          'tool_name': context.toolCall.name,
          aiSessionMessageToolCallIdMetadataKey: context.toolCall.id,
          'model_protocol': summaryModel.protocolType.name,
          'model_id': summaryModel.modelId,
          'engines': engineSummaries,
          'fallback_used': orchestrationResult.fallbackUsed,
          'merged_hit_count': merged.length,
          'allowed_domains': allowedDomains,
          'blocked_domains': blockedDomains,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
    }

    recordTelemetry(
      cacheStatus: settings.cacheEnabled ? 'miss-stored' : 'disabled',
      success: true,
      summaryChars: body.length,
      orchestration: orchestrationResult,
      summaryModel: summaryModel,
    );
    return AiToolUtils.progressSuccessResult(
      command: command,
      workingDirectory: workingDirectory,
      progress: progress,
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: body,
      metadata:
          meta(
              resultCount: merged.length,
              engines: engineSummaries,
              fallbackUsed: orchestrationResult.fallbackUsed,
            )
            ..['websearch_cache'] = settings.cacheEnabled
                ? 'miss-stored'
                : 'disabled',
    );
  }

  String _engineLabels(AiWebSearchSettings settings) {
    final active = settings.engines.where((e) => e.enabled).toList();
    if (active.isEmpty) return '<fallback: bing,duckduckgo>';
    return active.map((e) => e.kind.name).join(',');
  }

  AiModelConfig _resolveSummaryModel({
    required AiWebSearchSettings settings,
    required AiModelConfig sessionModel,
  }) {
    if (settings.modelMode != AiWebSearchModelMode.fixed) {
      return sessionModel;
    }
    final cfgId = settings.fixedModelProviderConfigId;
    final modelId = settings.fixedModelId;
    if (cfgId == null || modelId == null) return sessionModel;
    for (final m in availableModels) {
      if (m.id == cfgId) {
        return m.copyWith(modelId: modelId);
      }
    }
    return sessionModel;
  }

  Future<_SummaryPrompts> _composeSummaryPrompt(
    AiWebSearchSettings settings,
    String query,
    List<WebSearchAggregatedHit> hits,
  ) async {
    String template;
    try {
      template = await _summaryTemplateCache.load();
    } catch (_) {
      template = _fallbackSummaryTemplate;
    }

    final detail = settings.summaryDetail.name;
    final style = settings.summaryStyle.name;
    final minChars = settings.summaryMinChars;
    final maxChars = settings.summaryMaxChars;

    final system = template
        .replaceAll('<<QUERY>>', query)
        .replaceAll('<<DETAIL>>', detail)
        .replaceAll('<<STYLE>>', style)
        .replaceAll('<<MIN_CHARS>>', minChars.toString())
        .replaceAll('<<MAX_CHARS>>', maxChars.toString());

    final hitBuf = StringBuffer();
    var remainingRawContentChars = 6000;
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      hitBuf
        ..writeln('[${i + 1}] ${h.title}')
        ..writeln('    url: ${h.url}')
        ..writeln(
          '    engines: ${h.contributingEngines.map((e) => e.name).join(", ")}'
          ' (weight=${h.totalWeight})',
        );
      if (h.publishedAt != null) {
        hitBuf.writeln('    published: ${h.publishedAt!.toIso8601String()}');
      }
      if ((h.source ?? '').trim().isNotEmpty) {
        hitBuf.writeln('    source: ${h.source!.trim()}');
      }
      if (h.score != null) {
        hitBuf.writeln('    provider_score: ${h.score!.toStringAsFixed(3)}');
      }
      hitBuf
        ..writeln('    snippet:')
        ..writeln('    ${h.snippet.replaceAll("\n", "\n    ")}')
        ..writeln();
      final rawContent = (h.rawContent ?? '').trim();
      if (rawContent.isNotEmpty && remainingRawContentChars > 0) {
        final excerpt = webPromptExcerpt(
          rawContent,
          remainingRawContentChars < 1200 ? remainingRawContentChars : 1200,
        );
        remainingRawContentChars -= excerpt.length;
        hitBuf
          ..writeln('    content_excerpt:')
          ..writeln('    ${excerpt.replaceAll("\n", "\n    ")}')
          ..writeln();
      }
    }

    final user = StringBuffer()
      ..writeln('Query:')
      ..writeln(query)
      ..writeln()
      ..writeln('Detail level: $detail')
      ..writeln('Style: $style')
      ..writeln('Char bounds: [$minChars, $maxChars]')
      ..writeln()
      ..writeln('Hits:')
      ..write(hitBuf);

    return _SummaryPrompts(
      system: system,
      user: user.toString(),
      rawHits: hitBuf.toString(),
    );
  }

  static const String _fallbackSummaryTemplate = '''
You are a faithful summarization sub-agent. Read the hits and answer the
query. Cite each fact as [N]. Never invent results. Match the query
language. Honor detail=<<DETAIL>>, style=<<STYLE>>, char bounds
[<<MIN_CHARS>>, <<MAX_CHARS>>].
''';

  final WebEngineHealthAlertTracker _healthAlertTracker =
      WebEngineHealthAlertTracker();

  Future<void> _maybeFireHealthAlerts(AiWebSearchSettings settings) {
    return _healthAlertTracker.notifyFromStats(
      loadStats: WebSearchTelemetryStore.instance.engineStats,
      engineName: (engine) => engine.name,
      successRateThresholdPct: settings.resilience.alertSuccessRatePct,
      averageDurationThresholdMs: settings.resilience.alertAvgDurationMs,
      titlePrefix: 'WebSearch',
      logTag: 'ai_web_search_tool',
    );
  }
}

class _SummaryPrompts {
  const _SummaryPrompts({
    required this.system,
    required this.user,
    required this.rawHits,
  });

  final String system;
  final String user;
  final String rawHits;
}
