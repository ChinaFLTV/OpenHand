import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/dsml/ai_dsml_tool_call_parser.dart';

void main() {
  group('decodeDsmlParameterValue', () {
    test('uses shared boolean parsing for non-string parameters', () {
      expect(decodeDsmlParameterValue('enabled', treatAsString: false), isTrue);
      expect(decodeDsmlParameterValue('off', treatAsString: false), isFalse);
    });

    test('keeps string parameters as text', () {
      expect(decodeDsmlParameterValue('off', treatAsString: true), 'off');
    });
  });
}
