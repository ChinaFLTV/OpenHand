import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/home/openhand_home_page.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets('write approval consumes Escape and blocks system back', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      _testApp(onContext: (context) => hostContext = context),
    );
    final result = showWriteCommandConfirmationDialog(
      hostContext,
      request: _writeRequest(),
    );
    await _pumpDialogTransition(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Confirm Write Command'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Confirm Write Command'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpDialogTransition(tester);

    expect(await result, BashCommandApprovalDecision.approved);
    expect(find.text('Confirm Write Command'), findsNothing);
    expect(find.text('host-page'), findsOneWidget);
  });

  testWidgets('write approval timeout cannot dismiss its covering route', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late BuildContext hostContext;
    await tester.pumpWidget(
      _testApp(
        navigatorKey: navigatorKey,
        onContext: (context) => hostContext = context,
      ),
    );
    final now = DateTime.now().toUtc();
    final session = showWriteCommandConfirmationDialogSession(
      hostContext,
      request: _writeRequest(
        requestedAt: now.subtract(const Duration(seconds: 2)),
        expiresAt: now.subtract(const Duration(seconds: 1)),
      ),
    );
    final cover = showAnimatedDialog<void>(
      context: hostContext,
      builder: (_) => const AlertDialog(content: Text('write-cover')),
    );
    await _pumpDialogTransition(tester);

    expect(find.text('write-cover'), findsOneWidget);
    expect(find.text('Confirm Write Command'), findsOneWidget);
    expect(session.isClosed, isFalse);

    navigatorKey.currentState!.pop();
    await _pumpDialogTransition(tester);
    await cover;
    await session.closed;

    expect(await session.result, BashCommandApprovalDecision.timedOut);
    expect(find.text('write-cover'), findsNothing);
    expect(find.text('Confirm Write Command'), findsNothing);
    expect(find.text('host-page'), findsOneWidget);
  });
}

BashCommandApprovalRequest _writeRequest({
  DateTime? requestedAt,
  DateTime? expiresAt,
}) {
  final requested = requestedAt ?? DateTime.now().toUtc();
  return BashCommandApprovalRequest(
    command: 'touch example.txt',
    workingDirectory: '/tmp',
    isWriteCommand: true,
    requestedAt: requested,
    expiresAt: expiresAt ?? requested.add(const Duration(minutes: 10)),
  );
}

Future<void> _pumpDialogTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Widget _testApp({
  GlobalKey<NavigatorState>? navigatorKey,
  required ValueChanged<BuildContext> onContext,
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        onContext(context);
        return const Scaffold(body: Center(child: Text('host-page')));
      },
    ),
  );
}
