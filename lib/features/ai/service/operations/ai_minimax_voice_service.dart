import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

/// Loads provider-managed MiniMax voices for the TTS settings surface.
final class AiMiniMaxVoiceService {
  AiMiniMaxVoiceService({
    AiTransportClient? transport,
    this._router = const AiEndpointRouter(),
  }) : _transport = transport ?? AiTransportClient(),
       _ownsTransport = transport == null;

  static const int _maxResponseBytes = 4 * kBytesPerMiB;
  static const Set<String> _voiceTypes = <String>{
    'system',
    'voice_cloning',
    'voice_generation',
    'all',
  };

  final AiTransportClient _transport;
  final AiEndpointRouter _router;
  final bool _ownsTransport;

  Future<Map<String, Object?>> loadVoices({
    required AiModelConfig model,
    String voiceType = 'all',
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    _validateModel(model);
    if (!_voiceTypes.contains(voiceType)) {
      throw ArgumentError.value(
        voiceType,
        'voiceType',
        'Unsupported MiniMax voice type.',
      );
    }
    final endpoint = _router.resolveProviderPath(
      model,
      AiApiFamily.audioVoices,
      path: 'v1/get_voice',
    );
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        acceptJson: true,
      ),
      body: <String, Object?>{'voice_type': voiceType},
      timeout: timeout,
      maxResponseBytes: _maxResponseBytes,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'MiniMax get_voice',
    );
    AiOperationHttp.throwIfProviderFailed(
      payload,
      contextHint: 'MiniMax get_voice',
    );
    return Map<String, Object?>.unmodifiable(payload);
  }

  void _validateModel(AiModelConfig model) {
    if (model.protocolType != AiProtocolType.minimax) {
      throw ArgumentError.value(
        model.protocolType.storageValue,
        'model.protocolType',
        'MiniMax voice loading requires the MiniMax protocol.',
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

  void dispose() {
    if (_ownsTransport) _transport.dispose();
  }
}
