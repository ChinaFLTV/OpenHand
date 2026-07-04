import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/motion_preference.dart';

void main() {
  testWidgets('motion durations respect reduce motion and ticker mode', (
    tester,
  ) async {
    Duration? duration;
    Duration? durationMs;

    Widget host({
      required bool disableAnimations,
      required bool tickerEnabled,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: TickerMode(
            enabled: tickerEnabled,
            child: Builder(
              builder: (context) {
                duration = openHandMotionDuration(
                  context,
                  const Duration(milliseconds: 220),
                );
                durationMs = openHandMotionDurationMs(context, 180);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      host(disableAnimations: false, tickerEnabled: true),
    );
    expect(duration, const Duration(milliseconds: 220));
    expect(durationMs, const Duration(milliseconds: 180));

    await tester.pumpWidget(host(disableAnimations: true, tickerEnabled: true));
    expect(duration, Duration.zero);
    expect(durationMs, Duration.zero);

    await tester.pumpWidget(
      host(disableAnimations: false, tickerEnabled: false),
    );
    expect(duration, Duration.zero);
    expect(durationMs, Duration.zero);
  });
}
