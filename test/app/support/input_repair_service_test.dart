import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/input_repair_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InputRepairService', () {
    tearDown(() {
      InputRepairService.instance.resetForTest();
    });

    setUp(() {
      Future<void> noopTextInput(String _, [Object? unused]) async {}

      InputRepairService.instance.debugKillTrackedChildrenOverride =
          () async {};
      InputRepairService.instance.debugKillDirectChildrenOverride = () async =>
          0;
      InputRepairService.instance.debugTextInputMethodOverride = noopTextInput;
      InputRepairService.instance.debugFocusSettleDelay = Duration.zero;
    });

    testWidgets('does not restore unsafe previous focus nodes', (tester) async {
      final unsafeNode = FocusNode(debugLabel: 'unsafe-node');
      final sentinelNode = FocusNode(debugLabel: 'sentinel-node');
      final editableNode = FocusNode(debugLabel: 'editable-node');
      addTearDown(() {
        unsafeNode.dispose();
        sentinelNode.dispose();
        editableNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Focus(focusNode: sentinelNode, child: const SizedBox.shrink()),
                Focus(focusNode: unsafeNode, child: const SizedBox.shrink()),
                TextField(focusNode: editableNode),
              ],
            ),
          ),
        ),
      );

      unsafeNode.requestFocus();
      await tester.pump();
      expect(unsafeNode.hasFocus, isTrue);

      final report = await InputRepairService.instance.repair(
        sentinelFocusNode: sentinelNode,
        isSafeRestoreTarget: (node) => identical(node, editableNode),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(report.result, isNot(InputRepairResult.failure));
      expect(unsafeNode.hasFocus, isFalse);
      expect(sentinelNode.hasFocus, isTrue);
    });

    testWidgets(
      'runs registered participants before and after text input reset',
      (tester) async {
        final sentinelNode = FocusNode(debugLabel: 'sentinel-node');
        addTearDown(sentinelNode.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Focus(
                focusNode: sentinelNode,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        );

        final calls = <String>[];
        final token = InputRepairService.instance.registerParticipant(
          debugLabel: 'probe',
          onRepair: (phase) async {
            calls.add(phase.name);
            return const InputRepairParticipantResult.success();
          },
        );
        addTearDown(token.dispose);

        await InputRepairService.instance.repair(
          sentinelFocusNode: sentinelNode,
        );
        await tester.pump(const Duration(milliseconds: 80));

        expect(
          calls,
          containsAllInOrder(['beforeTextInputReset', 'afterTextInputReset']),
        );
      },
    );

    testWidgets('records text input channel calls in repair report', (
      tester,
    ) async {
      final sentinelNode = FocusNode(debugLabel: 'sentinel-node');
      addTearDown(sentinelNode.dispose);
      final calls = <String>[];
      Future<void> captureTextInput(String method, [Object? arguments]) async {
        calls.add(method);
      }

      InputRepairService.instance.debugTextInputMethodOverride =
          captureTextInput;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              focusNode: sentinelNode,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      );

      final report = await InputRepairService.instance.repair(
        sentinelFocusNode: sentinelNode,
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        calls,
        containsAll(<String>[
          'TextInput.clearClient',
          'TextInput.hide',
          'TextInput.finishAutofillContext',
          'TextInput.requestExistingInputState',
        ]),
      );
      expect(
        report.steps.any(
          (step) => step.stage == InputRepairStage.clearTextInputClient,
        ),
        isTrue,
      );
    });
  });
}
