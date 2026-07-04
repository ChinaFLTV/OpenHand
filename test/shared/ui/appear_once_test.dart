import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/appear_once.dart';

void main() {
  testWidgets('AppearOnce normalizes invalid animation parameters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AppearOnce(
          duration: Duration(milliseconds: -1),
          slideOffset: double.nan,
          child: Text('ready'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('AppearOnce renders directly when ticker is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: false,
          child: AppearOnce(child: Text('ready')),
        ),
      ),
    );

    expect(find.text('ready'), findsOneWidget);
    expect(find.byType(FadeTransition), findsNothing);
  });
}
