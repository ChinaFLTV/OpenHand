import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../app/support/system_proxy.dart';
import '../model/ai_model_config.dart';
import 'ai_transport_diagnostic_messages.dart';

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
    : _httpClient = httpClient ?? SystemProxyResolver.instance.createHttpClient();

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
    } on HandshakeException catch (e) {
      // Cloudflare 等 WAF 可能根据 JA3/JA4 TLS 指纹拒绝非浏览器
      // 客户端，表现为 SSLV3_ALERT_HANDSHAKE_FAILURE。给出明确
      // 诊断，并附上默认 fallback 模型 id 以便用户手动完成配置。
      final fallback = _fallbackModelIdsForProtocol(config.protocolType);
      return AiModelScanResult(
        modelIds: fallback,
        error: _ScanErrorMessages.handshake(e),
      );
    } on TlsException catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.tls(e),
      );
    } on SocketException catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.socket(e),
      );
    } on HttpException catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.http(e),
      );
    } on TimeoutException {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.timeout(timeout),
      );
    } on FormatException catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.formatError(e.message),
      );
    } catch (e) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.unexpected(e),
      );
    }
  }

  /// 在扫描失败（比如被 WAF 拦截、或代理不提供 /v1/models）时，
  /// 为常见协议返回一组该协议下使用者可能需要的主流模型 id，
  /// 让用户从下拉选中而不是完全手输。
  ///
  /// 列表需保守：只架设“宕机递增选项”，不代表 OpenHand 背书或股补。
  static List<String> _fallbackModelIdsForProtocol(
    AiProtocolType protocolType,
  ) {
    switch (protocolType) {
      case AiProtocolType.claude:
        return const <String>[
          'claude-sonnet-4-5',
          'claude-opus-4-1',
          'claude-haiku-4-5',
          'claude-sonnet-4',
          'claude-opus-4',
        ];
      default:
        return const <String>[];
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
        // vllm, sglang, seed-adjacent providers, stepfun, minimax,
        // longcat, joycode, wenxin, meta, mimo, hunyuan
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
        error: _ScanErrorMessages.httpStatus(
          response.statusCode,
          isAuth: true,
        ),
      );
    }
    if (response.statusCode != 200) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.httpStatus(response.statusCode),
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
        error: _ScanErrorMessages.httpStatus(response.statusCode),
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
          error: _ScanErrorMessages.httpStatus(
            response.statusCode,
            isAuth: true,
          ),
        );
      }
      if (response.statusCode != 200) {
        return AiModelScanResult(
          modelIds: const <String>[],
          error: _ScanErrorMessages.httpStatus(response.statusCode),
        );
      }

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return AiModelScanResult(
          modelIds: const <String>[],
          error: _ScanErrorMessages.formatError(
            'expected a JSON object at $baseModelsUrl',
          ),
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
            error: _ScanErrorMessages.httpStatus(
              response.statusCode,
              isAuth: true,
            ),
          );
        }
        if (response.statusCode != 200) {
          // Some Anthropic-compatible proxies may not support /models.
          if (allIds.isNotEmpty) break;
          return AiModelScanResult(
            modelIds: const <String>[],
            error: _ScanErrorMessages.httpStatus(
              response.statusCode,
              hint:
                  'If you are using a proxy / relay, it may not expose '
                  'a /v1/models listing endpoint. Add model IDs manually below.',
            ),
          );
        }

        final json = jsonDecode(response.body);
        if (json is! Map<String, dynamic>) {
          if (allIds.isNotEmpty) break;
          return AiModelScanResult(
            modelIds: const <String>[],
            error: _ScanErrorMessages.formatError(
              'expected a JSON object at /v1/models',
            ),
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
        final fallback = _fallbackModelIdsForProtocol(config.protocolType);
        return AiModelScanResult(
          modelIds: fallback,
          error: _ScanErrorMessages._format(
            title: 'Empty model list · 未返回任何模型',
            reason: '服务端 /v1/models 端点连通但返回了空列表。多数中转 代理不提供该接口，或者仅准许某一个账号调用后才返回。',
            try_:
                '· 在「手动添加模型 ID」处直接录入希望使用的模型名\n'
                '· 联系中转方确认 /v1/models 是否需要付费 / 鉴权',
          ),
        );
      }
      allIds.sort();
      return AiModelScanResult(modelIds: allIds);
    } catch (e) {
      if (allIds.isNotEmpty) {
        allIds.sort();
        return AiModelScanResult(modelIds: allIds);
      }
      // 其他未后续被上层 try/on 处理的错误（比如 jsonDecode
      // 报 FormatException）会随同 rethrow，由 scan() 顶层统一格式化。
      rethrow;
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
        error: _ScanErrorMessages.httpStatus(
          response.statusCode,
          isAuth: true,
        ),
      );
    }
    if (response.statusCode != 200) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.httpStatus(response.statusCode),
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

/// 集中收敛“扫描模型”阶段的错误文案，让用户在弹窗里一眼看清
/// 「现象 / 原因 / 建议」三段，避免直接抛出 BoringSSL / Dart 内部
/// 错误码导致的困惑。所有文案都做成中英双语，因为该字段会原样
/// 渲染在设置页提示条里，并未再走 ARB l10n。
/// Scanner 错误文案统一收口；多数 transport 层情况复用
/// [AiTransportDiagnosticMessages]，仅保留 /models 扫描场景特有的措辞
/// (例如 404 / 405 推荐「在「手动添加模型 ID」处录入」)。
class _ScanErrorMessages {
  _ScanErrorMessages._();

  static String handshake(HandshakeException e) =>
      AiTransportDiagnosticMessages.handshake(e);

  static String tls(TlsException e) =>
      AiTransportDiagnosticMessages.tls(e);

  static String timeout(Duration limit) =>
      AiTransportDiagnosticMessages.timeout(limit);

  static String http(HttpException e) =>
      AiTransportDiagnosticMessages.format(
        title: 'HTTP protocol error · HTTP 协议错误',
        reason:
            'HTTP 客户端在解析响应阶段失败：${e.message}\n'
            '通常意味着服务端返回的并非合法 HTTP 报文，或响应被中间设备截断。',
        try_: '· 复核 Base URL 是否指向了 HTTPS 端口\n· 联系中转方确认是否做了端口劫持',
      );

  static String socket(SocketException e) {
    final msg = e.message.toLowerCase();
    String reason;
    String suggest;
    if (msg.contains('failed host lookup') || msg.contains('no address')) {
      reason =
          '主机名无法解析 (DNS lookup failed)。可能的原因：\n'
          '  · Base URL 输入了错别字或多余协议前缀\n'
          '  · 本机 DNS 配置异常或当前网络无外网访问\n'
          '  · 域名已被运营商 / 防火墙劫持或屏蔽';
      suggest =
          '· 复核 Base URL 是否完整 (含 https://)\n'
          '· 在终端执行 `ping` / `nslookup` 验证域名解析\n'
          '· 切换网络 (热点 / VPN) 后重试';
    } else if (msg.contains('connection refused')) {
      reason =
          'TCP 连接被服务端主动拒绝 (connection refused)。可能的原因：\n'
          '  · 端口号写错或服务并未在该端口监听\n'
          '  · 服务进程已经停止 / 重启中\n'
          '  · 本机防火墙或 SELinux 拦截了出站连接';
      suggest =
          '· 确认 Base URL 中的端口与服务端实际暴露端口一致\n'
          '· 在服务端 `curl` 自身验证服务是否健康\n'
          '· 暂时关闭本机 / 公司防火墙再试';
    } else if (msg.contains('network is unreachable') ||
        msg.contains('no route to host')) {
      reason = '本机当前无法到达目标网络 (network unreachable / no route to host)。';
      suggest =
          '· 检查本机网络连接 (Wi-Fi / 蜂窝 / 有线)\n'
          '· 如目标在内网，确认 VPN 已连通且路由表生效';
    } else if (msg.contains('timed out') || msg.contains('timeout')) {
      reason =
          'TCP 连接超时。请求长时间没有任何响应，常见诱因：\n'
          '  · 中间链路丢包严重 (跨境 / 弱网)\n'
          '  · 服务端被防火墙静默丢包 (无 RST)\n'
          '  · 端口被运营商屏蔽';
      suggest =
          '· 切换网络后重试\n'
          '· 通过 traceroute / mtr 定位卡点\n'
          '· 联系中转方确认服务可用性';
    } else {
      reason = '底层 socket 抛出错误：${e.message}';
      suggest = '· 确认网络可用并复核 Base URL\n· 必要时联系中转方排查链路';
    }
    return AiTransportDiagnosticMessages.format(
      title: 'Network error · 网络层错误',
      reason: reason,
      try_: suggest,
      raw: e.osError == null ? e.message : '${e.message} (${e.osError})',
    );
  }

  static String httpStatus(int code, {bool isAuth = false, String? hint}) {
    String title;
    String reason;
    String suggest;
    switch (code) {
      case 400:
        title = 'Bad request (400) · 请求被拒';
        reason =
            '服务端拒绝处理本次请求 (400 Bad Request)。Base URL 或自定义 header 可能不符合该协议规范。';
        suggest =
            '· 确认 Base URL 与协议类型匹配 (例如 Claude 协议应指向 /v1)\n· 检查自定义 header 中是否有非法字符';
        break;
      case 401:
        title = 'Authentication failed (401) · 鉴权失败';
        reason = '服务端返回 401 Unauthorized：身份令牌缺失或已失效。';
        suggest =
            '· 确认 API Key / Token 已正确粘贴，无前后空格\n· 在中转方控制台重新生成令牌\n· 确认鉴权方式 (Bearer / X-API-Key) 与中转要求一致';
        break;
      case 403:
        title = 'Forbidden (403) · 访问被拒';
        reason =
            '服务端返回 403 Forbidden。可能的原因：\n'
            '  · 当前令牌不具备访问该模型 / 接口的权限\n'
            '  · IP 地理位置不在中转方允许的区域\n'
            '  · 触发了中转方的 WAF / 风控规则';
        suggest =
            '· 在中转方控制台确认账号余额与权限\n· 切换网络或地区后重试\n· 联系中转方支持核实账号状态';
        break;
      case 404:
        title = 'Endpoint not found (404) · 端点不存在';
        reason =
            '服务端返回 404 Not Found：该 Base URL 下没有 /models 端点。多数中转 / 代理只转发 /v1/messages 而不暴露模型列表。';
        suggest = '· 在「手动添加模型 ID」处直接录入希望使用的模型名\n· 确认 Base URL 是否需要去掉多余的 /v1 后缀';
        break;
      case 405:
        title = 'Method not allowed (405) · 方法不被允许';
        reason = '服务端不接受 GET 方法访问 /models。该端点可能仅暴露 POST 或不支持模型列表。';
        suggest = '· 在「手动添加模型 ID」处录入模型名继续配置';
        break;
      case 408:
        title = 'Server timeout (408) · 服务端超时';
        reason = '服务端在收到请求头后超时关闭连接 (408 Request Timeout)。';
        suggest = '· 稍后重试\n· 切换网络后再试';
        break;
      case 429:
        title = 'Rate limited (429) · 触发限流';
        reason = '服务端返回 429 Too Many Requests：当前账户调用过于频繁或额度已用尽。';
        suggest = '· 稍等几分钟后重试\n· 在中转方控制台确认配额 / 余额\n· 升级套餐或更换 token';
        break;
      case 500:
        title = 'Server error (500) · 服务端内部错误';
        reason = '服务端返回 500 Internal Server Error：上游或中转方自身出现故障。';
        suggest = '· 稍后重试\n· 联系中转方查看服务状态';
        break;
      case 502:
        title = 'Bad gateway (502) · 网关异常';
        reason = '服务端返回 502 Bad Gateway：中转无法从上游 (Anthropic / OpenAI 等) 取得有效响应。';
        suggest = '· 稍后重试\n· 联系中转方确认上游通路';
        break;
      case 503:
        title = 'Service unavailable (503) · 服务不可用';
        reason = '服务端返回 503 Service Unavailable：服务在维护或被熔断。';
        suggest = '· 稍后重试\n· 关注中转方公告';
        break;
      case 504:
        title = 'Gateway timeout (504) · 网关超时';
        reason = '服务端返回 504 Gateway Timeout：中转访问上游 LLM 时超过了时限。';
        suggest = '· 稍后重试\n· 切换中转或网络后再试';
        break;
      default:
        if (isAuth) {
          title = 'Authentication failed ($code) · 鉴权失败';
          reason = '服务端返回 $code，并提示鉴权失败。';
          suggest = '· 检查 API Key / Token / 鉴权方式是否正确';
        } else if (code >= 500) {
          title = 'Server error ($code) · 服务端错误';
          reason = '服务端返回 $code。多为中转 / 上游故障。';
          suggest = '· 稍后重试\n· 联系中转方排查';
        } else if (code >= 400) {
          title = 'Client error ($code) · 客户端请求被拒';
          reason = '服务端返回 $code。请求未通过协议或鉴权校验。';
          suggest = '· 复核 Base URL / token / 自定义 header';
        } else {
          title = 'Unexpected status ($code) · 非预期响应';
          reason = '服务端返回非 2xx 状态码 $code。';
          suggest = '· 联系中转方排查';
        }
    }
    return AiTransportDiagnosticMessages.format(
      title: title,
      reason: reason,
      try_: hint == null ? suggest : '$suggest\n· $hint',
    );
  }

  static String formatError(String detail) =>
      AiTransportDiagnosticMessages.format(
        title: 'Unexpected response format · 响应格式异常',
        reason:
            '服务端虽返回了 200，但响应体不是合法 JSON：$detail\n'
            '通常意味着中转返回了 HTML 错误页 / Cloudflare 验证页 / 纯文本错误提示。',
        try_: '· 在浏览器直接打开该 URL 查看真实响应\n· 联系中转方确认 /models 是否真正提供 JSON 输出',
      );

  static String unexpected(Object error) =>
      AiTransportDiagnosticMessages.format(
        title: 'Unexpected error · 未识别错误',
        reason: '$error',
        try_: '· 重试或更换网络环境\n· 在「手动添加模型 ID」处直接录入模型名以绕过扫描',
      );

  static String _format({
    required String title,
    required String reason,
    required String try_,
    String? raw,
  }) =>
      AiTransportDiagnosticMessages.format(
        title: title,
        reason: reason,
        try_: try_,
        raw: raw,
      );
}
