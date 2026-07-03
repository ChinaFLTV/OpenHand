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
}
