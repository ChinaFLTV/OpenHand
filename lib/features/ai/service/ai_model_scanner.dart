import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/ai_model_config.dart';

/// Result of a model scan attempt.
class AiModelScanResult {
  const AiModelScanResult({
    required this.modelIds,
    this.error,
  });

  /// Successfully discovered model IDs (empty if scan failed).
  final List<String> modelIds;

  /// Human-readable error message (null on success).
  final String? error;

  bool get isSuccess => error == null;
}

/// Scans an AI provider's API to discover available model IDs.
class AiModelScanner {
  AiModelScanner({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const Duration _defaultTimeout = Duration(seconds: 15);

  /// Attempts to list all models available at the provider defined by [config].
  ///
  /// Uses the appropriate models endpoint based on [config.protocolType].
  /// Returns an [AiModelScanResult] that is never null and always safe to use.
  Future<AiModelScanResult> scan(
    AiModelConfig config, {
    Duration timeout = _defaultTimeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    if (baseUrl.isEmpty) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Base URL is empty.',
      );
    }

    try {
      return await _scanByProtocol(config, timeout: timeout);
    } on SocketException catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: 'Network error: ${e.message}',
      );
    } on HttpException catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: 'HTTP error: ${e.message}',
      );
    } on TimeoutException {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Request timed out.',
      );
    } on FormatException catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: 'Invalid response format: ${e.message}',
      );
    } catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: 'Unexpected error: $e',
      );
    }
  }

  Future<AiModelScanResult> _scanByProtocol(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    switch (config.protocolType) {
      case AiProtocolType.gemini:
        return _scanGemini(config, timeout: timeout);
      case AiProtocolType.claude:
        return _scanClaude(config, timeout: timeout);
      case AiProtocolType.ollama:
        return _scanOllama(config, timeout: timeout);
      default:
        // OpenAI-compatible: openai, deepseek, qwen, kimi, glm, grok, vllm, sglang
        return _scanOpenAiCompatible(config, timeout: timeout);
    }
  }

  /// OpenAI-compatible /models endpoint.
  Future<AiModelScanResult> _scanOpenAiCompatible(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    // Many OpenAI-compatible services have base URL like https://api.xxx.com/v1
    // The models endpoint is /v1/models — normalize by trimming /chat/completions if present
    String modelsUrl;
    if (baseUrl.endsWith('/chat/completions')) {
      modelsUrl =
          '${baseUrl.substring(0, baseUrl.length - '/chat/completions'.length)}/models';
    } else {
      modelsUrl = '$baseUrl/models';
    }

    final headers = _buildHeaders(config);
    final response = await _httpClient
        .get(Uri.parse(modelsUrl), headers: headers)
        .timeout(timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error:
            'Authentication failed (${response.statusCode}). Check your token.',
      );
    }
    if (response.statusCode != 200) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: 'Server returned status ${response.statusCode}.',
      );
    }

    return _parseOpenAiModelsResponse(response.body);
  }

  /// Ollama /api/tags endpoint.
  Future<AiModelScanResult> _scanOllama(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    // Ollama base URL is usually http://localhost:11434
    // Try both /v1/models (OpenAI compat) and /api/tags (native).
    // First try OpenAI-compatible endpoint.
    try {
      final result = await _scanOpenAiCompatible(config, timeout: timeout);
      if (result.isSuccess && result.modelIds.isNotEmpty) {
        return result;
      }
    } catch (_) {
      // Fall through to native endpoint.
    }

    // Try Ollama native endpoint.
    String tagsUrl;
    if (baseUrl.endsWith('/v1')) {
      tagsUrl =
          '${baseUrl.substring(0, baseUrl.length - '/v1'.length)}/api/tags';
    } else {
      tagsUrl = '$baseUrl/api/tags';
    }

    final response = await _httpClient
        .get(Uri.parse(tagsUrl), headers: _buildHeaders(config))
        .timeout(timeout);

    if (response.statusCode != 200) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: 'Server returned status ${response.statusCode}.',
      );
    }

    return _parseOllamaTagsResponse(response.body);
  }

  /// Gemini models.list endpoint.
  Future<AiModelScanResult> _scanGemini(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    final token = config.token.trim();
    // Gemini REST: GET /v1beta/models?key=API_KEY
    // Or: /v1/models with bearer token
    String modelsUrl;
    if (baseUrl.contains('/v1beta')) {
      modelsUrl = '$baseUrl/models';
    } else if (baseUrl.endsWith('/v1')) {
      modelsUrl = '$baseUrl/models';
    } else {
      modelsUrl = '$baseUrl/v1beta/models';
    }

    final headers = <String, String>{};
    if (config.authScheme == AiAuthScheme.apiKey && token.isNotEmpty) {
      // Gemini uses key= query parameter, but also supports header-based auth
      final uri = Uri.parse(modelsUrl);
      modelsUrl = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'key': token,
      }).toString();
    } else if (token.isNotEmpty) {
      headers.addAll(_buildHeaders(config));
    }

    final response = await _httpClient
        .get(Uri.parse(modelsUrl), headers: headers)
        .timeout(timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error:
            'Authentication failed (${response.statusCode}). Check your API key.',
      );
    }
    if (response.statusCode != 200) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: 'Server returned status ${response.statusCode}.',
      );
    }

    return _parseGeminiModelsResponse(response.body);
  }

  /// Claude/Anthropic doesn't have a public models list endpoint.
  /// Return a hardcoded list of known models as a best-effort fallback.
  Future<AiModelScanResult> _scanClaude(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    // Anthropic does not expose a /models endpoint publicly.
    // Try the beta endpoint first — if it fails, return well-known models.
    final baseUrl = config.normalizedBaseUrl;
    String modelsUrl;
    if (baseUrl.endsWith('/v1')) {
      modelsUrl = '$baseUrl/models';
    } else {
      modelsUrl = '$baseUrl/v1/models';
    }

    final headers = _buildHeaders(config);
    headers['anthropic-version'] = '2023-06-01';

    try {
      final response = await _httpClient
          .get(Uri.parse(modelsUrl), headers: headers)
          .timeout(timeout);

      if (response.statusCode == 200) {
        final parsed = _parseOpenAiModelsResponse(response.body);
        if (parsed.isSuccess && parsed.modelIds.isNotEmpty) {
          return parsed;
        }
      }
    } catch (_) {
      // Fall through to default known models.
    }

    return const AiModelScanResult(
      modelIds: <String>[
        'claude-sonnet-4-20250514',
        'claude-opus-4-20250514',
        'claude-3-7-sonnet-20250219',
        'claude-3-5-sonnet-20241022',
        'claude-3-5-haiku-20241022',
        'claude-3-opus-20240229',
        'claude-3-haiku-20240307',
      ],
    );
  }

  Map<String, String> _buildHeaders(AiModelConfig config) {
    final headers = <String, String>{
      'accept': 'application/json',
    };
    final rawToken = config.token.trim();
    if (rawToken.isEmpty || config.authScheme == AiAuthScheme.none) {
      return headers;
    }
    if (config.authScheme == AiAuthScheme.apiKey) {
      headers['x-api-key'] = config.authScheme.apply(rawToken);
      return headers;
    }
    headers['authorization'] = config.authScheme.apply(rawToken);
    return headers;
  }

  /// Parses OpenAI-style `{ "data": [ { "id": "model-name" }, ... ] }`.
  AiModelScanResult _parseOpenAiModelsResponse(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Unexpected response format.',
      );
    }
    final data = json['data'];
    if (data is! List) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Response does not contain a "data" array.',
      );
    }
    final ids = <String>[];
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final id = '${item['id'] ?? ''}'.trim();
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    ids.sort();
    return AiModelScanResult(modelIds: ids);
  }

  /// Parses Ollama `{ "models": [ { "name": "llama3:latest" }, ... ] }`.
  AiModelScanResult _parseOllamaTagsResponse(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Unexpected response format.',
      );
    }
    final models = json['models'];
    if (models is! List) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Response does not contain a "models" array.',
      );
    }
    final ids = <String>[];
    for (final item in models) {
      if (item is Map<String, dynamic>) {
        final name = '${item['name'] ?? ''}'.trim();
        if (name.isNotEmpty) {
          ids.add(name);
        }
      }
    }
    ids.sort();
    return AiModelScanResult(modelIds: ids);
  }

  /// Parses Gemini `{ "models": [ { "name": "models/gemini-pro" }, ... ] }`.
  AiModelScanResult _parseGeminiModelsResponse(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Unexpected response format.',
      );
    }
    final models = json['models'];
    if (models is! List) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: 'Response does not contain a "models" array.',
      );
    }
    final ids = <String>[];
    for (final item in models) {
      if (item is Map<String, dynamic>) {
        String name = '${item['name'] ?? ''}'.trim();
        // Gemini returns "models/gemini-pro" — strip the "models/" prefix.
        if (name.startsWith('models/')) {
          name = name.substring('models/'.length);
        }
        if (name.isNotEmpty) {
          ids.add(name);
        }
      }
    }
    ids.sort();
    return AiModelScanResult(modelIds: ids);
  }

  void dispose() {
    _httpClient.close();
  }
}
