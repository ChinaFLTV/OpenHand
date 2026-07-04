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
}

Widget _buildHost() {
  return const MaterialApp(home: Scaffold(body: OpenHandGlobalSnackBarHost()));
}
