import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/operations/ai_audio_io_service.dart';
import 'package:openhand/features/ai/service/operations/ai_image_edit_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

http.StreamedResponse _jsonResponse(int statusCode, Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

AiModelConfig _config() {
  return const AiModelConfig(
    id: 'provider-1',
    baseUrl: 'https://relay.example.com/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'sk-test',
    modelId: 'gpt-4.1-mini',
    protocolType: AiProtocolType.openai,
  );
}

void main() {
  test('audio io service uploads file with multipart request', () async {
    late http.BaseRequest captured;
    final temp = await File(
      '${Directory.systemTemp.path}/openhand-audio-upload-test.wav',
    ).writeAsBytes(const <int>[1, 2, 3, 4]);
    final service = AiAudioIoService(
      transport: AiTransportClient(
        client: _FakeHttpClient((request) async {
          captured = request;
          return _jsonResponse(200, <String, Object?>{'text': 'ok'});
        }),
      ),
    );

    final result = await service.transcribe(
      model: _config(),
      filePath: temp.path,
    );

    expect(captured, isA<http.MultipartRequest>());
    expect(result.text, 'ok');
  });

  test('image edit service uploads image with multipart request', () async {
    late http.BaseRequest captured;
    final temp = await File(
      '${Directory.systemTemp.path}/openhand-image-edit-test.png',
    ).writeAsBytes(const <int>[137, 80, 78, 71]);
    final service = AiImageEditService(
      transport: AiTransportClient(
        client: _FakeHttpClient((request) async {
          captured = request;
          return _jsonResponse(200, <String, Object?>{'data': <Object?>[]});
        }),
      ),
    );

    await service.editImage(
      model: _config(),
      prompt: 'fix image',
      imageFilePath: temp.path,
    );

    expect(captured, isA<http.MultipartRequest>());
  });
}
