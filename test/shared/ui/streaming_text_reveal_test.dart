import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/streaming_text_reveal.dart';

void main() {
  testWidgets('StreamingTextRevealText stages streaming text by grapheme', (
    tester,
  ) async {
    var visible = '<unset>';

    await tester.pumpWidget(
      _host(
        StreamingTextRevealText(
          text: 'A🙂B',
          streaming: true,
          builder: (context, text) {
            visible = text;
            return Text(text);
          },
        ),
      ),
    );

    expect(visible, isEmpty);

    await tester.pump(const Duration(milliseconds: 20));
    expect(visible, 'A');

    await tester.pump(const Duration(milliseconds: 20));
    expect(visible, 'A🙂');

    await tester.pump(const Duration(milliseconds: 20));
    expect(visible, 'A🙂B');
  });

  testWidgets('StreamingTextRevealText bypasses staging when not streaming', (
    tester,
  ) async {
    var visible = '<unset>';

    await tester.pumpWidget(
      _host(
        StreamingTextRevealText(
          text: 'complete',
          streaming: false,
          builder: (context, text) {
            visible = text;
            return Text(text);
          },
        ),
      ),
    );

    expect(visible, 'complete');
  });
}

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}
