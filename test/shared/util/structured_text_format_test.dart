import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/structured_text_format.dart';

void main() {
  group('StructuredTextFormatResult', () {
    test('round-trips maps and parses format names leniently', () {
      final result = StructuredTextFormatResult.fromMap(<String, Object?>{
        'text': 'value',
        'format': ' YAML ',
      });

      expect(result.text, 'value');
      expect(result.format, StructuredTextFormat.yaml);
      expect(result.toMap(), <String, Object?>{
        'text': 'value',
        'format': 'yaml',
      });
    });

    test('ignores unknown format names', () {
      final result = StructuredTextFormatResult.fromMap(<String, Object?>{
        'text': 'value',
        'format': 'unknown',
      });

      expect(result.format, isNull);
    });
  });

  group('formatStructuredTextForDisplay', () {
    test('formats JSON objects', () {
      final result = formatStructuredTextForDisplay('{"b":2,"a":1}');

      expect(result.format, StructuredTextFormat.json);
      expect(result.text, '{\n  "b": 2,\n  "a": 1\n}');
    });

    test('formats XML documents', () {
      final result = formatStructuredTextForDisplay(
        '<root><item>1</item></root>',
      );

      expect(result.format, StructuredTextFormat.xml);
      expect(result.text, contains('<root>'));
      expect(result.text, contains('<item>1</item>'));
    });

    test('formats YAML as JSON-safe display text', () {
      final result = formatStructuredTextForDisplay(
        'name: OpenHand\nitems:\n  - 1',
      );

      expect(result.format, StructuredTextFormat.yaml);
      expect(
        result.text,
        '{\n  "name": "OpenHand",\n  "items": [\n    1\n  ]\n}',
      );
    });

    test('keeps malformed structured text trimmed and unformatted', () {
      final result = formatStructuredTextForDisplay('  {"missing":  ');

      expect(result.format, isNull);
      expect(result.text, '{"missing":');
    });

    test(
      'stringifies non-finite YAML numbers instead of dropping formatting',
      () {
        final result = formatStructuredTextForDisplay('value: .nan');

        expect(result.format, StructuredTextFormat.yaml);
        expect(result.text, contains('"value": "NaN"'));
      },
    );

    test('caps very deep YAML values before JSON encoding', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 70; i++) {
        buffer.writeln('${'  ' * i}level$i:');
      }
      buffer.writeln('${'  ' * 70}done');

      final result = formatStructuredTextForDisplay(buffer.toString());

      expect(result.format, StructuredTextFormat.yaml);
      expect(result.text, contains('<max-depth>'));
    });
  });

  group('structuredTextFormatLabel', () {
    test('returns display labels', () {
      expect(structuredTextFormatLabel(StructuredTextFormat.json), 'JSON');
      expect(structuredTextFormatLabel(StructuredTextFormat.xml), 'XML');
      expect(structuredTextFormatLabel(StructuredTextFormat.yaml), 'YAML');
    });
  });
}
