import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_endpoint_override.dart';

void main() {
  group('AiEndpointOverride.fromJson', () {
    test('parses loose map values and sanitizes string maps', () {
      final override = AiEndpointOverride.fromJson(<Object?, Object?>{
        'path': ' /v1/chat/completions ',
        'method': 123,
        'transport': '  sse ',
        'headers': <Object?, Object?>{
          ' Authorization ': ' Bearer token ',
          'Blank': '   ',
          'Null': null,
        },
        'query_defaults': <Object?, Object?>{'limit': 20},
      });

      expect(override, isNotNull);
      expect(override!.path, '/v1/chat/completions');
      expect(override.method, '123');
      expect(override.transport, 'sse');
      expect(override.headers, <String, String>{
        'Authorization': 'Bearer token',
      });
      expect(override.queryDefaults, <String, String>{'limit': '20'});
    });

    test('parses JSON string input without throwing on invalid text', () {
      final override = AiEndpointOverride.fromJson(
        '{"url":" https://example.com/v1 ","headers":{"X-Test":" ok "}}',
      );

      expect(override, isNotNull);
      expect(override!.url, 'https://example.com/v1');
      expect(override.headers, <String, String>{'X-Test': 'ok'});
      expect(AiEndpointOverride.fromJson('not-json'), isNull);
      expect(AiEndpointOverride.fromJson('[]'), isNull);
    });
  });

  group('parseAiEndpointOverrides', () {
    test('accepts JSON text and ignores unknown or empty entries', () {
      final overrides = parseAiEndpointOverrides('''
        {
          "chat_completions": {"url": "https://chat.example.com"},
          "responses": {"headers": {"X-Mode": "responses"}},
          "unknown": {"url": "https://ignored.example.com"},
          "embeddings": {}
        }
      ''');

      expect(overrides.keys, <AiApiFamily>[
        AiApiFamily.chatCompletions,
        AiApiFamily.responses,
      ]);
      expect(
        overrides[AiApiFamily.chatCompletions]!.url,
        'https://chat.example.com',
      );
      expect(overrides[AiApiFamily.responses]!.headers, <String, String>{
        'X-Mode': 'responses',
      });
    });
  });
}
