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

  testWidgets('StreamingTextReveal renders directly when ticker is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(
          enabled: false,
          child: StreamingTextReveal(
            textLength: 5,
            streaming: true,
            child: Text('hello'),
          ),
        ),
      ),
    );

    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(AnimatedSize), findsNothing);
  });

  testWidgets('StreamingTextRevealText exposes full text without motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: StreamingTextRevealText(
            text: 'hello',
            streaming: true,
            builder: (context, visibleText) => Text(visibleText),
          ),
        ),
      ),
    );

    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(StreamingTextReveal), findsNothing);
  });

  testWidgets('StreamingTextRevealText respects disabled animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StreamingTextRevealText(
            text: 'disabled motion',
            streaming: true,
            builder: (context, visibleText) => Text(visibleText),
          ),
        ),
      ),
    );

    expect(find.text('disabled motion'), findsOneWidget);
    expect(find.byType(StreamingTextReveal), findsNothing);
  });
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
