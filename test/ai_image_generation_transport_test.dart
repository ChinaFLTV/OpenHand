import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_api_dialect.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/media/ai_image_generation_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  const model = AiModelConfig(
    id: 'image-transport-test',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: 'dall-e-3',
    protocolType: AiProtocolType.openai,
    providerKind: AiProviderKind.openai,
  );

  test('media HTTP errors keep status semantics with a bounded body', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final client = _CallbackClient(
      (request) async => http.StreamedResponse(
        controller.stream,
        413,
        request: request,
        headers: const <String, String>{'content-type': 'text/plain'},
      ),
    );
    final service = AiImageGenerationService(client: client);
    final generation = service.generateImage(model: model, prompt: 'test');

    controller.add(
      List<int>.filled(defaultAiTransportErrorResponseMaxBytes + 1, 120),
    );

    final error = await generation.then<AiMediaGenerationException>(
      (_) => throw StateError('Expected image generation to fail.'),
      onError: (Object error, StackTrace _) {
        expect(error, isA<AiMediaGenerationException>());
        return error as AiMediaGenerationException;
      },
    );
    expect(error.message, contains('413'));
    expect(
      error.rawResponseBody?.length,
      defaultAiTransportErrorResponseMaxBytes,
    );
    await cancelled.future.timeout(const Duration(seconds: 1));
    await controller.close();
    service.dispose();
  });

  test('oversized reference images are rejected before transport', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_reference_image_limit_',
    );
    final image = File('${tempDirectory.path}/oversized.png');
    final output = await image.open(mode: FileMode.write);
    await output.setPosition(32 * 1024 * 1024);
    await output.writeByte(0);
    await output.close();
    var requests = 0;
    final client = _CallbackClient((request) async {
      requests += 1;
      return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
    });
    final service = AiImageGenerationService(client: client);
    try {
      await expectLater(
        service.generateImage(
          model: model.copyWith(protocolType: AiProtocolType.agnes),
          prompt: 'test',
          referenceImages: <AiChatContentPart>[
            AiChatContentPart.imageFile(
              filePath: image.path,
              mimeType: 'image/png',
            ),
          ],
        ),
        throwsA(
          isA<AiMediaGenerationException>().having(
            (error) => error.message,
            'message',
            contains('per-file limit'),
          ),
        ),
      );
      expect(requests, 0);
    } finally {
      service.dispose();
      await tempDirectory.delete(recursive: true);
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
