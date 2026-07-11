import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_menu.dart';

void main() {
  testWidgets('anchored menu animates barrier dismissal before removal', (
    tester,
  ) async {
    await tester.pumpWidget(const _AnchoredMenuHarness());

    await tester.tap(find.byKey(const ValueKey<String>('open-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey<String>('menu-content')), findsOneWidget);

    await tester.tapAt(const Offset(790, 590));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(const ValueKey<String>('menu-content')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('menu-content')), findsNothing);
  });

  testWidgets('anchored menu returns a value through animated route pop', (
    tester,
  ) async {
    await tester.pumpWidget(const _AnchoredMenuHarness());

    await tester.tap(find.byKey(const ValueKey<String>('open-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('select-menu-value')));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('menu-content')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('selected: applied'), findsOneWidget);
  });
}

class _AnchoredMenuHarness extends StatefulWidget {
  const _AnchoredMenuHarness();

  @override
  State<_AnchoredMenuHarness> createState() => _AnchoredMenuHarnessState();
}

class _AnchoredMenuHarnessState extends State<_AnchoredMenuHarness> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (anchorContext) => Column(
            children: [
              ElevatedButton(
                key: const ValueKey<String>('open-menu'),
                onPressed: () async {
                  final selected = await showAnimatedAnchoredMenu<String>(
                    context: anchorContext,
                    builder: (menuContext) => Material(
                      key: const ValueKey<String>('menu-content'),
                      child: SizedBox(
                        width: 220,
                        height: 120,
                        child: Center(
                          child: TextButton(
                            key: const ValueKey<String>('select-menu-value'),
                            onPressed: () =>
                                Navigator.of(menuContext).pop('applied'),
                            child: const Text('Apply'),
                          ),
                        ),
                      ),
                    ),
                  );
                  if (mounted && selected != null) {
                    setState(() => _selected = selected);
                  }
                },
                child: const Text('Open'),
              ),
              Text('selected: ${_selected ?? 'none'}'),
            ],
          ),
        ),
      ),
    );
  }
}
