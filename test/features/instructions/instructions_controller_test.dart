import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/features/instructions/data/instructions_store.dart';
import 'package:openhand/features/instructions/instructions_controller.dart';
import 'package:openhand/features/instructions/model/user_instruction_entry.dart';
import 'package:openhand/features/instructions/widgets/instructions_view.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class _Store implements InstructionsStore {
  List<UserInstructionEntry> entries = [];
  Completer<void>? saveGate;
  bool failSave = false;
  VoidCallback? onSaveStarted;

  @override
  Future<List<UserInstructionEntry>> loadAll() async => List.of(entries);

  @override
  Future<void> saveAll(List<UserInstructionEntry> next) async {
    onSaveStarted?.call();
    await saveGate?.future;
    if (failSave) throw StateError('模拟保存失败');
    entries = List.of(next);
  }
}

class _Settings extends ChangeNotifier implements SettingsController {
  _Settings(this.motionEnabled);

  final bool motionEnabled;
  @override
  DialogAnimationSettings get listItemAnimationSettings => motionEnabled
      ? OpenHandMotionDefaults.listItem
      : OpenHandMotionDefaults.disabled;
  @override
  DialogAnimationSettings get dialogAnimationSettings => motionEnabled
      ? OpenHandMotionDefaults.dialog
      : OpenHandMotionDefaults.disabled;
  @override
  DialogAnimationSettings get menuAnimationSettings => motionEnabled
      ? OpenHandMotionDefaults.menu
      : OpenHandMotionDefaults.disabled;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Store store;
  late InstructionsController controller;
  setUp(() async {
    store = _Store();
    var nextId = 0;
    controller = InstructionsController.uninitialized(
      store: store,
      idGenerator: () => '${++nextId}',
    );
    await controller.refresh();
  });
  tearDown(() => controller.dispose());

  test('每次增删改、启停、排序、清空后，订阅者收到已提交快照', () async {
    var observed = controller.entries;
    var enabled = controller.enabledEntries;
    controller.addListener(() {
      observed = controller.entries;
      enabled = controller.enabledEntries;
    });
    expect(await controller.createEntry(name: '第一条', body: '正文'), isTrue);
    expect(observed.single.name, '第一条');
    expect(enabled.single.id, '1');
    expect(await controller.updateEntry(observed.single, name: '已更新'), isTrue);
    expect(observed.single.name, '已更新');
    expect(await controller.setEnabled('1', false), isTrue);
    expect(observed.single.enabled, isFalse);
    expect(enabled, isEmpty);
    expect(await controller.setEnabled('1', true), isTrue);
    expect(enabled.single.id, '1');
    await controller.createEntry(name: '第二条', body: '正文');
    await controller.reorder(['2', '1']);
    expect(observed.map((entry) => entry.id), ['2', '1']);
    await controller.deleteEntry('1');
    expect(observed.map((entry) => entry.id), ['2']);
    await controller.clearAll();
    expect(observed, isEmpty);
    expect(store.entries, isEmpty);
  });

  test('慢速保存期间保留已提交指令，只在成功后通知一次', () async {
    await controller.createEntry(name: '已提交', body: '正文');
    final started = Completer<void>();
    store.saveGate = Completer<void>();
    store.onSaveStarted = started.complete;
    var notifications = 0;
    controller.addListener(() => notifications++);
    final saving = controller.updateEntry(
      controller.entries.single,
      name: '新名称',
    );
    await started.future;
    expect(controller.enabledEntries.single.name, '已提交');
    expect(notifications, 0);
    store.saveGate!.complete();
    expect(await saving, isTrue);
    expect(controller.enabledEntries.single.name, '新名称');
    expect(notifications, 1);
  });

  test('删除与刷新、旧编辑并发时，条目不会被恢复', () async {
    await controller.createEntry(name: '待删除', body: '正文');
    final oldEntry = controller.entries.single;
    store.saveGate = Completer<void>();
    final deleting = controller.deleteEntry(oldEntry.id);
    final refreshing = controller.refresh();
    final editing = controller.updateEntry(oldEntry, name: '旧编辑');
    store.saveGate!.complete();
    expect(await deleting, isTrue);
    await refreshing;
    expect(await editing, isFalse);
    expect(controller.entries, isEmpty);
    expect(store.entries, isEmpty);
  });

  test('保存失败保留条目并报告错误，随后可再次删除', () async {
    await controller.createEntry(name: '待删除', body: '正文');
    final successCount = controller.saveSuccessSignal.value;
    store.failSave = true;
    expect(await controller.deleteEntry('1'), isFalse);
    expect(controller.entries.single.id, '1');
    expect(controller.errorMessage, isNotNull);
    expect(controller.saveSuccessSignal.value, successCount);
    store.failSave = false;
    expect(await controller.deleteEntry('1'), isTrue);
    await controller.refresh();
    expect(controller.entries, isEmpty);
  });

  for (final motionEnabled in [true, false]) {
    testWidgets('指令删除及清空后不回弹，动画${motionEnabled ? '开启' : '关闭'}', (tester) async {
      await tester.runAsync(() async {
        await controller.createEntry(name: '待删除指令', body: '正文');
        await controller.createEntry(name: '保留指令', body: '正文');
      });
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: controller),
            ChangeNotifierProvider<SettingsController>(
              create: (_) => _Settings(motionEnabled),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: InstructionsView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('待删除指令'), findsOneWidget);
      Future<void> deleteFirstCard() async {
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除').last);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
      }

      await deleteFirstCard();
      expect(store.entries.map((entry) => entry.name), ['保留指令']);
      expect(find.text('待删除指令'), findsNothing);
      expect(find.text('保留指令'), findsOneWidget);
      await deleteFirstCard();
      expect(store.entries, isEmpty);
      expect(find.text('保留指令'), findsNothing);
    });
  }
}
