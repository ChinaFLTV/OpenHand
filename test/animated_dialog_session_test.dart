import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  const animatedEntrance = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.fade,
    exitStyle: DialogAnimationStyle.none,
    durationMs: 300,
  );
  const animatedExit = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.none,
    exitStyle: DialogAnimationStyle.fade,
    durationMs: 300,
  );

  testWidgets('tracked dialog preserves a typed user result', (tester) async {
    final context = await _pumpHost(tester);
    final session = showTrackedAnimatedDialog<bool>(
      context: context,
      settings: animatedEntrance,
      builder: (dialogContext) => AlertDialog(
        content: const Text('typed-dialog'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('confirm'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('confirm'));
    await tester.pumpAndSettle();

    expect(await session.result, isTrue);
    await session.closed;
    expect(session.isClosed, isTrue);
    expect(find.text('host-page'), findsOneWidget);
  });

  testWidgets('exit none dismisses in one frame with the requested result', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    final session = _showTestDialog(
      context,
      settings: animatedEntrance,
      label: 'instant-exit',
    );
    await tester.pumpAndSettle();

    final dismissed = session.dismiss(result: true);
    await tester.pump();

    expect(await dismissed, isTrue);
    await tester.pump();
    expect(await session.result, isTrue);
    expect(find.text('instant-exit'), findsNothing);
    expect(find.text('host-page'), findsOneWidget);
  });

  testWidgets('entrance none still honors an animated exit duration', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    final session = _showTestDialog(
      context,
      settings: animatedExit,
      label: 'animated-exit',
    );
    await tester.pump();
    expect(find.text('animated-exit'), findsOneWidget);
    await tester.pump();

    final dismissed = session.dismiss(result: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('animated-exit'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(await dismissed, isTrue);
    await tester.pump();
    expect(find.text('animated-exit'), findsNothing);
  });

  testWidgets(
    'concurrent dismiss requests pop once and keep the first result',
    (tester) async {
      final context = await _pumpHost(tester);
      final session = _showTestDialog(
        context,
        settings: animatedEntrance,
        label: 'single-pop',
      );
      await tester.pumpAndSettle();

      final first = session.dismiss(result: true);
      final second = session.dismiss(result: false);
      await tester.pump();

      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(await session.result, isTrue);
      expect(find.text('host-page'), findsOneWidget);
    },
  );

  testWidgets('dismiss before first build waits for route attachment', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    final session = _showTestDialog(
      context,
      settings: animatedEntrance,
      label: 'early-dismiss',
    );

    final dismissed = session.dismiss(result: true);
    await tester.pump();
    await tester.pump();

    expect(await dismissed, isTrue);
    expect(await session.result, isTrue);
    expect(find.text('early-dismiss'), findsNothing);
    expect(find.text('host-page'), findsOneWidget);
  });

  testWidgets('covered tracked dialog defers without closing the top route', (
    tester,
  ) async {
    final context = await _pumpHost(tester);
    final session = _showTestDialog(
      context,
      settings: animatedEntrance,
      label: 'tracked-underlay',
    );
    await tester.pumpAndSettle();

    final cover = showAnimatedDialog<void>(
      context: context,
      settings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.none,
        exitStyle: DialogAnimationStyle.none,
      ),
      builder: (coverContext) => AlertDialog(
        content: const Text('cover-dialog'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(coverContext).pop(),
            child: const Text('close-cover'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(await session.dismiss(result: true), isTrue);
    await tester.pump();
    expect(find.text('cover-dialog'), findsOneWidget);
    expect(find.text('tracked-underlay'), findsOneWidget);

    await tester.tap(find.text('close-cover'));
    await tester.pump();
    await cover;
    await tester.pump();

    expect(await session.result, isTrue);
    expect(find.text('cover-dialog'), findsNothing);
    expect(find.text('tracked-underlay'), findsNothing);
    expect(find.text('host-page'), findsOneWidget);
  });
}

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (hostContext) {
          context = hostContext;
          return const Scaffold(body: Text('host-page'));
        },
      ),
    ),
  );
  return context;
}

OpenHandDialogSession<bool> _showTestDialog(
  BuildContext context, {
  required DialogAnimationSettings settings,
  required String label,
}) {
  return showTrackedAnimatedDialog<bool>(
    context: context,
    settings: settings,
    builder: (_) => AlertDialog(content: Text(label)),
  );
}
