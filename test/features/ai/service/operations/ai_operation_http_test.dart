import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/operations/ai_operation_http.dart';

void main() {
  group('AiOperationHttp', () {
    test('builds auth headers without dropping custom endpoint headers', () {
      const model = AiModelConfig(
        id: 'test',
        baseUrl: 'https://api.example.test',
        authScheme: AiAuthScheme.bearer,
        token: 'secret',
        modelId: 'model',
        protocolType: AiProtocolType.openai,
        customHeaders: <String, String>{'x-custom': 'one'},
      );

      final headers = AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: const <String, String>{'x-endpoint': 'two'},
      );

      expect(headers['content-type'], 'application/json');
      expect(headers['authorization'], 'Bearer secret');
      expect(headers['x-custom'], 'one');
      expect(headers['x-endpoint'], 'two');
    });

    test('supports multipart accept-json headers without content-type', () {
      const model = AiModelConfig(
        id: 'test',
        baseUrl: 'https://api.example.test',
        authScheme: AiAuthScheme.apiKey,
        token: 'secret',
        modelId: 'model',
        protocolType: AiProtocolType.openai,
      );

      final headers = AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: const <String, String>{},
        includeJsonContentType: false,
        acceptJson: true,
      );

      expect(headers.containsKey('content-type'), isFalse);
      expect(headers['accept'], 'application/json');
      expect(headers['x-api-key'], 'secret');
    });

    test('decodes maps and annotates malformed JSON', () {
      expect(
        AiOperationHttp.jsonMapOrEmpty(
          AiOperationHttp.decodeJsonResponse('{"ok": true}', contextHint: 'x'),
        ),
        <String, Object?>{'ok': true},
      );

      expect(
        () => AiOperationHttp.decodeJsonResponse('{', contextHint: 'responses'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('responses'),
          ),
        ),
      );
    });
  });
}
