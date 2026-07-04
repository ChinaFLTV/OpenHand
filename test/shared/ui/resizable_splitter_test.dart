import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/resizable_splitter.dart';

void main() {
  Widget splitter({bool tickerEnabled = true, bool disableAnimations = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: TickerMode(
          enabled: tickerEnabled,
          child: const SizedBox(
            width: 320,
            height: 160,
            child: ResizableSplitter(
              left: Center(child: Text('left')),
              right: Center(child: Text('right')),
            ),
          ),
        ),
      ),
    );
  }

  Finder handleAnimation() {
    return find.descendant(
      of: find.byType(ResizableSplitter),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedContainer && widget.curve == Curves.easeOutCubic,
      ),
    );
  }

  testWidgets('ResizableSplitter normalizes invalid sizing parameters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 160,
          child: ResizableSplitter(
            initialLeftFraction: double.nan,
            minLeft: -100,
            minRight: double.infinity,
            handleWidth: -8,
            left: Center(child: Text('left')),
            right: Center(child: Text('right')),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('left'), findsOneWidget);
    expect(find.text('right'), findsOneWidget);
  });

  testWidgets('ResizableSplitter disables handle motion with ticker off', (
    tester,
  ) async {
    await tester.pumpWidget(splitter(tickerEnabled: false));

    final handle = tester.widget<AnimatedContainer>(handleAnimation());
    expect(handle.duration, Duration.zero);
  });

  testWidgets(
    'ResizableSplitter disables handle motion when animations are off',
    (tester) async {
      await tester.pumpWidget(splitter(disableAnimations: true));

      final handle = tester.widget<AnimatedContainer>(handleAnimation());
      expect(handle.duration, Duration.zero);
    },
  );
}
