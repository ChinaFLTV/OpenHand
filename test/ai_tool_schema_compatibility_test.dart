import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';

void main() {
  group('tool parameter root compatibility', () {
    test('marks shorthand anyOf aliases as object branches', () {
      final tool = stableToolDefinitionForAiRequest(
        const AiToolDefinition(
          name: 'Bash',
          description: 'Run a command.',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'command': <String, Object?>{'type': 'string'},
              'cmd': <String, Object?>{'type': 'string'},
            },
            'anyOf': <Object?>[
              <String, Object?>{
                'required': <String>['command'],
              },
              <String, Object?>{
                'required': <String>['cmd'],
              },
            ],
          },
        ),
      );

      expect(tool.parameters['type'], 'object');
      expect(tool.parameters['anyOf'], <Object?>[
        <String, Object?>{
          'required': <String>['command'],
          'type': 'object',
        },
        <String, Object?>{
          'required': <String>['cmd'],
          'type': 'object',
        },
      ]);
    });

    test('removes impossible non-object union branches', () {
      final normalized = objectRootToolSchemaForAiRequest(
        const <String, Object?>{
          'oneOf': <Object?>[
            <String, Object?>{
              'type': <String>['object', 'null'],
              'required': <String>['value'],
            },
            <String, Object?>{'type': 'string'},
            false,
          ],
        },
      );

      expect(normalized, <String, Object?>{
        'type': 'object',
        'oneOf': <Object?>[
          <String, Object?>{
            'type': 'object',
            'required': <String>['value'],
          },
        ],
      });
    });

    test('falls back to an unconstrained object for invalid root unions', () {
      final normalized = objectRootToolSchemaForAiRequest(
        const <String, Object?>{
          'type': 'array',
          'anyOf': <Object?>[
            <String, Object?>{'type': 'string'},
            false,
          ],
        },
      );

      expect(normalized, const <String, Object?>{'type': 'object'});
    });
  });
}
