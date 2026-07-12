import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server_ops.dart';
import 'package:openhand/features/mcp/widgets/mcp_ops_approval_dialog.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  testWidgets(
    'approval ignores Escape and system back until an explicit choice',
    (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        _testApp(onContext: (context) => hostContext = context),
      );
      final result = showMcpOpsWriteApprovalDialog(
        hostContext,
        request: _approvalRequest(),
      );
      await _pumpDialogTransition(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('MCP Write Call Confirmation'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('MCP Write Call Confirmation'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumpDialogTransition(tester);

      expect(await result, isTrue);
      expect(find.text('MCP Write Call Confirmation'), findsNothing);
      expect(find.text('host-page'), findsOneWidget);
    },
  );

  testWidgets('external dismissal preserves a route covering the approval', (
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
    final session = showMcpOpsWriteApprovalDialogOnNavigator(
      navigatorKey.currentState!,
      context: hostContext,
      request: _approvalRequest(),
    );
    await _pumpDialogTransition(tester);

    final cover = showAnimatedDialog<void>(
      context: hostContext,
      builder: (_) => const AlertDialog(content: Text('cover-route')),
    );
    await _pumpDialogTransition(tester);

    expect(await session.dismiss(), isTrue);
    await tester.pump();
    expect(find.text('cover-route'), findsOneWidget);
    expect(find.text('MCP Write Call Confirmation'), findsOneWidget);

    navigatorKey.currentState!.pop();
    await _pumpDialogTransition(tester);
    await cover;
    await session.closed;

    expect(await session.result, isNull);
    expect(find.text('cover-route'), findsNothing);
    expect(find.text('MCP Write Call Confirmation'), findsNothing);
    expect(find.text('host-page'), findsOneWidget);
  });

  testWidgets(
    'approval timeout preserves its covering route and rejects once',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      late BuildContext hostContext;
      await tester.pumpWidget(
        _testApp(
          navigatorKey: navigatorKey,
          onContext: (context) => hostContext = context,
        ),
      );
      final now = DateTime.now().toUtc();
      final session = showMcpOpsWriteApprovalDialogOnNavigator(
        navigatorKey.currentState!,
        context: hostContext,
        request: _approvalRequest(
          requestedAt: now.subtract(const Duration(seconds: 2)),
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
      );
      await tester.pump();

      final cover = showAnimatedDialog<void>(
        context: hostContext,
        builder: (_) => const AlertDialog(content: Text('timeout-cover')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('timeout-cover'), findsOneWidget);
      expect(find.text('MCP Write Call Confirmation'), findsOneWidget);
      expect(session.isClosed, isFalse);

      navigatorKey.currentState!.pop();
      await _pumpDialogTransition(tester);
      await cover;
      await session.closed;

      expect(await session.result, isFalse);
      expect(find.text('timeout-cover'), findsNothing);
      expect(find.text('MCP Write Call Confirmation'), findsNothing);
      expect(find.text('host-page'), findsOneWidget);
    },
  );
}

McpOpsApprovalRequest _approvalRequest({
  DateTime? requestedAt,
  DateTime? expiresAt,
}) {
  final requested = requestedAt ?? DateTime.now().toUtc();
  return McpOpsApprovalRequest(
    id: 'approval-test',
    toolName: 'write_file',
    clientName: 'test-client',
    ipAddress: '127.0.0.1',
    requestedAt: requested,
    expiresAt: expiresAt ?? requested.add(const Duration(minutes: 10)),
    argumentsPreview: '{"path":"/tmp/example.txt"}',
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
    home: Builder(
      builder: (context) {
        onContext(context);
        return const Scaffold(body: Center(child: Text('host-page')));
      },
    ),
  );
}
