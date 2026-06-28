import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'StepFun image-to-image falls back for non-finite source weight',
    () async {
      final client = _CapturePostClient(
        responseBody: jsonEncode(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{'b64_json': _onePixelPngBase64},
          ],
        }),
      );
      final service = AiImageGenerationService(client: client);
      final tempDir = await Directory.systemTemp.createTemp('openhand_media_');
      final imageFile = File('${tempDir.path}/reference.png');
      await imageFile.writeAsBytes(base64Decode(_onePixelPngBase64));

      try {
        final result = await service.generateImage(
          model: const AiModelConfig(
            id: 'stepfun',
            baseUrl: 'https://api.stepfun.com',
            authScheme: AiAuthScheme.bearer,
            token: 'test-token',
            modelId: 'step-image-test',
            protocolType: AiProtocolType.stepfun,
          ),
          prompt: 'make it brighter',
          options: const AiCreationOptions(quality: 'Infinity', style: 'NaN'),
          referenceImages: <AiChatContentPart>[
            AiChatContentPart.imageFile(
              filePath: imageFile.path,
              mimeType: 'image/png',
            ),
          ],
        );

        expect(result.markdown, contains('![make it brighter]('));
        expect(client.postedJson['source_weight'], 0.5);
        expect(client.postedJson.containsKey('steps'), isFalse);
        expect(client.postedJson.containsKey('cfg_scale'), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );
}

const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

class _CapturePostClient extends http.BaseClient {
  _CapturePostClient({required this.responseBody});

  final String responseBody;
  Map<String, Object?> postedJson = const <String, Object?>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map) {
        postedJson = Map<String, Object?>.from(decoded);
      }
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(responseBody)),
      200,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }
}
