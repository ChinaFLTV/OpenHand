import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../app/support/openhand_notification_service.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/url_validation.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/chat/ai_transport_diagnostic_messages.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/web_engine/web_engine_health_alert_tracker.dart';
import '../../service/web_fetch/web_fetch_cache_store.dart';
import '../../service/web_fetch/web_fetch_orchestrator.dart';
import '../../service/web_fetch/web_fetch_scrapling_bridge.dart';
import '../../service/web_fetch/web_fetch_telemetry_store.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../web_reverse_cdp_first_guard.dart';

/// WebFetch 工具实现：
/// 1. 从 [AiBuiltinToolConfig.webFetchSettings] 读取启用的引擎清单 / 缓存策略 /
///    并行参数；缺省回落到默认配置（自动启用 Bing/DDG 兜底）。
/// 2. 通过 [WebFetchOrchestrator] 并行/串行扇出抓取，按质量评分挑选胜出引擎的内容。
/// 3. 把胜出内容喂给 background chat client，让模型按 user prompt 聚焦回答。
class AiWebFetchTool extends AiTool {
  AiWebFetchTool({
    required AiChatClient backgroundChatClient,
    required http.Client httpClient,
    required WebFetchScraplingBridge scraplingBridge,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
  }) : _backgroundChatClient = backgroundChatClient,
       _httpClient = httpClient,
       _scraplingBridge = scraplingBridge,
       _hostLookup = hostLookup ?? ((host) => InternetAddress.lookup(host));

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
      return AiToolUtils.invalidResult(
        'WebFetch',
        'WebFetch requires url and prompt.',
      );
    }
    final uri = tryParseValidHttpUrl(rawUrl);
    if (uri == null) {
      return AiToolUtils.invalidResult('WebFetch', 'Invalid URL: $rawUrl');
    }
    final cdpFirstDecision = WebReverseCdpFirstGuard.evaluateUrl(
      requestedUri: uri,
      metadata: context.metadata,
    );
    if (cdpFirstDecision != null) {
      return _webReverseCdpFirstBlock(
        decision: cdpFirstDecision,
        rawUrl: rawUrl,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }
    final blockedReason = await _blockedReason(uri);
    if (blockedReason != null) {
      return AiToolUtils.invalidResult('WebFetch', blockedReason);
    }

    final command = 'WebFetch $rawUrl';
    final workingDirectory = AiToolUtils.defaultWorkingDirectory();

    final resolved = context.catalog.find(context.toolCall.name);
    final settings =
        resolved?.builtinConfig?.webFetchSettings ??
        AiWebFetchSettings.defaults();

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
          if (_isSkippedWebEngineDiagnostic(r.error)) continue;
          perEngine.add(
            WebFetchPerEngineLog(
              kind: r.kind,
              success: r.isSuccess,
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
            )
            .then((_) => _maybeFireHealthAlerts(settings)),
      );
    }

    // 1) 缓存查询：同一 (url, prompt) 在 TTL 内直接复用。
    final cacheKey = WebFetchCacheStore.computeKey(
      url: rawUrl,
      prompt: prompt,
      settings: settings,
      modelProtocol: context.model.protocolType.name,
      modelId: context.model.modelId,
    );
    final cached = await WebFetchCacheStore.instance.lookup(
      key: cacheKey,
      settings: settings,
    );
    if (cached != null) {
      progressReporter.emit(
        'cache.hit',
        'Reused cached fetch (${cached.content.length} chars, '
            'expires ${cached.expiresAt.toIso8601String()}).',
      );
      recordTelemetry(
        cacheStatus: 'hit',
        success: true,
        contentChars: cached.content.length,
      );
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.success,
        command: command,
        workingDirectory: workingDirectory,
        stdout: progress.toString().trimRight(),
        stderr: '',
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

    progressReporter.emit('fetching', 'Dispatching to enabled fetch engines.');

    // 2) Orchestrator fan-out。
    final orchestrator = WebFetchOrchestrator(
      settings: settings,
      httpClient: _httpClient,
      availableModels: availableModels,
      scraplingBridge: _scraplingBridge,
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
                    ? '${p.contentBytes} bytes in ${p.elapsedMs}ms'
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
        'WebFetch timed out while contacting fetch engines.',
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
          ? 'All enabled fetch engines failed. '
                'See `engines` metadata for per-engine diagnostics.'
          : 'No content extracted from any fetch engine.';
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
      'Winner: ${orchestrationResult.winningKind?.name} '
          '(${winner.content.length} chars). Asking model to focus on prompt.',
    );

    // 3) 让模型按 user prompt 聚焦回答（保留原 ai_web_fetch_tool 行为）。
    late final AiChatCompletion? completion;
    try {
      completion = await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
        _backgroundChatClient.sendMessage(
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
        'WebFetch timed out while focusing on the fetched page.',
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
              'WebFetch timed out while focusing on the fetched page.',
            )
          : errorResult(
              BashToolExecutionStatus.failed,
              'WebFetch failed while focusing on the fetched page: $msg',
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
              'WebFetch timed out while focusing on the fetched page.',
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

    progressReporter.emit('completed', 'Fetch + focus answer ready.');

    final engineSummaries = orchestrationResult.engineRuns
        .map(
          (r) =>
              '${r.kind.name}:${r.isSuccess ? "ok(${r.contents.isEmpty ? 0 : r.contents.first.content.length})" : (r.error ?? "fail")}',
        )
        .toList(growable: false);

    // 4) 写本地持久化缓存（await chain 完成以保证下次可读）。
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
            'tool_call_id': context.toolCall.id,
            'winning_engine': orchestrationResult.winningKind?.name,
            'engines': engineSummaries,
            'fallback_used': orchestrationResult.fallbackUsed,
            'final_url': winner.url,
            'content_type': winner.contentType,
            'http_status': winner.statusCode,
            'response_headers': winner.responseHeaders,
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
      } catch (error, stack) {
        silentLog('ai_web_fetch', 'cache_store', error, stack);
      }
    }

    recordTelemetry(
      cacheStatus: settings.cacheEnabled ? 'miss-stored' : 'disabled',
      success: true,
      contentChars: output.length,
      orchestration: orchestrationResult,
    );

    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: command,
      workingDirectory: workingDirectory,
      stdout: progress.toString().trimRight(),
      stderr: '',
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

  Future<String?> _blockedReason(Uri uri) async {
    final directReason = agentFetchBlockReasonForUri(uri);
    if (directReason != null) {
      return 'WebFetch blocks $directReason: ${uri.host}';
    }
    if (InternetAddress.tryParse(uri.host) != null) return null;
    try {
      final resolvedAddresses = await _hostLookup(
        uri.host,
      ).timeout(const Duration(seconds: 2));
      for (final address in resolvedAddresses) {
        final addressReason = agentFetchBlockReasonForAddress(address);
        if (addressReason != null) {
          return 'WebFetch blocked ${uri.host} because it resolved to '
              '$addressReason (${address.address}).';
        }
      }
    } on SocketException {
      return null;
    } on TimeoutException {
      return 'WebFetch blocked ${uri.host} because DNS resolution timed out.';
    } catch (_) {
      return null;
    }
    return null;
  }

  final WebEngineHealthAlertTracker _healthAlertTracker =
      WebEngineHealthAlertTracker();

  /// 健康度告警：在每次 recordCall 之后扫一遍当前 engineStats，命中阈值
  /// 触发系统通知；同一异常持续期间只提醒一次，恢复后再次恶化才重新提醒。
  Future<void> _maybeFireHealthAlerts(AiWebFetchSettings settings) async {
    final pctTh = settings.alertSuccessRatePct;
    final avgTh = settings.alertAvgDurationMs;
    if (pctTh <= 0 && avgTh <= 0) {
      _healthAlertTracker.reset();
      return;
    }
    try {
      final stats = await WebFetchTelemetryStore.instance.engineStats();
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
            title: 'WebFetch · ${alert.engineName}',
            body: body,
            level: OpenHandNotificationLevel.warning,
          );
        }
      }
    } catch (error, stack) {
      silentLog('ai_web_fetch_tool', '_maybeFireHealthAlerts', error, stack);
    }
  }
}

bool _isSkippedWebEngineDiagnostic(String? error) {
  return error?.startsWith('skipped: ') ?? false;
}

AiToolExecutionResult _webReverseCdpFirstBlock({
  required WebReverseCdpFirstDecision decision,
  required String rawUrl,
  required int durationMs,
}) {
  final message = decision.blockedMessage('WebFetch');
  return AiToolExecutionResult(
    status: BashToolExecutionStatus.invalidArguments,
    command: 'WebFetch $rawUrl',
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
      'webfetch_url': rawUrl,
      ...decision.metadata(
        requestedUrl: rawUrl,
        blockedFlag: 'web_reverse_webfetch_blocked_for_cdp_first',
      ),
    },
  );
}
