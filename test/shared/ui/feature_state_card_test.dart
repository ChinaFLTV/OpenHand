import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/feature_state_card.dart';

void main() {
  testWidgets('centered state card does not overflow in short containers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 560,
            height: 132,
            child: FeatureStateCard.centered(
              icon: Icons.error_outline_rounded,
              title: 'Load failed',
              body: List<String>.filled(8, 'Details').join(' '),
              action: const FilledButton(onPressed: null, child: Text('Retry')),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
