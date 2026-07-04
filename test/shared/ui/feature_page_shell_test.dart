import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/feature_page_shell.dart';

void main() {
  Widget shell() {
    return const FeaturePageShell(
      title: 'Title',
      subtitle: 'Subtitle',
      actions: Text('Actions'),
      notices: <Widget>[Text('Notice')],
      body: Text('Body'),
    );
  }

  Finder shellDescendant(Type type) {
    return find.descendant(
      of: find.byType(FeaturePageShell),
      matching: find.byType(type),
    );
  }

  testWidgets('FeaturePageShell renders directly when ticker is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TickerMode(enabled: false, child: shell())),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Notice'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(shellDescendant(AnimatedSwitcher), findsNothing);
    expect(shellDescendant(SizeTransition), findsNothing);
    expect(shellDescendant(SlideTransition), findsNothing);
  });

  testWidgets('FeaturePageShell renders directly when animations disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: shell(),
          ),
        ),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Notice'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(shellDescendant(AnimatedSwitcher), findsNothing);
    expect(shellDescendant(SizeTransition), findsNothing);
    expect(shellDescendant(SlideTransition), findsNothing);
  });
}
