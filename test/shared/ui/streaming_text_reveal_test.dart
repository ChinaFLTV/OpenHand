import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/streaming_text_reveal.dart';

void main() {
  testWidgets(
    'StreamingTextRevealText rebuilds when append crosses graphemes',
    (tester) async {
      await tester.pumpWidget(_buildReveal(text: 'e', streaming: false));
      expect(find.text('e'), findsOneWidget);

      await tester.pumpWidget(_buildReveal(text: 'e\u0301', streaming: true));

      expect(find.text('e\u0301'), findsOneWidget);
      expect(find.text('e'), findsNothing);
    },
  );
}

Widget _buildReveal({required String text, required bool streaming}) {
  return MaterialApp(
    home: StreamingTextRevealText(
      text: text,
      streaming: streaming,
      builder: (context, visibleText) => Text(visibleText),
    ),
  );
}
