import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_snack_bar.dart';

void main() {
  testWidgets('global snack bar normalizes invalid margin and padding', (
    tester,
  ) async {
    await tester.pumpWidget(_buildHost());

    OpenHandGlobalSnackBarHost.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(-8, double.nan, 12, -4),
        padding: EdgeInsets.fromLTRB(double.nan, -1, 4, 6),
        content: Text('safe insets'),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('safe insets'), findsOneWidget);
  });

  testWidgets('global snack bar normalizes invalid width', (tester) async {
    await tester.pumpWidget(_buildHost());

    OpenHandGlobalSnackBarHost.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        width: double.nan,
        content: Text('safe width'),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('safe width'), findsOneWidget);
  });

  testWidgets('global snack bar shows immediately when ticker is disabled', (
    tester,
  ) async {
    var visible = false;
    await tester.pumpWidget(_buildHost(tickerEnabled: false));

    OpenHandGlobalSnackBarHost.showSnackBar(
      SnackBar(
        content: const Text('instant snack'),
        onVisible: () => visible = true,
      ),
    );
    await tester.pump();

    expect(visible, isTrue);
    expect(find.text('instant snack'), findsOneWidget);

    OpenHandGlobalSnackBarHost.hideCurrent();
    await tester.pump();

    expect(find.text('instant snack'), findsNothing);
  });

  testWidgets(
    'global snack bar continues queued items when ticker is disabled',
    (tester) async {
      final visible = <String>[];
      await tester.pumpWidget(_buildHost(tickerEnabled: false));

      OpenHandGlobalSnackBarHost.showSnackBar(
        SnackBar(
          duration: Duration.zero,
          content: const Text('first snack'),
          onVisible: () => visible.add('first'),
        ),
      );
      OpenHandGlobalSnackBarHost.showSnackBar(
        SnackBar(
          content: const Text('second snack'),
          onVisible: () => visible.add('second'),
        ),
      );
      await tester.pump();

      expect(visible, <String>['first', 'second']);
      expect(find.text('first snack'), findsNothing);
      expect(find.text('second snack'), findsOneWidget);
    },
  );
}

Widget _buildHost({bool tickerEnabled = true}) {
  return MaterialApp(
    home: TickerMode(
      enabled: tickerEnabled,
      child: const Scaffold(body: OpenHandGlobalSnackBarHost()),
    ),
  );
}
