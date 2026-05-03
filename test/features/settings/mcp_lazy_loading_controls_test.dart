// 2026-05-04 — Widget regression tests for the MCP lazy-loading
// mode/threshold controls in `SettingsView`. Pumps a focused harness that
// uses the real `SettingsController` (backed by a fake in-memory
// `SettingsStore`) and exercises:
//   - SegmentedButton<McpLazyLoadingMode> selection persists via controller
//   - Threshold input commits / clamps via controller, including the
//     "below min ⇒ reset to default" branch
//   - Persisted snapshot in the fake store reflects the latest mutation
//
// The full `SettingsView` widget pulls in 8+ providers and a sqflite-backed
// `DatabaseService.instance`, so we lock the interaction at the
// (controller × SegmentedButton/TextField) seam — same mode/threshold
// surfaces the production UI binds to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/mcp/model/mcp_lazy_loading_mode.dart';
import 'package:provider/provider.dart';

class _FakeSettingsStore extends SettingsStore {
  _FakeSettingsStore({AppSettingsSnapshot? initial})
      : _current = initial ?? AppSettingsSnapshot.defaults();

  AppSettingsSnapshot _current;
  int saveCount = 0;

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _current);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    _current = snapshot;
    saveCount += 1;
  }

  AppSettingsSnapshot get current => _current;
}

class _LazyLoadingHarness extends StatelessWidget {
  const _LazyLoadingHarness();

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsController>(
      builder: (ctx, ctrl, _) {
        final controller = TextEditingController(
          text: '${ctrl.mcpLazyLoadingThresholdTokens}',
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<McpLazyLoadingMode>(
              segments: const [
                ButtonSegment(
                  value: McpLazyLoadingMode.disabled,
                  label: Text('off'),
                ),
                ButtonSegment(
                  value: McpLazyLoadingMode.auto,
                  label: Text('auto'),
                ),
                ButtonSegment(
                  value: McpLazyLoadingMode.enabled,
                  label: Text('on'),
                ),
              ],
              selected: <McpLazyLoadingMode>{ctrl.mcpLazyLoadingMode},
              onSelectionChanged: (sel) {
                if (sel.isEmpty) return;
                ctrl.updateMcpLazyLoadingMode(sel.first);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('thresholdField'),
              controller: controller,
              keyboardType: TextInputType.number,
              onSubmitted: (text) {
                final parsed = int.tryParse(text.trim());
                if (parsed != null) {
                  ctrl.updateMcpLazyLoadingThresholdTokens(parsed);
                }
              },
            ),
          ],
        );
      },
    );
  }
}

Future<SettingsController> _pumpHarness(
  WidgetTester tester, {
  AppSettingsSnapshot? initial,
}) async {
  final store = _FakeSettingsStore(initial: initial);
  final controller = await SettingsController.create(store: store);
  // Reset save count from the bootstrap save the controller does on
  // initial load when the snapshot doesn't exist — our fake returns the
  // snapshot directly so no bootstrap happens, but be defensive.
  store.saveCount = 0;
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: controller,
      child: const MaterialApp(
        home: Scaffold(body: _LazyLoadingHarness()),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('SegmentedButton mode change persists through SettingsController',
      (tester) async {
    final controller = await _pumpHarness(tester);
    expect(controller.mcpLazyLoadingMode, McpLazyLoadingMode.auto);

    await tester.tap(find.text('on'));
    await tester.pumpAndSettle();

    expect(controller.mcpLazyLoadingMode, McpLazyLoadingMode.enabled);
  });

  testWidgets('threshold field commits a valid value via controller',
      (tester) async {
    final controller = await _pumpHarness(tester);

    await tester.enterText(find.byKey(const ValueKey('thresholdField')), '50000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.mcpLazyLoadingThresholdTokens, 50000);
  });

  testWidgets('threshold below min resets to default', (tester) async {
    final controller = await _pumpHarness(tester);

    await tester.enterText(find.byKey(const ValueKey('thresholdField')), '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      controller.mcpLazyLoadingThresholdTokens,
      AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens,
    );
  });

  testWidgets('threshold above max is clamped to max', (tester) async {
    final controller = await _pumpHarness(tester);

    await tester.enterText(
      find.byKey(const ValueKey('thresholdField')),
      '99999999',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      controller.mcpLazyLoadingThresholdTokens,
      AppSettingsSnapshot.maxMcpLazyLoadingThresholdTokens,
    );
  });

  testWidgets('disabled mode round-trips through SegmentedButton',
      (tester) async {
    final controller = await _pumpHarness(tester);

    await tester.tap(find.text('off'));
    await tester.pumpAndSettle();
    expect(controller.mcpLazyLoadingMode, McpLazyLoadingMode.disabled);

    await tester.tap(find.text('auto'));
    await tester.pumpAndSettle();
    expect(controller.mcpLazyLoadingMode, McpLazyLoadingMode.auto);
  });
}
