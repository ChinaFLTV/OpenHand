import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/dsml/ai_dsml_partial_stream_scanner.dart';
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

  group('DSML parameter string attribute', () {
    test('uses shared boolean parsing for completed tool calls', () {
      final result = extractDsmlToolCalls(
        '<DSML:invoke name="demo">'
        '<DSML:parameter name="enabled" string="off">off</DSML:parameter>'
        '<DSML:parameter name="label">off</DSML:parameter>'
        '</DSML:invoke>',
      );

      final args =
          jsonDecode(result.toolCalls.single.arguments) as Map<String, Object?>;
      expect(args['enabled'], isFalse);
      expect(args['label'], 'off');
    });

    test('uses the same attribute parsing for partial tool calls', () {
      final invokes = scanPartialDsmlInvokes(
        '<DSML:invoke name="demo">'
        '<DSML:parameter name="enabled" string="no">yes</DSML:parameter>',
      );

      final args =
          jsonDecode(invokes.single.argumentsJson) as Map<String, Object?>;
      expect(invokes.single.isComplete, isFalse);
      expect(args['enabled'], isTrue);
    });
  });
}
