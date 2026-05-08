import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../model/ai_model_config.dart';
import '../../model/ai_web_fetch_settings.dart';

/// 单个 URL 抓取的统一返回。
class WebFetchEngineContent {
  WebFetchEngineContent({
    required this.url,
    required this.title,
    required this.content,
    this.contentType,
    this.statusCode,
    this.responseHeaders = const <String, String>{},
    this.publishedAt,
    this.score,
  });

  final String url;
  final String title;
  final String content;
  final String? contentType;
  final int? statusCode;
  final Map<String, String> responseHeaders;
  final DateTime? publishedAt;
  final double? score;

  WebFetchEngineContent truncated(int maxChars) {
    if (maxChars <= 0 || content.length <= maxChars) return this;
    return WebFetchEngineContent(
      url: url,
      title: title,
      content: '${content.substring(0, maxChars)}…',
      contentType: contentType,
      statusCode: statusCode,
      responseHeaders: responseHeaders,
      publishedAt: publishedAt,
      score: score,
    );
  }
}

class WebFetchEngineRequest {
  const WebFetchEngineRequest({
    required this.url,
    required this.prompt,
    required this.maxChars,
    this.cancelSignal,
  });

  final String url;
  final String prompt;
  final int maxChars;
  final Future<void>? cancelSignal;
}

class WebFetchEngineResult {
  const WebFetchEngineResult({
    required this.kind,
    required this.contents,
    this.error,
    this.attempts = 1,
    this.elapsedMs = 0,
  });

  final AiWebFetchEngineKind kind;
  final List<WebFetchEngineContent> contents;
  final String? error;
  final int attempts;
  final int elapsedMs;

  bool get isSuccess => error == null && contents.isNotEmpty;
}

abstract class WebFetchEngine {
  WebFetchEngine({required this.config, required this.httpClient});

  final AiWebFetchEngineConfig config;
  final http.Client httpClient;

  AiWebFetchEngineKind get kind => config.kind;

  /// 是否准备就绪（API key / endpoint 等就位）。
  bool get isReady;

  /// 单次执行（不含重试）。
  Future<List<WebFetchEngineContent>> fetch(WebFetchEngineRequest request);

  /// 带重试的对外 API。指数退避 250ms·2^attempt（上限 4s）。
  Future<WebFetchEngineResult> run(WebFetchEngineRequest request) async {
    if (!isReady) {
      return WebFetchEngineResult(
        kind: kind,
        contents: const [],
        error: 'engine_not_ready',
      );
    }
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    final maxAttempts = (config.maxRetries + 1).clamp(1, 8);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (request.cancelSignal != null) {
        final cancelled = await Future.any([
          Future.value(false),
          request.cancelSignal!.then((_) => true),
        ]);
        if (cancelled) {
          return WebFetchEngineResult(
            kind: kind,
            contents: const [],
            error: 'cancelled',
            attempts: attempt - 1,
            elapsedMs: stopwatch.elapsedMilliseconds,
          );
        }
      }
      try {
        final raw = await fetch(request).timeout(const Duration(seconds: 30));
        final truncated = raw
            .map((c) => c.truncated(config.truncationChars))
            .toList(growable: false);
        return WebFetchEngineResult(
          kind: kind,
          contents: truncated,
          attempts: attempt,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      } catch (error, _) {
        lastError = error;
        if (attempt >= maxAttempts) break;
        final backoff = Duration(
          milliseconds: (250 * (1 << (attempt - 1))).clamp(250, 4000),
        );
        await Future<void>.delayed(backoff);
      }
    }
    return WebFetchEngineResult(
      kind: kind,
      contents: const [],
      error: lastError == null
          ? 'unknown_error'
          : '${lastError.runtimeType}: $lastError',
      attempts: maxAttempts,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }
}

class WebFetchEngineContext {
  WebFetchEngineContext({
    required this.httpClient,
    required this.availableModels,
  });

  final http.Client httpClient;
  final List<AiModelConfig> availableModels;

  String? resolveProviderApiKey(String? configId) {
    if (configId == null || configId.isEmpty) return null;
    for (final m in availableModels) {
      if (m.id == configId) return m.token.isEmpty ? null : m.token;
    }
    return null;
  }
}

/// JSON 解析容错。
String stringOf(Object? raw, {String fallback = ''}) {
  if (raw == null) return fallback;
  if (raw is String) return raw.trim();
  return '$raw'.trim();
}

T? readJsonPath<T>(Object? root, List<Object> path) {
  Object? cur = root;
  for (final seg in path) {
    if (cur is Map && seg is String && cur.containsKey(seg)) {
      cur = cur[seg];
    } else if (cur is List && seg is int && seg >= 0 && seg < cur.length) {
      cur = cur[seg];
    } else {
      return null;
    }
  }
  return cur is T ? cur : null;
}

Object? maybeJsonDecode(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }
  return raw;
}

class WebFetchHttpException implements Exception {
  WebFetchHttpException(this.message);
  final String message;
  @override
  String toString() => 'WebFetchHttpException: $message';
}
