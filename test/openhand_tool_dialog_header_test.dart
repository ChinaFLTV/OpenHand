import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('tool dialog header wraps actions on compact widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _HeaderHarness(
        width: kOpenHandToolDialogHeaderCompactBreakpoint - 1,
      ),
    );

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.text('Responsive Tool Dialog Header'), findsOneWidget);
  });

  testWidgets('tool dialog header keeps actions inline on wide widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _HeaderHarness(
        width: kOpenHandToolDialogHeaderCompactBreakpoint + 180,
      ),
    );

    expect(find.byType(Wrap), findsNothing);
    expect(find.byKey(const ValueKey<String>('copy-action')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('refresh-action')),
      findsOneWidget,
    );
  });
}

class _HeaderHarness extends StatelessWidget {
  const _HeaderHarness({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: SizedBox(
                width: width,
                child: buildOpenHandToolDialogHeader(
                  context: context,
                  icon: Icons.build_rounded,
                  title: 'Responsive Tool Dialog Header',
                  subtitle: 'Compact titles must not collide with actions.',
                  actions: [
                    IconButton(
                      key: const ValueKey<String>('copy-action'),
                      onPressed: () {},
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    IconButton(
                      key: const ValueKey<String>('refresh-action'),
                      onPressed: () {},
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
