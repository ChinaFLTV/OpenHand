import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/ui/structured_error_text.dart';
import '../../../../shared/util/localized_text.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../operations/ai_operation_http.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

/// 模型扫描结果。
class AiModelScanResult {
  const AiModelScanResult({required this.modelIds, this.error});

  /// 成功发现的模型 ID；扫描失败时为空。
  final List<String> modelIds;

  /// 可读错误信息；成功时为空。
  final String? error;

  bool get isSuccess => error == null;
}

/// 扫描 AI 服务商接口以发现可用模型 ID。
class AiModelScanner {
  AiModelScanner({
    http.Client? httpClient,
    AiEndpointRouter? router,
    AiTransportClient? transport,
  }) : _transport = _resolveTransport(httpClient, transport),
       _ownsTransport = transport == null,
       _router = router ?? const AiEndpointRouter();

  final AiTransportClient _transport;
  final bool _ownsTransport;
  final AiEndpointRouter _router;

  static const Duration _defaultTimeout = Duration(seconds: 15);

  static AiTransportClient _resolveTransport(
    http.Client? httpClient,
    AiTransportClient? transport,
  ) {
    if (httpClient != null && transport != null) {
      throw ArgumentError('httpClient 和 transport 不能同时提供。');
    }
    return transport ?? AiTransportClient(client: httpClient);
  }

  /// 列出 [config] 指定服务商的全部可用模型。
  ///
  /// 根据 [config.protocolType] 选择模型列表接口，始终返回非空结果。
  Future<AiModelScanResult> scan(
    AiModelConfig config, {
    Duration timeout = _defaultTimeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    if (baseUrl.isEmpty) {
      return const AiModelScanResult(modelIds: <String>[], error: '基础 URL 为空。');
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
    } catch (error, stack) {
      silentLog('ai_model_scanner', '扫描模型列表', error, stack);
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.unexpected(),
      );
    }
  }

  /// 在扫描失败（比如被 WAF 拦截、或代理不提供 /v1/models）时，
  /// 为常见协议返回一组该协议下使用者可能需要的主流模型 id，
  /// 让用户从下拉选中而不是完全手输。
  ///
  /// 列表保持保守，仅用于扫描失败时提供候选项，不代表 OpenHand 推荐。
  static List<String> _fallbackModelIdsForProtocol(
    AiProtocolType protocolType,
  ) {
    switch (protocolType) {
      case AiProtocolType.dots:
        return const <String>['dots3-note-prev'];
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
      case AiProtocolType.dots:
        // Dots 文档当前没有 /v1/models，直接提供官方公开模型候选。
        return const AiModelScanResult(modelIds: <String>['dots3-note-prev']);
      case AiProtocolType.gemini:
        return _scanGemini(config, timeout: timeout);
      case AiProtocolType.claude:
        return _scanClaude(config, timeout: timeout);
      case AiProtocolType.ollama:
        return _scanOllama(config, timeout: timeout);
      case AiProtocolType.seed:
        return _scanSeed(config, timeout: timeout);
      default:
        // OpenAI 兼容协议包括 openai、deepseek、qwen、kimi、glm、grok、
        // vllm、sglang、stepfun、minimax、longcat、joycode、wenxin、
        // meta、mimo、hunyuan 及 Seed 相邻服务商。
        return _scanOpenAiCompatible(config, timeout: timeout);
    }
  }

  /// OpenAI 兼容的 /models 接口。
  Future<AiModelScanResult> _scanOpenAiCompatible(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final headers = _buildHeaders(config);
    AiModelScanResult? lastFailure;
    final candidates = <String>[
      _router.resolve(config, AiApiFamily.models, method: 'GET').url,
    ];

    for (final modelsUrl in candidates) {
      final response = await _transport.get(
        uri: Uri.parse(modelsUrl),
        headers: headers,
        timeout: timeout,
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        return AiModelScanResult(
          modelIds: const <String>[],
          error: _ScanErrorMessages.httpStatus(
            response.statusCode,
            isAuth: true,
            hint: modelsUrl,
          ),
        );
      }
      if (response.statusCode == 200) {
        final parsed = _parseOpenAiModelsResponse(
          response.body,
          url: modelsUrl,
        );
        if (parsed.isSuccess) {
          return parsed;
        }
        lastFailure = parsed;
        continue;
      }
      lastFailure = AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.httpStatus(
          response.statusCode,
          hint: modelsUrl,
        ),
      );
      if (response.statusCode != 404 && response.statusCode != 405) {
        break;
      }
    }

    return lastFailure ??
        const AiModelScanResult(
          modelIds: <String>[],
          error: '无法从基础 URL 推导模型列表接口。',
        );
  }

  /// Ollama /api/tags 接口。
  Future<AiModelScanResult> _scanOllama(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    // Ollama 基础 URL 通常为 http://localhost:11434。
    // 先尝试 OpenAI 兼容的 /v1/models，再回退到原生 /api/tags。
    try {
      final result = await _scanOpenAiCompatible(config, timeout: timeout);
      if (result.isSuccess && result.modelIds.isNotEmpty) {
        return result;
      }
    } catch (_) {
      // 回退到原生接口。
    }

    // 尝试 Ollama 原生接口。
    String tagsUrl;
    if (baseUrl.endsWith('/v1')) {
      tagsUrl =
          '${baseUrl.substring(0, baseUrl.length - '/v1'.length)}/api/tags';
    } else {
      tagsUrl = '$baseUrl/api/tags';
    }

    final response = await _transport.get(
      uri: Uri.parse(tagsUrl),
      headers: _buildHeaders(config),
      timeout: timeout,
    );

    if (response.statusCode != 200) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.httpStatus(response.statusCode),
      );
    }

    return _parseOllamaTagsResponse(response.body);
  }

  /// Gemini models.list 接口，通过 `nextPageToken` 拉取全部分页。
  Future<AiModelScanResult> _scanGemini(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final baseUrl = config.normalizedBaseUrl;
    final token = config.token.trim();
    // Gemini REST 支持携带 API_KEY 的 /v1beta/models，或使用
    // Bearer Token 的 /v1/models。
    late final String baseModelsUrl;
    if (!config.autoCompleteBaseUrl) {
      baseModelsUrl = _router
          .resolve(
            config,
            AiApiFamily.models,
            method: 'GET',
            fallbackPath: 'v1beta/models',
          )
          .url;
    } else if (baseUrl.contains('/v1beta')) {
      baseModelsUrl = '$baseUrl/models';
    } else if (baseUrl.endsWith('/v1')) {
      baseModelsUrl = '$baseUrl/models';
    } else {
      baseModelsUrl = _router
          .resolve(
            config,
            AiApiFamily.models,
            method: 'GET',
            fallbackPath: 'v1beta/models',
          )
          .url;
    }

    final headers = <String, String>{};
    final useQueryAuth =
        config.authScheme == AiAuthScheme.apiKey && token.isNotEmpty;
    if (!useQueryAuth && token.isNotEmpty) {
      headers.addAll(_buildHeaders(config));
    }

    final allIds = <String>[];
    String? pageToken;
    // 限制页数，防止异常分页形成无限循环。
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

      final response = await _transport.get(
        uri: uri,
        headers: headers,
        timeout: timeout,
      );

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
          error: _ScanErrorMessages.formatError('$baseModelsUrl 应返回 JSON 对象'),
        );
      }

      final models = json['models'];
      if (models is List) {
        for (final item in models) {
          if (item is Map<String, dynamic>) {
            String name = '${item['name'] ?? ''}'.trim();
            // Gemini 返回 models/gemini-pro，需移除 models/ 前缀。
            if (name.startsWith('models/')) {
              name = name.substring('models/'.length);
            }
            if (name.isNotEmpty) {
              allIds.add(name);
            }
          }
        }
      }

      // 处理分页。
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

  /// Claude/Anthropic 模型列表接口。
  ///
  /// Anthropic 使用带 `anthropic-version` 请求头的 GET /v1/models；
  /// 响应包含 `data`、`has_more` 和 `last_id`，分页时持续传入
  /// `after_id=last_id`，直至 `has_more` 为 false。
  Future<AiModelScanResult> _scanClaude(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final modelsUrl = _router
        .resolve(
          config,
          AiApiFamily.models,
          method: 'GET',
          fallbackPath: 'v1/models',
        )
        .url;

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

        final response = await _transport.get(
          uri: uri,
          headers: headers,
          timeout: timeout,
        );

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
          // 部分 Anthropic 兼容代理不支持 /models。
          if (allIds.isNotEmpty) break;
          return AiModelScanResult(
            modelIds: const <String>[],
            error: _ScanErrorMessages.httpStatus(
              response.statusCode,
              hint: '代理或中转服务可能未提供 /v1/models 列表接口，请在下方手动添加模型 ID。',
            ),
          );
        }

        final json = jsonDecode(response.body);
        if (json is! Map<String, dynamic>) {
          if (allIds.isNotEmpty) break;
          return AiModelScanResult(
            modelIds: const <String>[],
            error: _ScanErrorMessages.formatError(
              '$modelsUrl 应返回 JSON 对象',
              url: modelsUrl,
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

        // 处理游标分页。
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
            title: openHandAmbientText(
              zh: '未返回任何模型',
              zhHant: '未返回任何模型',
              en: 'Empty model list',
              fr: 'Liste de modèles vide',
              de: 'Leere Modellliste',
              ja: 'モデル一覧が空です',
            ),
            reason: openHandAmbientText(
              zh: '服务端 /v1/models 端点连通但返回了空列表。多数中转代理不提供该接口，或者仅准许某一个账号调用后才返回。',
              zhHant:
                  '服務端 /v1/models 端點可連通但返回了空列表。多數中轉代理不提供該介面，或只允許特定帳號呼叫後才返回。',
              en: 'The /v1/models endpoint is reachable but returned an empty list. Many relay providers do not expose this endpoint, or only return data for specific accounts.',
              fr: 'Le point de terminaison /v1/models répond, mais renvoie une liste vide. Beaucoup de relais ne l’exposent pas, ou le réservent à certains comptes.',
              de: 'Der Endpunkt /v1/models ist erreichbar, liefert aber eine leere Liste. Viele Relay-Anbieter stellen ihn nicht bereit oder erlauben ihn nur für bestimmte Konten.',
              ja: '/v1/models エンドポイントには接続できましたが、空の一覧が返りました。多くの中継プロバイダーはこの API を公開していないか、特定アカウントだけに返します。',
            ),
            try_: openHandAmbientText(
              zh:
                  '· 在“手动添加模型 ID”处直接录入希望使用的模型名\n'
                  '· 联系中转方确认 /v1/models 是否需要付费或额外鉴权',
              zhHant:
                  '· 在「手動新增模型 ID」處直接輸入要使用的模型名\n'
                  '· 聯絡中轉方確認 /v1/models 是否需要付費或額外鑑權',
              en:
                  '· Add the model name directly in “Manually add model ID”\n'
                  '· Ask the relay provider whether /v1/models requires payment or extra authorization',
              fr:
                  '· Ajoutez directement le nom dans « Ajouter manuellement un ID de modèle »\n'
                  '· Vérifiez auprès du relais si /v1/models exige un paiement ou une autorisation supplémentaire',
              de:
                  '· Trage den Modellnamen direkt unter „Modell-ID manuell hinzufügen“ ein\n'
                  '· Frage den Relay-Anbieter, ob /v1/models Zahlung oder zusätzliche Autorisierung erfordert',
              ja:
                  '· 「モデル ID を手動追加」に使用したいモデル名を直接入力してください\n'
                  '· /v1/models に支払いまたは追加認証が必要か中継プロバイダーに確認してください',
            ),
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

  static String _seedModelsUrl(String baseUrl) {
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

  /// Seed/豆包/Volcengine（火山方舟）模型接口。
  ///
  /// 基础 URL 通常为 https://ark.cn-beijing.volces.com/api/v3，
  /// 对应 /api/v3/models，而不是 /v1/models。
  Future<AiModelScanResult> _scanSeed(
    AiModelConfig config, {
    required Duration timeout,
  }) async {
    final modelsUrl = _seedModelsUrl(config.normalizedBaseUrl);

    final headers = _buildHeaders(config);
    final response = await _transport.get(
      uri: Uri.parse(modelsUrl),
      headers: headers,
      timeout: timeout,
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.httpStatus(response.statusCode, isAuth: true),
      );
    }
    if (response.statusCode != 200) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.httpStatus(response.statusCode),
      );
    }

    return _parseOpenAiModelsResponse(response.body, url: modelsUrl);
  }

  Map<String, String> _buildHeaders(AiModelConfig config) {
    return AiOperationHttp.buildHeaders(
      model: config,
      endpointHeaders: const <String, String>{},
      family: AiApiFamily.models,
      includeJsonContentType: false,
      acceptJson: true,
    );
  }

  /// 解析 OpenAI 风格的 `{ "data": [ { "id": "model-name" }, ... ] }`。
  AiModelScanResult _parseOpenAiModelsResponse(String body, {String? url}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (error) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.formatError(error.message, url: url),
      );
    }
    if (json is! Map<String, dynamic>) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.formatError('响应必须是 JSON 对象', url: url),
      );
    }
    final data = json['data'];
    if (data is! List) {
      return AiModelScanResult(
        modelIds: const <String>[],
        error: _ScanErrorMessages.formatError('响应缺少“data”数组', url: url),
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

  /// 解析 Ollama `{ "models": [ { "name": "llama3:latest" }, ... ] }`。
  AiModelScanResult _parseOllamaTagsResponse(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      return const AiModelScanResult(modelIds: <String>[], error: '响应格式异常。');
    }
    final models = json['models'];
    if (models is! List) {
      return const AiModelScanResult(
        modelIds: <String>[],
        error: '响应缺少“models”数组。',
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
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}

/// 集中收敛“扫描模型”阶段的错误文案，让用户在弹窗里一眼看清
/// 「现象 / 原因 / 建议」三段，避免直接抛出 BoringSSL / Dart 内部
/// 错误码导致的困惑。所有文案都做成中英双语，因为该字段会原样
/// 渲染在设置页提示条里，并未再走 ARB l10n。
/// 扫描错误文案统一收口；多数传输层情况复用
/// [AiTransportDiagnosticMessages]，仅保留 /models 扫描场景特有的措辞
/// (例如 404 / 405 推荐「在「手动添加模型 ID」处录入」)。
class _ScanErrorMessages {
  _ScanErrorMessages._();

  static String handshake(HandshakeException e) =>
      AiTransportDiagnosticMessages.handshake(e);

  static String tls(TlsException e) => AiTransportDiagnosticMessages.tls(e);

  static String timeout(Duration limit) =>
      AiTransportDiagnosticMessages.timeout(limit);

  static String http(HttpException e) => AiTransportDiagnosticMessages.format(
    title: StructuredErrorText.pick(zh: 'HTTP 协议错误', en: 'HTTP protocol error'),
    reason: StructuredErrorText.pick(
      zh: 'HTTP 客户端在解析响应阶段失败：${e.message}\n通常意味着服务端返回的并非合法 HTTP 报文，或响应被中间设备截断。',
      en:
          'The HTTP client failed while parsing the response: ${e.message}\n'
          'This usually means the server did not return a valid HTTP response, or the payload was truncated by an intermediate device.',
    ),
    try_: StructuredErrorText.pick(
      zh: '· 复核 Base URL 是否指向了 HTTPS 端口\n· 联系中转方确认是否做了端口劫持',
      en:
          '· Verify that the Base URL points to the correct HTTPS endpoint\n'
          '· Ask the relay provider whether the port is being intercepted or rewritten',
    ),
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
      title: StructuredErrorText.pick(zh: '网络层错误', en: 'Network error'),
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
        title = StructuredErrorText.pick(
          zh: '请求被拒 (400)',
          en: 'Bad request (400)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端拒绝处理本次请求（400 Bad Request）。Base URL 或自定义 header 可能不符合该协议规范。',
          en: 'The server refused to process the request (400 Bad Request). The Base URL or custom headers may not match the expected protocol.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 确认 Base URL 与协议类型匹配（例如 Claude 协议应指向 /v1）\n· 检查自定义 header 中是否有非法字符',
          en:
              '· Confirm that the Base URL matches the protocol type (for example, Claude-compatible endpoints should usually point to /v1)\n'
              '· Check for invalid characters in custom headers',
        );
      case 401:
        title = StructuredErrorText.pick(
          zh: '鉴权失败 (401)',
          en: 'Authentication failed (401)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端返回 401 Unauthorized：身份令牌缺失或已失效。',
          en: 'The server returned 401 Unauthorized: the credential is missing or has expired.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 确认 API Key / Token 已正确粘贴且无前后空格\n· 在中转方控制台重新生成令牌\n· 确认鉴权方式（Bearer / X-API-Key）与中转要求一致',
          en:
              '· Make sure the API key or token was pasted correctly with no surrounding spaces\n'
              '· Regenerate the credential in the relay console\n'
              '· Confirm that the authentication scheme (Bearer / X-API-Key) matches the relay requirements',
        );
      case 403:
        title = StructuredErrorText.pick(
          zh: '访问被拒 (403)',
          en: 'Forbidden (403)',
        );
        reason = StructuredErrorText.pick(
          zh:
              '服务端返回 403 Forbidden。可能的原因：\n'
              '  · 当前令牌不具备访问该模型或接口的权限\n'
              '  · IP 地理位置不在中转方允许的区域\n'
              '  · 触发了中转方的 WAF 或风控规则',
          en:
              'The server returned 403 Forbidden. Possible causes:\n'
              '  · The current credential does not have permission to access the model or endpoint\n'
              '  · The IP location is outside the relay provider\'s allowed region\n'
              '  · A WAF or risk-control rule was triggered',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 在中转方控制台确认账号余额与权限\n· 切换网络或地区后重试\n· 联系中转方支持核实账号状态',
          en:
              '· Check account balance and permissions in the relay console\n'
              '· Retry from another network or region\n'
              '· Ask the relay provider to verify the account status',
        );
      case 404:
        title = StructuredErrorText.pick(
          zh: '端点不存在 (404)',
          en: 'Endpoint not found (404)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端返回 404 Not Found：该 Base URL 下没有 /models 端点。多数中转或代理只转发 /v1/messages，而不暴露模型列表。',
          en: 'The server returned 404 Not Found: there is no /models endpoint under this Base URL. Many relays or proxies forward only /v1/messages and do not expose a model list.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 在「手动添加模型 ID」处直接录入希望使用的模型名\n· 确认 Base URL 是否需要去掉多余的 /v1 后缀',
          en:
              '· Enter the model ID manually in the model field\n'
              '· Check whether the Base URL should omit an extra /v1 suffix',
        );
      case 405:
        title = StructuredErrorText.pick(
          zh: '方法不被允许 (405)',
          en: 'Method not allowed (405)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端不接受用 GET 方法访问 /models。该端点可能只暴露 POST，或者根本不支持模型列表。',
          en: 'The server does not allow GET requests to /models. This endpoint may only expose POST, or may not support model listing at all.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 在「手动添加模型 ID」处录入模型名继续配置',
          en: '· Enter the model ID manually and continue configuring the model',
        );
      case 408:
        title = StructuredErrorText.pick(
          zh: '服务端超时 (408)',
          en: 'Server timeout (408)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端在收到请求头后超时关闭了连接。',
          en: 'The server closed the connection after timing out while handling the request headers.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 稍后重试\n· 切换网络后再试',
          en: '· Retry later\n· Try again from another network',
        );
      case 429:
        title = StructuredErrorText.pick(
          zh: '触发限流 (429)',
          en: 'Rate limited (429)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端返回 429 Too Many Requests：当前账户调用过于频繁，或额度已用尽。',
          en: 'The server returned 429 Too Many Requests: the current account is calling too frequently, or the quota has been exhausted.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 稍等几分钟后重试\n· 在中转方控制台确认配额或余额\n· 升级套餐或更换 token',
          en:
              '· Wait a few minutes and try again\n'
              '· Check quota or balance in the relay console\n'
              '· Upgrade the plan or switch to another token',
        );
      case 500:
        title = StructuredErrorText.pick(
          zh: '服务端内部错误 (500)',
          en: 'Server error (500)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端返回 500 Internal Server Error：上游或中转方自身出现故障。',
          en: 'The server returned 500 Internal Server Error: the upstream provider or relay itself encountered a failure.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 稍后重试\n· 联系中转方查看服务状态',
          en:
              '· Retry later\n'
              '· Ask the relay provider to check service status',
        );
      case 502:
        title = StructuredErrorText.pick(
          zh: '网关异常 (502)',
          en: 'Bad gateway (502)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端返回 502 Bad Gateway：中转无法从上游（Anthropic / OpenAI 等）获得有效响应。',
          en: 'The server returned 502 Bad Gateway: the relay could not obtain a valid response from the upstream provider (Anthropic / OpenAI, etc.).',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 稍后重试\n· 联系中转方确认上游通路',
          en:
              '· Retry later\n'
              '· Ask the relay provider to verify the upstream connection',
        );
      case 503:
        title = StructuredErrorText.pick(
          zh: '服务不可用 (503)',
          en: 'Service unavailable (503)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端返回 503 Service Unavailable：服务在维护，或已被熔断。',
          en: 'The server returned 503 Service Unavailable: the service is under maintenance or has been circuit-broken.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 稍后重试\n· 关注中转方公告',
          en:
              '· Retry later\n'
              '· Check announcements from the relay provider',
        );
      case 504:
        title = StructuredErrorText.pick(
          zh: '网关超时 (504)',
          en: 'Gateway timeout (504)',
        );
        reason = StructuredErrorText.pick(
          zh: '服务端返回 504 Gateway Timeout：中转访问上游 LLM 时超时。',
          en: 'The server returned 504 Gateway Timeout: the relay timed out while talking to the upstream LLM.',
        );
        suggest = StructuredErrorText.pick(
          zh: '· 稍后重试\n· 切换中转或网络后再试',
          en:
              '· Retry later\n'
              '· Switch to another relay or network and try again',
        );
      default:
        if (isAuth) {
          title = StructuredErrorText.pick(
            zh: '鉴权失败 ($code)',
            en: 'Authentication failed ($code)',
          );
          reason = StructuredErrorText.pick(
            zh: '服务端返回 $code，并提示鉴权失败。',
            en: 'The server returned $code and indicated an authentication failure.',
          );
          suggest = StructuredErrorText.pick(
            zh: '· 检查 API Key、Token 与鉴权方式是否正确',
            en: '· Check whether the API key, token, and authentication scheme are correct',
          );
        } else if (code >= 500) {
          title = StructuredErrorText.pick(
            zh: '服务端错误 ($code)',
            en: 'Server error ($code)',
          );
          reason = StructuredErrorText.pick(
            zh: '服务端返回 $code，多为中转或上游故障。',
            en: 'The server returned $code, which usually indicates a relay or upstream failure.',
          );
          suggest = StructuredErrorText.pick(
            zh: '· 稍后重试\n· 联系中转方排查',
            en: '· Retry later\n· Ask the relay provider to investigate',
          );
        } else if (code >= 400) {
          title = StructuredErrorText.pick(
            zh: '客户端请求被拒 ($code)',
            en: 'Client error ($code)',
          );
          reason = StructuredErrorText.pick(
            zh: '服务端返回 $code，请求未通过协议或鉴权校验。',
            en: 'The server returned $code, and the request failed protocol or authentication validation.',
          );
          suggest = StructuredErrorText.pick(
            zh: '· 复核 Base URL、token 与自定义 header',
            en: '· Recheck the Base URL, token, and custom headers',
          );
        } else {
          title = StructuredErrorText.pick(
            zh: '非预期响应 ($code)',
            en: 'Unexpected status ($code)',
          );
          reason = StructuredErrorText.pick(
            zh: '服务端返回了非 2xx 状态码 $code。',
            en: 'The server returned a non-2xx status code: $code.',
          );
          suggest = StructuredErrorText.pick(
            zh: '· 联系中转方排查',
            en: '· Ask the relay provider to investigate',
          );
        }
    }
    return AiTransportDiagnosticMessages.format(
      title: title,
      reason: reason,
      try_: hint == null ? suggest : '$suggest\n· $hint',
    );
  }

  static String formatError(
    String detail, {
    String? url,
  }) => AiTransportDiagnosticMessages.format(
    title: StructuredErrorText.pick(
      zh: '响应格式异常',
      en: 'Unexpected response format',
    ),
    reason: StructuredErrorText.pick(
      zh: '服务端虽然返回了 200，但响应体不是合法 JSON：$detail\n通常意味着中转返回了 HTML 错误页、Cloudflare 验证页或纯文本错误提示。',
      en:
          'The server returned 200, but the body was not valid JSON: $detail\n'
          'This usually means the relay returned an HTML error page, a Cloudflare challenge page, or a plain-text error message.',
    ),
    try_: StructuredErrorText.pick(
      zh:
          '· 在浏览器直接打开${url == null ? '该 URL' : ' $url '}查看真实响应\n'
          '· 联系中转方确认 /models 是否真正提供 JSON 输出',
      en:
          '· Open ${url ?? 'the URL'} directly in a browser to inspect the real response\n'
          '· Ask the relay provider to confirm that /models really returns JSON',
    ),
  );

  static String unexpected() => AiTransportDiagnosticMessages.format(
    title: StructuredErrorText.pick(zh: '未识别错误', en: 'Unexpected error'),
    reason: StructuredErrorText.pick(
      zh: '扫描模型列表时发生未预期错误。',
      en: 'An unexpected error occurred while scanning the model list.',
    ),
    try_: StructuredErrorText.pick(
      zh: '· 重试或更换网络环境\n· 在「手动添加模型 ID」处直接录入模型名以绕过扫描',
      en:
          '· Retry or switch to another network environment\n'
          '· Enter the model ID manually to bypass scanning',
    ),
  );

  static String _format({
    required String title,
    required String reason,
    required String try_,
    String? raw,
  }) => AiTransportDiagnosticMessages.format(
    title: title,
    reason: reason,
    try_: try_,
    raw: raw,
  );
}
