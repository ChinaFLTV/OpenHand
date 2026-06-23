import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiRealtimeSessionResult {
  const AiRealtimeSessionResult({
    required this.rawResponse,
    required this.payload,
    this.clientSecret,
    this.sessionId,
  });

  final String rawResponse;
  final Map<String, Object?> payload;
  final String? clientSecret;
  final String? sessionId;
}

class AiRealtimeSessionDescriptor {
  const AiRealtimeSessionDescriptor({
    required this.url,
    required this.transport,
    required this.modelId,
    this.voice,
    this.inputFormat,
    this.outputFormat,
    this.sampleRate,
  });

  final String url;
  final String transport;
  final String modelId;
  final String? voice;
  final String? inputFormat;
  final String? outputFormat;
  final int? sampleRate;
}

class AiRealtimeConnection {
  const AiRealtimeConnection({required this.channel, required this.descriptor});

  final WebSocketChannel channel;
  final AiRealtimeSessionDescriptor descriptor;
}

class AiRealtimeService {
  AiRealtimeService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  AiRealtimeSessionDescriptor describeSession(AiModelConfig model) {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.realtime,
      method: 'GET',
      transport: 'websocket',
    );
    final endpointUrl = model.realtime.urlOverride?.trim().isNotEmpty == true
        ? model.realtime.urlOverride!.trim()
        : endpoint.url;
    return AiRealtimeSessionDescriptor(
      url: _realtimeWebSocketUrl(endpointUrl, model),
      transport: model.realtime.transport?.trim().isNotEmpty == true
          ? model.realtime.transport!.trim()
          : endpoint.transport,
      modelId: model.resolveOperationModelId(AiApiFamily.realtime),
      voice: model.realtime.voice ?? model.operationRouting.defaultVoice,
      inputFormat: model.realtime.inputFormat,
      outputFormat: model.realtime.outputFormat,
      sampleRate: model.realtime.sampleRate,
    );
  }

  Future<AiRealtimeConnection> connect(AiModelConfig model) async {
    final descriptor = describeSession(model);
    final channel = WebSocketChannel.connect(Uri.parse(descriptor.url));
    return AiRealtimeConnection(channel: channel, descriptor: descriptor);
  }

  Future<AiRealtimeSessionResult> createSession({
    required AiModelConfig model,
    Duration timeout = const Duration(seconds: 60),
    String? voice,
    String? inputAudioFormat,
    String? outputAudioFormat,
    Object? modalities,
    Object? instructions,
    Object? turnDetection,
    Object? tools,
  }) async {
    const family = AiApiFamily.realtime;
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
      fallbackPath: 'v1/realtime/sessions',
    );
    final body = AiOperationHttp.mergeBodyExtras(
      model,
      family,
      <String, Object?>{
        ...model.realtime.sessionDefaults,
        'model': model.resolveOperationModelId(family),
        if (modalities != null) 'modalities': modalities,
        if (instructions != null) 'instructions': instructions,
        if (turnDetection != null) 'turn_detection': turnDetection,
        if (tools != null) 'tools': tools,
        if (voice?.trim().isNotEmpty == true)
          'voice': voice!.trim()
        else if (model.realtime.voice?.trim().isNotEmpty == true)
          'voice': model.realtime.voice!.trim()
        else if (model.operationRouting.defaultVoice?.trim().isNotEmpty == true)
          'voice': model.operationRouting.defaultVoice!.trim(),
        if (inputAudioFormat?.trim().isNotEmpty == true)
          'input_audio_format': inputAudioFormat!.trim()
        else if (model.realtime.inputFormat?.trim().isNotEmpty == true)
          'input_audio_format': model.realtime.inputFormat!.trim(),
        if (outputAudioFormat?.trim().isNotEmpty == true)
          'output_audio_format': outputAudioFormat!.trim()
        else if (model.realtime.outputFormat?.trim().isNotEmpty == true)
          'output_audio_format': model.realtime.outputFormat!.trim(),
      },
    );
    final response = await _transport.sendJson(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
      ),
      body: body,
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'realtime/sessions',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'realtime/sessions',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    final clientSecret = payload['client_secret'];
    final nestedSecret = clientSecret is Map
        ? Map<String, Object?>.from(clientSecret)
        : const <String, Object?>{};
    return AiRealtimeSessionResult(
      rawResponse: response.body,
      payload: payload,
      sessionId: '${payload['id'] ?? ''}'.trim().isEmpty
          ? null
          : '${payload['id']}'.trim(),
      clientSecret:
          '${nestedSecret['value'] ?? payload['client_secret'] ?? ''}'
              .trim()
              .isEmpty
          ? null
          : '${nestedSecret['value'] ?? payload['client_secret']}'.trim(),
    );
  }

  String _realtimeWebSocketUrl(String url, AiModelConfig model) {
    final uri = Uri.parse(url);
    final scheme = switch (uri.scheme.toLowerCase()) {
      'http' => 'ws',
      'https' => 'wss',
      '' => 'wss',
      _ => uri.scheme,
    };
    return uri
        .replace(
          scheme: scheme,
          queryParameters: <String, String>{
            ...uri.queryParameters,
            if (!uri.queryParameters.containsKey('model'))
              'model': model.resolveOperationModelId(AiApiFamily.realtime),
          },
        )
        .toString();
  }

  void dispose() {
    _transport.dispose();
  }
}
