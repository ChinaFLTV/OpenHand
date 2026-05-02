import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_dsml_partial_stream_scanner.dart';

void main() {
  group('scanPartialDsmlInvokes', () {
    test('returns empty for buffer without DSML markup', () {
      expect(scanPartialDsmlInvokes('hello world'), isEmpty);
    });

    test('parses a single complete invoke with parameters', () {
      const buffer = '''
prelude
<DSML:invoke name="Bash">
<DSML:parameter name="command">ls -la</DSML:parameter>
</DSML:invoke>
trailing
''';
      final result = scanPartialDsmlInvokes(buffer);
      expect(result, hasLength(1));
      expect(result.first.name, 'Bash');
      expect(result.first.id, 'dsml-tool-call-1');
      expect(result.first.isComplete, isTrue);
      expect(result.first.argumentsJson, contains('ls -la'));
    });

    test('parses a partial invoke (no closing tag)', () {
      const buffer = '''
<DSML:invoke name="Read">
<DSML:parameter name="path">lib/main.dart</DSML:parameter>
''';
      final result = scanPartialDsmlInvokes(buffer);
      expect(result, hasLength(1));
      expect(result.first.name, 'Read');
      expect(result.first.isComplete, isFalse);
      expect(result.first.argumentsJson, contains('lib/main.dart'));
    });

    test('parses a partial invoke with no parameters yet', () {
      const buffer = '<DSML:invoke name="Glob">';
      final result = scanPartialDsmlInvokes(buffer);
      expect(result, hasLength(1));
      expect(result.first.name, 'Glob');
      expect(result.first.argumentsJson, '{}');
      expect(result.first.isComplete, isFalse);
    });

    test('handles multiple complete invokes with sequential IDs', () {
      const buffer = '''
<DSML:invoke name="Read">
<DSML:parameter name="path">a</DSML:parameter>
</DSML:invoke>
<DSML:invoke name="Read">
<DSML:parameter name="path">b</DSML:parameter>
</DSML:invoke>
''';
      final result = scanPartialDsmlInvokes(buffer);
      expect(result.map((i) => i.id).toList(), [
        'dsml-tool-call-1',
        'dsml-tool-call-2',
      ]);
      expect(result.every((i) => i.isComplete), isTrue);
    });

    test('handles complete + trailing partial mix', () {
      const buffer = '''
<DSML:invoke name="Read">
<DSML:parameter name="path">a</DSML:parameter>
</DSML:invoke>
<DSML:invoke name="Bash">
<DSML:parameter name="command">echo
''';
      final result = scanPartialDsmlInvokes(buffer);
      expect(result, hasLength(2));
      expect(result[0].isComplete, isTrue);
      expect(result[1].isComplete, isFalse);
      expect(result[1].name, 'Bash');
    });

    test('skips invoke with empty name attribute', () {
      const buffer = '<DSML:invoke name="">body</DSML:invoke>';
      expect(scanPartialDsmlInvokes(buffer), isEmpty);
    });
  });
}
