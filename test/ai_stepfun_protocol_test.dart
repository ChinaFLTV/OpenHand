import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  group('StepFun protocol coverage', () {
    test('parses OpenAI-compatible tool calls', () {
      final adapter = AiProtocolRegistry.adapterFor(AiProtocolType.stepfun);
      final calls = adapter.parseToolCalls(
        jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'tool_calls': <Object?>[
                  <String, Object?>{
                    'id': 'call_1',
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': 'lookup_weather',
                      'arguments': <String, Object?>{'city': '上海'},
                    },
                  },
                ],
              },
            },
          ],
        }),
      );

      expect(calls, hasLength(1));
      expect(calls.single.id, 'call_1');
      expect(calls.single.name, 'lookup_weather');
      expect(jsonDecode(calls.single.arguments), <String, Object?>{
        'city': '上海',
      });
    });

    test('recognises Step 3.7 Flash as a multimodal model', () {
      final profile = AiModelCatalog.lookup(
        'step-3.7-flash',
        AiProtocolType.stepfun,
      );

      expect(profile, isNotNull);
      expect(profile!.supportsAttachments, isTrue);
      expect(profile.supportedModalities, contains(AiModelModality.image));
      expect(profile.supportedModalities, contains(AiModelModality.video));
    });
  });
}
