import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

class AiAudioIoResult {
  const AiAudioIoResult({required this.text, required this.rawResponse});

  final String text;
  final String rawResponse;
}

class AiAudioIoService {
  AiAudioIoService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiAudioIoResult> transcribe({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(seconds: 120),
  }) {
    return _sendAudioRequest(
      model: model,
      family: AiApiFamily.audioTranscription,
      filePath: filePath,
      timeout: timeout,
    );
  }

  Future<AiAudioIoResult> translate({
    required AiModelConfig model,
    required String filePath,
    Duration timeout = const Duration(seconds: 120),
  }) {
    return _sendAudioRequest(
      model: model,
      family: AiApiFamily.audioTranslation,
      filePath: filePath,
      timeout: timeout,
    );
  }

  Future<AiAudioIoResult> _sendAudioRequest({
    required AiModelConfig model,
    required AiApiFamily family,
    required String filePath,
    required Duration timeout,
  }) async {
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
      transport: 'multipart',
    );
    final headers = <String, String>{
      'accept': 'application/json',
      ...model.customHeaders,
      ...endpoint.headers,
    };
    final token = model.token.trim();
    if (token.isNotEmpty && model.authScheme != AiAuthScheme.none) {
      if (model.authScheme == AiAuthScheme.apiKey) {
        headers['x-api-key'] = model.authScheme.apply(token);
      } else {
        headers['authorization'] = model.authScheme.apply(token);
      }
    }
    final response = await _transport.sendMultipart(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: headers,
      body: <String, Object?>{
        'model': model.resolveOperationModelId(family),
        'file': AiMultipartUploadFile(filePath: filePath),
      },
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: response.body,
          contextHint: family.storageValue,
        ),
      );
    }
    final decoded = jsonDecode(response.body);
    final text = decoded is Map<String, Object?>
        ? '${decoded['text'] ?? decoded['output_text'] ?? ''}'.trim()
        : '';
    return AiAudioIoResult(text: text, rawResponse: response.body);
  }

  void dispose() {
    _transport.dispose();
  }
}
