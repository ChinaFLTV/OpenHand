import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../shared/util/input_value_parsing.dart';
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
    final endpointUrl = nullIfBlank(model.realtime.urlOverride) ?? endpoint.url;
    final transport =
        nullIfBlank(model.realtime.transport) ?? endpoint.transport;
    return AiRealtimeSessionDescriptor(
      url: _realtimeWebSocketUrl(endpointUrl, model),
      transport: transport,
      modelId: model.resolveOperationModelId(AiApiFamily.realtime),
      voice:
          nullIfBlank(model.realtime.voice) ??
          nullIfBlank(model.operationRouting.defaultVoice),
      inputFormat: nullIfBlank(model.realtime.inputFormat),
      outputFormat: nullIfBlank(model.realtime.outputFormat),
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
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
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
    final resolvedVoice =
        nullIfBlank(voice) ??
        nullIfBlank(model.realtime.voice) ??
        nullIfBlank(model.operationRouting.defaultVoice);
    final resolvedInputAudioFormat =
        nullIfBlank(inputAudioFormat) ??
        nullIfBlank(model.realtime.inputFormat);
    final resolvedOutputAudioFormat =
        nullIfBlank(outputAudioFormat) ??
        nullIfBlank(model.realtime.outputFormat);
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          ...model.realtime.sessionDefaults,
          'model': model.resolveOperationModelId(family),
          if (modalities != null) 'modalities': modalities,
          if (instructions != null) 'instructions': instructions,
          if (turnDetection != null) 'turn_detection': turnDetection,
          if (tools != null) 'tools': tools,
          if (resolvedVoice != null) 'voice': resolvedVoice,
          if (resolvedInputAudioFormat != null)
            'input_audio_format': resolvedInputAudioFormat,
          if (resolvedOutputAudioFormat != null)
            'output_audio_format': resolvedOutputAudioFormat,
        });
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
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'realtime/sessions',
    );
    final clientSecret = payload['client_secret'];
    final nestedSecret = AiOperationHttp.jsonMapOrEmpty(clientSecret);
    final sessionId = optionalStringFromValue(payload['id']);
    final clientSecretValue = optionalStringFromValue(
      nestedSecret['value'] ?? payload['client_secret'],
    );
    return AiRealtimeSessionResult(
      rawResponse: response.body,
      payload: payload,
      sessionId: sessionId,
      clientSecret: clientSecretValue,
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
