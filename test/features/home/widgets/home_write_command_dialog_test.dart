import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/home/openhand_home_page.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  testWidgets('write command confirmation ignores Esc and approves with Enter', (
    tester,
  ) async {
    BashCommandApprovalDecision? decision;
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showWriteCommandConfirmationDialog(
                  context,
                  request: const BashCommandApprovalRequest(
                    command: 'touch /tmp/openhand-write-test',
                    workingDirectory: '/tmp',
                    isWriteCommand: true,
                  ),
                ).then((value) {
                  decision = value;
                  completed = true;
                });
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Write Command'), findsOneWidget);
    expect(
      find.text(
        'Shortcuts: Enter approves · Esc is ignored; choose Run or Cancel explicitly',
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Write Command'), findsOneWidget);
    expect(completed, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(decision, BashCommandApprovalDecision.approved);
    expect(find.text('Confirm Write Command'), findsNothing);
  });
}
