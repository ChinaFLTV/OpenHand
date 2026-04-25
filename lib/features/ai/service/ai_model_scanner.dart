import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/ai_model_config.dart';

/// Result of a model scan attempt.
class AiModelScanResult {
  const AiModelScanResult({required this.modelIds, this.error});

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
      case AiProtocolType.seed:
        return _scanSeed(config, timeout: timeout);
      default:
        // OpenAI-compatible: openai, deepseek, qwen, kimi, glm, grok,
        // vllm, sglang, stepfun, mimo
        return _scanOpenAiCompatible(config, timeout: timeout);
    }
  }

  /// Strips common endpoint suffixes from a base URL and appends `/models`.
  ///
  /// Users sometimes paste the full endpoint URL (e.g.
  /// `https://api.openai.com/v1/chat/completions`) as their base URL.
  /// This normalizes such URLs so the models endpoint is correctly derived.
  static String _toModelsUrl(String baseUrl) {
    const suffixes = <String>[
      '/chat/completions',
      '/completions',
      '/embeddings',
      '/models',
    ];
    for (final suffix in suffixes) {
      if (baseUrl.endsWith(suffix)) {
        return '${baseUrl.substring(0, baseUrl.length - suffix.length)}/models';
      }
    }
    return '$baseUrl/models';
  }

  /// OpenAI-compatible /models endpoint.
  Future<AiModelScanResult> _scanOpenAiCompatible(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final modelsUrl = _toModelsUrl(config.normalizedBaseUrl);

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
  /// Handles pagination via `nextPageToken` to retrieve all models.
  Future<AiModelScanResult> _scanGemini(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    final token = config.token.trim();
    // Gemini REST: GET /v1beta/models?key=API_KEY
    // Or: /v1/models with bearer token
    String baseModelsUrl;
    if (baseUrl.contains('/v1beta')) {
      baseModelsUrl = '$baseUrl/models';
    } else if (baseUrl.endsWith('/v1')) {
      baseModelsUrl = '$baseUrl/models';
    } else {
      baseModelsUrl = '$baseUrl/v1beta/models';
    }

    final headers = <String, String>{};
    final useQueryAuth =
        config.authScheme == AiAuthScheme.apiKey && token.isNotEmpty;
    if (!useQueryAuth && token.isNotEmpty) {
      headers.addAll(_buildHeaders(config));
    }

    final allIds = <String>[];
    String? pageToken;
    // Limit iterations to avoid infinite loops on malformed pagination.
    const maxPages = 20;

    for (var page = 0; page < maxPages; page++) {
      var uri = Uri.parse(baseModelsUrl);
      final queryParams = <String, String>{
        ...uri.queryParameters,
        'pageSize': '100',
      };
      if (useQueryAuth) {
        queryParams['key'] = token;
      }
      if (pageToken != null) {
        queryParams['pageToken'] = pageToken;
      }
      uri = uri.replace(queryParameters: queryParams);

      final response = await _httpClient
          .get(uri, headers: headers)
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

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return const AiModelScanResult(
          modelIds: <String>[],
          error: 'Unexpected response format.',
        );
      }

      final models = json['models'];
      if (models is List) {
        for (final item in models) {
          if (item is Map<String, dynamic>) {
            String name = '${item['name'] ?? ''}'.trim();
            // Gemini returns "models/gemini-pro" — strip the "models/" prefix.
            if (name.startsWith('models/')) {
              name = name.substring('models/'.length);
            }
            if (name.isNotEmpty) {
              allIds.add(name);
            }
          }
        }
      }

      // Handle pagination.
      final nextToken = json['nextPageToken'];
      if (nextToken is String && nextToken.isNotEmpty) {
        pageToken = nextToken;
      } else {
        break;
      }
    }

    allIds.sort();
    return AiModelScanResult(modelIds: allIds);
  }

  /// Claude/Anthropic models list endpoint.
  /// Anthropic supports GET /v1/models with `anthropic-version` header.
  /// Response: `{ "data": [...], "has_more": bool, "last_id": "..." }`.
  /// Pagination: pass `after_id=last_id` until `has_more` is false.
  Future<AiModelScanResult> _scanClaude(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    String modelsUrl;
    if (baseUrl.endsWith('/v1')) {
      modelsUrl = '$baseUrl/models';
    } else {
      modelsUrl = '$baseUrl/v1/models';
    }

    final headers = _buildHeaders(config);
    headers['anthropic-version'] = '2023-06-01';

    final allIds = <String>[];
    String? afterId;
    const maxPages = 20;

    try {
      for (var page = 0; page < maxPages; page++) {
        var uri = Uri.parse(modelsUrl);
        final queryParams = <String, String>{
          ...uri.queryParameters,
          'limit': '100',
        };
        if (afterId != null) {
          queryParams['after_id'] = afterId;
        }
        uri = uri.replace(queryParameters: queryParams);

        final response = await _httpClient
            .get(uri, headers: headers)
            .timeout(timeout);

        if (response.statusCode == 401 || response.statusCode == 403) {
          return AiModelScanResult(
            modelIds: const <String>[],
            error:
                'Authentication failed (${response.statusCode}). '
                'Check your API key.',
          );
        }
        if (response.statusCode != 200) {
          // Some Anthropic-compatible proxies may not support /models.
          if (allIds.isNotEmpty) break;
          return AiModelScanResult(
            modelIds: const <String>[],
            error:
                'Server returned status ${response.statusCode}. '
                'If using a proxy, it may not support model listing.',
          );
        }

        final json = jsonDecode(response.body);
        if (json is! Map<String, dynamic>) {
          if (allIds.isNotEmpty) break;
          return const AiModelScanResult(
            modelIds: <String>[],
            error: 'Unexpected response format.',
          );
        }

        final data = json['data'];
        if (data is List) {
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final id = '${item['id'] ?? ''}'.trim();
              if (id.isNotEmpty) {
                allIds.add(id);
              }
            }
          }
        }

        // Handle cursor-based pagination.
        final hasMore = json['has_more'];
        final lastId = json['last_id'];
        if (hasMore == true && lastId is String && lastId.isNotEmpty) {
          afterId = lastId;
        } else {
          break;
        }
      }

      if (allIds.isEmpty) {
        return const AiModelScanResult(
          modelIds: <String>[],
          error:
              'No models returned. If using a proxy, it may not support '
              'model listing. Please add model IDs manually.',
        );
      }
      allIds.sort();
      return AiModelScanResult(modelIds: allIds);
    } catch (e) {
      if (allIds.isNotEmpty) {
        allIds.sort();
        return AiModelScanResult(modelIds: allIds);
      }
      return AiModelScanResult(
        modelIds: const <String>[],
        error:
            'Failed to scan Claude/Anthropic models ($e). '
            'Please add model IDs manually.',
      );
    }
  }

  /// Seed/豆包/Volcengine (火山方舟) models endpoint.
  /// Base URL is typically https://ark.cn-beijing.volces.com/api/v3
  /// which uses /api/v3/models instead of /v1/models.
  Future<AiModelScanResult> _scanSeed(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final modelsUrl = _toModelsUrl(config.normalizedBaseUrl);

    final headers = _buildHeaders(config);
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

    return _parseOpenAiModelsResponse(response.body);
  }

  Map<String, String> _buildHeaders(AiModelConfig config) {
    final headers = <String, String>{'accept': 'application/json'};
    final rawToken = config.token.trim();
    if (rawToken.isEmpty || config.authScheme == AiAuthScheme.none) {
      _mergeCustomHeaders(headers, config);
      return headers;
    }
    if (config.authScheme == AiAuthScheme.apiKey) {
      headers['x-api-key'] = config.authScheme.apply(rawToken);
      _mergeCustomHeaders(headers, config);
      return headers;
    }
    headers['authorization'] = config.authScheme.apply(rawToken);
    _mergeCustomHeaders(headers, config);
    return headers;
  }

  void _mergeCustomHeaders(Map<String, String> headers, AiModelConfig config) {
    if (config.customHeaders.isEmpty) return;
    for (final entry in config.customHeaders.entries) {
      final key = entry.key.trim();
      if (key.isNotEmpty) {
        headers[key] = entry.value;
      }
    }
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

  void dispose() {
    _httpClient.close();
  }
}
