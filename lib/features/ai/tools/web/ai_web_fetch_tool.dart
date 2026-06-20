import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../app/support/openhand_notification_service.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/url_validation.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/chat/ai_transport_diagnostic_messages.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/web_fetch/web_fetch_cache_store.dart';
import '../../service/web_fetch/web_fetch_orchestrator.dart';
import '../../service/web_fetch/web_fetch_scrapling_bridge.dart';
import '../../service/web_fetch/web_fetch_telemetry_store.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

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

  // 由 AiSessionController 推送的运行时参数（保留向后兼容字段）。
  // 这三项历史 settings 仍由 settings_controller 推到 runtime context；保留即可，
  // 新代码主要依赖 [AiBuiltinToolConfig.webFetchSettings]。
  int maxRedirects = 5;
  int maxResponseBytes = kBytesPerMiB;
  int maxCacheEntries = 64; // 仅作占位，新缓存层走磁盘 LRU
  List<AiModelConfig> availableModels = const <AiModelConfig>[];

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.webFetch;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final stopwatch = Stopwatch()..start();
    final rawUrl = '${args['url'] ?? ''}'.trim();
    final prompt = '${args['prompt'] ?? ''}'.trim();
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
    final cdpFirstBlock = _webReverseCdpFirstBlock(
      requestedUri: uri,
      rawUrl: rawUrl,
      metadata: context.metadata,
      durationMs: stopwatch.elapsedMilliseconds,
    );
    if (cdpFirstBlock != null) {
      return cdpFirstBlock;
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

    void emit(String stage, String detail) {
      if (progress.isNotEmpty) progress.writeln();
      progress
        ..writeln('stage: $stage')
        ..write('detail: $detail');
      context.onBashUpdate?.call(
        BashToolExecutionUpdate(
          phase: BashToolExecutionPhase.running,
          command: command,
          workingDirectory: workingDirectory,
          stdout: progress.toString().trimRight(),
          stderr: '',
          durationMs: stopwatch.elapsedMilliseconds,
        ),
      );
    }

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

    AiToolExecutionResult timedOut(String message) => AiToolExecutionResult(
      status: BashToolExecutionStatus.timedOut,
      command: command,
      workingDirectory: workingDirectory,
      stdout: progress.toString().trimRight(),
      stderr: message,
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: 'status: timed_out\nerror: $message',
      metadata: meta(),
    );

    AiToolExecutionResult failed(String message) => AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: command,
      workingDirectory: workingDirectory,
      stdout: progress.toString().trimRight(),
      stderr: message,
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: 'status: failed\nerror: $message',
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
      emit(
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

    emit('fetching', 'Dispatching to enabled fetch engines.');

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
          emit(
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
      return timedOut('WebFetch timed out while contacting fetch engines.');
    } catch (error) {
      recordTelemetry(
        cacheStatus: 'bypass',
        success: false,
        contentChars: 0,
        errorMessage: '$error',
      );
      return failed(_friendlyFetchTransportError(error));
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
      emit('completed', detail);
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

    emit(
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
      return timedOut('WebFetch timed out while focusing on the fetched page.');
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
          ? timedOut('WebFetch timed out while focusing on the fetched page.')
          : failed('WebFetch failed while focusing on the fetched page: $msg');
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
          ? timedOut('WebFetch timed out while focusing on the fetched page.')
          : failed(_friendlyFetchTransportError(error));
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

    emit('completed', 'Fetch + focus answer ready.');

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

  // 进程内已经发过告警的 (engine, reason)，避免连续刷屏。重启进程后清空。
  final Set<String> _alertedKeys = <String>{};

  /// 健康度告警：在每次 recordCall 之后扫一遍当前 engineStats，命中阈值
  /// 触发系统通知（同一 key 进程内只发一次，重启 / clearLogs 后重新生效）。
  Future<void> _maybeFireHealthAlerts(AiWebFetchSettings settings) async {
    final pctTh = settings.alertSuccessRatePct;
    final avgTh = settings.alertAvgDurationMs;
    if (pctTh <= 0 && avgTh <= 0) return;
    try {
      final stats = await WebFetchTelemetryStore.instance.engineStats();
      for (final entry in stats.entries) {
        final s = entry.value;
        if (s.totalCalls < 5) continue;
        if (pctTh > 0) {
          final pct = (s.successRate * 100).round();
          if (pct < pctTh) {
            final key = '${entry.key.name}::low-success::$pct';
            if (_alertedKeys.add(key)) {
              await OpenHandNotificationService.showInApp(
                title: 'WebFetch · ${entry.key.name}',
                body: '成功率 $pct% < 阈值 $pctTh%（共 ${s.totalCalls} 次调用）',
                level: OpenHandNotificationLevel.warning,
              );
            }
          }
        }
        if (avgTh > 0) {
          final avg = s.avgDurationMs.round();
          if (avg > avgTh) {
            final key = '${entry.key.name}::slow::$avg';
            if (_alertedKeys.add(key)) {
              await OpenHandNotificationService.showInApp(
                title: 'WebFetch · ${entry.key.name}',
                body: '平均耗时 ${avg}ms > 阈值 ${avgTh}ms',
                level: OpenHandNotificationLevel.warning,
              );
            }
          }
        }
      }
    } catch (error, stack) {
      silentLog('ai_web_fetch_tool', '_maybeFireHealthAlerts', error, stack);
    }
  }
}

/// 把底层 dart:io / http 异常转换成「现象 / 原因 / 建议」三段式中英双语
/// 文本，给 LLM 足够上下文以便后续回复用户。
String _friendlyFetchTransportError(Object error) {
  if (error is HandshakeException) {
    return AiTransportDiagnosticMessages.handshake(
      error,
      contextLabel: 'WebFetch',
    );
  }
  if (error is TlsException) {
    return AiTransportDiagnosticMessages.tls(error, contextLabel: 'WebFetch');
  }
  if (error is SocketException) {
    return AiTransportDiagnosticMessages.socket(
      error,
      contextLabel: 'WebFetch',
    );
  }
  if (error is http.ClientException) {
    return AiTransportDiagnosticMessages.httpClient(
      error,
      contextLabel: 'WebFetch',
    );
  }
  return '$error';
}

bool _isSkippedWebEngineDiagnostic(String? error) {
  return error?.startsWith('skipped: ') ?? false;
}

AiToolExecutionResult? _webReverseCdpFirstBlock({
  required Uri requestedUri,
  required String rawUrl,
  required Map<String, Object?> metadata,
  required int durationMs,
}) {
  final runtime = _stringObjectMap(metadata['web_reverse_runtime']);
  if (runtime == null || !_boolValue(runtime['cdp_first_required'])) {
    return null;
  }

  final route = _webReverseCdpRoute(runtime);
  if (route == null) return null;

  Uri? matchedTargetUri;
  for (final targetUri in _webReverseTargetUris(runtime)) {
    if (_isSameHttpOrigin(requestedUri, targetUri)) {
      matchedTargetUri = targetUri;
      break;
    }
  }
  if (matchedTargetUri == null) return null;

  final targetOrigin = _httpOriginLabel(matchedTargetUri);
  final requestedOrigin = _httpOriginLabel(requestedUri);
  final toolPreview = route.toolNames.take(8).toList(growable: false);
  final toolText = toolPreview.isEmpty
      ? route.fallbackToolLabel
      : toolPreview.join(', ');
  final action = route.requiresToolSearch
      ? 'Call ToolSearch first to load the CDP MCP tools, then inspect the live browser with those exact tool names.'
      : 'Use the exact callable CDP MCP tools first: $toolText.';
  final message =
      'WebFetch is blocked for this Web Reverse target because live CDP is available.\n'
      'target_origin: $targetOrigin\n'
      'requested_origin: $requestedOrigin\n'
      'next_action: $action\n'
      'allowed: Use WebFetch only for unrelated external docs/static references, or after live CDP is unavailable.';

  return AiToolExecutionResult(
    status: BashToolExecutionStatus.invalidArguments,
    command: 'WebFetch $rawUrl',
    workingDirectory: AiToolUtils.defaultWorkingDirectory(),
    stdout:
        'cdp_first_required: true\n'
        'target_origin: $targetOrigin\n'
        'requested_origin: $requestedOrigin\n'
        'cdp_route: ${route.kind}\n'
        'cdp_tools: $toolText',
    stderr: message,
    durationMs: durationMs,
    resultText: 'status: invalid_arguments\nerror: $message',
    metadata: <String, Object?>{
      'webfetch_url': rawUrl,
      'web_reverse_webfetch_blocked_for_cdp_first': true,
      'web_reverse_cdp_first_block_reason':
          'same_target_origin_with_live_cdp_route',
      'web_reverse_cdp_route': route.kind,
      'web_reverse_cdp_route_requires_tool_search': route.requiresToolSearch,
      'web_reverse_target_url': matchedTargetUri.toString(),
      'web_reverse_target_origin': targetOrigin,
      'web_reverse_requested_origin': requestedOrigin,
      'web_reverse_cdp_tool_preview': toolPreview,
    },
  );
}

_WebReverseCdpRoute? _webReverseCdpRoute(Map<String, Object?> runtime) {
  final availability = _stringObjectMap(runtime['cdp_mcp_tool_availability']);
  final cdpRuntime = _stringObjectMap(runtime['cdp_runtime']);
  final runtimeLive =
      _boolValue(availability?['browser_runtime_live']) ||
      _boolValue(cdpRuntime?['browser_alive']);
  if (!runtimeLive) return null;

  final currentToolNames = _stringList(
    availability?['current_turn_callable_names'],
  );
  final currentToolCount = _intValue(
    availability?['current_turn_callable_count'],
  );
  final currentCallable =
      _boolValue(availability?['live_cdp_actions_current_turn_callable']) ||
      (_boolValue(availability?['current_turn_callable']) &&
          (currentToolNames.isNotEmpty || currentToolCount > 0));
  if (currentCallable) {
    return _WebReverseCdpRoute.current(
      currentToolNames,
      fallbackToolLabel: currentToolCount > 0
          ? '$currentToolCount current CDP MCP tools'
          : 'current CDP MCP tools',
    );
  }

  final deferredToolNames = _stringList(
    availability?['tool_search_deferred_cdp_mcp_names'],
  );
  final deferredToolCount = _intValue(
    availability?['tool_search_deferred_cdp_mcp_count'],
  );
  if (_boolValue(availability?['tool_search_available']) &&
      (deferredToolNames.isNotEmpty || deferredToolCount > 0)) {
    return _WebReverseCdpRoute.deferred(
      deferredToolNames,
      fallbackToolLabel: deferredToolCount > 0
          ? '$deferredToolCount deferred CDP MCP tools'
          : 'deferred CDP MCP tools',
    );
  }

  return null;
}

List<Uri> _webReverseTargetUris(Map<String, Object?> runtime) {
  final urls = <String>[];
  final config = _stringObjectMap(runtime['config']);
  _addUrl(urls, config?['target_url']);

  final cdpRuntime = _stringObjectMap(runtime['cdp_runtime']);
  _addUrl(urls, _stringObjectMap(cdpRuntime?['current_target'])?['url']);

  final dashboardState = _stringObjectMap(runtime['dashboard_state']);
  _addUrl(
    urls,
    _stringObjectMap(dashboardState?['browser_current_target'])?['url'],
  );
  final tabUrls = dashboardState?['browser_tab_urls'];
  if (tabUrls is List) {
    for (final entry in tabUrls) {
      if (entry is Map) {
        _addUrl(urls, _stringObjectMap(entry)?['url']);
      } else {
        _addUrl(urls, entry);
      }
    }
  }

  final seen = <String>{};
  final uris = <Uri>[];
  for (final url in urls) {
    final uri = tryParseValidHttpUrl(url);
    if (uri == null || uri.host.isEmpty) continue;
    final key =
        '${uri.scheme}://${uri.host.toLowerCase()}:${_effectivePort(uri)}';
    if (seen.add(key)) uris.add(uri);
  }
  return uris;
}

void _addUrl(List<String> urls, Object? raw) {
  final value = '${raw ?? ''}'.trim();
  if (value.isNotEmpty) urls.add(value);
}

bool _isSameHttpOrigin(Uri a, Uri b) {
  return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      _effectivePort(a) == _effectivePort(b);
}

String _httpOriginLabel(Uri uri) {
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = _effectivePort(uri);
  final defaultPort = _defaultPort(uri.scheme);
  final portSuffix = defaultPort == port ? '' : ':$port';
  return '${uri.scheme.toLowerCase()}://$host$portSuffix';
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return _defaultPort(uri.scheme);
}

int _defaultPort(String scheme) {
  return switch (scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => 0,
  };
}

Map<String, Object?>? _stringObjectMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is! Map) return null;
  return <String, Object?>{
    for (final entry in raw.entries) '${entry.key}': entry.value,
  };
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((entry) => '$entry'.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

bool _boolValue(Object? raw) {
  if (raw is bool) return raw;
  final normalized = '${raw ?? ''}'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

int _intValue(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? ''}'.trim()) ?? 0;
}

class _WebReverseCdpRoute {
  const _WebReverseCdpRoute._({
    required this.kind,
    required this.toolNames,
    required this.requiresToolSearch,
    required this.fallbackToolLabel,
  });

  factory _WebReverseCdpRoute.current(
    List<String> toolNames, {
    required String fallbackToolLabel,
  }) {
    return _WebReverseCdpRoute._(
      kind: 'current_turn_callable',
      toolNames: toolNames,
      requiresToolSearch: false,
      fallbackToolLabel: fallbackToolLabel,
    );
  }

  factory _WebReverseCdpRoute.deferred(
    List<String> toolNames, {
    required String fallbackToolLabel,
  }) {
    return _WebReverseCdpRoute._(
      kind: 'deferred_tool_search',
      toolNames: toolNames,
      requiresToolSearch: true,
      fallbackToolLabel: fallbackToolLabel,
    );
  }

  final String kind;
  final List<String> toolNames;
  final bool requiresToolSearch;
  final String fallbackToolLabel;
}
