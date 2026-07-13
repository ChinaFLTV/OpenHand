import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_sse_data_parser.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_files_service.dart';
import 'ai_models_service.dart';
import 'ai_operation_http.dart';

typedef AiMiniMaxStreamEventCallback =
    FutureOr<void> Function(Map<String, Object?> event);

class AiMiniMaxApiException implements Exception {
  const AiMiniMaxApiException(
    this.message, {
    required this.operation,
    this.httpStatus,
    this.providerStatus,
    this.rawResponse,
  });

  final String message;
  final String operation;
  final int? httpStatus;
  final int? providerStatus;
  final String? rawResponse;

  @override
  String toString() => message;
}

class AiMiniMaxJsonResponse {
  const AiMiniMaxJsonResponse({
    required this.payload,
    required this.rawResponse,
    required this.statusCode,
    required this.headers,
  });

  final Map<String, Object?> payload;
  final String rawResponse;
  final int statusCode;
  final Map<String, String> headers;
}

class AiMiniMaxStreamSummary {
  const AiMiniMaxStreamSummary({
    required this.eventCount,
    required this.lastEvent,
    required this.statusCode,
    required this.headers,
  });

  final int eventCount;
  final Map<String, Object?>? lastEvent;
  final int statusCode;
  final Map<String, String> headers;
}

class AiMiniMaxWebSocketSpeechResult {
  const AiMiniMaxWebSocketSpeechResult({
    required this.audioBytes,
    required this.events,
    required this.audioFormat,
  });

  final Uint8List audioBytes;
  final List<Map<String, Object?>> events;
  final String audioFormat;
}

/// Native MiniMax API facade.
///
/// The app's chat and media services provide the user-facing integrations.
/// This facade exposes every provider-native endpoint that does not map
/// cleanly to an OpenAI operation (voice management, async TTS, music, and so
/// on). Request bodies remain schema-transparent maps so new optional MiniMax
/// fields can be used immediately without waiting for another DTO migration;
/// required fields, transport bounds, application-level status codes, and
/// resource cleanup are still enforced centrally.
class AiMiniMaxService {
  AiMiniMaxService({AiTransportClient? transport, AiEndpointRouter? router})
    : _transport = transport ?? AiTransportClient(),
      _router = router ?? const AiEndpointRouter(),
      _ownsTransport = transport == null;

  static const int _jsonResponseMaxBytes = 96 * kBytesPerMiB;
  static const int _largeJsonResponseMaxBytes = 128 * kBytesPerMiB;
  static const int _streamEventMaxBytes = 4 * kBytesPerMiB;
  static const int _webSocketMessageMaxBytes = 16 * kBytesPerMiB;
  static const int _webSocketAudioMaxBytes = 64 * kBytesPerMiB;
  static const int _webSocketRetainedEvents = 128;
  static const Duration _webSocketConnectTimeout = Duration(seconds: 20);
  static const Duration _webSocketIdleTimeout = Duration(seconds: 30);
  static const Duration _resourceCloseTimeout = Duration(seconds: 2);
  static const Set<String> _voiceQueryTypes = <String>{
    'system',
    'voice_cloning',
    'voice_generation',
    'all',
  };
  static const Set<String> _voiceDeleteTypes = <String>{
    'voice_cloning',
    'voice_generation',
  };
  static const Set<String> _imageModels = <String>{'image-01', 'image-01-live'};
  static const Set<String> _imageAspectRatios = <String>{
    '1:1',
    '16:9',
    '4:3',
    '3:2',
    '2:3',
    '3:4',
    '9:16',
    '21:9',
  };
  static const Set<String> _videoResolutions = <String>{
    '512P',
    '720P',
    '768P',
    '1080P',
  };
  static const Set<String> _musicModels = <String>{
    'music-2.6',
    'music-cover',
    'music-2.6-free',
    'music-cover-free',
  };
  static final RegExp _customVoiceIdPattern = RegExp(
    r'^[A-Za-z](?:[A-Za-z0-9_-]{6,254}[A-Za-z0-9])$',
  );

  final AiTransportClient _transport;
  final AiEndpointRouter _router;
  final bool _ownsTransport;

  Future<AiMiniMaxJsonResponse> createOpenAiChatCompletion({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    _requireFields(body, const <String>['model']);
    _requireNonEmptyList(body, 'messages');
    _rejectStreamingBody(body, 'chat/completions');
    return _postJson(
      model: model,
      family: AiApiFamily.chatCompletions,
      path: 'v1/chat/completions',
      body: body,
      timeout: timeout,
      operation: 'chat/completions',
    );
  }

  Future<AiMiniMaxStreamSummary> streamOpenAiChatCompletion({
    required AiModelConfig model,
    required Map<String, Object?> body,
    required AiMiniMaxStreamEventCallback onEvent,
    Duration timeout = const Duration(minutes: 5),
  }) {
    _requireFields(body, const <String>['model']);
    _requireNonEmptyList(body, 'messages');
    return _streamJsonEvents(
      model: model,
      family: AiApiFamily.chatCompletions,
      path: 'v1/chat/completions',
      body: <String, Object?>{...body, 'stream': true},
      timeout: timeout,
      operation: 'chat/completions/stream',
      onEvent: onEvent,
    );
  }

  Future<AiMiniMaxJsonResponse> createAnthropicMessage({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    _requireFields(body, const <String>['model', 'max_tokens']);
    _requireNonEmptyList(body, 'messages');
    _rejectStreamingBody(body, 'anthropic/messages');
    return _postJson(
      model: model,
      family: AiApiFamily.chatCompletions,
      path: 'anthropic/v1/messages',
      body: body,
      timeout: timeout,
      operation: 'anthropic/messages',
    );
  }

  Future<AiMiniMaxStreamSummary> streamAnthropicMessage({
    required AiModelConfig model,
    required Map<String, Object?> body,
    required AiMiniMaxStreamEventCallback onEvent,
    Duration timeout = const Duration(minutes: 5),
  }) {
    _requireFields(body, const <String>['model', 'max_tokens']);
    _requireNonEmptyList(body, 'messages');
    return _streamJsonEvents(
      model: model,
      family: AiApiFamily.chatCompletions,
      path: 'anthropic/v1/messages',
      body: <String, Object?>{...body, 'stream': true},
      timeout: timeout,
      operation: 'anthropic/messages/stream',
      onEvent: onEvent,
    );
  }

  Future<AiMiniMaxJsonResponse> createResponse({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    _requireFields(body, const <String>['model']);
    _requirePresentField(body, 'input');
    _rejectStreamingBody(body, 'responses');
    return _postJson(
      model: model,
      family: AiApiFamily.responses,
      path: 'v1/responses',
      body: body,
      timeout: timeout,
      operation: 'responses',
    );
  }

  Future<AiMiniMaxStreamSummary> streamResponse({
    required AiModelConfig model,
    required Map<String, Object?> body,
    required AiMiniMaxStreamEventCallback onEvent,
    Duration timeout = const Duration(minutes: 5),
  }) {
    _requireFields(body, const <String>['model']);
    _requirePresentField(body, 'input');
    return _streamJsonEvents(
      model: model,
      family: AiApiFamily.responses,
      path: 'v1/responses',
      body: <String, Object?>{...body, 'stream': true},
      timeout: timeout,
      operation: 'responses/stream',
      onEvent: onEvent,
    );
  }

  Future<AiMiniMaxJsonResponse> estimateResponseInputTokens({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    _requireFields(body, const <String>['model']);
    _requirePresentField(body, 'input');
    return _postJson(
      model: model,
      family: AiApiFamily.responses,
      path: 'v1/responses/input_tokens',
      body: body,
      timeout: timeout,
      operation: 'responses/input_tokens',
    );
  }

  Future<AiMiniMaxJsonResponse> synthesizeSpeechHttp({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 3),
  }) {
    _validateSpeechBody(body, maxTextCharacters: 9999);
    _rejectStreamingBody(body, 't2a_v2');
    return _postJson(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/t2a_v2',
      body: body,
      timeout: timeout,
      operation: 't2a_v2',
      maxResponseBytes: _largeJsonResponseMaxBytes,
    );
  }

  Future<AiMiniMaxStreamSummary> streamSpeechHttp({
    required AiModelConfig model,
    required Map<String, Object?> body,
    required AiMiniMaxStreamEventCallback onEvent,
    Duration timeout = const Duration(minutes: 3),
  }) {
    _validateSpeechBody(body, maxTextCharacters: 9999);
    return _streamJsonEvents(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/t2a_v2',
      body: <String, Object?>{...body, 'stream': true, 'output_format': 'hex'},
      timeout: timeout,
      operation: 't2a_v2/stream',
      onEvent: onEvent,
    );
  }

  Future<AiMiniMaxJsonResponse> createAsyncSpeech({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 2),
  }) {
    _requireFields(body, const <String>['model']);
    final hasText = nullIfBlank(stringFromValue(body['text'])) != null;
    final hasFileId =
        optionalNonNegativeIntFromValue(body['text_file_id']) != null;
    if (hasText == hasFileId) {
      throw ArgumentError(
        'MiniMax async TTS requires exactly one of text or text_file_id.',
      );
    }
    if (hasText) {
      _validateStringLength(body, 'text', max: 50000);
    }
    _requireNonEmptyMap(body, 'voice_setting');
    _requirePresentField(
      AiOperationHttp.stringKeyedMap(body['voice_setting']),
      'voice_id',
    );
    return _postJson(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/t2a_async_v2',
      body: body,
      timeout: timeout,
      operation: 't2a_async_v2',
    );
  }

  Future<AiMiniMaxJsonResponse> queryAsyncSpeech({
    required AiModelConfig model,
    required String taskId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return _getJson(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/query/t2a_async_query_v2',
      query: <String, String>{'task_id': _requiredValue(taskId, 'taskId')},
      timeout: timeout,
      operation: 'query/t2a_async_query_v2',
    );
  }

  Future<AiMiniMaxWebSocketSpeechResult> synthesizeSpeechWebSocket({
    required AiModelConfig model,
    required Map<String, Object?> taskStart,
    required List<String> textChunks,
    Duration timeout = const Duration(minutes: 3),
    AiMiniMaxStreamEventCallback? onEvent,
  }) async {
    _requireMiniMax(model);
    _requireFields(taskStart, const <String>['model']);
    _requireNonEmptyMap(taskStart, 'voice_setting');
    _requirePresentField(
      AiOperationHttp.stringKeyedMap(taskStart['voice_setting']),
      'voice_id',
    );
    final chunks = textChunks
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (chunks.isEmpty) {
      throw ArgumentError.value(textChunks, 'textChunks', 'Text is empty.');
    }
    if (chunks.any((value) => value.length >= 10000)) {
      throw ArgumentError(
        'Each MiniMax WebSocket TTS text chunk must be shorter than 10000 characters.',
      );
    }
    final endpoint = _router.resolveProviderPath(
      model,
      AiApiFamily.audioSpeech,
      path: 'ws/v1/t2a_v2',
      method: 'GET',
      transport: 'websocket',
    );
    final httpUri = Uri.parse(endpoint.url);
    final uri = httpUri.replace(
      scheme: httpUri.scheme == 'http' ? 'ws' : 'wss',
    );
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
      includeJsonContentType: false,
    );
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(_webSocketConnectTimeout);
      socket.pingInterval = const Duration(seconds: 15);
      return await _consumeSpeechWebSocket(
        socket: socket,
        taskStart: taskStart,
        textChunks: chunks,
        onEvent: onEvent,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      throw AiMiniMaxApiException(
        'MiniMax WebSocket TTS timed out: ${error.message ?? ''}'.trim(),
        operation: 'ws/t2a_v2',
      );
    } finally {
      if (socket != null) {
        try {
          await socket.close().timeout(_resourceCloseTimeout);
        } catch (_) {
          socket.close();
        }
      }
    }
  }

  Future<AiMiniMaxJsonResponse> cloneVoice({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 2),
  }) {
    _requireFields(body, const <String>['file_id', 'voice_id']);
    _validateCustomVoiceId(stringFromValue(body['voice_id']));
    _validateStringLength(body, 'text', max: 1000);
    _validateStringLength(body, 'text_validation', max: 200);
    _validateNumberRange(body, 'accuracy', min: 0, max: 1);
    final previewText = nullIfBlank(stringFromValue(body['text']));
    if (previewText != null &&
        nullIfBlank(stringFromValue(body['model'])) == null) {
      throw ArgumentError('MiniMax voice clone preview text requires model.');
    }
    final clonePrompt = AiOperationHttp.stringKeyedMap(body['clone_prompt']);
    if (clonePrompt.isNotEmpty) {
      _requireFields(clonePrompt, const <String>[
        'prompt_audio',
        'prompt_text',
      ]);
    }
    return _postJson(
      model: model,
      family: AiApiFamily.audioVoices,
      path: 'v1/voice_clone',
      body: body,
      timeout: timeout,
      operation: 'voice_clone',
    );
  }

  Future<AiMiniMaxJsonResponse> designVoice({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 2),
  }) {
    _requireFields(body, const <String>['prompt', 'preview_text']);
    _validateStringLength(body, 'preview_text', max: 500);
    final voiceId = nullIfBlank(stringFromValue(body['voice_id']));
    if (voiceId != null) _validateCustomVoiceId(voiceId);
    return _postJson(
      model: model,
      family: AiApiFamily.audioVoicePreview,
      path: 'v1/voice_design',
      body: body,
      timeout: timeout,
      operation: 'voice_design',
    );
  }

  Future<AiMiniMaxJsonResponse> getVoices({
    required AiModelConfig model,
    String voiceType = 'all',
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    _validateEnumValue(voiceType, 'voiceType', _voiceQueryTypes);
    return _postJson(
      model: model,
      family: AiApiFamily.audioVoices,
      path: 'v1/get_voice',
      body: <String, Object?>{'voice_type': voiceType},
      timeout: timeout,
      operation: 'get_voice',
    );
  }

  Future<AiMiniMaxJsonResponse> deleteVoice({
    required AiModelConfig model,
    required String voiceType,
    required String voiceId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    _validateEnumValue(voiceType, 'voiceType', _voiceDeleteTypes);
    return _postJson(
      model: model,
      family: AiApiFamily.audioVoices,
      path: 'v1/delete_voice',
      body: <String, Object?>{
        'voice_type': _requiredValue(voiceType, 'voiceType'),
        'voice_id': _requiredValue(voiceId, 'voiceId'),
      },
      timeout: timeout,
      operation: 'delete_voice',
    );
  }

  Future<AiMiniMaxJsonResponse> generateImage({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 3),
  }) {
    _requireFields(body, const <String>['model', 'prompt']);
    _validateImageBody(body);
    return _postJson(
      model: model,
      family: AiApiFamily.imageGeneration,
      path: 'v1/image_generation',
      body: body,
      timeout: timeout,
      operation: 'image_generation',
      maxResponseBytes: _largeJsonResponseMaxBytes,
    );
  }

  Future<AiMiniMaxJsonResponse> createVideo({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 2),
  }) {
    _requireFields(body, const <String>['model']);
    _validateVideoBody(body);
    return _postJson(
      model: model,
      family: AiApiFamily.videoGeneration,
      path: 'v1/video_generation',
      body: body,
      timeout: timeout,
      operation: 'video_generation',
    );
  }

  Future<AiMiniMaxJsonResponse> queryVideo({
    required AiModelConfig model,
    required String taskId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return _getJson(
      model: model,
      family: AiApiFamily.videoGeneration,
      path: 'v1/query/video_generation',
      query: <String, String>{'task_id': _requiredValue(taskId, 'taskId')},
      timeout: timeout,
      operation: 'query/video_generation',
    );
  }

  Future<AiFileDownloadResult> downloadVideo({
    required AiModelConfig model,
    required String fileId,
    required File destination,
    Duration timeout = const Duration(minutes: 10),
    int maxBytes = defaultAiTransportFileDownloadMaxBytes,
  }) {
    return downloadFileContent(
      model: model,
      fileId: fileId,
      destination: destination,
      timeout: timeout,
      maxBytes: maxBytes,
    );
  }

  Future<AiMiniMaxJsonResponse> generateMusic({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 10),
  }) {
    _validateMusicBody(body, streaming: false);
    _rejectStreamingBody(body, 'music_generation');
    return _postJson(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/music_generation',
      body: body,
      timeout: timeout,
      operation: 'music_generation',
      maxResponseBytes: _largeJsonResponseMaxBytes,
    );
  }

  Future<AiMiniMaxStreamSummary> streamMusic({
    required AiModelConfig model,
    required Map<String, Object?> body,
    required AiMiniMaxStreamEventCallback onEvent,
    Duration timeout = const Duration(minutes: 10),
  }) {
    _validateMusicBody(body, streaming: true);
    return _streamJsonEvents(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/music_generation',
      body: <String, Object?>{...body, 'stream': true, 'output_format': 'hex'},
      timeout: timeout,
      operation: 'music_generation/stream',
      onEvent: onEvent,
      maxResponseBytes: _largeJsonResponseMaxBytes,
    );
  }

  Future<AiMiniMaxJsonResponse> preprocessMusicCover({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 5),
  }) {
    _requireFields(body, const <String>['model']);
    _validateEnumValue(stringFromValue(body['model']), 'model', const <String>{
      'music-cover',
    });
    _requireExactlyOne(body, const <String>[
      'audio_url',
      'audio_base64',
    ], operation: 'Music cover preprocessing');
    return _postJson(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/music_cover_preprocess',
      body: body,
      timeout: timeout,
      operation: 'music_cover_preprocess',
      maxResponseBytes: _largeJsonResponseMaxBytes,
    );
  }

  Future<AiMiniMaxJsonResponse> generateLyrics({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 2),
  }) {
    _requireFields(body, const <String>['mode']);
    final mode = stringFromValue(body['mode']);
    _validateEnumValue(mode, 'mode', const <String>{'write_full_song', 'edit'});
    _validateStringLength(body, 'prompt', max: 2000);
    _validateStringLength(body, 'lyrics', max: 3500);
    if (mode == 'edit' &&
        nullIfBlank(stringFromValue(body['lyrics'])) == null) {
      throw ArgumentError('MiniMax lyrics edit mode requires lyrics.');
    }
    return _postJson(
      model: model,
      family: AiApiFamily.audioSpeech,
      path: 'v1/lyrics_generation',
      body: body,
      timeout: timeout,
      operation: 'lyrics_generation',
    );
  }

  Future<AiFileRecord?> uploadFile({
    required AiModelConfig model,
    required String filePath,
    required String purpose,
    Duration timeout = const Duration(minutes: 2),
  }) {
    return AiFilesService(router: _router, transport: _transport).uploadFile(
      model: model,
      filePath: filePath,
      purpose: purpose,
      timeout: timeout,
    );
  }

  Future<AiFileRecord?> uploadVoiceCloneAudio({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(minutes: 2),
  }) {
    return uploadFile(
      model: model,
      filePath: filePath,
      purpose: 'voice_clone',
      timeout: timeout,
    );
  }

  Future<AiFileRecord?> uploadVoiceClonePrompt({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(minutes: 2),
  }) {
    return uploadFile(
      model: model,
      filePath: filePath,
      purpose: 'prompt_audio',
      timeout: timeout,
    );
  }

  Future<List<AiFileRecord>> listFiles({
    required AiModelConfig model,
    required String purpose,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return AiFilesService(
      router: _router,
      transport: _transport,
    ).listFiles(model: model, purpose: purpose, timeout: timeout);
  }

  Future<AiFileRecord?> retrieveFile({
    required AiModelConfig model,
    required String fileId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return AiFilesService(
      router: _router,
      transport: _transport,
    ).retrieveFile(model: model, fileId: fileId, timeout: timeout);
  }

  Future<AiFileContentResult> retrieveFileContent({
    required AiModelConfig model,
    required String fileId,
    Duration timeout = const Duration(minutes: 2),
  }) {
    return AiFilesService(
      router: _router,
      transport: _transport,
    ).retrieveFileContent(model: model, fileId: fileId, timeout: timeout);
  }

  Future<AiFileDownloadResult> downloadFileContent({
    required AiModelConfig model,
    required String fileId,
    required File destination,
    Duration timeout = const Duration(minutes: 10),
    int maxBytes = defaultAiTransportFileDownloadMaxBytes,
  }) {
    return AiFilesService(
      router: _router,
      transport: _transport,
    ).downloadFileContent(
      model: model,
      fileId: fileId,
      destination: destination,
      timeout: timeout,
      maxBytes: maxBytes,
    );
  }

  Future<void> deleteFile({
    required AiModelConfig model,
    required String fileId,
    required String purpose,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return AiFilesService(router: _router, transport: _transport).deleteFile(
      model: model,
      fileId: fileId,
      purpose: purpose,
      timeout: timeout,
    );
  }

  Future<AiModelsListResult> listModels({
    required AiModelConfig model,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return AiModelsService(
      router: _router,
      transport: _transport,
    ).listModels(model: model, timeout: timeout);
  }

  Future<AiModelRecord?> retrieveModel({
    required AiModelConfig model,
    required String modelId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return AiModelsService(
      router: _router,
      transport: _transport,
    ).retrieveModel(model: model, modelId: modelId, timeout: timeout);
  }

  Future<AiMiniMaxJsonResponse> _postJson({
    required AiModelConfig model,
    required AiApiFamily family,
    required String path,
    required Map<String, Object?> body,
    required Duration timeout,
    required String operation,
    int maxResponseBytes = _jsonResponseMaxBytes,
  }) async {
    _requireMiniMax(model);
    final endpoint = _router.resolveProviderPath(model, family, path: path);
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        acceptJson: true,
      ),
      body: body,
      timeout: timeout,
      maxResponseBytes: maxResponseBytes,
    );
    return _decodeJsonResponse(response, operation: operation);
  }

  Future<AiMiniMaxJsonResponse> _getJson({
    required AiModelConfig model,
    required AiApiFamily family,
    required String path,
    required Map<String, String> query,
    required Duration timeout,
    required String operation,
  }) async {
    _requireMiniMax(model);
    final endpoint = _router.resolveProviderPath(
      model,
      family,
      path: path,
      method: 'GET',
    );
    final baseUri = Uri.parse(endpoint.url);
    final response = await _transport.get(
      uri: baseUri.replace(
        queryParameters: <String, String>{...baseUri.queryParameters, ...query},
      ),
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        includeJsonContentType: false,
        acceptJson: true,
      ),
      timeout: timeout,
      maxResponseBytes: _jsonResponseMaxBytes,
    );
    return _decodeJsonResponse(response, operation: operation);
  }

  AiMiniMaxJsonResponse _decodeJsonResponse(
    http.Response response, {
    required String operation,
  }) {
    if (isHttpFailureStatus(response.statusCode)) {
      throw AiMiniMaxApiException(
        'MiniMax $operation HTTP ${response.statusCode}: '
        '${AiOperationHttp.extractErrorMessage(response.body)}',
        operation: operation,
        httpStatus: response.statusCode,
        rawResponse: response.body,
      );
    }
    final payload = AiOperationHttp.jsonMapOrEmpty(
      AiOperationHttp.decodeJsonResponse(response.body, contextHint: operation),
    );
    _throwIfProviderFailed(
      payload,
      operation: operation,
      rawResponse: response.body,
    );
    return AiMiniMaxJsonResponse(
      payload: Map<String, Object?>.unmodifiable(payload),
      rawResponse: response.body,
      statusCode: response.statusCode,
      headers: Map<String, String>.unmodifiable(response.headers),
    );
  }

  Future<AiMiniMaxStreamSummary> _streamJsonEvents({
    required AiModelConfig model,
    required AiApiFamily family,
    required String path,
    required Map<String, Object?> body,
    required Duration timeout,
    required String operation,
    required AiMiniMaxStreamEventCallback onEvent,
    int maxResponseBytes = _jsonResponseMaxBytes,
  }) async {
    _requireMiniMax(model);
    final endpoint = _router.resolveProviderPath(model, family, path: path);
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
    )..['accept'] = 'text/event-stream';
    return _transport.consumeJsonStream<AiMiniMaxStreamSummary>(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: headers,
      body: body,
      timeout: timeout,
      maxResponseBytes: maxResponseBytes,
      consume: (response, stream) async {
        var pending = '';
        var pendingBytes = 0;
        var eventCount = 0;
        Map<String, Object?>? lastEvent;

        Never throwEventTooLarge() {
          throw AiMiniMaxApiException(
            'MiniMax $operation stream event exceeded the '
            '${formatByteSize(_streamEventMaxBytes)} limit.',
            operation: operation,
          );
        }

        Future<void> processBlock(String block) async {
          final dataLines = extractSseDataLines(block);
          final rawData = dataLines.isEmpty
              ? block.trim()
              : dataLines.join('\n');
          if (rawData.isEmpty || rawData == '[DONE]') return;
          final Object? decoded;
          try {
            decoded = jsonDecode(rawData);
          } on FormatException catch (error) {
            throw AiMiniMaxApiException(
              'MiniMax $operation returned an invalid stream event: '
              '${error.message}',
              operation: operation,
              rawResponse: rawData,
            );
          }
          final event = AiOperationHttp.jsonMapOrEmpty(decoded);
          if (event.isEmpty) return;
          _throwIfProviderFailed(
            event,
            operation: operation,
            rawResponse: rawData,
          );
          eventCount += 1;
          lastEvent = Map<String, Object?>.unmodifiable(event);
          await onEvent(lastEvent!);
        }

        await for (final chunk in stream.transform(utf8.decoder)) {
          final normalizedChunk = chunk
              .replaceAll('\r\n', '\n')
              .replaceAll('\r', '\n');
          pending += normalizedChunk;
          pendingBytes += utf8.encode(normalizedChunk).length;
          var separator = pending.indexOf('\n\n');
          while (separator >= 0) {
            final block = pending.substring(0, separator);
            final consumedBytes = utf8
                .encode(pending.substring(0, separator + 2))
                .length;
            if (consumedBytes - 2 > _streamEventMaxBytes) {
              throwEventTooLarge();
            }
            pending = pending.substring(separator + 2);
            pendingBytes -= consumedBytes;
            await processBlock(block);
            separator = pending.indexOf('\n\n');
          }
          if (pendingBytes > _streamEventMaxBytes) throwEventTooLarge();
        }
        if (pending.trim().isNotEmpty) await processBlock(pending);
        return AiMiniMaxStreamSummary(
          eventCount: eventCount,
          lastEvent: lastEvent,
          statusCode: response.statusCode,
          headers: Map<String, String>.unmodifiable(response.headers),
        );
      },
    );
  }

  Future<AiMiniMaxWebSocketSpeechResult> _consumeSpeechWebSocket({
    required WebSocket socket,
    required Map<String, Object?> taskStart,
    required List<String> textChunks,
    required AiMiniMaxStreamEventCallback? onEvent,
  }) async {
    final audio = BytesBuilder(copy: false);
    final retainedEvents = <Map<String, Object?>>[];
    var startSent = false;
    var textSent = false;
    String audioFormat = stringFromValue(
      AiOperationHttp.stringKeyedMap(taskStart['audio_setting'])['format'],
    );

    Never throwWebSocketMessageTooLarge() {
      throw AiMiniMaxApiException(
        'MiniMax WebSocket event exceeded the '
        '${formatByteSize(_webSocketMessageMaxBytes)} limit.',
        operation: 'ws/t2a_v2',
      );
    }

    await for (final message in socket.timeout(_webSocketIdleTimeout)) {
      final String raw;
      final int rawBytes;
      if (message is String) {
        raw = message;
        rawBytes = utf8.encode(message).length;
      } else if (message is List<int>) {
        if (message.length > _webSocketMessageMaxBytes) {
          throwWebSocketMessageTooLarge();
        }
        rawBytes = message.length;
        raw = utf8.decode(message);
      } else {
        throw const AiMiniMaxApiException(
          'MiniMax WebSocket returned an unsupported message type.',
          operation: 'ws/t2a_v2',
        );
      }
      if (rawBytes > _webSocketMessageMaxBytes) {
        throwWebSocketMessageTooLarge();
      }
      final decoded = jsonDecode(raw);
      final event = AiOperationHttp.jsonMapOrEmpty(decoded);
      if (event.isEmpty) continue;
      _throwIfProviderFailed(event, operation: 'ws/t2a_v2', rawResponse: raw);
      if (retainedEvents.length < _webSocketRetainedEvents) {
        retainedEvents.add(Map<String, Object?>.unmodifiable(event));
      }
      await onEvent?.call(event);
      final eventName = lowercaseStringFromValue(event['event']);
      if (eventName == 'connected_success' && !startSent) {
        startSent = true;
        final streamOptions = <String, Object?>{
          ...AiOperationHttp.stringKeyedMap(taskStart['stream_options']),
          'exclude_aggregated_audio': true,
        };
        socket.add(
          jsonEncode(<String, Object?>{
            ...taskStart,
            'event': 'task_start',
            'stream_options': streamOptions,
          }),
        );
        continue;
      }
      if (eventName == 'task_started' && !textSent) {
        textSent = true;
        for (final text in textChunks) {
          socket.add(
            jsonEncode(<String, Object?>{
              'event': 'task_continue',
              'text': text,
            }),
          );
        }
        socket.add(jsonEncode(const <String, Object?>{'event': 'task_finish'}));
        continue;
      }
      final data = AiOperationHttp.stringKeyedMap(event['data']);
      final audioHex = nullIfBlank(stringFromValue(data['audio']));
      if (audioHex != null) {
        _appendHexAudio(audio, audioHex);
      }
      final extraInfo = AiOperationHttp.stringKeyedMap(event['extra_info']);
      audioFormat =
          optionalStringFromValue(extraInfo['audio_format']) ?? audioFormat;
      if (eventName == 'task_failed') {
        throw AiMiniMaxApiException(
          'MiniMax WebSocket TTS failed.',
          operation: 'ws/t2a_v2',
          rawResponse: raw,
        );
      }
      if (eventName == 'task_finished') {
        return AiMiniMaxWebSocketSpeechResult(
          audioBytes: audio.takeBytes(),
          events: List<Map<String, Object?>>.unmodifiable(retainedEvents),
          audioFormat: nullIfBlank(audioFormat) ?? 'mp3',
        );
      }
    }
    throw const AiMiniMaxApiException(
      'MiniMax closed the WebSocket before task_finished.',
      operation: 'ws/t2a_v2',
    );
  }

  void _appendHexAudio(BytesBuilder output, String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length.isOdd) {
      throw const AiMiniMaxApiException(
        'MiniMax WebSocket returned malformed hexadecimal audio.',
        operation: 'ws/t2a_v2',
      );
    }
    final byteLength = normalized.length ~/ 2;
    if (output.length > _webSocketAudioMaxBytes - byteLength) {
      throw const AiMiniMaxApiException(
        'MiniMax WebSocket audio exceeded the bounded 64 MiB limit.',
        operation: 'ws/t2a_v2',
      );
    }
    final bytes = Uint8List(byteLength);
    for (var index = 0; index < normalized.length; index += 2) {
      final byte = int.tryParse(
        normalized.substring(index, index + 2),
        radix: 16,
      );
      if (byte == null) {
        throw const AiMiniMaxApiException(
          'MiniMax WebSocket returned malformed hexadecimal audio.',
          operation: 'ws/t2a_v2',
        );
      }
      bytes[index ~/ 2] = byte;
    }
    output.add(bytes);
  }

  void _throwIfProviderFailed(
    Map<String, Object?> payload, {
    required String operation,
    required String rawResponse,
  }) {
    final baseResponse = AiOperationHttp.stringKeyedMap(payload['base_resp']);
    final status = optionalIntFromValue(baseResponse['status_code']);
    if (status == null || status == 0) return;
    final statusMessage =
        optionalStringFromValue(baseResponse['status_msg']) ??
        'Provider request failed.';
    throw AiMiniMaxApiException(
      'MiniMax $operation failed ($status): $statusMessage',
      operation: operation,
      providerStatus: status,
      rawResponse: rawResponse,
    );
  }

  void _validateSpeechBody(
    Map<String, Object?> body, {
    required int maxTextCharacters,
  }) {
    _requireFields(body, const <String>['model', 'text']);
    _validateStringLength(body, 'text', max: maxTextCharacters);
    _validateEnumField(body, 'output_format', const <String>{'url', 'hex'});
    _validateEnumField(body, 'subtitle_type', const <String>{
      'sentence',
      'word',
      'word_streaming',
    });
    final voice = AiOperationHttp.stringKeyedMap(body['voice_setting']);
    if (voice.isNotEmpty) {
      if (!voice.containsKey('voice_id')) {
        throw ArgumentError('MiniMax voice_setting requires voice_id.');
      }
      _validateNumberRange(voice, 'speed', min: 0.5, max: 2);
      _validateNumberRange(voice, 'vol', min: 0, max: 10, exclusiveMin: true);
      _validateNumberRange(voice, 'pitch', min: -12, max: 12);
      _validateEnumField(voice, 'emotion', const <String>{
        'happy',
        'sad',
        'angry',
        'fearful',
        'disgusted',
        'surprised',
        'calm',
        'fluent',
        'whisper',
      });
    }
    final audio = AiOperationHttp.stringKeyedMap(body['audio_setting']);
    if (audio.isNotEmpty) {
      _validateEnumField(audio, 'sample_rate', const <int>{
        8000,
        16000,
        22050,
        24000,
        32000,
        44100,
      });
      _validateEnumField(audio, 'bitrate', const <int>{
        32000,
        64000,
        128000,
        256000,
      });
      _validateEnumField(audio, 'format', const <String>{
        'mp3',
        'pcm',
        'flac',
        'wav',
        'pcmu_raw',
        'pcmu_wav',
        'opus',
      });
      _validateEnumField(audio, 'channel', const <int>{1, 2});
    }
    final timbreWeights = body['timbre_weights'];
    if (timbreWeights is List) {
      if (timbreWeights.isEmpty || timbreWeights.length > 4) {
        throw ArgumentError(
          'MiniMax timbre_weights must contain between 1 and 4 voices.',
        );
      }
      for (final rawWeight in timbreWeights) {
        final weight = AiOperationHttp.stringKeyedMap(rawWeight);
        _requireFields(weight, const <String>['voice_id', 'weight']);
        _validateNumberRange(weight, 'weight', min: 1, max: 100);
      }
    }
  }

  void _validateImageBody(Map<String, Object?> body) {
    final modelId = stringFromValue(body['model']);
    _validateEnumValue(modelId, 'model', _imageModels);
    _validateStringLength(body, 'prompt', max: 1500);
    _validateEnumField(body, 'response_format', const <String>{
      'url',
      'base64',
    });
    _validateEnumField(body, 'aspect_ratio', _imageAspectRatios);
    final aspectRatio = nullIfBlank(stringFromValue(body['aspect_ratio']));
    if (modelId == 'image-01-live' && aspectRatio == '21:9') {
      throw ArgumentError('MiniMax image-01-live does not support 21:9.');
    }
    _validateNumberRange(body, 'n', min: 1, max: 9);
    final width = optionalIntFromValue(body['width']);
    final height = optionalIntFromValue(body['height']);
    if ((width == null) != (height == null)) {
      throw ArgumentError(
        'MiniMax image width and height must be set together.',
      );
    }
    if (width != null && height != null) {
      if (modelId != 'image-01' ||
          width < 512 ||
          width > 2048 ||
          height < 512 ||
          height > 2048 ||
          width % 8 != 0 ||
          height % 8 != 0) {
        throw ArgumentError(
          'MiniMax image width and height require image-01, values from 512 to 2048, and multiples of 8.',
        );
      }
    }
    final style = AiOperationHttp.stringKeyedMap(body['style']);
    if (style.isNotEmpty) {
      if (modelId != 'image-01-live') {
        throw ArgumentError('MiniMax image styles require image-01-live.');
      }
      _requireFields(style, const <String>['style_type']);
      _validateEnumField(style, 'style_type', const <String>{
        '漫画',
        '元气',
        '中世纪',
        '水彩',
      });
      _validateNumberRange(
        style,
        'style_weight',
        min: 0,
        max: 1,
        exclusiveMin: true,
      );
    }
  }

  void _validateVideoBody(Map<String, Object?> body) {
    final modelId = lowercaseStringFromValue(body['model']);
    final prompt = nullIfBlank(stringFromValue(body['prompt']));
    _validateStringLength(body, 'prompt', max: 2000);
    _validateEnumField(body, 'resolution', _videoResolutions);
    _validateEnumField(body, 'duration', const <int>{6, 10});
    final firstFrame = nullIfBlank(stringFromValue(body['first_frame_image']));
    final lastFrame = nullIfBlank(stringFromValue(body['last_frame_image']));
    final subjectReference = body['subject_reference'];
    final hasSubjectReference =
        subjectReference is List && subjectReference.isNotEmpty;
    if (modelId.startsWith('s2v-') && !hasSubjectReference) {
      throw ArgumentError('MiniMax S2V requires subject_reference.');
    }
    if (modelId.startsWith('i2v-') && firstFrame == null) {
      throw ArgumentError('MiniMax I2V requires first_frame_image.');
    }
    if (modelId.startsWith('t2v-') && prompt == null) {
      throw ArgumentError('MiniMax T2V requires prompt.');
    }
    if (prompt == null &&
        firstFrame == null &&
        lastFrame == null &&
        !hasSubjectReference) {
      throw ArgumentError('MiniMax video generation requires an input source.');
    }
    if (lastFrame != null && firstFrame == null) {
      throw ArgumentError(
        'MiniMax first/last-frame video requires first_frame_image.',
      );
    }
    final duration = optionalIntFromValue(body['duration']);
    final resolution = nullIfBlank(stringFromValue(body['resolution']));
    if (duration == 10 && resolution == '1080P') {
      throw ArgumentError('MiniMax 10-second video does not support 1080P.');
    }
    if (lastFrame != null && resolution == '512P') {
      throw ArgumentError(
        'MiniMax first/last-frame video does not support 512P.',
      );
    }
  }

  void _validateMusicBody(
    Map<String, Object?> body, {
    required bool streaming,
  }) {
    _requireFields(body, const <String>['model']);
    final modelId = stringFromValue(body['model']);
    _validateEnumValue(modelId, 'model', _musicModels);
    _validateStringLength(body, 'prompt', max: 2000);
    _validateStringLength(body, 'lyrics', max: 3500);
    _validateEnumField(body, 'output_format', const <String>{'url', 'hex'});
    if (streaming &&
        nullIfBlank(stringFromValue(body['output_format'])) == 'url') {
      throw ArgumentError('MiniMax streaming music only supports hex output.');
    }
    final prompt = nullIfBlank(stringFromValue(body['prompt']));
    final lyrics = nullIfBlank(stringFromValue(body['lyrics']));
    final audio = AiOperationHttp.stringKeyedMap(body['audio_setting']);
    if (audio.isNotEmpty) {
      _validateEnumField(audio, 'sample_rate', const <int>{
        16000,
        24000,
        32000,
        44100,
      });
      _validateEnumField(audio, 'bitrate', const <int>{
        32000,
        64000,
        128000,
        256000,
      });
      _validateEnumField(audio, 'format', const <String>{'mp3', 'wav', 'pcm'});
    }
    final isCover = modelId.contains('cover');
    if (isCover) {
      if (prompt == null || prompt.length < 10 || prompt.length > 300) {
        throw ArgumentError(
          'MiniMax music-cover prompt must contain 10 to 300 characters.',
        );
      }
      _requireExactlyOne(body, const <String>[
        'audio_url',
        'audio_base64',
        'cover_feature_id',
      ], operation: 'MiniMax music-cover');
      if (lyrics != null && (lyrics.length < 10 || lyrics.length > 1000)) {
        throw ArgumentError(
          'MiniMax music-cover lyrics must contain 10 to 1000 characters.',
        );
      }
      if (nullIfBlank(stringFromValue(body['cover_feature_id'])) != null &&
          (lyrics == null || lyrics.length < 10 || lyrics.length > 1000)) {
        throw ArgumentError(
          'MiniMax cover_feature_id requires lyrics with 10 to 1000 characters.',
        );
      }
      return;
    }
    final instrumental = body['is_instrumental'] == true;
    final lyricsOptimizer = body['lyrics_optimizer'] == true;
    if (instrumental && prompt == null) {
      throw ArgumentError('MiniMax instrumental music requires prompt.');
    }
    if (!instrumental && lyrics == null && !lyricsOptimizer) {
      throw ArgumentError(
        'MiniMax vocal music requires lyrics or lyrics_optimizer.',
      );
    }
    if (!instrumental && lyrics == null && prompt == null) {
      throw ArgumentError(
        'MiniMax lyrics_optimizer requires prompt when lyrics are empty.',
      );
    }
  }

  void _validateCustomVoiceId(String value) {
    if (!_customVoiceIdPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'voiceId',
        'MiniMax custom voice ID must be 8-256 characters, start with a letter, use letters, digits, - or _, and end with a letter or digit.',
      );
    }
  }

  void _requireNonEmptyMap(Map<String, Object?> body, String field) {
    if (AiOperationHttp.stringKeyedMap(body[field]).isEmpty) {
      throw ArgumentError('MiniMax $field is required.');
    }
  }

  void _requireNonEmptyList(Map<String, Object?> body, String field) {
    final value = body[field];
    if (value is! List || value.isEmpty) {
      throw ArgumentError('MiniMax $field must be a non-empty list.');
    }
  }

  void _requirePresentField(Map<String, Object?> body, String field) {
    if (!body.containsKey(field) || body[field] == null) {
      throw ArgumentError('MiniMax $field is required.');
    }
  }

  void _validateStringLength(
    Map<String, Object?> body,
    String field, {
    required int max,
  }) {
    final value = body[field];
    if (value == null) return;
    if (value is! String) {
      throw ArgumentError.value(value, field, '$field must be a string.');
    }
    if (value.length > max) {
      throw ArgumentError.value(
        value.length,
        field,
        '$field cannot exceed $max characters.',
      );
    }
  }

  void _validateNumberRange(
    Map<String, Object?> body,
    String field, {
    required num min,
    required num max,
    bool exclusiveMin = false,
  }) {
    final value = body[field];
    if (value == null) return;
    final parsed = value is num ? value : num.tryParse('$value');
    if (parsed == null ||
        (exclusiveMin ? parsed <= min : parsed < min) ||
        parsed > max) {
      throw ArgumentError.value(
        value,
        field,
        '$field must be ${exclusiveMin ? 'greater than' : 'at least'} $min and at most $max.',
      );
    }
  }

  void _validateEnumField(
    Map<String, Object?> body,
    String field,
    Set<Object> allowed,
  ) {
    final value = body[field];
    if (value == null) return;
    if (!allowed.contains(value)) {
      throw ArgumentError.value(
        value,
        field,
        '$field must be one of ${allowed.join(', ')}.',
      );
    }
  }

  void _validateEnumValue(String value, String field, Set<String> allowed) {
    if (!allowed.contains(value)) {
      throw ArgumentError.value(
        value,
        field,
        '$field must be one of ${allowed.join(', ')}.',
      );
    }
  }

  void _requireExactlyOne(
    Map<String, Object?> body,
    List<String> fields, {
    required String operation,
  }) {
    final supplied = fields
        .where((field) => nullIfBlank(stringFromValue(body[field])) != null)
        .length;
    if (supplied != 1) {
      throw ArgumentError(
        '$operation requires exactly one of ${fields.join(', ')}.',
      );
    }
  }

  void _requireMiniMax(AiModelConfig model) {
    if (model.protocolType != AiProtocolType.minimax) {
      throw ArgumentError.value(
        model.protocolType.storageValue,
        'model.protocolType',
        'AiMiniMaxService requires the MiniMax protocol.',
      );
    }
    if (nullIfBlank(model.normalizedBaseUrl) == null) {
      throw ArgumentError.value(
        model.baseUrl,
        'model.baseUrl',
        'URL is empty.',
      );
    }
  }

  void _requireFields(Map<String, Object?> body, List<String> fields) {
    final missing = fields
        .where((field) => nullIfBlank(stringFromValue(body[field])) == null)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw ArgumentError('Missing MiniMax fields: ${missing.join(', ')}.');
    }
  }

  void _rejectStreamingBody(Map<String, Object?> body, String operation) {
    if (body['stream'] == true) {
      throw ArgumentError(
        'Use the streaming method for MiniMax $operation requests.',
      );
    }
  }

  String _requiredValue(String value, String name) {
    final normalized = nullIfBlank(value);
    if (normalized == null) {
      throw ArgumentError.value(value, name, '$name is empty.');
    }
    return normalized;
  }

  void dispose() {
    if (_ownsTransport) _transport.dispose();
  }
}
