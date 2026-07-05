import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/operations/ai_embeddings_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  group('AiEmbeddingsService', () {
    test('sends and applies positive custom dimensions', () async {
      final service = _serviceExpectingBody((body) {
        expect(body['model'], 'embed-test');
        expect(body['input'], 'hello');
        expect(body['dimensions'], 2);
      });

      final result = await service.createEmbedding(
        model: _model(supportsDimensions: true),
        input: 'hello',
        dimensions: 2,
      );

      expect(result.vectors, <List<double>>[
        <double>[0.1, 0.2],
      ]);
      service.dispose();
    });

    test('drops non-positive custom dimensions', () async {
      final service = _serviceExpectingBody((body) {
        expect(body['model'], 'embed-test');
        expect(body['input'], 'hello');
        expect(body.containsKey('dimensions'), isFalse);
      });

      final result = await service.createEmbedding(
        model: _model(supportsDimensions: true),
        input: 'hello',
        dimensions: -2,
      );

      expect(result.vectors, <List<double>>[
        <double>[0.1, 0.2, 0.3],
      ]);
      service.dispose();
    });
  });
}

AiEmbeddingsService _serviceExpectingBody(
  void Function(Map<String, Object?> body) inspect,
) {
  final transport = AiTransportClient(
    client: MockClient((request) async {
      inspect(jsonDecode(request.body) as Map<String, Object?>);
      return http.Response(
        jsonEncode(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'embedding': <double>[0.1, 0.2, 0.3],
            },
          ],
        }),
        200,
      );
    }),
  );
  return AiEmbeddingsService(transport: transport);
}

AiModelConfig _model({required bool supportsDimensions}) {
  return AiModelConfig(
    id: 'embed-test',
    baseUrl: 'https://example.com',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'embed-test',
    protocolType: AiProtocolType.openai,
    capabilityOverrides: const <AiApiFamily, String>{
      AiApiFamily.embeddings: 'embedding_generation',
    },
    modelProfiles: <String, AiModelProfile>{
      'embed-test': AiModelProfile(
        supportedParameters: supportsDimensions
            ? const <String>['dimensions']
            : const <String>[],
      ),
    },
  );
}
