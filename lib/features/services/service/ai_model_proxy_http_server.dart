import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../shared/net/bounded_server_bind.dart';
import '../../ai/index.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';
import 'ai_model_proxy_dispatcher.dart';

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

  static const int _maxRequestBodyBytes = 8 * 1024 * 1024;
  static const int _maxConcurrentRequests = 16;
  static const Duration _bindTimeout = Duration(seconds: 10);
  static const Duration _requestReadTimeout = Duration(seconds: 30);
  static const Duration _requestKeepAliveTimeout = Duration(seconds: 30);

  final AiModelProxyController _controller;
  final AiModelProxyDispatcher _dispatcher;
  HttpServer? _server;
  int _activeRequests = 0;
  bool _closing = false;

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
    unawaited(_serve(server));
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
    try {
      await for (final request in server) {
        if (_server != server || _closing) {
          await _closeRequest(request);
          continue;
        }
        if (_activeRequests >= _maxConcurrentRequests) {
          await _writeError(
            request,
            429,
            '当前中转站请求过多，请稍后重试。',
            type: 'rate_limit_error',
          );
          continue;
        }
        _activeRequests += 1;
        unawaited(
          _handleRequest(request).whenComplete(() {
            _activeRequests = (_activeRequests - 1).clamp(0, 1 << 30);
          }),
        );
      }
    } on Object {
      // 服务器关闭会结束迭代；其他监听异常由控制器的下一次启动兜底。
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
      if (!_controller.authorize(_headers(request))) {
        await _writeError(
          request,
          401,
          'API 鉴权失败。',
          type: 'authentication_error',
        );
        return;
      }
      if (method == 'GET' && path == '/v1/models') {
        await _writeJson(request, 200, _dispatcher.buildModelsResponse());
        return;
      }
      if (method == 'GET' && path == '/models') {
        await _writeJson(request, 200, _dispatcher.buildModelsResponse());
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

      final style = _controller.settings.apiStyle;
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
      final payload = await _readJsonBody(request);
      final messages = _parseMessages(payload, route);
      if (messages.isEmpty) {
        await _writeError(
          request,
          400,
          '请求中缺少有效的消息内容。',
          type: 'invalid_request_error',
        );
        return;
      }
      final payloadModel = _readString(payload['model']);
      final requestedModel = payloadModel.isNotEmpty
          ? payloadModel
          : _modelFromPath(path, route);
      if (requestedModel.isEmpty) {
        await _writeError(
          request,
          400,
          '请求中缺少 model。',
          type: 'invalid_request_error',
        );
        return;
      }
      final result = await _dispatcher.dispatch(
        exposedModel: requestedModel,
        messages: messages,
        headers: _headers(request),
      );
      final response = _buildResponse(result, route, requestedModel);
      if (_isStreaming(payload)) {
        await _writeStreamingResponse(request, response, route);
      } else {
        await _writeJson(request, 200, response);
      }
    } on AiModelProxyException catch (error) {
      await _writeError(request, error.statusCode, error.message);
    } on FormatException catch (error) {
      await _writeError(
        request,
        400,
        '请求 JSON 无效：${error.message}',
        type: 'invalid_request_error',
      );
    } on TimeoutException {
      await _writeError(request, 408, '请求读取超时。', type: 'timeout_error');
    } on SocketException catch (error) {
      await _writeError(request, 503, '中转站网络服务不可用：${error.message}');
    } on Object catch (error) {
      await _writeError(request, 500, '中转站处理请求失败：$error');
    }
  }

  Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
    final contentLength = request.contentLength;
    if (contentLength > _maxRequestBodyBytes) {
      throw const AiModelProxyException(413, '请求体过大。');
    }
    final builder = BytesBuilder(copy: false);
    var total = 0;
    try {
      await for (final chunk in request.timeout(_requestReadTimeout)) {
        total += chunk.length;
        if (total > _maxRequestBodyBytes) {
          throw const AiModelProxyException(413, '请求体过大。');
        }
        builder.add(chunk);
      }
    } on TimeoutException {
      throw TimeoutException('请求体读取超时。');
    }
    final text = utf8.decode(builder.takeBytes(), allowMalformed: false).trim();
    if (text.isEmpty) throw const FormatException('请求体不能为空。');
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('请求体必须是 JSON 对象。');
    return Map<String, Object?>.from(decoded);
  }

  List<AiChatTurn> _parseMessages(Object? raw, _ProxyRoute route) {
    final payload = raw is Map
        ? Map<String, Object?>.from(raw)
        : const <String, Object?>{};
    return switch (route) {
      _ProxyRoute.chat => _parseChatMessages(payload['messages']),
      _ProxyRoute.responses => _parseResponsesInput(payload['input']),
      _ProxyRoute.claude => _parseClaudeMessages(payload),
      _ProxyRoute.gemini => _parseGeminiMessages(payload['contents']),
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
    if (raw is! List) return const <AiChatTurn>[];
    final result = <AiChatTurn>[];
    for (final item in raw.take(256)) {
      if (item is String) {
        result.add(AiChatTurn(role: AiChatRole.user, content: item));
      } else if (item is Map) {
        final map = Map<String, Object?>.from(item);
        final role = _parseRole(map['role']);
        final text = _extractText(
          map['content'] ?? map['text'] ?? map['input'],
        );
        if (role != null && text.trim().isNotEmpty) {
          result.add(AiChatTurn(role: role, content: text));
        }
      }
    }
    return result;
  }

  List<AiChatTurn> _parseClaudeMessages(Map<String, Object?> payload) {
    final result = <AiChatTurn>[];
    final system = _extractText(payload['system']);
    if (system.trim().isNotEmpty) {
      result.add(AiChatTurn(role: AiChatRole.system, content: system));
    }
    result.addAll(_parseChatMessages(payload['messages']));
    return result;
  }

  List<AiChatTurn> _parseGeminiMessages(Object? raw) {
    if (raw is! List) return const <AiChatTurn>[];
    final result = <AiChatTurn>[];
    for (final item in raw.take(256)) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.from(item);
      final role = '${map['role'] ?? 'user'}'.toLowerCase() == 'model'
          ? AiChatRole.assistant
          : AiChatRole.user;
      final text = _extractGeminiText(map['parts']);
      if (text.trim().isNotEmpty) {
        result.add(AiChatTurn(role: role, content: text));
      }
    }
    return result;
  }

  AiChatTurn? _parseMessage(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final role = _parseRole(map['role']);
    if (role == null) return null;
    final content = _extractText(map['content']);
    if (content.trim().isEmpty) return null;
    return AiChatTurn(role: role, content: content);
  }

  AiChatRole? _parseRole(Object? value) => switch ('$value'.toLowerCase()) {
    'system' => AiChatRole.system,
    'user' => AiChatRole.user,
    'assistant' || 'model' => AiChatRole.assistant,
    'tool' => AiChatRole.tool,
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
    String requestedModel,
  ) {
    final id = 'openhand-${DateTime.now().microsecondsSinceEpoch}';
    final usage = result.usage;
    final inputTokens = usage?.promptTokens ?? 0;
    final outputTokens = usage?.completionTokens ?? 0;
    final usageJson = <String, Object?>{
      'prompt_tokens': inputTokens,
      'completion_tokens': outputTokens,
      'total_tokens': usage?.totalTokens ?? inputTokens + outputTokens,
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
              'content': result.reply,
            },
            'finish_reason': 'stop',
          },
        ],
        'usage': usageJson,
      },
      _ProxyRoute.responses => <String, Object?>{
        'id': id,
        'object': 'response',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'status': 'completed',
        'model': requestedModel,
        'output': <Object?>[
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
        ],
        'output_text': result.reply,
        'usage': <String, Object?>{
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
          'total_tokens': usage?.totalTokens ?? inputTokens + outputTokens,
        },
      },
      _ProxyRoute.claude => <String, Object?>{
        'id': id,
        'type': 'message',
        'role': 'assistant',
        'model': requestedModel,
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': result.reply},
        ],
        'stop_reason': 'end_turn',
        'usage': <String, Object?>{
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
        },
      },
      _ProxyRoute.gemini => <String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'role': 'model',
              'parts': <Object?>[
                <String, Object?>{'text': result.reply},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
        'usageMetadata': <String, Object?>{
          'promptTokenCount': inputTokens,
          'candidatesTokenCount': outputTokens,
          'totalTokenCount': usage?.totalTokens ?? inputTokens + outputTokens,
        },
      },
    };
  }

  Future<void> _writeStreamingResponse(
    HttpRequest request,
    Map<String, Object?> response,
    _ProxyRoute route,
  ) async {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set('cache-control', 'no-cache')
      ..headers.set('access-control-allow-origin', '*')
      ..headers.set('connection', 'keep-alive');
    final id = _readString(response['id']);
    final model = _readString(response['model']);
    switch (route) {
      case _ProxyRoute.chat:
        _writeSse(request, <String, Object?>{
          'id': id,
          'object': 'chat.completion.chunk',
          'created': response['created'],
          'model': model,
          'choices': <Object?>[
            <String, Object?>{
              'index': 0,
              'delta': <String, Object?>{
                'role': 'assistant',
                'content': _chatReply(response),
              },
              'finish_reason': null,
            },
          ],
        });
        _writeSse(request, <String, Object?>{
          'id': id,
          'object': 'chat.completion.chunk',
          'created': response['created'],
          'model': model,
          'choices': <Object?>[
            <String, Object?>{
              'index': 0,
              'delta': const <String, Object?>{},
              'finish_reason': 'stop',
            },
          ],
        });
      case _ProxyRoute.responses:
        _writeSse(request, <String, Object?>{
          'type': 'response.created',
          'response': response,
        });
        _writeSse(request, <String, Object?>{
          'type': 'response.output_text.delta',
          'item_id': '$id-output',
          'output_index': 0,
          'content_index': 0,
          'delta': _readString(response['output_text']),
        });
        _writeSse(request, <String, Object?>{
          'type': 'response.completed',
          'response': response,
        });
      case _ProxyRoute.claude:
        _writeSse(request, <String, Object?>{
          'type': 'message_start',
          'message': response,
        });
        _writeSse(request, <String, Object?>{
          'type': 'content_block_delta',
          'index': 0,
          'delta': <String, Object?>{
            'type': 'text_delta',
            'text': _claudeReply(response),
          },
        });
        _writeSse(request, <String, Object?>{'type': 'message_stop'});
      case _ProxyRoute.gemini:
        _writeSse(request, response);
    }
    if (route == _ProxyRoute.chat || route == _ProxyRoute.responses) {
      request.response.write('data: [DONE]\n\n');
    }
    await request.response.close();
  }

  static void _writeSse(HttpRequest request, Map<String, Object?> data) {
    final event = _readString(data['type']);
    if (event.isNotEmpty) request.response.write('event: $event\n');
    request.response.write('data: ${jsonEncode(data)}\n\n');
  }

  static String _chatReply(Map<String, Object?> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final choice = Map<String, Object?>.from(choices.first as Map);
    final message = choice['message'];
    return message is Map
        ? _readString(Map<String, Object?>.from(message)['content'])
        : '';
  }

  static String _claudeReply(Map<String, Object?> response) {
    final content = response['content'];
    if (content is! List || content.isEmpty || content.first is! Map) return '';
    return _readString(Map<String, Object?>.from(content.first as Map)['text']);
  }

  static bool _isStreaming(Map<String, Object?> payload) =>
      payload['stream'] == true ||
      '${payload['stream']}'.toLowerCase() == 'true';

  Future<void> _writeJson(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('access-control-allow-origin', '*')
      ..headers.set(
        'access-control-allow-headers',
        'authorization, content-type, x-api-key',
      );
    if (status != 204) request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _writeError(
    HttpRequest request,
    int status,
    String message, {
    String type = 'server_error',
  }) async {
    try {
      await _writeJson(request, status, <String, Object?>{
        'error': <String, Object?>{
          'message': message,
          'type': type,
          'code': status,
        },
      });
    } on Object {
      await _closeRequest(request);
    }
  }

  Future<void> _closeRequest(HttpRequest request) async {
    try {
      await request.response.close();
    } on Object {
      // 客户端提前断开时无需继续抛出异常。
    }
  }

  Map<String, String> _headers(HttpRequest request) {
    final result = <String, String>{};
    request.headers.forEach((name, values) {
      result[name.toLowerCase()] = values.join(',');
    });
    result['x-client-ip'] = request.connectionInfo?.remoteAddress.address ?? '';
    result['x-client-port'] = '${request.connectionInfo?.remotePort ?? ''}';
    return result;
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
    if (path == '/v1/messages' && style == AiModelProxyApiStyle.claude) {
      return _ProxyRoute.claude;
    }
    if (path.startsWith('/v1beta/models:generateContent') &&
        style == AiModelProxyApiStyle.gemini) {
      return _ProxyRoute.gemini;
    }
    if (path.startsWith('/v1beta/models/') &&
        path.contains(':generateContent') &&
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
    return (separator < 0 ? value : value.substring(0, separator)).trim();
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

  static Object _resolveListenAddress(String host) {
    final value = host.trim().toLowerCase();
    if (value == '*' || value == '0.0.0.0') return InternetAddress.anyIPv4;
    if (value == '::' || value == '[::]') return InternetAddress.anyIPv6;
    if (value == 'localhost') return InternetAddress.loopbackIPv4;
    return InternetAddress.tryParse(value) ?? value;
  }
}

enum _ProxyRoute { chat, responses, claude, gemini }
