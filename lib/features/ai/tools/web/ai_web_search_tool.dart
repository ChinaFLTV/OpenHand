import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../../../app/support/openhand_notification_service.dart';
import '../../../../app/support/silent_log.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_web_search_settings.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/chat/ai_transport_diagnostic_messages.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/web_engine/web_engine_health_alert_tracker.dart';
import '../../service/web_engine/web_engine_quality.dart';
import '../../service/web_search/web_search_cache_store.dart';
import '../../service/web_search/web_search_orchestrator.dart';
import '../../service/web_search/web_search_telemetry_store.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../web_reverse_cdp_first_guard.dart';

/// WebSearch sub-agent 实现：
/// 1. 从 [AiBuiltinToolConfig.webSearchSettings] 读取引擎清单 / 并行 / 模型策略
/// 2. 通过 [WebSearchOrchestrator] 并行/串行调用启用的引擎
/// 3. 把聚合后的命中喂给 background chat client，让模型按 summary prompt 生成
///    最终回答；总结模型可跟随会话或固定为指定模型
///
/// 当 webSearchSettings 缺失（旧用户）时回落到默认配置（自动启用 bing+ddg 兜底）。
class AiWebSearchTool extends AiTool {
  AiWebSearchTool({
    required AiChatClient backgroundChatClient,
    required http.Client httpClient,
  }) : _backgroundChatClient = backgroundChatClient,
       _httpClient = httpClient;

  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;

  /// 由 [AiSessionController._captureLatestRuntimeContext] 注入：
  /// 当 webSearchSettings.modelMode == fixed 时,我们需要在所有 provider 列表里
  /// 找出对应的 AiModelConfig 当作 sub-agent 的 model 句柄;
  /// 同时也会传给 orchestrator 用于 kimi/grok/gemini provider key 复用。
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
        'WebSearch requires query with at least 2 characters.',
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
      return _webReverseCdpFirstBlock(
        decision: cdpFirstDecision,
        query: query,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final command = 'WebSearch $query';
    final workingDirectory = AiToolUtils.defaultWorkingDirectory();

    final resolved = context.catalog.find(context.toolCall.name);
    final settings =
        resolved?.builtinConfig?.webSearchSettings ??
        AiWebSearchSettings.defaults();

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

    // 记录一次完整调用到 telemetry store。失败 silentLog（store 内部
    // 已 swallow），不阻塞主流程：fire-and-forget。
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
          if (_isSkippedWebEngineDiagnostic(r.error)) continue;
          perEngine.add(
            WebSearchPerEngineLog(
              kind: r.kind,
              success: r.isSuccess,
              hitCount: r.hits.length,
              elapsedMs: r.elapsedMs,
              error: r.error,
            ),
          );
        }
      }
      // 命中 cache 不会有 orchestration，但仍然要把 cache 这一"伪引擎"
      // 计入历史以便排查；UI 在统计成功率时只考虑 perEngine 不为空的项
      // （orchestrator 真实跑过的）。
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
            )
            .then((_) => _maybeFireHealthAlerts(settings)),
      );
    }

    AiToolExecutionResult errorResult(
      BashToolExecutionStatus status,
      String message,
    ) => progressReporter.errorResult(
      status: status,
      message: message,
      metadata: meta(),
    );

    progressReporter.emit(
      'searching',
      'Dispatching to enabled search engines.',
    );

    // 优先查本地缓存：同一 query+设置在 TTL 内直接复用 summary。
    final cacheKey = WebSearchCacheStore.computeKey(
      query: query,
      settings: settings,
      allowedDomains: allowedDomains,
      blockedDomains: blockedDomains,
      localeTag: Platform.localeName,
    );
    final cached = await WebSearchCacheStore.instance.lookup(
      key: cacheKey,
      settings: settings,
    );
    if (cached != null) {
      progressReporter.emit(
        'cache.hit',
        'Reused cached summary (${cached.summary.length} chars, '
            'expires ${cached.expiresAt.toIso8601String()}).',
      );
      recordTelemetry(
        cacheStatus: 'hit',
        success: true,
        summaryChars: cached.summary.length,
      );
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.success,
        command: command,
        workingDirectory: workingDirectory,
        stdout: progress.toString().trimRight(),
        stderr: '',
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
                    ? '${p.hitCount} hits in ${p.elapsedMs}ms'
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
        'WebSearch timed out while contacting search engines.',
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
      final allFailed = orchestrationResult.engineRuns.every(
        (r) => !r.isSuccess,
      );
      final detail = allFailed
          ? 'All enabled engines returned no results or errored. '
                'See `engines` metadata for per-engine diagnostics.'
          : 'No search results matched the current filters.';
      progressReporter.emit('completed', detail);
      recordTelemetry(
        cacheStatus: settings.cacheEnabled ? 'miss-empty' : 'disabled',
        success: !allFailed,
        summaryChars: 0,
        orchestration: orchestrationResult,
      );
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.success,
        command: command,
        workingDirectory: workingDirectory,
        stdout: progress.toString().trimRight(),
        stderr: '',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: detail,
        metadata: meta(
          resultCount: 0,
          engines: orchestrationResult.engineRuns
              .map((r) => '${r.kind.name}:${r.error ?? "ok"}')
              .toList(growable: false),
          fallbackUsed: orchestrationResult.fallbackUsed,
        ),
      );
    }

    progressReporter.emit(
      'summarizing',
      'Asking summary model to compose the final answer.',
    );

    final summaryModel = _resolveSummaryModel(
      settings: settings,
      sessionModel: context.model,
    );

    final prompt = await _composeSummaryPrompt(settings, query, merged);

    late final AiChatCompletion completion;
    try {
      final maybe = await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
        _backgroundChatClient.sendMessage(
          model: summaryModel,
          messages: <AiChatTurn>[
            AiChatTurn(role: AiChatRole.system, content: prompt.system),
            AiChatTurn(role: AiChatRole.user, content: prompt.user),
          ],
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
        'WebSearch timed out while summarizing the results.',
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
          ? errorResult(
              BashToolExecutionStatus.timedOut,
              'WebSearch timed out while summarizing the results.',
            )
          : errorResult(
              BashToolExecutionStatus.failed,
              'WebSearch failed while summarizing the results: $msg',
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
          ? errorResult(
              BashToolExecutionStatus.timedOut,
              'WebSearch timed out while summarizing the results.',
            )
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

    progressReporter.emit('completed', 'Search summary is ready.');

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
          'tool_call_id': context.toolCall.id,
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
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: command,
      workingDirectory: workingDirectory,
      stdout: progress.toString().trimRight(),
      stderr: '',
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
      template = await rootBundle.loadString(
        'assets/prompts/common/web_search_summary.md',
      );
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

  /// 健康度告警：在每次 recordCall 之后扫一遍当前 engineStats，命中阈值
  /// 触发系统通知；同一异常持续期间只提醒一次，恢复后再次恶化才重新提醒。
  Future<void> _maybeFireHealthAlerts(AiWebSearchSettings settings) async {
    final pctTh = settings.alertSuccessRatePct;
    final avgTh = settings.alertAvgDurationMs;
    if (pctTh <= 0 && avgTh <= 0) {
      _healthAlertTracker.reset();
      return;
    }
    try {
      final stats = await WebSearchTelemetryStore.instance.engineStats();
      _healthAlertTracker.retainEngines(
        stats.keys.map((engine) => engine.name),
      );
      for (final entry in stats.entries) {
        final s = entry.value;
        final alerts = _healthAlertTracker.update(
          engineName: entry.key.name,
          totalCalls: s.totalCalls,
          successRate: s.successRate,
          averageDurationMs: s.avgDurationMs,
          successRateThresholdPct: pctTh,
          averageDurationThresholdMs: avgTh,
        );
        for (final alert in alerts) {
          final body = switch (alert.kind) {
            WebEngineHealthAlertKind.lowSuccessRate =>
              '成功率 ${alert.actualValue}% < 阈值 ${alert.threshold}%'
                  '（共 ${s.totalCalls} 次调用）',
            WebEngineHealthAlertKind.slowAverageDuration =>
              '平均耗时 ${alert.actualValue}ms > 阈值 ${alert.threshold}ms',
          };
          await OpenHandNotificationService.showInApp(
            title: 'WebSearch · ${alert.engineName}',
            body: body,
            level: OpenHandNotificationLevel.warning,
          );
        }
      }
    } catch (error, stack) {
      silentLog('ai_web_search_tool', '_maybeFireHealthAlerts', error, stack);
    }
  }
}

AiToolExecutionResult _webReverseCdpFirstBlock({
  required WebReverseCdpFirstDecision decision,
  required String query,
  required int durationMs,
}) {
  final message = decision.blockedMessage('WebSearch');
  return AiToolExecutionResult(
    status: BashToolExecutionStatus.invalidArguments,
    command: 'WebSearch $query',
    workingDirectory: AiToolUtils.defaultWorkingDirectory(),
    stdout:
        'cdp_first_required: true\n'
        'target_origin: ${decision.targetOrigin}\n'
        'requested_origin: ${decision.requestedOrigin}\n'
        'cdp_route: ${decision.routeKind}\n'
        'cdp_tools: ${decision.toolText}',
    stderr: message,
    durationMs: durationMs,
    resultText: 'status: invalid_arguments\nerror: $message',
    metadata: <String, Object?>{
      'web_reverse_websearch_blocked_query_char_count': query.length,
      ...decision.metadata(
        requestedUrl: decision.requestedUri.toString(),
        blockedFlag: 'web_reverse_websearch_blocked_for_cdp_first',
      ),
    },
  );
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

bool _isSkippedWebEngineDiagnostic(String? error) {
  return error?.startsWith('skipped: ') ?? false;
}
