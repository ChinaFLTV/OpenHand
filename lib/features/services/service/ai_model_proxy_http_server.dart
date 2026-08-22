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
      if (_isStreaming(payload)) {
        final stream = await _dispatcher.dispatchStream(
          exposedModel: requestedModel,
          messages: messages,
          request: payload,
          headers: _headers(request),
        );
        await _writeNativeStreamingResponse(
          request,
          stream,
          route,
          requestedModel,
          includeUsage: _streamIncludesUsage(payload),
        );
        return;
      }
      final result = await _dispatcher.dispatch(
        exposedModel: requestedModel,
        messages: messages,
        request: payload,
        headers: _headers(request),
      );
      final response = _buildResponse(result, route, requestedModel);
      await _writeJson(request, 200, response);
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
    if (raw is! List) return const <AiChatTurn>[];
    final result = <AiChatTurn>[];
    for (final item in raw.take(256)) {
      if (item is String) {
        result.add(AiChatTurn(role: AiChatRole.user, content: item));
      } else if (item is Map) {
        final map = Map<String, Object?>.from(item);
        final type = _readString(map['type']);
        final role = _parseRole(
          map['role'] ?? (type == 'message' ? 'assistant' : null),
        );
        final text = _extractText(
          map['content'] ?? map['text'] ?? map['input'],
        );
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
            (text.trim().isNotEmpty ||
                toolCallId.isNotEmpty ||
                functionCalls.isNotEmpty)) {
          result.add(
            AiChatTurn(
              role: effectiveRole,
              content: text,
              toolCallId: toolCallId.isEmpty ? null : toolCallId,
              toolCalls: functionCalls,
              reasoningContent:
                  _readString(
                    map['reasoning_content'] ?? map['reasoning'],
                  ).isEmpty
                  ? null
                  : _readString(map['reasoning_content'] ?? map['reasoning']),
            ),
          );
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
              if (thinking.isNotEmpty) textParts.add(thinking);
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
        final effectiveRole = toolCallId.isNotEmpty ? AiChatRole.tool : role;
        if (text.isNotEmpty || toolCalls.isNotEmpty || toolCallId.isNotEmpty) {
          result.add(
            AiChatTurn(
              role: effectiveRole,
              content: text,
              toolCallId: toolCallId.isEmpty ? null : toolCallId,
              toolCalls: toolCalls,
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
          }
        }
      }
      final effectiveRole = toolCallId.isNotEmpty ? AiChatRole.tool : role;
      if (text.trim().isNotEmpty ||
          toolCalls.isNotEmpty ||
          toolCallId.isNotEmpty) {
        result.add(
          AiChatTurn(
            role: effectiveRole,
            content: text,
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
    final content = _extractText(map['content']);
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
              if (result.reasoningContent != null)
                'reasoning_content': result.reasoningContent,
              if (result.toolCalls.isNotEmpty)
                'tool_calls': result.toolCalls
                    .map((call) => call.toOpenAiJson())
                    .toList(growable: false),
            },
            'finish_reason': result.toolCalls.isNotEmpty
                ? 'tool_calls'
                : 'stop',
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

  Future<void> _writeNativeStreamingResponse(
    HttpRequest request,
    AiModelProxyStreamDispatch dispatch,
    _ProxyRoute route,
    String requestedModel, {
    required bool includeUsage,
  }) async {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set('cache-control', 'no-cache')
      ..headers.set('connection', 'keep-alive')
      ..headers.set('access-control-allow-origin', '*')
      ..headers.set('access-control-allow-methods', 'GET, POST, OPTIONS')
      ..headers.set(
        'access-control-allow-headers',
        'authorization, content-type, x-api-key, anthropic-version',
      );
    final id = 'openhand-${DateTime.now().microsecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (route == _ProxyRoute.chat) {
      _writeSse(request, <String, Object?>{
        'id': id,
        'object': 'chat.completion.chunk',
        'created': created,
        'model': requestedModel,
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'delta': <String, Object?>{'role': 'assistant'},
            'finish_reason': null,
          },
        ],
      });
    } else if (route == _ProxyRoute.claude) {
      _writeSse(request, <String, Object?>{
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
      _writeSse(request, <String, Object?>{
        'type': 'response.created',
        'response': <String, Object?>{
          'id': id,
          'object': 'response',
          'status': 'in_progress',
          'model': requestedModel,
          'output': const <Object?>[],
        },
      });
    }
    var toolBlockIndex = 0;
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
              _writeSse(request, <String, Object?>{
                'id': id,
                'object': 'chat.completion.chunk',
                'created': created,
                'model': requestedModel,
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
              _writeSse(request, <String, Object?>{
                'type': 'response.output_text.delta',
                'item_id': '$id-output',
                'output_index': 0,
                'content_index': 0,
                'delta': event.textDelta ?? '',
              });
            } else if (event.type == AiChatStreamEventType.reasoningDelta) {
              _writeSse(request, <String, Object?>{
                'type': 'response.reasoning_summary_text.delta',
                'item_id': '$id-reasoning',
                'output_index': 0,
                'summary_index': 0,
                'delta': event.reasoningDelta ?? '',
              });
            } else if (event.type == AiChatStreamEventType.toolCallDelta) {
              final call = event.toolCallDelta!;
              _writeSse(request, <String, Object?>{
                'type': 'response.function_call_arguments.delta',
                'item_id': call.id ?? '$id-tool-${call.index}',
                'output_index': call.index,
                'delta': call.argumentsFragment,
              });
            }
          case _ProxyRoute.claude:
            if (event.type == AiChatStreamEventType.textDelta) {
              _writeSse(request, <String, Object?>{
                'type': 'content_block_delta',
                'index': 0,
                'delta': <String, Object?>{
                  'type': 'text_delta',
                  'text': event.textDelta ?? '',
                },
              });
            } else if (event.type == AiChatStreamEventType.reasoningDelta) {
              _writeSse(request, <String, Object?>{
                'type': 'content_block_delta',
                'index': 0,
                'delta': <String, Object?>{
                  'type': 'thinking_delta',
                  'thinking': event.reasoningDelta ?? '',
                },
              });
            } else if (event.type == AiChatStreamEventType.toolCallDelta) {
              final call = event.toolCallDelta!;
              final index = toolBlockIndex++;
              _writeSse(request, <String, Object?>{
                'type': 'content_block_start',
                'index': index,
                'content_block': <String, Object?>{
                  'type': 'tool_use',
                  'id': call.id ?? '$id-tool-${call.index}',
                  'name': call.name ?? '',
                  'input': const <String, Object?>{},
                },
              });
              if (call.argumentsFragment.isNotEmpty) {
                _writeSse(request, <String, Object?>{
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
              _writeSse(request, <String, Object?>{
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
      final response = _buildResponse(
        AiModelProxyDispatchResult(
          reply: streamResult.reply,
          exposedModel: dispatch.exposedModel,
          backend: dispatch.backend,
          durationMs: 0,
          usage: streamResult.usage,
          reasoningContent: streamResult.reasoning,
          toolCalls: streamResult.toolCalls,
        ),
        route,
        requestedModel,
      );
      switch (route) {
        case _ProxyRoute.chat:
          _writeSse(request, <String, Object?>{
            'id': id,
            'object': 'chat.completion.chunk',
            'created': created,
            'model': requestedModel,
            'choices': <Object?>[
              <String, Object?>{
                'index': 0,
                'delta': const <String, Object?>{},
                'finish_reason': streamResult.toolCalls.isNotEmpty
                    ? 'tool_calls'
                    : 'stop',
              },
            ],
            if (includeUsage) 'usage': _openAiUsage(response['usage']),
          });
          request.response.write('data: [DONE]\n\n');
        case _ProxyRoute.responses:
          _writeSse(request, <String, Object?>{
            'type': 'response.completed',
            'response': response,
          });
          request.response.write('data: [DONE]\n\n');
        case _ProxyRoute.claude:
          _writeSse(request, <String, Object?>{
            'type': 'message_delta',
            'delta': <String, Object?>{
              'stop_reason': streamResult.toolCalls.isNotEmpty
                  ? 'tool_use'
                  : 'end_turn',
              'stop_sequence': null,
            },
            'usage': response['usage'],
          });
          _writeSse(request, <String, Object?>{'type': 'message_stop'});
        case _ProxyRoute.gemini:
          _writeSse(request, <String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{'finishReason': 'STOP'},
            ],
            'usageMetadata': response['usageMetadata'],
          });
      }
    } on Object catch (error) {
      _writeSse(request, <String, Object?>{
        'type': 'error',
        'error': <String, Object?>{'message': '$error'},
      });
    } finally {
      await request.response.close();
    }
  }

  static void _writeSse(HttpRequest request, Map<String, Object?> data) {
    final event = _readString(data['type']);
    if (event.isNotEmpty) request.response.write('event: $event\n');
    request.response.write('data: ${jsonEncode(data)}\n\n');
  }

  static bool _isStreaming(Map<String, Object?> payload) =>
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

  Future<void> _writeJson(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('access-control-allow-origin', '*')
      ..headers.set('access-control-allow-methods', 'GET, POST, OPTIONS')
      ..headers.set(
        'access-control-allow-headers',
        'authorization, content-type, x-api-key, anthropic-version',
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

  static Object _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, Object?>.from(decoded) : decoded;
    } on Object {
      return const <String, Object?>{};
    }
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
