import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/ansi_text.dart';

void main() {
  final colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);

  test('ansiToSpans applies basic SGR foreground colors', () {
    final spans = ansiToSpans(
      'plain \x1B[31mred\x1B[0m',
      colorScheme: colorScheme,
    );

    expect(spans.map((span) => span.text).toList(), <String>['plain ', 'red']);
    expect(spans.last.style?.color, isNotNull);
  });

  test('ansiToSpans applies truecolor SGR foreground colors', () {
    final spans = ansiToSpans(
      '\x1B[38;2;1;2;3mtrue\x1B[0m',
      colorScheme: colorScheme,
    );

    expect(spans.single.text, 'true');
    expect(spans.single.style?.color, const Color.fromARGB(255, 1, 2, 3));
  });
}
