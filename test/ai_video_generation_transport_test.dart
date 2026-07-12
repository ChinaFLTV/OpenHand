import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_api_dialect.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/operations/ai_video_generation_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  const model = AiModelConfig(
    id: 'video-transport-test',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: 'sora-2',
    protocolType: AiProtocolType.openai,
    providerKind: AiProviderKind.openai,
  );

  test('video content is returned as a file-backed result', () async {
    final client = _CallbackClient(
      (request) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable(const <List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ]),
        200,
        request: request,
        headers: const <String, String>{'content-type': 'video/mp4'},
      ),
    );
    final transport = AiTransportClient(client: client);
    final service = AiVideoGenerationService(transport: transport);

    final result = await service.getVideoContent(model: model, id: 'video-1');
    final filePath = result.filePath;
    try {
      expect(result.hasFile, isTrue);
      expect(result.byteLength, 4);
      expect(result.rawResponse, isEmpty);
      expect(filePath, isNotNull);
      expect(await result.openRead().expand((chunk) => chunk).toList(), <int>[
        1,
        2,
        3,
        4,
      ]);
    } finally {
      if (filePath != null) {
        try {
          await File(filePath).delete();
        } on FileSystemException {
          // Test cleanup only.
        }
      }
      service.dispose();
    }
  });
}

class _CallbackClient extends http.BaseClient {
  _CallbackClient(this.onSend);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);
}
