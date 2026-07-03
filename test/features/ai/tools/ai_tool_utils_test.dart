import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';

void main() {
  group('AiToolUtils.decodeArguments', () {
    test('coerces boolean schema values through shared bool parsing', () {
      final decoded = AiToolUtils.decodeArguments(
        '{"enabled":"on","dry_run":"0","label":"on"}',
        parameters: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'enabled': <String, Object?>{'type': 'boolean'},
            'dry_run': <String, Object?>{'type': 'boolean'},
            'label': <String, Object?>{'type': 'string'},
          },
        },
      );

      expect(decoded['enabled'], isTrue);
      expect(decoded['dry_run'], isFalse);
      expect(decoded['label'], 'on');
    });
  });

  group('AiToolUtils string arguments', () {
    test('readString trims values and normalizes blank fallback', () {
      expect(AiToolUtils.readString('  query  '), 'query');
      expect(AiToolUtils.readString(null, fallback: '  default  '), 'default');
      expect(AiToolUtils.readString('  ', fallback: '  default  '), 'default');
    });

    test('readFirstString returns the first non-blank key', () {
      expect(
        AiToolUtils.readFirstString(
          const <String, Object?>{'target': '  ', 'ref': '  HEAD~1  '},
          const <String>['target', 'ref'],
          fallback: 'HEAD',
        ),
        'HEAD~1',
      );
      expect(
        AiToolUtils.readFirstString(const <String, Object?>{}, const <String>[
          'target',
          'ref',
        ], fallback: '  HEAD  '),
        'HEAD',
      );
    });
  });
}
