import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/choice_input_dialog.dart';

void main() {
  Widget host({bool tickerEnabled = true, bool disableAnimations = false}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: TickerMode(enabled: tickerEnabled, child: child!),
        );
      },
      home: Builder(
        builder: (context) {
          return TextButton(
            onPressed: () {
              showChoiceInputDialog(
                context: context,
                title: 'Choose',
                options: const [ChoiceInputOption(value: 'a', label: 'A')],
              );
            },
            child: const Text('open'),
          );
        },
      ),
    );
  }

  Future<void> openAndSelectCustom(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final customOption = find.text('Custom input');
    final customTile = find.ancestor(
      of: customOption,
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(customTile).onTap!();
    await tester.pump();
  }

  Finder customFieldSizeAnimation() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedSize && widget.curve == Curves.easeInOutCubic,
    );
  }

  testWidgets('Choice input disables custom field motion with ticker off', (
    tester,
  ) async {
    await tester.pumpWidget(host(tickerEnabled: false));

    await openAndSelectCustom(tester);

    expect(customFieldSizeAnimation(), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
    'Choice input disables custom field motion when animations are off',
    (tester) async {
      await tester.pumpWidget(host(disableAnimations: true));

      await openAndSelectCustom(tester);

      expect(customFieldSizeAnimation(), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    },
  );
}
