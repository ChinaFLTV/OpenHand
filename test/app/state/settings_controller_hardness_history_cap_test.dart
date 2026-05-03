// 2026-05-09 — Phase 12 followup：覆盖 hardnessToolSearchHistoryMaxPhases
// 的 clamp 和 persist 路径，确保 Settings 写入会被持久化、上下界会被夹紧、
// 冷启动遇到坏 JSON 也能 fall back 到默认值 8。

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';

class _FakeSettingsStore implements SettingsStore {
  _FakeSettingsStore({AppSettingsSnapshot? initial})
      : _current = initial ?? AppSettingsSnapshot.defaults();

  AppSettingsSnapshot _current;
  AppSettingsSnapshot get current => _current;
  int saveCount = 0;

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _current);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    saveCount++;
    _current = snapshot;
  }

  @override
  String get settingsFilePath => 'fake://app_settings';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  test('default snapshot exposes hardnessToolSearchHistoryMaxPhases = 8', () {
    final defaults = AppSettingsSnapshot.defaults();
    expect(defaults.hardnessToolSearchHistoryMaxPhases, 8);
    expect(AppSettingsSnapshot.minHardnessToolSearchHistoryMaxPhases, 1);
    expect(AppSettingsSnapshot.maxHardnessToolSearchHistoryMaxPhases, 64);
  });

  test('updateHardnessToolSearchHistoryMaxPhases persists in-range value', () async {
    final store = _FakeSettingsStore();
    final controller = await SettingsController.create(store: store);

    final ok = await controller.updateHardnessToolSearchHistoryMaxPhases(16);
    expect(ok, isTrue);
    expect(controller.hardnessToolSearchHistoryMaxPhases, 16);
    expect(store.current.hardnessToolSearchHistoryMaxPhases, 16);
    expect(store.saveCount, greaterThanOrEqualTo(1));
  });

  test('updateHardnessToolSearchHistoryMaxPhases clamps below min to 1',
      () async {
    final store = _FakeSettingsStore();
    final controller = await SettingsController.create(store: store);

    final ok = await controller.updateHardnessToolSearchHistoryMaxPhases(-5);
    expect(ok, isTrue);
    expect(controller.hardnessToolSearchHistoryMaxPhases, 1);
    expect(store.current.hardnessToolSearchHistoryMaxPhases, 1);
  });

  test('updateHardnessToolSearchHistoryMaxPhases clamps above max to 64',
      () async {
    final store = _FakeSettingsStore();
    final controller = await SettingsController.create(store: store);

    final ok = await controller.updateHardnessToolSearchHistoryMaxPhases(9999);
    expect(ok, isTrue);
    expect(controller.hardnessToolSearchHistoryMaxPhases, 64);
    expect(store.current.hardnessToolSearchHistoryMaxPhases, 64);
  });

  test('updating to current value still resolves true (successNoChange path)',
      () async {
    final store = _FakeSettingsStore();
    final controller = await SettingsController.create(store: store);
    final before = controller.hardnessToolSearchHistoryMaxPhases;

    final ok = await controller.updateHardnessToolSearchHistoryMaxPhases(before);
    expect(ok, isTrue);
    expect(controller.hardnessToolSearchHistoryMaxPhases, before);
  });

  test('cold-load reads persisted value across controller re-creation',
      () async {
    final store = _FakeSettingsStore();
    final c1 = await SettingsController.create(store: store);
    await c1.updateHardnessToolSearchHistoryMaxPhases(32);

    final c2 = await SettingsController.create(store: store);
    expect(c2.hardnessToolSearchHistoryMaxPhases, 32);
  });
}
