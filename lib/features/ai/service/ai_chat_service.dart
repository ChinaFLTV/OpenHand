import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/ai_model_config.dart';
import '../model/ai_token_usage.dart';
import 'ai_dsml_tool_call_parser.dart';
import 'ai_protocol_adapter.dart';

abstract class AiChatClient {
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools,
    List<String> responseModalities,
    Duration timeout,
  });

  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools,
    List<String> responseModalities,
    Duration timeout,
    Future<void>? cancelSignal,
  });

  Future<String> testModel(AiModelConfig model);

  void dispose();
}

class AiChatCompletion {
  const AiChatCompletion({
    required this.reply,
    this.usage,
    this.rawResponse,
    this.toolCalls = const <AiToolCall>[],
  });

  final String reply;
  final AiTokenUsage? usage;
  final String? rawResponse;
  final List<AiToolCall> toolCalls;
}

enum AiChatStreamEventType { textDelta, reasoningDelta, toolCallDelta, usage }

class AiToolCallDelta {
  const AiToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsFragment = '',
  });

  final int index;
  final String? id;
  final String? name;
  final String argumentsFragment;
}

class AiChatStreamEvent {
  const AiChatStreamEvent._({
    required this.type,
    this.textDelta,
    this.reasoningDelta,
    this.toolCallDelta,
    this.usage,
  });

  const AiChatStreamEvent.textDelta(String value)
    : this._(type: AiChatStreamEventType.textDelta, textDelta: value);

  const AiChatStreamEvent.reasoningDelta(String value)
    : this._(type: AiChatStreamEventType.reasoningDelta, reasoningDelta: value);

  const AiChatStreamEvent.toolCallDelta(AiToolCallDelta value)
    : this._(type: AiChatStreamEventType.toolCallDelta, toolCallDelta: value);

  const AiChatStreamEvent.usage(AiTokenUsage value)
    : this._(type: AiChatStreamEventType.usage, usage: value);

  final AiChatStreamEventType type;
  final String? textDelta;
  final String? reasoningDelta;
  final AiToolCallDelta? toolCallDelta;
  final AiTokenUsage? usage;
}

class AiChatStreamResult {
  const AiChatStreamResult({
    required this.reply,
    required this.reasoning,
    required this.toolCalls,
    this.wasCancelled = false,
    this.usage,
    this.rawResponse,
  });

  final String reply;
  final String reasoning;
  final List<AiToolCall> toolCalls;
  final bool wasCancelled;
  final AiTokenUsage? usage;
  final String? rawResponse;
}

class AiChatStreamingResponse {
  const AiChatStreamingResponse({
    required this.events,
    required this.result,
    this.cancel,
  });

  final Stream<AiChatStreamEvent> events;
  final Future<AiChatStreamResult> result;
  final Future<void> Function()? cancel;
}

class AiChatService implements AiChatClient {
  AiChatService({http.Client? client}) : _client = client ?? http.Client();

  static const String _availabilityProbePrompt =
      'Reply with OK only if this model configuration works.';
  static const Duration _streamIdleWarningInterval = Duration(seconds: 4);

  final http.Client _client;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
      final blueprint = await adapter.buildChatRequest(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
      );
      final response = await http.Response.fromStream(
        await _sendHttpRequestWithRedirects(
          client: _client,
          method: 'POST',
          uri: Uri.parse(blueprint.url),
          headers: blueprint.headers,
          body: jsonEncode(blueprint.body),
          timeout: timeout,
        ),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorMessage = adapter.extractErrorMessage(response.body);
        throw AiChatException(
          'HTTP ${response.statusCode}${errorMessage.isEmpty ? '' : ': $errorMessage'}',
        );
      }
      try {
        final parsedReply = await adapter.parseAssistantMessage(response.body);
        final parsedToolCalls = adapter.parseToolCalls(response.body);
        final dsmlExtraction = extractDsmlToolCalls(parsedReply);
        return AiChatCompletion(
          reply: dsmlExtraction.sanitizedText,
          usage: adapter.parseUsage(response.body),
          rawResponse: response.body,
          toolCalls: parsedToolCalls.isNotEmpty
              ? parsedToolCalls
              : dsmlExtraction.toolCalls,
        );
      } on FormatException catch (error) {
        throw AiChatException(error.message);
      }
    } on TimeoutException {
      throw const AiChatException('Request timed out.');
    } on http.ClientException catch (error) {
      throw AiChatException(error.message);
    } on SocketException catch (error) {
      throw AiChatException('Network error: ${error.message}');
    } on TlsException catch (error) {
      throw AiChatException('TLS error: ${error.message}');
    }
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    Duration timeout = const Duration(seconds: 60),
    Future<void>? cancelSignal,
  }) async {
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    if (adapter is! OpenAiProtocolAdapter || !adapter.supportsServerStreaming) {
      _debugAiStreamLog(
        'model=${model.modelId} using synthetic stream adapter=${adapter.runtimeType}',
      );
      return _sendMessageAsSyntheticStream(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
    }

    final blueprint = await adapter.buildChatRequest(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: true,
    );
    final request = http.Request('POST', Uri.parse(blueprint.url))
      ..headers.addAll(blueprint.headers)
      ..body = jsonEncode(blueprint.body);
    final streamedResponseFuture = _sendHttpRequestWithRedirects(
      client: _client,
      method: request.method,
      uri: request.url,
      headers: request.headers,
      body: request.body,
      timeout: timeout,
    );
    late final http.StreamedResponse streamedResponse;
    try {
      if (cancelSignal == null) {
        streamedResponse = await streamedResponseFuture;
      } else {
        final firstResult = await Future.any(<Future<Object?>>[
          streamedResponseFuture,
          cancelSignal.then((_) => _cancelledStreamSentinel),
        ]);
        if (identical(firstResult, _cancelledStreamSentinel)) {
          _debugAiStreamLog(
            'model=${model.modelId} stream_cancelled_before_connect',
          );
          unawaited(
            streamedResponseFuture
                .then((response) => response.stream.drain<void>())
                .catchError((Object _, StackTrace stackTrace) {}),
          );
          return AiChatStreamingResponse(
            events: const Stream<AiChatStreamEvent>.empty(),
            result: Future<AiChatStreamResult>.value(
              const AiChatStreamResult(
                reply: '',
                reasoning: '',
                toolCalls: <AiToolCall>[],
                wasCancelled: true,
              ),
            ),
          );
        }
        streamedResponse = firstResult as http.StreamedResponse;
      }
    } on TimeoutException {
      throw const AiChatException('Request timed out.');
    } on http.ClientException catch (error) {
      throw AiChatException(error.message);
    }
    _debugAiStreamLog(
      'model=${model.modelId} stream_connected status=${streamedResponse.statusCode} url=${streamedResponse.request?.url ?? blueprint.url}',
    );

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final errorBody = await streamedResponse.stream.bytesToString();
      final errorMessage = adapter.extractErrorMessage(errorBody);
      throw AiChatException(
        'HTTP ${streamedResponse.statusCode}${errorMessage.isEmpty ? '' : ': $errorMessage'}',
      );
    }
    final eventController = StreamController<AiChatStreamEvent>(sync: true);
    final resultCompleter = Completer<AiChatStreamResult>();
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final rawResponseBuffer = StringBuffer();
    final toolCalls = <int, _MutableToolCall>{};
    AiTokenUsage? usage;
    final lineBuffer = StringBuffer();
    StreamSubscription<String>? responseSubscription;
    Timer? idleWarningTimer;
    var idleWarningBucket = 0;
    var lastActivityAt = DateTime.now().toUtc();
    var lastActivityLabel = 'connected';

    bool canEmitEvents() {
      return !resultCompleter.isCompleted && !eventController.isClosed;
    }

    void markStreamActivity(String label) {
      lastActivityAt = DateTime.now().toUtc();
      lastActivityLabel = label;
      idleWarningBucket = 0;
    }

    void startIdleWarningTimer() {
      idleWarningTimer?.cancel();
      idleWarningTimer = Timer.periodic(_streamIdleWarningInterval, (_) {
        if (resultCompleter.isCompleted) {
          return;
        }
        final idleMs = DateTime.now()
            .toUtc()
            .difference(lastActivityAt)
            .inMilliseconds;
        final nextBucket = idleMs ~/ _streamIdleWarningInterval.inMilliseconds;
        if (nextBucket <= 0 || nextBucket == idleWarningBucket) {
          return;
        }
        idleWarningBucket = nextBucket;
        _debugAiStreamLog(
          'model=${model.modelId} stream_idle_warning idle_ms=$idleMs last_activity=$lastActivityLabel line_buffer=${lineBuffer.length} raw_chars=${rawResponseBuffer.length} reply_chars=${textBuffer.length} reasoning_chars=${reasoningBuffer.length} tool_calls=${toolCalls.length}',
        );
      });
    }

    void emitEvent(AiChatStreamEvent event) {
      if (!canEmitEvents()) {
        return;
      }
      eventController.add(event);
    }

    void completeStreamResult(String reason, {bool wasCancelled = false}) {
      if (resultCompleter.isCompleted) {
        return;
      }
      idleWarningTimer?.cancel();
      idleWarningTimer = null;
      final resolvedToolCalls = toolCalls.entries.toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
      final streamedReply = textBuffer.toString().trim();
      final dsmlExtraction = extractDsmlToolCalls(streamedReply);
      final resolvedParsedToolCalls = resolvedToolCalls
          .map(
            (entry) => AiToolCall(
              id: entry.value.id.isEmpty
                  ? 'tool-call-${entry.key}'
                  : entry.value.id,
              name: entry.value.name,
              arguments: entry.value.argumentsBuffer.toString(),
            ),
          )
          .where((item) => item.name.trim().isNotEmpty)
          .toList(growable: false);
      resultCompleter.complete(
        AiChatStreamResult(
          reply: dsmlExtraction.sanitizedText,
          reasoning: reasoningBuffer.toString().trim(),
          toolCalls: resolvedParsedToolCalls.isNotEmpty
              ? resolvedParsedToolCalls
              : dsmlExtraction.toolCalls,
          wasCancelled: wasCancelled,
          usage: usage,
          rawResponse: rawResponseBuffer.toString(),
        ),
      );
      _debugAiStreamLog(
        'model=${model.modelId} stream_complete reason=$reason cancelled=$wasCancelled reply_chars=${textBuffer.length} reasoning_chars=${reasoningBuffer.length} tool_calls=${resolvedToolCalls.length}',
      );
      if (!eventController.isClosed) {
        unawaited(eventController.close());
      }
    }

    void processEventBlock(String block) {
      if (resultCompleter.isCompleted) {
        return;
      }
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) {
        return;
      }
      final dataLines = trimmedBlock
          .split('\n')
          .where((line) => line.startsWith('data:'))
          .map((line) => line.substring(5).trim())
          .toList(growable: false);
      if (dataLines.isEmpty) {
        return;
      }
      final data = dataLines.join('\n');
      if (data == '[DONE]') {
        completeStreamResult('done_marker');
        unawaited(responseSubscription?.cancel());
        return;
      }
      rawResponseBuffer.writeln(data);
      late final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        return;
      }
      if (decoded is! Map<String, Object?>) {
        return;
      }
      final usageJson = decoded['usage'];
      if (usageJson is Map || usageJson is Map<String, Object?>) {
        final usageMap = usageJson is Map<String, Object?>
            ? usageJson
            : Map<String, Object?>.from(usageJson as Map);
        usage = AiTokenUsage(
          promptTokens: _readInt(usageMap['prompt_tokens']),
          completionTokens: _readInt(usageMap['completion_tokens']),
          totalTokens: _readInt(usageMap['total_tokens']),
        );
        if (usage != null && !usage!.isEmpty) {
          markStreamActivity('usage');
          _debugAiStreamLog(
            'model=${model.modelId} usage prompt=${usage!.promptTokens ?? 0} completion=${usage!.completionTokens ?? 0} total=${usage!.totalTokens ?? 0}',
          );
          emitEvent(AiChatStreamEvent.usage(usage!));
        }
      }
      final choices = decoded['choices'];
      if (choices is! List<dynamic>) {
        return;
      }
      for (final choice in choices) {
        if (choice is! Map<String, Object?>) {
          continue;
        }
        final delta = choice['delta'];
        if (delta is! Map<String, Object?>) {
          continue;
        }
        final textDelta = _extractStreamText(delta['content']);
        if (textDelta.isNotEmpty) {
          textBuffer.write(textDelta);
          markStreamActivity('text_delta');
          _debugAiStreamLog(
            'model=${model.modelId} text_delta chars=${textDelta.length}',
          );
          emitEvent(AiChatStreamEvent.textDelta(textDelta));
        }
        final reasoningDelta = _extractReasoningText(delta);
        if (reasoningDelta.isNotEmpty) {
          reasoningBuffer.write(reasoningDelta);
          markStreamActivity('reasoning_delta');
          _debugAiStreamLog(
            'model=${model.modelId} reasoning_delta chars=${reasoningDelta.length}',
          );
          emitEvent(AiChatStreamEvent.reasoningDelta(reasoningDelta));
        }
        final toolCallJson = delta['tool_calls'];
        if (toolCallJson is! List) {
          continue;
        }
        for (final rawToolCall in toolCallJson) {
          if (rawToolCall is! Map) {
            continue;
          }
          final toolCallMap = Map<String, Object?>.from(rawToolCall);
          final index = _readInt(toolCallMap['index']) ?? 0;
          final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
          final id = '${toolCallMap['id'] ?? ''}'.trim();
          if (id.isNotEmpty) {
            entry.id = id;
          }
          final function = toolCallMap['function'];
          if (function is Map) {
            final functionMap = Map<String, Object?>.from(function);
            final name = '${functionMap['name'] ?? ''}'.trim();
            if (name.isNotEmpty) {
              entry.name = name;
            }
            final argumentsFragment = '${functionMap['arguments'] ?? ''}';
            if (argumentsFragment.isNotEmpty) {
              entry.argumentsBuffer.write(argumentsFragment);
            }
            markStreamActivity('tool_call_delta');
            _debugAiStreamLog(
              'model=${model.modelId} tool_call_delta index=$index name=${entry.name} arg_chars=${argumentsFragment.length}',
            );
            emitEvent(
              AiChatStreamEvent.toolCallDelta(
                AiToolCallDelta(
                  index: index,
                  id: entry.id,
                  name: entry.name,
                  argumentsFragment: argumentsFragment,
                ),
              ),
            );
          }
        }
      }
    }

    void processChunk(String chunk) {
      markStreamActivity('chunk');
      lineBuffer.write(chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
      while (!resultCompleter.isCompleted) {
        // Avoid calling toString() on every iteration – check length first.
        if (lineBuffer.length < 2) {
          break;
        }
        final current = lineBuffer.toString();
        final separatorIndex = current.indexOf('\n\n');
        if (separatorIndex == -1) {
          break;
        }
        final block = current.substring(0, separatorIndex);
        final remaining = current.substring(separatorIndex + 2);
        lineBuffer
          ..clear()
          ..write(remaining);
        processEventBlock(block);
      }
    }

    responseSubscription = streamedResponse.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .timeout(timeout)
        .listen(
          processChunk,
          onError: (Object error, StackTrace stackTrace) {
            idleWarningTimer?.cancel();
            idleWarningTimer = null;
            _debugAiStreamLog(
              'model=${model.modelId} stream_error error=$error',
            );
            if (!resultCompleter.isCompleted) {
              resultCompleter.completeError(
                error is TimeoutException
                    ? const AiChatException('Request timed out.')
                    : AiChatException('$error'),
                stackTrace,
              );
            }
            if (!eventController.isClosed) {
              unawaited(eventController.close());
            }
          },
          onDone: () {
            idleWarningTimer?.cancel();
            idleWarningTimer = null;
            if (lineBuffer.isNotEmpty) {
              processEventBlock(lineBuffer.toString());
            }
            completeStreamResult('stream_closed');
          },
          cancelOnError: true,
        );
    startIdleWarningTimer();

    return AiChatStreamingResponse(
      events: eventController.stream,
      result: resultCompleter.future,
      cancel: () async {
        idleWarningTimer?.cancel();
        idleWarningTimer = null;
        _debugAiStreamLog('model=${model.modelId} cancel_requested');
        completeStreamResult('cancelled', wasCancelled: true);
        await responseSubscription?.cancel();
      },
    );
  }

  Future<AiChatStreamingResponse> _sendMessageAsSyntheticStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required List<String> responseModalities,
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
    final controller = StreamController<AiChatStreamEvent>(sync: true);
    final completer = Completer<AiChatStreamResult>();
    var cancelled = false;

    void completeCancelled() {
      if (cancelled) {
        return;
      }
      cancelled = true;
      if (!completer.isCompleted) {
        completer.complete(
          const AiChatStreamResult(
            reply: '',
            reasoning: '',
            toolCalls: <AiToolCall>[],
            wasCancelled: true,
          ),
        );
      }
    }

    unawaited(() async {
      try {
        final completionFuture = sendMessage(
          model: model,
          messages: messages,
          tools: tools,
          responseModalities: responseModalities,
          timeout: timeout,
        );
        final completion = cancelSignal == null
            ? await completionFuture
            : await Future.any(<Future<Object?>>[
                completionFuture,
                cancelSignal.then((_) => _cancelledStreamSentinel),
              ]).then((value) {
                if (identical(value, _cancelledStreamSentinel)) {
                  completeCancelled();
                  throw _SyntheticStreamCancelledException();
                }
                return value! as AiChatCompletion;
              });
        if (cancelled) {
          return;
        }
        if (completion.reply.isNotEmpty) {
          controller.add(AiChatStreamEvent.textDelta(completion.reply));
        }
        if (completion.usage != null && !completion.usage!.isEmpty) {
          controller.add(AiChatStreamEvent.usage(completion.usage!));
        }
        if (!completer.isCompleted) {
          completer.complete(
            AiChatStreamResult(
              reply: completion.reply,
              reasoning: '',
              toolCalls: completion.toolCalls,
              usage: completion.usage,
              rawResponse: completion.rawResponse,
            ),
          );
        }
      } catch (error, stackTrace) {
        if (error is _SyntheticStreamCancelledException) {
          return;
        }
        if (!cancelled && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        await controller.close();
      }
    }());
    return AiChatStreamingResponse(
      events: controller.stream,
      result: completer.future,
      cancel: () async {
        completeCancelled();
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    if (model.normalizedBaseUrl.isEmpty) {
      throw const AiChatException('Missing base URL.');
    }
    if (model.modelId.trim().isEmpty) {
      throw const AiChatException('Missing model ID.');
    }
    final reply = await sendMessage(
      model: model,
      messages: const <AiChatTurn>[
        AiChatTurn(role: AiChatRole.user, content: _availabilityProbePrompt),
      ],
      timeout: const Duration(seconds: 20),
    );
    final normalizedReply = reply.reply.trim();
    if (normalizedReply.isEmpty) {
      throw const AiChatException('Empty assistant reply.');
    }
    return normalizedReply;
  }

  @override
  void dispose() {
    _client.close();
  }
}

const Object _cancelledStreamSentinel = Object();

class _SyntheticStreamCancelledException implements Exception {}

void _debugAiStreamLog(String message) {
  return;
}

class AiChatException implements Exception {
  const AiChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _MutableToolCall {
  String id = '';
  String name = '';
  final StringBuffer argumentsBuffer = StringBuffer();
}

const int _maxAiChatRedirects = 4;

Future<http.StreamedResponse> _sendHttpRequestWithRedirects({
  required http.Client client,
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  String? body,
  required Duration timeout,
}) async {
  var currentMethod = method;
  var currentUri = uri;
  var currentBody = body;
  final currentHeaders = Map<String, String>.from(headers);

  for (var redirectCount = 0; ; redirectCount++) {
    final request = http.Request(currentMethod, currentUri)
      ..followRedirects = false
      ..headers.addAll(currentHeaders);
    if (currentBody != null) {
      request.body = currentBody;
    }

    final response = await client.send(request).timeout(timeout);
    if (!_isRedirectStatusCode(response.statusCode)) {
      return response;
    }

    final redirectLocation = _readResponseHeader(response.headers, 'location');
    if (redirectLocation.isEmpty) {
      return response;
    }
    if (redirectCount >= _maxAiChatRedirects) {
      final responseBody = await response.stream.bytesToString();
      throw AiChatException(
        'Too many redirects (${_maxAiChatRedirects + 1})${responseBody.trim().isEmpty ? '' : ': ${responseBody.trim()}'}',
      );
    }

    await response.stream.drain<void>();
    final redirectedUri = currentUri.resolve(redirectLocation);
    if (_isCrossOriginRedirect(currentUri, redirectedUri)) {
      _stripSensitiveRedirectHeaders(currentHeaders);
    }
    currentUri = redirectedUri;
    if (response.statusCode == 303 &&
        currentMethod != 'GET' &&
        currentMethod != 'HEAD') {
      currentMethod = 'GET';
      currentBody = null;
    }
  }
}

bool _isRedirectStatusCode(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

bool _isCrossOriginRedirect(Uri source, Uri target) {
  return source.scheme != target.scheme ||
      source.host != target.host ||
      _effectivePort(source) != _effectivePort(target);
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => -1,
  };
}

void _stripSensitiveRedirectHeaders(Map<String, String> headers) {
  const sensitiveHeaderNames = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
    'x-api-key',
    'api-key',
  };
  headers.removeWhere(
    (name, value) => sensitiveHeaderNames.contains(name.toLowerCase()),
  );
}

String _readResponseHeader(Map<String, String> headers, String name) {
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value.trim();
    }
  }
  return '';
}

String _extractStreamText(Object? rawContent) {
  if (rawContent is String) {
    return rawContent;
  }
  if (rawContent is List) {
    final buffer = StringBuffer();
    for (final item in rawContent) {
      if (item is String) {
        buffer.write(item);
        continue;
      }
      if (item is! Map) {
        continue;
      }
      final itemMap = Map<String, Object?>.from(item);
      final text = '${itemMap['text'] ?? itemMap['content'] ?? ''}';
      if (text.isNotEmpty) {
        buffer.write(text);
      }
    }
    return buffer.toString();
  }
  return '';
}

String _extractReasoningText(Map<String, Object?> delta) {
  final directReasoning =
      _extractStreamText(delta['reasoning_content']) +
      _extractStreamText(delta['reasoning']);
  if (directReasoning.isNotEmpty) {
    return directReasoning;
  }
  final reasoningDetails = delta['reasoning_details'];
  if (reasoningDetails is! List) {
    return '';
  }
  final buffer = StringBuffer();
  for (final item in reasoningDetails) {
    if (item is! Map) {
      continue;
    }
    final itemMap = Map<String, Object?>.from(item);
    final text = '${itemMap['text'] ?? itemMap['content'] ?? ''}';
    if (text.isNotEmpty) {
      buffer.write(text);
    }
  }
  return buffer.toString();
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    final coercedValue = value.toInt();
    return value == coercedValue ? coercedValue : null;
  }
  final rawText = '${value ?? ''}'.trim();
  if (rawText.isEmpty) {
    return null;
  }
  final parsedInt = int.tryParse(rawText);
  if (parsedInt != null) {
    return parsedInt;
  }
  final parsedDouble = double.tryParse(rawText);
  if (parsedDouble == null) {
    return null;
  }
  final coercedValue = parsedDouble.toInt();
  return parsedDouble == coercedValue ? coercedValue : null;
}
