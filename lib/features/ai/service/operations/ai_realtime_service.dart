import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';

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
  const AiRealtimeConnection({
    required this.channel,
    required this.descriptor,
  });

  final WebSocketChannel channel;
  final AiRealtimeSessionDescriptor descriptor;
}

class AiRealtimeService {
  AiRealtimeService({AiEndpointRouter? router})
    : _router = router ?? const AiEndpointRouter();

  final AiEndpointRouter _router;

  AiRealtimeSessionDescriptor describeSession(AiModelConfig model) {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.realtime,
      method: 'GET',
      transport: 'websocket',
    );
    return AiRealtimeSessionDescriptor(
      url: endpoint.url,
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
}
