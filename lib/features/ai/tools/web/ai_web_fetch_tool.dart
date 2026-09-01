import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../app/support/silent_log.dart';
import '../../../../app/support/url_validation.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_session_message.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/chat/ai_transport_diagnostic_messages.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/usage/ai_usage_tracker.dart';
import '../../service/web_engine/web_engine_concurrency.dart';
import '../../service/web_engine/web_engine_health_alert_tracker.dart';
import '../../service/web_engine/web_engine_telemetry_store_base.dart';
import '../../service/web_fetch/web_fetch_cache_store.dart';
import '../../service/web_fetch/web_fetch_orchestrator.dart';
import '../../service/web_fetch/web_fetch_scrapling_bridge.dart';
import '../../service/web_fetch/web_fetch_telemetry_store.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../web_reverse_cdp_first_guard.dart';

/// WebFetch：按配置调度抓取引擎，选择最佳内容后由模型聚焦回答。
/// 旧配置缺失时使用默认引擎。
class AiWebFetchTool extends AiTool {
  AiWebFetchTool({
    required this._backgroundChatClient,
    required this._httpClient,
    required this._scraplingBridge,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
  }) : _hostLookup = hostLookup ?? ((host) => InternetAddress.lookup(host));

  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  final WebFetchScraplingBridge _scraplingBridge;
  final Future<List<InternetAddress>> Function(String host) _hostLookup;

  List<AiModelConfig> availableModels = const <AiModelConfig>[];

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.webFetch;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final stopwatch = Stopwatch()..start();
    final rawUrl = AiToolUtils.readString(args['url']);
    final prompt = AiToolUtils.readString(args['prompt']);
    if (rawUrl.isEmpty || prompt.isEmpty) {
      return AiToolUtils.invalidResult('WebFetch', 'WebFetch 需要 url 和 prompt。');
    }
    final uri = tryParseValidHttpUrl(rawUrl);
    if (uri == null) {
      return AiToolUtils.invalidResult('WebFetch', '无效网址：$rawUrl');
    }
    final cdpFirstDecision = WebReverseCdpFirstGuard.evaluateUrl(
      requestedUri: uri,
      metadata: context.metadata,
    );
    if (cdpFirstDecision != null) {
      final message = cdpFirstDecision.blockedMessage('WebFetch');
      return AiToolUtils.invalidResult(
        'WebFetch $rawUrl',
        message,
        stdout: cdpFirstDecision.diagnosticText(),
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: <String, Object?>{
          'webfetch_url': rawUrl,
          ...cdpFirstDecision.metadata(
            requestedUrl: rawUrl,
            blockedFlag: 'web_reverse_webfetch_blocked_for_cdp_first',
          ),
        },
      );
    }
    final blockedReason = await _uriBlockReason(uri);
    if (blockedReason != null) {
      return AiToolUtils.invalidResult(
        'WebFetch',
        'WebFetch 拒绝访问 ${uri.host}: $blockedReason。',
      );
    }

    final command = 'WebFetch $rawUrl';
    final workingDirectory = AiToolUtils.defaultWorkingDirectory();

    final resolved = context.catalog.find(context.toolCall.name);
    final settings =
        resolved?.builtinConfig?.webFetchSettings ??
        AiWebFetchSettings.defaults();
    final cooldownConfig = WebEngineCooldownConfig.fromResilience(
      settings.resilience,
    );

    final progress = StringBuffer()
      ..writeln('url: $rawUrl')
      ..writeln('engines_active: ${_engineLabels(settings)}')
      ..writeln(
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
      int? contentChars,
      List<String>? engines,
      bool? fallbackUsed,
      AiWebFetchEngineKind? winner,
    }) {
      return <String, Object?>{
        'webfetch_url': rawUrl,
        if (contentChars != null) 'webfetch_content_chars': contentChars,
        if (engines != null) 'webfetch_engines': engines,
        if (fallbackUsed != null) 'webfetch_fallback_used': fallbackUsed,
        if (winner != null) 'webfetch_winning_engine': winner.name,
      };
    }

    AiToolExecutionResult errorResult(
      BashToolExecutionStatus status,
      String message,
    ) => progressReporter.errorResult(
      status: status,
      message: message,
      metadata: meta(),
    );

    void recordTelemetry({
      required String cacheStatus,
      required bool success,
      required int contentChars,
      WebFetchOrchestrationResult? orchestration,
      String? errorMessage,
    }) {
      final perEngine = <WebFetchPerEngineLog>[];
      if (orchestration != null) {
        for (final r in orchestration.engineRuns) {
          if (isSkippedWebEngineDiagnostic(r.error)) continue;
          perEngine.add(
            WebFetchPerEngineLog(
              kind: r.kind,
              success: r.error == null,
              contentBytes: r.contents.isEmpty
                  ? 0
                  : r.contents.first.content.length,
              elapsedMs: r.elapsedMs,
              error: r.error,
            ),
          );
        }
      }
      unawaited(
        WebFetchTelemetryStore.instance
            .recordCall(
              WebFetchCallLog(
                timestampMs: DateTime.now().millisecondsSinceEpoch,
                url: rawUrl,
                cacheStatus: cacheStatus,
                success: success,
                totalDurationMs: stopwatch.elapsedMilliseconds,
                contentChars: contentChars,
                fallbackUsed: orchestration?.fallbackUsed ?? false,
                errorMessage: errorMessage,
                winningEngine: orchestration?.winningKind,
                perEngine: perEngine,
              ),
              cooldownConfig: cooldownConfig,
            )
            .then((_) => _maybeFireHealthAlerts(settings)),
      );
    }

    // 优先复用有效期内的同网址、同提示词缓存。
    final cacheKey = WebFetchCacheStore.computeKey(
      url: rawUrl,
      prompt: prompt,
      settings: settings,
      modelProtocol: context.model.protocolType.name,
      modelId: context.model.modelId,
      modelConfigId: context.model.id,
    );
    final cached = await WebFetchCacheStore.instance.lookup(
      key: cacheKey,
      settings: settings,
    );
    if (cached != null) {
      progressReporter.emit(
        'cache.hit',
        '已复用抓取缓存（${cached.content.length} 个字符，'
            '过期时间：${cached.expiresAt.toIso8601String()}）。',
      );
      recordTelemetry(
        cacheStatus: 'hit',
        success: true,
        contentChars: cached.content.length,
      );
      return AiToolUtils.progressSuccessResult(
        command: command,
        workingDirectory: workingDirectory,
        progress: progress,
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: cached.content,
        metadata: <String, Object?>{
          ...meta(contentChars: cached.content.length),
          'webfetch_cache': 'hit',
          'webfetch_cache_key': cacheKey,
          'webfetch_cache_cached_at': cached.cachedAt.toIso8601String(),
          'webfetch_cache_expires_at': cached.expiresAt.toIso8601String(),
          ...cached.metadata,
        },
      );
    }

    progressReporter.emit('fetching', '正在调度已启用的抓取引擎。');

    final orchestrator = WebFetchOrchestrator(
      settings: settings,
      httpClient: _httpClient,
      availableModels: availableModels,
      scraplingBridge: _scraplingBridge,
      uriBlockReason: _uriBlockReason,
    );

    final WebFetchOrchestrationResult orchestrationResult;
    try {
      orchestrationResult = await orchestrator.run(
        url: rawUrl,
        prompt: prompt,
        cancelSignal: context.cancelSignal,
        onProgress: (p) {
          progressReporter.emit(
            'engine.${p.kind.name}.${p.stage.name}',
            p.message ??
                (p.stage == WebFetchProgressStage.succeeded
                    ? '在 ${p.elapsedMs} 毫秒内抓取 ${p.contentBytes} 字节'
                    : ''),
          );
        },
      );
    } on TimeoutException {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        contentChars: 0,
        errorMessage: 'orchestrator_timeout',
      );
      return errorResult(
        BashToolExecutionStatus.timedOut,
        'WebFetch 连接抓取引擎超时。',
      );
    } catch (error) {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        contentChars: 0,
        errorMessage: '$error',
      );
      return errorResult(
        BashToolExecutionStatus.failed,
        AiTransportDiagnosticMessages.friendlyTransportError(
          error,
          contextLabel: 'WebFetch',
        ),
      );
    }

    final winner = orchestrationResult.merged;
    if (winner == null) {
      final allFailed = orchestrationResult.engineRuns.every(
        (r) => !r.isSuccess,
      );
      final detail = allFailed
          ? '所有已启用的抓取引擎均失败，请查看 `engines` 元数据中的引擎诊断。'
          : '所有抓取引擎均未提取到内容。';
      progressReporter.emit('completed', detail);
      recordTelemetry(
        cacheStatus: settings.cacheEnabled ? 'miss-empty' : 'disabled',
        success: false,
        contentChars: 0,
        orchestration: orchestrationResult,
      );
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: workingDirectory,
        stdout: progress.toString().trimRight(),
        stderr: detail,
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: $detail',
        metadata: meta(
          contentChars: 0,
          engines: orchestrationResult.engineRuns
              .map((r) => '${r.kind.name}:${r.error ?? "ok"}')
              .toList(growable: false),
          fallbackUsed: orchestrationResult.fallbackUsed,
        ),
      );
    }

    progressReporter.emit(
      'extracted',
      '已选择 ${orchestrationResult.winningKind?.name} '
          '（${winner.content.length} 个字符），正在请求模型聚焦回答。',
    );

    late final AiChatCompletion? completion;
    try {
      completion = await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
        AiUsageTraceContext.runDerived(
          source: AiUsageSource.webFetch,
          operation: 'content_summary',
          metadata: <String, Object?>{'content_chars': winner.content.length},
          body: () => _backgroundChatClient.sendMessage(
            model: context.model,
            messages: <AiChatTurn>[
              const AiChatTurn(
                role: AiChatRole.system,
                content:
                    'Answer the prompt using only the fetched page content. '
                    'Prefer concrete facts and quote short supporting phrases '
                    'when useful. If the fetched content is insufficient, say '
                    'what is missing instead of guessing.',
              ),
              AiChatTurn(
                role: AiChatRole.user,
                content:
                    'Requested URL: $rawUrl\n'
                    'Final URL: ${winner.url}\n'
                    'Winning engine: ${orchestrationResult.winningKind?.name ?? "unknown"}\n'
                    'HTTP status: ${winner.statusCode ?? "unknown"}\n'
                    'Content type: ${winner.contentType ?? "unknown"}\n'
                    'Prompt: $prompt\n\n'
                    'Fetched content:\n${winner.content}',
              ),
            ],
            cancelSignal: context.cancelSignal,
          ),
        ),
        cancelSignal: context.cancelSignal,
      );
    } on TimeoutException {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        contentChars: 0,
        orchestration: orchestrationResult,
        errorMessage: 'focus_timeout',
      );
      return errorResult(
        BashToolExecutionStatus.timedOut,
        'WebFetch 聚焦处理抓取页面超时。',
      );
    } on AiChatException catch (error) {
      final msg = error.message.trim();
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        contentChars: 0,
        orchestration: orchestrationResult,
        errorMessage: msg,
      );
      return AiToolUtils.looksLikeTimeoutMessage(msg)
          ? errorResult(
              BashToolExecutionStatus.timedOut,
              'WebFetch 聚焦处理抓取页面超时。',
            )
          : errorResult(
              BashToolExecutionStatus.failed,
              'WebFetch 聚焦处理抓取页面失败：$msg',
            );
    } catch (error) {
      final msg = '$error';
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        contentChars: 0,
        orchestration: orchestrationResult,
        errorMessage: msg,
      );
      return AiToolUtils.looksLikeTimeoutMessage(msg)
          ? errorResult(
              BashToolExecutionStatus.timedOut,
              'WebFetch 聚焦处理抓取页面超时。',
            )
          : errorResult(
              BashToolExecutionStatus.failed,
              AiTransportDiagnosticMessages.friendlyTransportError(
                error,
                contextLabel: 'WebFetch',
              ),
            );
    }
    if (completion == null) {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        contentChars: 0,
        orchestration: orchestrationResult,
        errorMessage: 'cancelled',
      );
      return AiToolUtils.cancelledResult(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }
    final output = completion.reply.trim().isEmpty
        ? winner.content
        : completion.reply.trim();

    progressReporter.emit('completed', '抓取与聚焦回答已完成。');

    final engineSummaries = orchestrationResult.engineRuns
        .map(
          (r) =>
              '${r.kind.name}:${r.isSuccess ? "ok(${r.contents.isEmpty ? 0 : r.contents.first.content.length})" : (r.error ?? "fail")}',
        )
        .toList(growable: false);

    // 等待缓存持久化完成，确保下次可读。
    if (settings.cacheEnabled && output.trim().isNotEmpty) {
      try {
        await WebFetchCacheStore.instance.store(
          key: cacheKey,
          settings: settings,
          url: rawUrl,
          content: output,
          metadata: <String, Object?>{
            'session_id': context.sessionId,
            'tool_name': context.toolCall.name,
            aiSessionMessageToolCallIdMetadataKey: context.toolCall.id,
            'winning_engine': orchestrationResult.winningKind?.name,
            'engines': engineSummaries,
            'fallback_used': orchestrationResult.fallbackUsed,
            'final_url': winner.url,
            'content_type': winner.contentType,
            'http_status': winner.statusCode,
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
      } catch (error, stack) {
        silentLog('ai_web_fetch', '写入抓取缓存', error, stack);
      }
    }

    recordTelemetry(
      cacheStatus: settings.cacheEnabled ? 'miss-stored' : 'disabled',
      success: true,
      contentChars: output.length,
      orchestration: orchestrationResult,
    );

    return AiToolUtils.progressSuccessResult(
      command: command,
      workingDirectory: workingDirectory,
      progress: progress,
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: output,
      metadata:
          meta(
              contentChars: output.length,
              engines: engineSummaries,
              fallbackUsed: orchestrationResult.fallbackUsed,
              winner: orchestrationResult.winningKind,
            )
            ..['webfetch_cache'] = settings.cacheEnabled
                ? 'miss-stored'
                : 'disabled',
    );
  }

  String _engineLabels(AiWebFetchSettings settings) {
    final active = settings.engines.where((e) => e.enabled).toList();
    if (active.isEmpty) return '<fallback: bing,duckduckgo>';
    return active.map((e) => e.kind.name).join(',');
  }

  Future<String?> _uriBlockReason(Uri uri) {
    return agentFetchBlockReasonForResolvedUri(uri, hostLookup: _hostLookup);
  }

  final WebEngineHealthAlertTracker _healthAlertTracker =
      WebEngineHealthAlertTracker();

  Future<void> _maybeFireHealthAlerts(AiWebFetchSettings settings) {
    return _healthAlertTracker.notifyFromStats(
      loadStats: WebFetchTelemetryStore.instance.engineStats,
      engineName: (engine) => engine.name,
      successRateThresholdPct: settings.resilience.alertSuccessRatePct,
      averageDurationThresholdMs: settings.resilience.alertAvgDurationMs,
      titlePrefix: 'WebFetch',
      logTag: 'ai_web_fetch_tool',
    );
  }
}
