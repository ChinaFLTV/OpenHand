import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/session_io/ai_session_jsonl_exporter.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_indexing_control.dart';
import 'package:openhand/features/knowledge_base/widgets/knowledge_indexing_progress_dialog.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';
import 'package:openhand/shared/ui/export_progress_dialog.dart';

void main() {
  testWidgets('covered export route defers cleanup until its own exit', (
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
    final token = ExportCancelToken();
    final controller = _TrackingExportProgressController(cancelToken: token);
    final session = showExportProgressDialog(
      context: hostContext,
      controller: controller,
      title: 'Export',
      subtitle: 'Exporting',
      cancelLabel: 'Cancel',
    );
    await _pumpDialogTransition(tester);

    final coverFuture = showAnimatedDialog<void>(
      context: hostContext,
      builder: (_) => const AlertDialog(content: Text('cover-route')),
    );
    await _pumpDialogTransition(tester);
    controller.markFinished();

    expect(await session.dismiss(), isTrue);
    expect(session.isClosed, isFalse);
    expect(controller.disposeCount, 0);
    expect(find.text('cover-route'), findsOneWidget);

    navigatorKey.currentState!.pop();
    await _pumpDialogTransition(tester);
    await _pumpDialogTransition(tester);
    await coverFuture;
    await session.closed;

    expect(controller.disposeCount, 1);
    expect(token.isCancelled, isFalse);
    expect(find.text('Exporting'), findsNothing);
  });

  testWidgets(
    'unexpected export close cancels before disposing its controller',
    (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        _testApp(onContext: (context) => hostContext = context),
      );
      final token = ExportCancelToken();
      final controller = _TrackingExportProgressController(cancelToken: token);
      final session = showExportProgressDialog(
        context: hostContext,
        controller: controller,
        title: 'Export',
        subtitle: 'Exporting',
        cancelLabel: 'Cancel',
      );
      await _pumpDialogTransition(tester);

      final dismissFuture = session.dismiss();
      await _pumpDialogTransition(tester);
      expect(await dismissFuture, isTrue);
      await session.closed;

      expect(token.isCancelled, isTrue);
      expect(controller.disposeCount, 1);
      controller
        ..updateProgress(const ExportProgress(processed: 1, total: 1))
        ..markFinished()
        ..requestCancel();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('covered indexing task returns without disposing a live dialog', (
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
    final token = KnowledgeIndexingCancelToken();
    final controller = _TrackingKnowledgeProgressController(cancelToken: token);
    final task = Completer<String?>();
    final runFuture = runKnowledgeIndexingProgressTask<String>(
      context: hostContext,
      controller: controller,
      title: 'Index',
      subtitle: 'Indexing',
      task: () => task.future,
    );
    await _pumpDialogTransition(tester);

    final coverFuture = showAnimatedDialog<void>(
      context: hostContext,
      builder: (_) => const AlertDialog(content: Text('index-cover')),
    );
    await _pumpDialogTransition(tester);
    task.complete('done');
    await tester.pump();

    expect(await runFuture, 'done');
    expect(controller.disposeCount, 0);
    expect(token.isCancelled, isFalse);

    navigatorKey.currentState!.pop();
    await _pumpDialogTransition(tester);
    await _pumpDialogTransition(tester);
    await coverFuture;

      expect(controller.disposeCount, 1);
      expect(token.isCancelled, isFalse);
      expect(find.text('Indexing'), findsNothing);
      controller
        ..updateProgress(
          const KnowledgeIndexingProgress(
            phase: KnowledgeIndexingPhase.embedding,
          ),
        )
        ..markFinished()
        ..requestCancel();
      expect(tester.takeException(), isNull);
  });
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
        return const Scaffold(body: SizedBox.expand());
      },
    ),
  );
}

class _TrackingExportProgressController extends ExportProgressController {
  _TrackingExportProgressController({required super.cancelToken});

  int disposeCount = 0;

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }
}

class _TrackingKnowledgeProgressController
    extends KnowledgeIndexingProgressController {
  _TrackingKnowledgeProgressController({required super.cancelToken});

  int disposeCount = 0;

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }
}
