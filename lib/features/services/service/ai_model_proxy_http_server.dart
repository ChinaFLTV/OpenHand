import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/net/bounded_server_bind.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import '../../ai/index.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';
import 'ai_model_proxy_dispatcher.dart';
import 'ai_model_proxy_status_page.dart';

/// OpenHand 模型中转站的本地 HTTP 入口。
///
/// 监听生命周期由控制器管理。此类只负责网络协议适配，不在 UI 线程执行
/// 阻塞 IO；所有请求体和并发均有上限，避免异常客户端耗尽进程资源。
class AiModelProxyHttpServer {
  AiModelProxyHttpServer({
    required AiModelProxyController controller,
    required List<AiModelConfig> Function() modelsProvider,
  }) : _controller = controller,
       _dispatcher = AiModelProxyDispatcher(
         controller: controller,
         modelsProvider: modelsProvider,
       );

  static const String _corsAllowedHeaders =
      'authorization, content-type, x-api-key, x-goog-api-key, api-key, '
      'anthropic-version, anthropic-beta, openai-beta, openai-organization, '
      'openai-project, x-goog-user-project, x-goog-api-client, '
      'x-openhand-client-pid, x-openhand-client-name, x-openhand-client-service, '
      'x-openhand-client-mac';
  static const String _corsApiMethods = 'GET, POST, OPTIONS';
  static const String _corsReadMethods = 'GET, HEAD, OPTIONS';

  static const int _maxRequestBodyBytes = 8 * 1024 * 1024;
  static const Duration _bindTimeout = Duration(seconds: 10);
  static const Duration _requestReadIdleTimeout = Duration(seconds: 30);
  static const Duration _requestReadTotalTimeout = Duration(minutes: 2);
  static const Duration _requestKeepAliveTimeout = Duration(seconds: 30);
  static const String _logoCacheControl = 'public, max-age=86400';

  final AiModelProxyController _controller;
  final AiModelProxyDispatcher _dispatcher;
  HttpServer? _server;
  final Set<int> _activeRequestTokens = <int>{};
  int _requestSequence = 0;
  bool _closing = false;
  Uint8List? _logoPng;

  bool get isRunning => _server != null && !_closing;
  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (isRunning) return;
    _closing = false;
    final address = _resolveListenAddress(_controller.settings.listenHost);
    final server = await bindHttpServerBounded(
      address,
      _controller.settings.listenPort,
      timeout: _bindTimeout,
    );
    server
      ..idleTimeout = _requestKeepAliveTimeout
      ..autoCompress = false;
    _server = server;
    unawaited(
      _serve(server).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            silentLog('ai_model_proxy_http_server', '收敛中转站监听任务', error, stack),
      ),
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _closing = true;
    if (server == null) return;
    try {
      await server.close(force: true).timeout(_bindTimeout);
    } on Object {
      // 关闭失败不能阻塞应用退出，句柄已从服务状态中移除。
    }
  }

  Future<void> dispose() async {
    await stop();
    _dispatcher.dispose();
  }

  Future<void> _serve(HttpServer server) async {
    Object? failure;
    try {
      await for (final request in server) {
        if (_server != server || _closing) {
          await _closeRequest(request);
          continue;
        }
        final path = _normalizePath(request.uri.path);
        final trackRuntime = !isAiModelProxyBrandingPath(path);
        if (trackRuntime) {
          _controller.runtimeRequestObserved(
            inboundBytes: request.contentLength < 0 ? 0 : request.contentLength,
          );
        }
        if (_activeRequestTokens.length >= aiModelProxyMaxConcurrentRequests) {
          await _writeError(
            request,
            429,
            '当前中转站请求过多，请稍后重试。',
            type: 'rate_limit_error',
          );
          continue;
        }
        final requestToken = ++_requestSequence;
        _activeRequestTokens.add(requestToken);
        final runtimeRequestId = trackRuntime
            ? _controller.runtimeRequestStarted(
                connectionKey: _connectionKey(request),
                userAgent: request.headers.value(HttpHeaders.userAgentHeader),
              )
            : null;
        unawaited(
          _handleRequest(request)
              .whenComplete(() {
                _activeRequestTokens.remove(requestToken);
                _controller.runtimeRequestFinished(runtimeRequestId);
              })
              .then<void>(
                (_) {},
                onError: (Object error, StackTrace stack) => silentLog(
                  'ai_model_proxy_http_server',
                  '收敛中转站请求任务',
                  error,
                  stack,
                ),
              ),
        );
      }
    } on Object catch (error, stack) {
      failure = error;
      silentLog('ai_model_proxy_http_server', '监听中转站请求', error, stack);
    } finally {
      if (identical(_server, server) && !_closing) {
        _server = null;
        _controller.runtimeServerStoppedUnexpectedly(failure);
        try {
          await server.close(force: true).timeout(_bindTimeout);
        } on Object {
          // 监听已失效，关闭失败不能阻塞状态收敛。
        }
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final method = request.method.toUpperCase();
      final path = _normalizePath(request.uri.path);
      if (method == 'OPTIONS') {
        await _writeJson(request, 204, const <String, Object?>{});
        return;
      }
      if ((method == 'GET' || method == 'HEAD') &&
          isAiModelProxyBrandingPath(path)) {
        await _writeBrandingAsset(request, headOnly: method == 'HEAD');
        return;
      }
      if ((method == 'GET' || method == 'HEAD') &&
          isAiModelProxyStatusJsonPath(path)) {
        await _writeStatusSnapshot(request, headOnly: method == 'HEAD');
        return;
      }
      if ((method == 'GET' || method == 'HEAD') &&
          isAiModelProxyStatusPath(path)) {
        await _writeStatusPage(request, headOnly: method == 'HEAD');
        return;
      }
      if (!_controller.authorize(_headers(request))) {
        await _writeError(
          request,
          401,
          'API 鉴权失败。',
          type: 'authentication_error',
        );
        return;
      }
      final style = _controller.settings.apiStyle;
      if (method == 'GET' &&
          (path == '/v1/models' || path == '/models') &&
          style != AiModelProxyApiStyle.gemini) {
        await _writeJson(
          request,
          200,
          _buildModelsResponse(style, request.uri.queryParameters),
        );
        return;
      }
      if (method == 'GET' && path == '/v1beta/models') {
        if (style != AiModelProxyApiStyle.gemini) {
          await _writeError(
            request,
            404,
            '请求路径不存在。',
            type: 'invalid_request_error',
            apiStyle: style,
          );
          return;
        }
        await _writeJson(
          request,
          200,
          _buildGeminiModelsResponse(request.uri.queryParameters),
        );
        return;
      }
      if (method == 'GET' &&
          ((path.startsWith('/v1/models/') &&
                  style != AiModelProxyApiStyle.gemini) ||
              (path.startsWith('/v1beta/models/') &&
                  style == AiModelProxyApiStyle.gemini))) {
        final modelId = _modelIdFromGetPath(path);
        final model = _findModelMetadata(modelId);
        if (model == null) {
          await _writeError(
            request,
            404,
            '模型不存在。',
            type: 'invalid_request_error',
            apiStyle: style,
          );
          return;
        }
        await _writeJson(
          request,
          200,
          style == AiModelProxyApiStyle.gemini
              ? _toGeminiModel(model)
              : style == AiModelProxyApiStyle.claude
              ? _toClaudeModel(model)
              : model,
        );
        return;
      }
      if (method == 'GET' &&
          (path == '/v1/models' ||
              path == '/models' ||
              path.startsWith('/v1/models/') ||
              path == '/v1beta/models' ||
              path.startsWith('/v1beta/models/'))) {
        await _writeError(
          request,
          404,
          '请求路径不存在。',
          type: 'invalid_request_error',
          apiStyle: style,
        );
        return;
      }
      if (method != 'POST') {
        await _writeError(
          request,
          405,
          '不支持的请求方法。',
          type: 'invalid_request_error',
        );
        return;
      }

      final route = _routeFor(path, style);
      if (route == null) {
        await _writeError(
          request,
          404,
          '请求路径不存在。',
          type: 'invalid_request_error',
        );
        return;
      }
      final body = await _readJsonBody(request);
      final payload = body.payload;
      final messages = _parseMessages(payload, route);
      final hasResponsesContinuation =
          route == _ProxyRoute.responses &&
          (_readString(payload['previous_response_id']).isNotEmpty ||
              payload['conversation'] != null ||
              payload['prompt'] != null ||
              payload['input'] != null ||
              _extractText(payload['instructions']).trim().isNotEmpty);
      if (messages.isEmpty && !hasResponsesContinuation) {
        await _writeError(
          request,
          400,
          '请求中缺少有效的消息内容。',
          type: 'invalid_request_error',
        );
        return;
      }
      final payloadModel = _readString(payload['model']);
      final pathModel = _modelFromPath(path, route);
      final requestedModel = pathModel.isNotEmpty
          ? pathModel
          : payloadModel.isNotEmpty
          ? payloadModel
          : _defaultGeminiModel(route);
      if (requestedModel.isEmpty) {
        await _writeError(
          request,
          400,
          '请求中缺少 model。',
          type: 'invalid_request_error',
        );
        return;
      }
      if (_isStreaming(payload, path)) {
        final stream = await _dispatcher.dispatchStream(
          exposedModel: requestedModel,
          messages: messages,
          request: payload,
          headers: _headers(request),
          requestPath: path,
          inboundBytes: body.byteLength,
        );
        await _writeNativeStreamingResponse(
          request,
          stream,
          route,
          requestedModel,
          requestBody: payload,
          includeUsage: _streamIncludesUsage(payload),
        );
        return;
      }
      final result = await _dispatcher.dispatch(
        exposedModel: requestedModel,
        messages: messages,
        request: payload,
        headers: _headers(request),
        requestPath: path,
        inboundBytes: body.byteLength,
      );
      final response = route == _ProxyRoute.responses
          ? _decorateResponsesResponse(
              _buildResponse(
                result,
                route,
                requestedModel,
                requestBody: payload,
              ),
              payload,
            )
          : _buildResponse(result, route, requestedModel, requestBody: payload);
      await _writeJson(request, 200, response);
    } on AiModelProxyException catch (error) {
      await _writeError(
        request,
        error.statusCode,
        error.message,
        type: _errorTypeForStatus(error.statusCode),
        apiStyle: _controller.settings.apiStyle,
      );
    } on FormatException catch (error) {
      await _writeError(
        request,
        400,
        '请求 JSON 无效：${error.message}',
        type: 'invalid_request_error',
        apiStyle: _controller.settings.apiStyle,
      );
    } on TimeoutException {
      await _writeError(
        request,
        408,
        '请求读取超时。',
        type: 'timeout_error',
        apiStyle: _controller.settings.apiStyle,
      );
    } on SocketException catch (error) {
      await _writeError(
        request,
        503,
        '中转站网络服务不可用：${error.message}',
        apiStyle: _controller.settings.apiStyle,
      );
    } on Object catch (error, stack) {
      silentLog('ai_model_proxy_http_server', '处理中转请求', error, stack);
      await _writeError(
        request,
        500,
        '中转站处理请求失败，请稍后重试。',
        apiStyle: _controller.settings.apiStyle,
      );
    }
  }

  String? _connectionKey(HttpRequest request) {
    final info = request.connectionInfo;
    if (info == null) return null;
    final address = info.remoteAddress.address.trim();
    final port = info.remotePort;
    if (address.isEmpty || port <= 0) return null;
    return aiModelProxyClientEndpoint(address, '$port');
  }

  Future<({Map<String, Object?> payload, int byteLength})> _readJsonBody(
    HttpRequest request,
  ) async {
    final contentLength = request.contentLength;
    if (contentLength > _maxRequestBodyBytes) {
      throw const AiModelProxyException(413, '请求体过大。');
    }
    late final Uint8List bytes;
    try {
      bytes = await readBoundedByteStream(
        request,
        maxBytes: _maxRequestBodyBytes,
        idleTimeout: _requestReadIdleTimeout,
        totalTimeout: _requestReadTotalTimeout,
        cancelOnFailure: false,
      );
    } on ByteStreamSizeLimitException {
      throw const AiModelProxyException(413, '请求体过大。');
    } on TimeoutException {
      throw TimeoutException('请求体读取超时。');
    }
    if (contentLength < 0) {
      _controller.runtimeInboundBytesReceived(bytes.length);
    }
    final text = utf8.decode(bytes).trim();
    if (text.isEmpty) throw const FormatException('请求体不能为空。');
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('请求体必须是 JSON 对象。');
    return (
      payload: Map<String, Object?>.from(decoded),
      byteLength: bytes.length,
    );
  }

  List<AiChatTurn> _parseMessages(Object? raw, _ProxyRoute route) {
    final payload = raw is Map
        ? Map<String, Object?>.from(raw)
        : const <String, Object?>{};
    return switch (route) {
      _ProxyRoute.chat => _parseChatMessages(payload['messages']),
      _ProxyRoute.responses => _parseResponsesPayload(payload),
      _ProxyRoute.claude => _parseClaudeMessages(payload),
      _ProxyRoute.gemini => _parseGeminiMessages(payload),
    };
  }

  List<AiChatTurn> _parseChatMessages(Object? raw) {
    if (raw is! List) return const <AiChatTurn>[];
    return raw
        .map(_parseMessage)
        .whereType<AiChatTurn>()
        .take(256)
        .toList(growable: false);
  }

  List<AiChatTurn> _parseResponsesInput(Object? raw) {
    if (raw is String) {
      return <AiChatTurn>[AiChatTurn(role: AiChatRole.user, content: raw)];
    }
    if (raw is Map) raw = <Object?>[raw];
    if (raw is! List) return const <AiChatTurn>[];
    final result = <AiChatTurn>[];
    for (final item in raw.take(256)) {
      if (item is String) {
        result.add(AiChatTurn(role: AiChatRole.user, content: item));
      } else if (item is Map) {
        final map = Map<String, Object?>.from(item);
        final type = _readString(map['type']);
        final role = _parseRole(
          map['role'] ??
              (type == 'message' || type == 'reasoning'
                  ? 'assistant'
                  : type.startsWith('input_')
                  ? 'user'
                  : null),
        );
        final reasoningText = type == 'reasoning'
            ? _extractText(map['summary'] ?? map['text'] ?? map['content'])
            : _readString(map['reasoning_content']);
        final rawContent =
            map['content'] ??
            map['text'] ??
            map['input'] ??
            map['output'] ??
            (type == 'reasoning'
                ? map['summary']
                : type.startsWith('input_')
                ? map
                : null);
        final text = _extractText(rawContent);
        final contentFallback =
            text.isEmpty &&
                ((rawContent is List && rawContent.isNotEmpty) ||
                    rawContent is Map)
            ? jsonEncode(rawContent)
            : text;
        final toolCallId = _readString(
          map['call_id'] ?? map['tool_call_id'] ?? map['id'],
        );
        final functionName = _readString(map['name']);
        final functionCalls = type == 'function_call' && functionName.isNotEmpty
            ? <AiToolCall>[
                AiToolCall(
                  id: toolCallId.isEmpty
                      ? 'tool-call-${result.length}'
                      : toolCallId,
                  name: functionName,
                  arguments: map['arguments'] is String
                      ? map['arguments'] as String
                      : jsonEncode(
                          map['arguments'] ?? const <String, Object?>{},
                        ),
                ),
              ]
            : _parseToolCalls(map['tool_calls']);
        final effectiveRole = type == 'function_call_output'
            ? AiChatRole.tool
            : type == 'function_call'
            ? AiChatRole.assistant
            : role;
        if (effectiveRole != null &&
            (contentFallback.trim().isNotEmpty ||
                toolCallId.isNotEmpty ||
                functionCalls.isNotEmpty)) {
          result.add(
            AiChatTurn(
              role: effectiveRole,
              content: contentFallback,
              toolCallId: toolCallId.isEmpty ? null : toolCallId,
              toolCalls: functionCalls,
              reasoningContent: reasoningText.isEmpty ? null : reasoningText,
            ),
          );
        }
      }
    }
    return result;
  }

  List<AiChatTurn> _parseResponsesPayload(Map<String, Object?> payload) {
    final result = <AiChatTurn>[];
    final instructions = _extractText(payload['instructions']);
    if (instructions.isNotEmpty) {
      result.add(AiChatTurn(role: AiChatRole.system, content: instructions));
    }
    result.addAll(_parseResponsesInput(payload['input']));
    return result;
  }

  List<AiChatTurn> _parseClaudeMessages(Map<String, Object?> payload) {
    final result = <AiChatTurn>[];
    final system = _extractText(payload['system']);
    if (system.trim().isNotEmpty) {
      result.add(AiChatTurn(role: AiChatRole.system, content: system));
    }
    final messages = payload['messages'];
    if (messages is List) {
      for (final raw in messages.take(256)) {
        if (raw is! Map) continue;
        final map = Map<String, Object?>.from(raw);
        final role = _parseRole(map['role']);
        if (role == null) continue;
        final toolCalls = <AiToolCall>[];
        var toolCallId = '';
        final textParts = <String>[];
        final reasoningParts = <String>[];
        final content = map['content'];
        if (content is List) {
          for (final block in content) {
            if (block is! Map) continue;
            final type = _readString(block['type']);
            if (type == 'text') {
              final text = _readString(block['text']);
              if (text.isNotEmpty) textParts.add(text);
            } else if (type == 'thinking') {
              final thinking = _readString(block['thinking'] ?? block['text']);
              if (thinking.isNotEmpty) reasoningParts.add(thinking);
            } else if (type == 'redacted_thinking') {
              final thinking = _readString(block['data']);
              if (thinking.isNotEmpty) reasoningParts.add(thinking);
            } else if (type == 'tool_use') {
              final id = _readString(block['id']);
              final name = _readString(block['name']);
              if (name.isNotEmpty) {
                toolCalls.add(
                  AiToolCall(
                    id: id.isEmpty ? 'tool-call-${toolCalls.length}' : id,
                    name: name,
                    arguments: jsonEncode(
                      block['input'] ?? const <String, Object?>{},
                    ),
                  ),
                );
              }
            } else if (type == 'tool_result') {
              toolCallId = _readString(block['tool_use_id']);
              final value = _extractText(block['content']);
              if (value.isNotEmpty) textParts.add(value);
            }
          }
        } else {
          final text = _extractText(content);
          if (text.isNotEmpty) textParts.add(text);
        }
        final text = textParts.join('\n');
        final reasoning = reasoningParts.join('\n');
        final effectiveRole = toolCallId.isNotEmpty ? AiChatRole.tool : role;
        if (text.isNotEmpty || toolCalls.isNotEmpty || toolCallId.isNotEmpty) {
          result.add(
            AiChatTurn(
              role: effectiveRole,
              content: text,
              toolCallId: toolCallId.isEmpty ? null : toolCallId,
              toolCalls: toolCalls,
              reasoningContent: reasoning.isEmpty ? null : reasoning,
            ),
          );
        }
      }
    }
    return result;
  }

  List<AiChatTurn> _parseGeminiMessages(Object? raw) {
    final payload = raw is Map
        ? Map<String, Object?>.from(raw)
        : const <String, Object?>{};
    final contents = payload['contents'];
    if (contents is! List) return const <AiChatTurn>[];
    final result = <AiChatTurn>[];
    final systemInstruction = payload['systemInstruction'];
    final system = systemInstruction is Map
        ? _extractGeminiText(
            Map<String, Object?>.from(systemInstruction)['parts'],
          )
        : '';
    if (system.isNotEmpty) {
      result.add(AiChatTurn(role: AiChatRole.system, content: system));
    }
    for (final item in contents.take(256)) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.from(item);
      final role = '${map['role'] ?? 'user'}'.toLowerCase() == 'model'
          ? AiChatRole.assistant
          : AiChatRole.user;
      final text = _extractGeminiText(map['parts']);
      final responseTextParts = <String>[];
      final toolCalls = <AiToolCall>[];
      var toolCallId = '';
      if (map['parts'] is List) {
        for (final part in map['parts'] as List) {
          if (part is! Map) continue;
          final functionCall = part['functionCall'];
          final functionResponse = part['functionResponse'];
          if (functionCall is Map) {
            final call = Map<String, Object?>.from(functionCall);
            final name = _readString(call['name']);
            if (name.isNotEmpty) {
              final id = _readString(call['id']);
              toolCalls.add(
                AiToolCall(
                  id: id.isEmpty ? 'tool-call-${toolCalls.length}' : id,
                  name: name,
                  arguments: jsonEncode(
                    call['args'] ?? const <String, Object?>{},
                  ),
                ),
              );
            }
          }
          if (functionResponse is Map) {
            toolCallId = _readString(functionResponse['name']);
            final response = functionResponse['response'];
            if (response is String) {
              if (response.trim().isNotEmpty) {
                responseTextParts.add(response.trim());
              }
            } else if (response != null) {
              responseTextParts.add(jsonEncode(response));
            }
          }
        }
      }
      final effectiveRole = toolCallId.isNotEmpty ? AiChatRole.tool : role;
      final combinedText = <String>[
        text,
        ...responseTextParts,
      ].where((value) => value.trim().isNotEmpty).join('\n');
      if (combinedText.trim().isNotEmpty ||
          toolCalls.isNotEmpty ||
          toolCallId.isNotEmpty) {
        result.add(
          AiChatTurn(
            role: effectiveRole,
            content: combinedText,
            toolCallId: toolCallId.isEmpty ? null : toolCallId,
            toolCalls: toolCalls,
          ),
        );
      }
    }
    return result;
  }

  AiChatTurn? _parseMessage(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final role = _parseRole(map['role']);
    if (role == null) return null;
    final rawContent = map['content'];
    final extractedContent = _extractText(rawContent);
    final content =
        extractedContent.isEmpty && rawContent is List && rawContent.isNotEmpty
        ? jsonEncode(rawContent)
        : extractedContent;
    final toolCalls = _parseToolCalls(map['tool_calls']);
    final reasoning = _readString(map['reasoning_content'] ?? map['reasoning']);
    if (content.trim().isEmpty && toolCalls.isEmpty && reasoning.isEmpty) {
      return null;
    }
    final toolCallId = _readString(map['tool_call_id']);
    return AiChatTurn(
      role: role,
      content: content,
      toolCallId: toolCallId.isEmpty ? null : toolCallId,
      toolCalls: toolCalls,
      reasoningContent: reasoning.isEmpty ? null : reasoning,
    );
  }

  List<AiToolCall> _parseToolCalls(Object? raw) {
    if (raw is! List) return const <AiToolCall>[];
    final result = <AiToolCall>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.from(item);
      final function = map['function'] is Map
          ? Map<String, Object?>.from(map['function'] as Map)
          : map;
      final name = _readString(function['name']);
      if (name.isEmpty) continue;
      final id = _readString(map['id']);
      final arguments = function['arguments'];
      result.add(
        AiToolCall(
          id: id.isEmpty ? 'tool-call-${result.length}' : id,
          name: name,
          arguments: arguments is String
              ? arguments
              : jsonEncode(arguments ?? const <String, Object?>{}),
        ),
      );
    }
    return result;
  }

  AiChatRole? _parseRole(Object? value) => switch ('$value'.toLowerCase()) {
    'system' => AiChatRole.system,
    'developer' => AiChatRole.system,
    'user' => AiChatRole.user,
    'assistant' || 'model' => AiChatRole.assistant,
    'tool' || 'function' => AiChatRole.tool,
    _ => null,
  };

  String _extractText(Object? raw) {
    if (raw is String) return raw;
    if (raw is Map) {
      final map = Map<String, Object?>.from(raw);
      return _extractText(map['text'] ?? map['value'] ?? map['content']);
    }
    if (raw is List) {
      return raw.map(_extractText).where((item) => item.isNotEmpty).join('\n');
    }
    return '';
  }

  String _extractGeminiText(Object? raw) {
    if (raw is! List) return '';
    return raw
        .map((part) {
          if (part is Map) return _extractText(part['text']);
          return '';
        })
        .where((item) => item.isNotEmpty)
        .join('\n');
  }

  Map<String, Object?> _buildResponse(
    AiModelProxyDispatchResult result,
    _ProxyRoute route,
    String requestedModel, {
    Map<String, Object?> requestBody = const <String, Object?>{},
  }) {
    final native = _nativeResponseMap(result.rawResponse, route);
    if (native != null) {
      native['model'] = requestedModel;
      if (route == _ProxyRoute.responses) {
        native['object'] = 'response';
      }
      return native;
    }
    final id = 'openhand-${DateTime.now().microsecondsSinceEpoch}';
    final usage = result.usage;
    final inputTokens = usage?.promptTokens ?? 0;
    final outputTokens = usage?.completionTokens ?? 0;
    final usageJson = <String, Object?>{
      'prompt_tokens': inputTokens,
      'completion_tokens': outputTokens,
      'total_tokens': usage?.totalTokens ?? inputTokens + outputTokens,
      if (usage?.cacheReadTokens != null || usage?.cacheCreationTokens != null)
        'prompt_tokens_details': <String, Object?>{
          if (usage?.cacheReadTokens != null)
            'cached_tokens': usage!.cacheReadTokens,
          if (usage?.cacheCreationTokens != null)
            'cache_creation_tokens': usage!.cacheCreationTokens,
        },
      if (usage?.reasoningTokens != null)
        'completion_tokens_details': <String, Object?>{
          'reasoning_tokens': usage!.reasoningTokens,
        },
    };
    return switch (route) {
      _ProxyRoute.chat => <String, Object?>{
        'id': id,
        'object': 'chat.completion',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': requestedModel,
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'message': <String, Object?>{
              'role': 'assistant',
              'content': result.reply.isEmpty && result.toolCalls.isNotEmpty
                  ? null
                  : result.reply,
              'refusal': null,
              'annotations': const <Object?>[],
              if (result.reasoningContent != null)
                'reasoning_content': result.reasoningContent,
              if (result.toolCalls.isNotEmpty)
                'tool_calls': result.toolCalls
                    .map((call) => call.toOpenAiJson())
                    .toList(growable: false),
            },
            'logprobs': null,
            'finish_reason': result.toolCalls.isNotEmpty
                ? 'tool_calls'
                : 'stop',
          },
        ],
        'usage': usageJson,
        'service_tier': requestBody['service_tier'] ?? 'default',
        'system_fingerprint': null,
      },
      _ProxyRoute.responses => <String, Object?>{
        'id': id,
        'object': 'response',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'status': 'completed',
        'model': requestedModel,
        'output': <Object?>[
          if (result.reasoningContent != null)
            <String, Object?>{
              'id': '$id-reasoning',
              'type': 'reasoning',
              'status': 'completed',
              'summary': <Object?>[
                <String, Object?>{
                  'type': 'summary_text',
                  'text': result.reasoningContent,
                },
              ],
            },
          if (result.reply.isNotEmpty)
            <String, Object?>{
              'id': '$id-output',
              'type': 'message',
              'status': 'completed',
              'role': 'assistant',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'output_text',
                  'text': result.reply,
                  'annotations': const <Object?>[],
                },
              ],
            },
          ...result.toolCalls.map(
            (call) => <String, Object?>{
              'id': call.id,
              'type': 'function_call',
              'status': 'completed',
              'call_id': call.id,
              'name': call.name,
              'arguments': call.arguments,
            },
          ),
        ],
        'output_text': result.reply,
        'usage': <String, Object?>{
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
          'total_tokens': usage?.totalTokens ?? inputTokens + outputTokens,
          if (usage?.cacheReadTokens != null)
            'input_tokens_details': <String, Object?>{
              'cached_tokens': usage!.cacheReadTokens,
            },
          if (usage?.reasoningTokens != null)
            'output_tokens_details': <String, Object?>{
              'reasoning_tokens': usage!.reasoningTokens,
            },
        },
      },
      _ProxyRoute.claude => <String, Object?>{
        'id': id,
        'type': 'message',
        'role': 'assistant',
        'model': requestedModel,
        'content': <Object?>[
          if (result.reasoningContent != null)
            <String, Object?>{
              'type': 'thinking',
              'thinking': result.reasoningContent,
            },
          if (result.reply.isNotEmpty)
            <String, Object?>{'type': 'text', 'text': result.reply},
          ...result.toolCalls.map(
            (call) => <String, Object?>{
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': _decodeJsonObject(call.arguments),
            },
          ),
        ],
        'stop_reason': result.toolCalls.isNotEmpty ? 'tool_use' : 'end_turn',
        'stop_sequence': null,
        'usage': <String, Object?>{
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
          if (usage?.cacheCreationTokens != null)
            'cache_creation_input_tokens': usage!.cacheCreationTokens,
          if (usage?.cacheReadTokens != null)
            'cache_read_input_tokens': usage!.cacheReadTokens,
        },
      },
      _ProxyRoute.gemini => <String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'role': 'model',
              'parts': <Object?>[
                if (result.reasoningContent != null)
                  <String, Object?>{
                    'text': result.reasoningContent,
                    'thought': true,
                  },
                if (result.reply.isNotEmpty)
                  <String, Object?>{'text': result.reply},
                ...result.toolCalls.map(
                  (call) => <String, Object?>{
                    'functionCall': <String, Object?>{
                      'name': call.name,
                      'args': _decodeJsonObject(call.arguments),
                    },
                  },
                ),
              ],
            },
            'finishReason': 'STOP',
          },
        ],
        'usageMetadata': <String, Object?>{
          'promptTokenCount': inputTokens,
          'candidatesTokenCount': outputTokens,
          'totalTokenCount': usage?.totalTokens ?? inputTokens + outputTokens,
          if (usage?.cacheReadTokens != null)
            'cachedContentTokenCount': usage!.cacheReadTokens,
          if (usage?.reasoningTokens != null)
            'thoughtsTokenCount': usage!.reasoningTokens,
        },
      },
    };
  }

  static Map<String, Object?> _decorateResponsesResponse(
    Map<String, Object?> response,
    Map<String, Object?> request,
  ) {
    final result = <String, Object?>{...response, 'object': 'response'};
    result.putIfAbsent('error', () => null);
    result.putIfAbsent('incomplete_details', () => null);
    result.putIfAbsent('instructions', () => request['instructions']);
    result.putIfAbsent('max_output_tokens', () => request['max_output_tokens']);
    result.putIfAbsent(
      'parallel_tool_calls',
      () => request['parallel_tool_calls'] ?? true,
    );
    result.putIfAbsent(
      'previous_response_id',
      () => request['previous_response_id'],
    );
    result.putIfAbsent(
      'reasoning',
      () =>
          request['reasoning'] ??
          const <String, Object?>{'effort': null, 'summary': null},
    );
    result.putIfAbsent('store', () => request['store'] ?? true);
    result.putIfAbsent('temperature', () => request['temperature'] ?? 1.0);
    result.putIfAbsent(
      'text',
      () =>
          request['text'] ??
          const <String, Object?>{
            'format': <String, Object?>{'type': 'text'},
          },
    );
    result.putIfAbsent('tool_choice', () => request['tool_choice'] ?? 'auto');
    result.putIfAbsent('tools', () => request['tools'] ?? const <Object?>[]);
    result.putIfAbsent('top_p', () => request['top_p'] ?? 1.0);
    result.putIfAbsent('truncation', () => request['truncation'] ?? 'disabled');
    result.putIfAbsent('user', () => request['user']);
    result.putIfAbsent(
      'metadata',
      () => request['metadata'] ?? const <String, Object?>{},
    );
    result.putIfAbsent('background', () => request['background'] ?? false);
    result.putIfAbsent('service_tier', () => request['service_tier'] ?? 'auto');
    result.putIfAbsent('conversation', () => request['conversation']);
    result.putIfAbsent(
      'context_management',
      () => request['context_management'],
    );
    result.putIfAbsent(
      'include',
      () => request['include'] ?? const <Object?>[],
    );
    result.putIfAbsent('max_tool_calls', () => request['max_tool_calls']);
    result.putIfAbsent('prompt', () => request['prompt']);
    result.putIfAbsent('prompt_cache_key', () => request['prompt_cache_key']);
    result.putIfAbsent(
      'prompt_cache_options',
      () => request['prompt_cache_options'],
    );
    result.putIfAbsent(
      'prompt_cache_retention',
      () => request['prompt_cache_retention'],
    );
    result.putIfAbsent('safety_identifier', () => request['safety_identifier']);
    result.putIfAbsent('top_logprobs', () => request['top_logprobs']);
    if (result['status'] == 'completed') {
      result.putIfAbsent('completed_at', () => result['created_at']);
    }
    return result;
  }

  static Map<String, Object?>? _nativeResponseMap(
    String? rawResponse,
    _ProxyRoute route,
  ) {
    if (rawResponse == null || rawResponse.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map) return null;
      final map = Map<String, Object?>.from(decoded);
      final matches = switch (route) {
        _ProxyRoute.chat => map['choices'] is List,
        _ProxyRoute.responses =>
          map['object'] == 'response' && map['output'] is List,
        _ProxyRoute.claude =>
          map['type'] == 'message' && map['content'] is List,
        _ProxyRoute.gemini => map['candidates'] is List,
      };
      return matches ? map : null;
    } on Object {
      return null;
    }
  }

  Future<void> _writeNativeStreamingResponse(
    HttpRequest request,
    AiModelProxyStreamDispatch dispatch,
    _ProxyRoute route,
    String requestedModel, {
    Map<String, Object?>? requestBody,
    required bool includeUsage,
  }) async {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..headers.set(HttpHeaders.connectionHeader, kConnectionKeepAlive);
    _applyCorsHeaders(request, methods: _corsApiMethods);
    final id = 'openhand-${DateTime.now().microsecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final chatStreamMetadata = <String, Object?>{
      'service_tier': requestBody?['service_tier'] ?? 'default',
      'system_fingerprint': null,
    };
    var responseSequenceNumber = 0;
    Future<void> writeSse(Map<String, Object?> data) {
      final payload = route == _ProxyRoute.responses
          ? <String, Object?>{
              'sequence_number': responseSequenceNumber++,
              ...data,
            }
          : data;
      return _writeSse(request, payload);
    }

    if (route == _ProxyRoute.chat) {
      await writeSse(<String, Object?>{
        'id': id,
        'object': 'chat.completion.chunk',
        'created': created,
        'model': requestedModel,
        ...chatStreamMetadata,
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'delta': <String, Object?>{'role': 'assistant'},
            'finish_reason': null,
          },
        ],
      });
    } else if (route == _ProxyRoute.claude) {
      await writeSse(<String, Object?>{
        'type': 'message_start',
        'message': <String, Object?>{
          'id': id,
          'type': 'message',
          'role': 'assistant',
          'model': requestedModel,
          'content': const <Object?>[],
          'stop_reason': null,
          'stop_sequence': null,
          'usage': const <String, Object?>{
            'input_tokens': 0,
            'output_tokens': 0,
          },
        },
      });
    } else if (route == _ProxyRoute.responses) {
      await writeSse(<String, Object?>{
        'type': 'response.created',
        'response': <String, Object?>{
          'id': id,
          'object': 'response',
          'created_at': created,
          'status': 'in_progress',
          'model': requestedModel,
          'output': const <Object?>[],
        },
      });
      await writeSse(<String, Object?>{
        'type': 'response.in_progress',
        'response': <String, Object?>{
          'id': id,
          'object': 'response',
          'created_at': created,
          'status': 'in_progress',
          'model': requestedModel,
          'output': const <Object?>[],
        },
      });
    }
    var nextClaudeBlockIndex = 0;
    int? claudeTextBlockIndex;
    int? claudeThinkingBlockIndex;
    final claudeToolBlockIndexes = <int, int>{};
    final responseToolArguments = <int, StringBuffer>{};
    final responseToolIds = <int, String>{};
    final responseToolNames = <int, String>{};
    final responseToolOutputIndexes = <int, int>{};
    final responseText = StringBuffer();
    final responseReasoning = StringBuffer();
    var nextResponseOutputIndex = 0;
    int? responseTextOutputIndex;
    int? responseReasoningOutputIndex;
    var responseTextStarted = false;
    var responseReasoningStarted = false;
    final responseToolStarted = <int>{};
    try {
      await for (final event in dispatch.response.events) {
        switch (route) {
          case _ProxyRoute.chat:
            final delta = <String, Object?>{};
            if (event.type == AiChatStreamEventType.textDelta) {
              delta['content'] = event.textDelta ?? '';
            } else if (event.type == AiChatStreamEventType.reasoningDelta) {
              delta['reasoning_content'] = event.reasoningDelta ?? '';
            } else if (event.type == AiChatStreamEventType.toolCallDelta) {
              final call = event.toolCallDelta!;
              delta['tool_calls'] = <Object?>[
                <String, Object?>{
                  'index': call.index,
                  if (call.id != null) 'id': call.id,
                  'type': 'function',
                  'function': <String, Object?>{
                    if (call.name != null) 'name': call.name,
                    if (call.argumentsFragment.isNotEmpty)
                      'arguments': call.argumentsFragment,
                  },
                },
              ];
            }
            if (delta.isNotEmpty) {
              await writeSse(<String, Object?>{
                'id': id,
                'object': 'chat.completion.chunk',
                'created': created,
                'model': requestedModel,
                ...chatStreamMetadata,
                'choices': <Object?>[
                  <String, Object?>{
                    'index': 0,
                    'delta': delta,
                    'finish_reason': null,
                  },
                ],
              });
            }
          case _ProxyRoute.responses:
            if (event.type == AiChatStreamEventType.textDelta) {
              final delta = event.textDelta ?? '';
              final outputIndex = responseTextOutputIndex ??=
                  nextResponseOutputIndex++;
              if (!responseTextStarted) {
                responseTextStarted = true;
                await writeSse(<String, Object?>{
                  'type': 'response.output_item.added',
                  'output_index': outputIndex,
                  'item': <String, Object?>{
                    'id': '$id-output',
                    'type': 'message',
                    'status': 'in_progress',
                    'role': 'assistant',
                    'content': const <Object?>[],
                  },
                });
                await writeSse(<String, Object?>{
                  'type': 'response.content_part.added',
                  'item_id': '$id-output',
                  'output_index': outputIndex,
                  'content_index': 0,
                  'part': <String, Object?>{
                    'type': 'output_text',
                    'text': '',
                    'annotations': const <Object?>[],
                  },
                });
              }
              responseText.write(delta);
              await writeSse(<String, Object?>{
                'type': 'response.output_text.delta',
                'item_id': '$id-output',
                'output_index': outputIndex,
                'content_index': 0,
                'delta': delta,
                'logprobs': const <Object?>[],
              });
            } else if (event.type == AiChatStreamEventType.reasoningDelta) {
              final delta = event.reasoningDelta ?? '';
              final outputIndex = responseReasoningOutputIndex ??=
                  nextResponseOutputIndex++;
              if (!responseReasoningStarted) {
                responseReasoningStarted = true;
                await writeSse(<String, Object?>{
                  'type': 'response.output_item.added',
                  'output_index': outputIndex,
                  'item': <String, Object?>{
                    'id': '$id-reasoning',
                    'type': 'reasoning',
                    'status': 'in_progress',
                    'summary': const <Object?>[],
                  },
                });
              }
              responseReasoning.write(delta);
              await writeSse(<String, Object?>{
                'type': 'response.reasoning_summary_text.delta',
                'item_id': '$id-reasoning',
                'output_index': outputIndex,
                'summary_index': 0,
                'delta': delta,
              });
            } else if (event.type == AiChatStreamEventType.toolCallDelta) {
              final call = event.toolCallDelta!;
              final index = call.index;
              final outputIndex = responseToolOutputIndexes.putIfAbsent(
                index,
                () => nextResponseOutputIndex++,
              );
              final itemId = call.id ?? '$id-tool-$index';
              responseToolIds[index] = itemId;
              if (call.name != null && call.name!.isNotEmpty) {
                responseToolNames[index] = call.name!;
              }
              final arguments = responseToolArguments.putIfAbsent(
                index,
                StringBuffer.new,
              );
              arguments.write(call.argumentsFragment);
              if (responseToolStarted.add(index)) {
                await writeSse(<String, Object?>{
                  'type': 'response.output_item.added',
                  'output_index': outputIndex,
                  'item': <String, Object?>{
                    'id': itemId,
                    'type': 'function_call',
                    'status': 'in_progress',
                    'name': call.name ?? '',
                    'call_id': itemId,
                    'arguments': '',
                  },
                });
              }
              await writeSse(<String, Object?>{
                'type': 'response.function_call_arguments.delta',
                'item_id': itemId,
                'output_index': outputIndex,
                'delta': call.argumentsFragment,
              });
            }
          case _ProxyRoute.claude:
            if (event.type == AiChatStreamEventType.textDelta) {
              final index = claudeTextBlockIndex ??= nextClaudeBlockIndex++;
              if (responseTextStarted == false) {
                responseTextStarted = true;
                await writeSse(<String, Object?>{
                  'type': 'content_block_start',
                  'index': index,
                  'content_block': <String, Object?>{
                    'type': 'text',
                    'text': '',
                  },
                });
              }
              await writeSse(<String, Object?>{
                'type': 'content_block_delta',
                'index': index,
                'delta': <String, Object?>{
                  'type': 'text_delta',
                  'text': event.textDelta ?? '',
                },
              });
            } else if (event.type == AiChatStreamEventType.reasoningDelta) {
              final index = claudeThinkingBlockIndex ??= nextClaudeBlockIndex++;
              if (!responseReasoningStarted) {
                responseReasoningStarted = true;
                await writeSse(<String, Object?>{
                  'type': 'content_block_start',
                  'index': index,
                  'content_block': <String, Object?>{
                    'type': 'thinking',
                    'thinking': '',
                  },
                });
              }
              await writeSse(<String, Object?>{
                'type': 'content_block_delta',
                'index': index,
                'delta': <String, Object?>{
                  'type': 'thinking_delta',
                  'thinking': event.reasoningDelta ?? '',
                },
              });
            } else if (event.type == AiChatStreamEventType.toolCallDelta) {
              final call = event.toolCallDelta!;
              final isNewToolBlock = !claudeToolBlockIndexes.containsKey(
                call.index,
              );
              final index = claudeToolBlockIndexes.putIfAbsent(
                call.index,
                () => nextClaudeBlockIndex++,
              );
              if (isNewToolBlock) {
                await writeSse(<String, Object?>{
                  'type': 'content_block_start',
                  'index': index,
                  'content_block': <String, Object?>{
                    'type': 'tool_use',
                    'id': call.id ?? '$id-tool-${call.index}',
                    'name': call.name ?? '',
                    'input': const <String, Object?>{},
                  },
                });
              }
              if (call.argumentsFragment.isNotEmpty) {
                await writeSse(<String, Object?>{
                  'type': 'content_block_delta',
                  'index': index,
                  'delta': <String, Object?>{
                    'type': 'input_json_delta',
                    'partial_json': call.argumentsFragment,
                  },
                });
              }
            }
          case _ProxyRoute.gemini:
            final parts = <Object?>[];
            if (event.type == AiChatStreamEventType.textDelta) {
              parts.add(<String, Object?>{'text': event.textDelta ?? ''});
            } else if (event.type == AiChatStreamEventType.reasoningDelta) {
              parts.add(<String, Object?>{
                'text': event.reasoningDelta ?? '',
                'thought': true,
              });
            } else if (event.type == AiChatStreamEventType.toolCallDelta) {
              final call = event.toolCallDelta!;
              parts.add(<String, Object?>{
                'functionCall': <String, Object?>{
                  'name': call.name ?? '',
                  'args': _decodeJsonObject(call.argumentsFragment),
                },
              });
            }
            if (parts.isNotEmpty) {
              await writeSse(<String, Object?>{
                'candidates': <Object?>[
                  <String, Object?>{
                    'content': <String, Object?>{
                      'role': 'model',
                      'parts': parts,
                    },
                  },
                ],
              });
            }
        }
      }
      final streamResult = await dispatch.response.result;
      if (streamResult.wasCancelled) {
        throw const AiModelProxyException(499, '流式请求已取消。');
      }
      final response = _buildResponse(
        AiModelProxyDispatchResult(
          reply: streamResult.reply,
          exposedModel: dispatch.exposedModel,
          backend: dispatch.backend,
          durationMs: 0,
          usage: streamResult.usage,
          reasoningContent: streamResult.reasoning,
          toolCalls: streamResult.toolCalls,
          rawResponse: streamResult.rawResponse,
        ),
        route,
        requestedModel,
        requestBody: requestBody ?? const <String, Object?>{},
      );
      final responsePayload =
          route == _ProxyRoute.responses && requestBody != null
          ? _decorateResponsesResponse(response, requestBody)
          : response;
      switch (route) {
        case _ProxyRoute.chat:
          await writeSse(<String, Object?>{
            'id': id,
            'object': 'chat.completion.chunk',
            'created': created,
            'model': requestedModel,
            ...chatStreamMetadata,
            'choices': <Object?>[
              <String, Object?>{
                'index': 0,
                'delta': const <String, Object?>{},
                'finish_reason': streamResult.toolCalls.isNotEmpty
                    ? 'tool_calls'
                    : 'stop',
              },
            ],
          });
          if (includeUsage) {
            await writeSse(<String, Object?>{
              'id': id,
              'object': 'chat.completion.chunk',
              'created': created,
              'model': requestedModel,
              ...chatStreamMetadata,
              'choices': const <Object?>[],
              'usage': _openAiUsage(responsePayload['usage']),
            });
          }
          await _writeSsePayload(request, 'data: [DONE]\n\n');
        case _ProxyRoute.responses:
          if (responseTextStarted) {
            final outputIndex = responseTextOutputIndex!;
            await writeSse(<String, Object?>{
              'type': 'response.output_text.done',
              'item_id': '$id-output',
              'output_index': outputIndex,
              'content_index': 0,
              'text': responseText.toString(),
              'logprobs': const <Object?>[],
            });
            await writeSse(<String, Object?>{
              'type': 'response.output_item.done',
              'output_index': outputIndex,
              'item': <String, Object?>{
                'id': '$id-output',
                'type': 'message',
                'status': 'completed',
                'role': 'assistant',
                'content': <Object?>[
                  <String, Object?>{
                    'type': 'output_text',
                    'text': responseText.toString(),
                    'annotations': const <Object?>[],
                  },
                ],
              },
            });
          }
          if (responseReasoningStarted) {
            final outputIndex = responseReasoningOutputIndex!;
            await writeSse(<String, Object?>{
              'type': 'response.reasoning_summary_text.done',
              'item_id': '$id-reasoning',
              'output_index': outputIndex,
              'summary_index': 0,
              'text': responseReasoning.toString(),
            });
            await writeSse(<String, Object?>{
              'type': 'response.output_item.done',
              'output_index': outputIndex,
              'item': <String, Object?>{
                'id': '$id-reasoning',
                'type': 'reasoning',
                'status': 'completed',
                'summary': <Object?>[
                  <String, Object?>{
                    'type': 'summary_text',
                    'text': responseReasoning.toString(),
                  },
                ],
              },
            });
          }
          for (final index in responseToolArguments.keys.toList()..sort()) {
            final itemId = responseToolIds[index] ?? '$id-tool-$index';
            final outputIndex = responseToolOutputIndexes[index] ?? index;
            final arguments = responseToolArguments[index]!.toString();
            await writeSse(<String, Object?>{
              'type': 'response.function_call_arguments.done',
              'item_id': itemId,
              'output_index': outputIndex,
              'arguments': arguments,
            });
            await writeSse(<String, Object?>{
              'type': 'response.output_item.done',
              'output_index': outputIndex,
              'item': <String, Object?>{
                'id': itemId,
                'type': 'function_call',
                'status': 'completed',
                'name': responseToolNames[index] ?? '',
                'call_id': itemId,
                'arguments': arguments,
              },
            });
          }
          await writeSse(<String, Object?>{
            'type': 'response.completed',
            'response': responsePayload,
          });
        case _ProxyRoute.claude:
          final claudeBlockIndexes = <int?>[
            claudeTextBlockIndex,
            claudeThinkingBlockIndex,
            ...claudeToolBlockIndexes.values,
          ].whereType<int>().toSet().toList()..sort();
          for (final index in claudeBlockIndexes) {
            await writeSse(<String, Object?>{
              'type': 'content_block_stop',
              'index': index,
            });
          }
          await writeSse(<String, Object?>{
            'type': 'message_delta',
            'delta': <String, Object?>{
              'stop_reason': streamResult.toolCalls.isNotEmpty
                  ? 'tool_use'
                  : 'end_turn',
              'stop_sequence': null,
            },
            'usage': responsePayload['usage'],
          });
          await writeSse(<String, Object?>{'type': 'message_stop'});
        case _ProxyRoute.gemini:
          await writeSse(<String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{'finishReason': 'STOP'},
            ],
            'usageMetadata': responsePayload['usageMetadata'],
          });
      }
    } on Object catch (error) {
      // SSE 已发送 200 后无法再修改 HTTP 状态，仍按真实原因记录入口错误遥测。
      _controller.runtimeResponseWritten(
        statusCode: error is AiModelProxyException ? error.statusCode : 502,
      );
      final cancel = dispatch.response.cancel;
      if (cancel != null) {
        try {
          await cancel();
        } on Object {
          // 取消逻辑已有独立超时，失败时继续关闭下游响应。
        }
      }
      if (error is! SocketException && error is! HttpException) {
        final message = switch (error) {
          AiModelProxyException error => error.message,
          AiChatException error => error.message,
          _ => '中转站流式响应失败。',
        };
        try {
          await writeSse(<String, Object?>{
            'type': 'error',
            'error': <String, Object?>{'type': 'api_error', 'message': message},
          });
        } on Object {
          // 客户端断开时无需再次写入错误事件。
        }
      }
    } finally {
      await _closeRequest(request);
    }
  }

  Future<void> _writeSse(HttpRequest request, Map<String, Object?> data) async {
    final event = _readString(data['type']);
    final payload = StringBuffer();
    if (event.isNotEmpty) payload.write('event: $event\n');
    payload.write('data: ${jsonEncode(data)}\n\n');
    await _writeSsePayload(request, payload.toString());
  }

  Future<void> _writeSsePayload(HttpRequest request, String payload) async {
    await _writeUtf8Payload(request, payload, flush: true);
  }

  static bool _isStreaming(Map<String, Object?> payload, String path) =>
      path.contains(':streamGenerateContent') ||
      payload['stream'] == true ||
      '${payload['stream']}'.toLowerCase() == 'true';

  static bool _streamIncludesUsage(Map<String, Object?> payload) {
    final options = payload['stream_options'];
    return options is Map && options['include_usage'] == true;
  }

  static Map<String, Object?> _openAiUsage(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    return const <String, Object?>{};
  }

  Map<String, Object?> _buildModelsResponse(
    AiModelProxyApiStyle style,
    Map<String, String> query,
  ) {
    final base = _dispatcher.buildModelsResponse();
    final data = base['data'];
    final allModels = data is List
        ? data
              .whereType<Map>()
              .map((item) => Map<String, Object?>.from(item))
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    if (style == AiModelProxyApiStyle.claude) {
      final page = _paginateClaudeModels(allModels, query);
      final models = page.models;
      return <String, Object?>{
        'data': models.map(_toClaudeModel).toList(growable: false),
        'has_more': page.hasMore,
        'first_id': models.isEmpty ? null : _readString(models.first['id']),
        'last_id': models.isEmpty ? null : _readString(models.last['id']),
      };
    }
    if (style == AiModelProxyApiStyle.gemini) {
      return _buildGeminiModelsResponse(query);
    }
    final page = _paginateOpenAiModels(allModels, query);
    return <String, Object?>{
      ...base,
      'data': page.models,
      'has_more': page.hasMore,
    };
  }

  Map<String, Object?> _buildGeminiModelsResponse(Map<String, String> query) {
    final base = _dispatcher.buildModelsResponse();
    final data = base['data'];
    final allModels = data is List
        ? data
              .whereType<Map>()
              .map((item) => Map<String, Object?>.from(item))
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    final filter = _readString(query['filter']);
    final filtered = filter.isEmpty
        ? allModels
        : allModels
              .where((model) => _geminiModelMatchesFilter(model, filter))
              .toList(growable: false);
    final pageSize = _queryInt(query['pageSize'], fallback: 50, max: 1000);
    final offset = _queryOffset(query['pageToken']);
    final page = offset >= filtered.length
        ? const <Map<String, Object?>>[]
        : filtered.skip(offset).take(pageSize).toList(growable: false);
    final nextOffset = offset + page.length;
    return <String, Object?>{
      'models': page.map(_toGeminiModel).toList(growable: false),
      if (nextOffset < filtered.length) 'nextPageToken': '$nextOffset',
    };
  }

  ({List<Map<String, Object?>> models, bool hasMore}) _paginateOpenAiModels(
    List<Map<String, Object?>> models,
    Map<String, String> query,
  ) {
    final result = List<Map<String, Object?>>.of(models);
    if (_readString(query['order']).toLowerCase() == 'desc') {
      result.setAll(0, result.reversed.toList(growable: false));
    }
    final before = _readString(query['before']);
    final after = _readString(query['after']);
    var start = 0;
    var end = result.length;
    if (after.isNotEmpty) {
      final index = result.indexWhere(
        (model) => _readString(model['id']) == after,
      );
      if (index >= 0) start = index + 1;
    }
    if (before.isNotEmpty) {
      final index = result.indexWhere(
        (model) => _readString(model['id']) == before,
      );
      if (index >= 0) end = index;
    }
    if (start > end) {
      return (models: const <Map<String, Object?>>[], hasMore: false);
    }
    final pageSize = _queryInt(query['limit'], fallback: 100, max: 100);
    final pageEnd = (start + pageSize).clamp(start, end).toInt();
    return (
      models: result
          .skip(start)
          .take(end - start)
          .take(pageSize)
          .toList(growable: false),
      hasMore: pageEnd < end,
    );
  }

  ({List<Map<String, Object?>> models, bool hasMore}) _paginateClaudeModels(
    List<Map<String, Object?>> models,
    Map<String, String> query,
  ) {
    final result = List<Map<String, Object?>>.of(models);
    final after = _readString(query['after_id']);
    final before = _readString(query['before_id']);
    var start = 0;
    var end = result.length;
    if (after.isNotEmpty) {
      final index = result.indexWhere(
        (model) => _readString(model['id']) == after,
      );
      if (index >= 0) start = index + 1;
    }
    if (before.isNotEmpty) {
      final index = result.indexWhere(
        (model) => _readString(model['id']) == before,
      );
      if (index >= 0) end = index;
    }
    if (start > end) {
      return (models: const <Map<String, Object?>>[], hasMore: false);
    }
    final limit = _queryInt(query['limit'], fallback: 20, max: 1000);
    final pageEnd = (start + limit).clamp(start, end).toInt();
    return (
      models: result
          .skip(start)
          .take(end - start)
          .take(limit)
          .toList(growable: false),
      hasMore: pageEnd < end,
    );
  }

  static bool _geminiModelMatchesFilter(
    Map<String, Object?> model,
    String filter,
  ) {
    final normalized = filter.trim();
    final match = RegExp(
      r"""^name\s*=\s*["']([^"']+)["']$""",
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match != null) {
      final expected = match.group(1)!.trim();
      return _readString(model['id']) == expected ||
          'models/${_readString(model['id'])}' == expected;
    }
    return _readString(model['id']).contains(normalized);
  }

  static int _queryInt(String? raw, {required int fallback, required int max}) {
    final value = int.tryParse(_readString(raw));
    return (value ?? fallback).clamp(1, max).toInt();
  }

  static int _queryOffset(String? raw) {
    final value = int.tryParse(_readString(raw));
    return (value ?? 0).clamp(0, 1 << 30).toInt();
  }

  Map<String, Object?>? _findModelMetadata(String modelId) {
    final normalizedModelId = modelId.startsWith('models/')
        ? modelId.substring('models/'.length)
        : modelId;
    final lookupKey = normalizedModelId.trim().toLowerCase();
    final data = _dispatcher.buildModelsResponse()['data'];
    if (data is! List) return null;
    for (final raw in data) {
      if (raw is! Map) continue;
      final model = Map<String, Object?>.from(raw);
      if (_readString(model['id']).toLowerCase() == lookupKey) return model;
    }
    return null;
  }

  static Map<String, Object?> _toClaudeModel(Map<String, Object?> model) {
    final created = model['created'];
    final createdAt =
        dateTimeFromValue(
          created,
          numericTimestampMode: DateTimeNumericTimestampMode.seconds,
        )?.toIso8601String() ??
        DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'type': 'model',
      'id': _readString(model['id']),
      'display_name': _readString(model['display_name'] ?? model['id']),
      'created_at': createdAt,
    };
  }

  static Map<String, Object?> _toGeminiModel(Map<String, Object?> model) {
    final id = _readString(model['id']);
    return <String, Object?>{
      'name': 'models/$id',
      'baseModelId': id,
      'displayName': _readString(model['display_name'] ?? id),
      'description': _readString(model['description']),
      if (model['context_length'] is num)
        'inputTokenLimit': model['context_length'],
      if (model['max_output_tokens'] is num)
        'outputTokenLimit': model['max_output_tokens'],
      'supportedGenerationMethods': const <String>[
        'generateContent',
        'streamGenerateContent',
      ],
    };
  }

  static String _modelIdFromGetPath(String path) {
    final prefix = path.startsWith('/v1beta/models/')
        ? '/v1beta/models/'
        : '/v1/models/';
    final value = path.substring(prefix.length);
    return decodeUriComponentOrOriginal(value).trim();
  }

  Future<Uint8List?> _loadLogoPng() async {
    final cached = _logoPng;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final data = await rootBundle.load(aiModelProxyLogoAsset);
      if (data.lengthInBytes <= 0) return null;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.isEmpty) return null;
      _logoPng = bytes;
      return bytes;
    } on Object catch (error, stack) {
      silentLog('ai_model_proxy_http_server', '加载状态页 Logo', error, stack);
      return null;
    }
  }

  Future<void> _writeBrandingAsset(
    HttpRequest request, {
    required bool headOnly,
  }) async {
    final bytes = await _loadLogoPng();
    if (bytes == null || bytes.isEmpty) {
      request.response.statusCode = 404;
      await _closeRequest(request);
      return;
    }
    try {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.parse(kImagePngMimeType)
        ..headers.set(HttpHeaders.cacheControlHeader, _logoCacheControl)
        ..headers.set('x-content-type-options', 'nosniff')
        ..contentLength = headOnly ? 0 : bytes.length;
      _applyCorsHeaders(
        request,
        methods: _corsReadMethods,
        publiclyReadable: true,
      );
      if (!headOnly) {
        request.response.add(bytes);
      }
      await request.response.close();
    } on Object {
      await _closeRequest(request);
    }
  }

  Future<void> _writeStatusPage(
    HttpRequest request, {
    required bool headOnly,
  }) async {
    final started = DateTime.now();
    var status = 200;
    var html = '';
    final look = _controller.resolveThemeLook();
    try {
      html = buildAiModelProxyStatusPage(
        controller: _controller,
        themeMode: look.themeMode,
        themePreset: look.preset,
        locale: look.locale,
        dialogAnimation: look.dialogAnimation,
        reduceMotion: look.reduceMotion,
      );
    } on Object {
      status = 500;
      html = buildAiModelProxyStatusUnavailablePage(look.locale);
    }
    final bytes = utf8.encode(html);
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
        ..headers.set(HttpHeaders.cacheControlHeader, kCacheControlNoStore)
        ..headers.set('x-content-type-options', 'nosniff')
        ..contentLength = headOnly ? 0 : bytes.length;
      _applyCorsHeaders(
        request,
        methods: _corsReadMethods,
        publiclyReadable: true,
      );
      if (!headOnly) {
        request.response.add(bytes);
      }
      await request.response.close();
    } on Object {
      await _closeRequest(request);
    }
    final outbound = headOnly ? 0 : bytes.length;
    _controller.runtimeResponseWritten(
      outboundBytes: outbound,
      statusCode: status,
    );
    _recordStatusSurface(
      request,
      started: started,
      statusCode: status,
      outboundBytes: outbound,
      error: status < 400 ? null : 'status_page_unavailable',
    );
  }

  Future<void> _writeStatusSnapshot(
    HttpRequest request, {
    required bool headOnly,
  }) async {
    final started = DateTime.now();
    var status = 200;
    var body = '{}';
    var etag = '';
    final look = _controller.resolveThemeLook();
    try {
      final snapshot = buildAiModelProxyStatusSnapshot(
        controller: _controller,
        themeMode: look.themeMode,
        themePreset: look.preset,
        locale: look.locale,
      );
      final fingerprint = Map<String, Object?>.from(snapshot)
        ..remove('generatedAt');
      etag = '"${stableJsonSha256(fingerprint)}"';
      body = jsonEncode(snapshot);
    } on Object {
      status = 500;
      body = '{"error":"status_unavailable"}';
      etag = '"${stableSha256Hex(body)}"';
    }
    final bytes = utf8.encode(body);
    final notModified =
        status == 200 && _statusSnapshotEtagMatches(request, etag);
    final responseStatus = notModified ? HttpStatus.notModified : status;
    final outbound = headOnly || notModified ? 0 : bytes.length;
    try {
      request.response
        ..statusCode = responseStatus
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.cacheControlHeader, kCacheControlNoStore)
        ..headers.set(HttpHeaders.etagHeader, etag)
        ..headers.set('x-content-type-options', 'nosniff')
        ..contentLength = outbound;
      _applyCorsHeaders(
        request,
        methods: _corsReadMethods,
        publiclyReadable: true,
      );
      if (!headOnly && !notModified) {
        request.response.add(bytes);
      }
      await request.response.close();
    } on Object {
      await _closeRequest(request);
    }
    _controller.runtimeResponseWritten(
      outboundBytes: outbound,
      statusCode: responseStatus,
    );
    _recordStatusSurface(
      request,
      started: started,
      statusCode: responseStatus,
      outboundBytes: outbound,
      error: status < 400 ? null : 'status_snapshot_unavailable',
    );
  }

  void _recordStatusSurface(
    HttpRequest request, {
    required DateTime started,
    required int statusCode,
    required int outboundBytes,
    String? error,
  }) {
    final headers = _headers(request);
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    unawaited(
      _controller.recordRequest(
        success: statusCode < 400,
        tokens: 0,
        durationMs: durationMs < 0 ? 0 : durationMs,
        error: error,
        clientIp: headers['x-client-ip'] ?? '',
        clientPort: headers['x-client-port'] ?? '',
        clientUserAgent: headers['user-agent'] ?? '',
        clientProcessId: _optionalClientHeader(
          headers,
          'x-openhand-client-pid',
        ),
        clientProcessName: _optionalClientHeader(
          headers,
          'x-openhand-client-name',
        ),
        clientServiceName: _optionalClientHeader(
          headers,
          'x-openhand-client-service',
        ),
        clientMacAddress: _optionalClientHeader(
          headers,
          'x-openhand-client-mac',
        ),
        proxyMode: aiModelProxyLocalMode,
        proxyEndpoint: _controller.publicStatusUrl,
        requestPath: _normalizePath(request.uri.path),
        inboundBytes: request.contentLength < 0 ? 0 : request.contentLength,
        outboundBytes: outboundBytes,
        statusCode: statusCode,
      ),
    );
  }

  static bool _statusSnapshotEtagMatches(HttpRequest request, String etag) {
    final raw = request.headers.value(HttpHeaders.ifNoneMatchHeader)?.trim();
    if (raw == null || raw.isEmpty) return false;
    if (raw == '*') return true;
    for (final part in raw.split(',')) {
      var token = part.trim();
      if (token.startsWith('W/')) {
        token = token.substring(2).trim();
      }
      if (token == etag) return true;
    }
    return false;
  }

  Future<void> _writeJson(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    _applyCorsHeaders(request, methods: _corsApiMethods);
    if (status != 204) {
      await _writeUtf8Payload(request, jsonEncode(body), statusCode: status);
    }
    await request.response.close();
  }

  Future<void> _writeUtf8Payload(
    HttpRequest request,
    String payload, {
    int statusCode = 200,
    bool flush = false,
  }) async {
    final bytes = utf8.encode(payload);
    request.response.add(bytes);
    _controller.runtimeResponseWritten(
      outboundBytes: bytes.length,
      statusCode: statusCode,
    );
    if (flush) await request.response.flush();
  }

  Future<void> _writeError(
    HttpRequest request,
    int status,
    String message, {
    String type = 'server_error',
    AiModelProxyApiStyle? apiStyle,
  }) async {
    try {
      final style = apiStyle ?? _controller.settings.apiStyle;
      if (status == HttpStatus.requestTimeout ||
          status == HttpStatus.requestEntityTooLarge) {
        request.response.headers.set(
          HttpHeaders.connectionHeader,
          kConnectionClose,
        );
      }
      final body = switch (style) {
        AiModelProxyApiStyle.claude => <String, Object?>{
          'type': 'error',
          'error': <String, Object?>{'type': type, 'message': message},
        },
        AiModelProxyApiStyle.gemini => <String, Object?>{
          'error': <String, Object?>{
            'code': status,
            'message': message,
            'status': _geminiErrorStatus(status),
          },
        },
        AiModelProxyApiStyle.openAiChatCompletions ||
        AiModelProxyApiStyle.openAiResponses => <String, Object?>{
          'error': <String, Object?>{
            'message': message,
            'type': type,
            'code': status,
          },
        },
      };
      await _writeJson(request, status, body);
    } on Object {
      await _closeRequest(request);
    }
  }

  static String _geminiErrorStatus(int status) => switch (status) {
    400 => 'INVALID_ARGUMENT',
    401 => 'UNAUTHENTICATED',
    403 => 'PERMISSION_DENIED',
    404 => 'NOT_FOUND',
    408 => 'DEADLINE_EXCEEDED',
    409 => 'ABORTED',
    429 => 'RESOURCE_EXHAUSTED',
    503 => 'UNAVAILABLE',
    _ => 'INTERNAL',
  };

  static String _errorTypeForStatus(int status) => switch (status) {
    400 || 422 => 'invalid_request_error',
    401 => 'authentication_error',
    403 => 'permission_error',
    404 => 'not_found_error',
    408 => 'timeout_error',
    409 || 425 || 429 => 'rate_limit_error',
    _ => 'api_error',
  };

  Future<void> _closeRequest(HttpRequest request) async {
    try {
      await request.response.close();
    } on Object {
      // 客户端提前断开时无需继续抛出异常。
    }
  }

  void _applyCorsHeaders(
    HttpRequest request, {
    required String methods,
    bool publiclyReadable = false,
  }) {
    final headers = request.response.headers;
    headers
      ..set('access-control-allow-methods', methods)
      ..set('access-control-allow-headers', _corsAllowedHeaders);
    final origin = request.headers.value('origin')?.trim() ?? '';
    if (publiclyReadable ||
        origin.isEmpty ||
        _controller.settings.requireAuthentication) {
      headers.set('access-control-allow-origin', '*');
    } else if (_isLoopbackOrigin(origin)) {
      headers
        ..set('access-control-allow-origin', origin)
        ..set('vary', 'Origin');
    }
  }

  static bool _isLoopbackOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host.endsWith('.localhost') ||
        AiModelProxyController.isLoopbackListenHost(host);
  }

  Map<String, String> _headers(HttpRequest request) {
    final result = <String, String>{};
    request.headers.forEach((name, values) {
      result[name.toLowerCase()] = values.join(',');
    });
    final queryKey =
        request.uri.queryParameters['key'] ??
        request.uri.queryParameters['api_key'] ??
        request.uri.queryParameters['x-goog-api-key'];
    if (queryKey != null && queryKey.trim().isNotEmpty) {
      result.putIfAbsent('x-goog-api-key', () => queryKey.trim());
      result.putIfAbsent('x-api-key', () => queryKey.trim());
    }
    final connectionInfo = request.connectionInfo;
    result['x-client-ip'] = connectionInfo?.remoteAddress.address ?? '';
    final remotePort = connectionInfo?.remotePort ?? 0;
    result['x-client-port'] = remotePort > 0 ? '$remotePort' : '';
    return result;
  }

  static String _optionalClientHeader(Map<String, String> headers, String key) {
    final value = headers[key]?.trim() ?? '';
    return value.length > 256 ? value.substring(0, 256) : value;
  }

  _ProxyRoute? _routeFor(String path, AiModelProxyApiStyle style) {
    if (path == '/v1/chat/completions' &&
        style == AiModelProxyApiStyle.openAiChatCompletions) {
      return _ProxyRoute.chat;
    }
    if (path == '/v1/responses' &&
        style == AiModelProxyApiStyle.openAiResponses) {
      return _ProxyRoute.responses;
    }
    if ((path == '/v1/messages' || path == '/messages') &&
        style == AiModelProxyApiStyle.claude) {
      return _ProxyRoute.claude;
    }
    if ((path.startsWith('/v1beta/models:generateContent') ||
            path.startsWith('/v1beta/models:streamGenerateContent')) &&
        style == AiModelProxyApiStyle.gemini) {
      return _ProxyRoute.gemini;
    }
    if (path.startsWith('/v1beta/models/') &&
        (path.contains(':generateContent') ||
            path.contains(':streamGenerateContent')) &&
        style == AiModelProxyApiStyle.gemini) {
      return _ProxyRoute.gemini;
    }
    return null;
  }

  static String _modelFromPath(String path, _ProxyRoute route) {
    if (route != _ProxyRoute.gemini) return '';
    const prefix = '/v1beta/models/';
    if (!path.startsWith(prefix)) return '';
    final value = path.substring(prefix.length);
    final separator = value.indexOf(':');
    final encoded = separator < 0 ? value : value.substring(0, separator);
    return decodeUriComponentOrOriginal(encoded).trim();
  }

  String _defaultGeminiModel(_ProxyRoute route) {
    if (route != _ProxyRoute.gemini) return '';
    final models = _controller.buildModelsMetadata();
    return models.length == 1 ? _readString(models.single['id']) : '';
  }

  static String _normalizePath(String path) {
    final value = path.trim();
    if (value.length > 1 && value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value.isEmpty ? '/' : value;
  }

  static String _readString(Object? value) {
    if (value is String) return value.trim();
    if (value == null) return '';
    return '$value'.trim();
  }

  static Object _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, Object?>.from(decoded) : decoded;
    } on Object {
      return const <String, Object?>{};
    }
  }

  static Object _resolveListenAddress(String host) {
    final value = normalizeAiModelProxyListenHost(host).toLowerCase();
    if (value == '*' || value == '0.0.0.0') return InternetAddress.anyIPv4;
    if (value == '::' || value == '::0') return InternetAddress.anyIPv6;
    if (value == 'localhost') return InternetAddress.loopbackIPv4;
    return InternetAddress.tryParse(value) ?? value;
  }
}

enum _ProxyRoute { chat, responses, claude, gemini }
