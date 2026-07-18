import 'package:http/http.dart' as http;

import '../../../../shared/util/text_clip.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_web_fetch_settings.dart';
import '../web_engine/web_engine_base.dart';
import '../web_engine/web_engine_http_utils.dart';
import '../web_engine/web_engine_value_parsing.dart';
import 'web_fetch_scrapling_bridge.dart';

export '../web_engine/web_engine_base.dart' show WebEngineRequest;
export '../web_engine/web_engine_http_exception.dart'
    show WebEngineHttpException;
export '../web_engine/web_engine_http_utils.dart'
    show decodeSuccessfulWebEngineJsonResponse;
export '../web_engine/web_engine_json_utils.dart'
    show decodeJsonObjectBytes, jsonObjectOf, stringOf, readJsonPath;
export '../web_engine/web_engine_value_parsing.dart'
    show resolveWebEngineApiKey;

/// 单个 URL 抓取的统一返回。
class WebFetchEngineContent {
  WebFetchEngineContent({
    required this.url,
    required this.title,
    required this.content,
    this.contentType,
    int? statusCode,
    this.responseHeaders = const <String, String>{},
    this.publishedAt,
    double? score,
  }) : statusCode = webEngineHttpStatusFromValue(statusCode),
       score = webEngineScoreFromValue(score);

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
      content: clipTextWithEllipsis(content, maxChars),
      contentType: contentType,
      statusCode: statusCode,
      responseHeaders: responseHeaders,
      publishedAt: publishedAt,
      score: score,
    );
  }
}

class WebFetchEngineRequest extends WebEngineRequest {
  const WebFetchEngineRequest({
    required this.url,
    required this.prompt,
    required this.maxChars,
    super.cancelSignal,
  });

  final String url;
  final String prompt;
  final int maxChars;
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

abstract class WebFetchEngine
    extends
        WebEngineBase<
          AiWebFetchEngineKind,
          WebFetchEngineContent,
          WebFetchEngineRequest,
          WebFetchEngineResult
        >
    with BoundedWebEngineHttpClient {
  WebFetchEngine({required this.config, required this.httpClient});

  final AiWebFetchEngineConfig config;
  @override
  final http.Client httpClient;

  @override
  AiWebFetchEngineKind get kind => config.kind;

  @override
  int get maxRetries => config.maxRetries;

  @override
  Duration get fetchTimeout => const Duration(seconds: 30);

  @override
  WebFetchEngineResult buildResult({
    required List<WebFetchEngineContent> items,
    String? error,
    required int attempts,
    required int elapsedMs,
  }) {
    return WebFetchEngineResult(
      kind: kind,
      contents: items,
      error: error,
      attempts: attempts,
      elapsedMs: elapsedMs,
    );
  }

  @override
  List<WebFetchEngineContent> postProcess(
    List<WebFetchEngineContent> raw,
    WebFetchEngineRequest request,
  ) {
    return raw
        .map((c) => c.truncated(config.truncationChars))
        .toList(growable: false);
  }
}

abstract class WebFetchProviderKeyEngine extends WebFetchEngine {
  WebFetchProviderKeyEngine({
    required super.config,
    required super.httpClient,
    required this.fallbackKey,
  });

  final String? fallbackKey;

  String? get effectiveApiKey =>
      resolveWebEngineApiKey(config.apiKey, fallbackKey);

  @override
  bool get isReady => (effectiveApiKey ?? '').isNotEmpty;
}

class WebFetchEngineContext {
  WebFetchEngineContext({
    required this.httpClient,
    required this.availableModels,
    this.scraplingBridge,
  });

  final http.Client httpClient;
  final List<AiModelConfig> availableModels;
  final WebFetchScraplingBridge? scraplingBridge;

  String? resolveProviderApiKey(String? configId) {
    if (configId == null || configId.isEmpty) return null;
    for (final m in availableModels) {
      if (m.id == configId) return m.token.isEmpty ? null : m.token;
    }
    return null;
  }
}
