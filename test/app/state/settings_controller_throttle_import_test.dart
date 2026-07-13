import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';

void main() {
  test('throttle import persists all fields atomically', () async {
    final store = _MemorySettingsStore();
    final controller = await SettingsController.create(store: store);

    final outcome = await controller
        .importAiStreamThrottleConfig(<String, Object?>{
          'throttle_enabled': false,
          'auto_mode': true,
          'duration_seconds': 20,
          'max_chars_per_second': 17,
          'max_message_cards_per_second': 4,
        }, overrideUpdatedAtMs: 1234);

    expect(outcome, AiStreamThrottleConfigImportOutcome.applied);
    expect(store.saveCount, 1);
    expect(controller.aiStreamThrottleEnabled, isFalse);
    expect(controller.aiStreamThrottleAutoMode, isTrue);
    expect(controller.aiStreamThrottleDurationSeconds, 20);
    expect(controller.aiStreamMaxCharsPerSecond, 17);
    expect(controller.aiStreamMaxMessageCardsPerSecond, 4);
    expect(controller.aiStreamThrottleConfigUpdatedAtMs, 1234);
    expect(
      controller.exportAiStreamThrottleConfig(),
      isNot(contains('cloud_sync')),
    );

    final unchanged = await controller.importAiStreamThrottleConfig(
      controller.exportAiStreamThrottleConfig(),
      overrideUpdatedAtMs: 1234,
    );
    expect(unchanged, AiStreamThrottleConfigImportOutcome.unchanged);
    expect(store.saveCount, 1);
    controller.dispose();
  });

  test('failed throttle import rolls back the complete snapshot', () async {
    final store = _MemorySettingsStore(saveError: StateError('disk full'));
    final controller = await SettingsController.create(store: store);
    final original = controller.exportAiStreamThrottleConfig();

    final outcome = await controller.importAiStreamThrottleConfig(
      <String, Object?>{
        'throttle_enabled': false,
        'auto_mode': true,
        'duration_seconds': 40,
      },
    );

    expect(outcome, AiStreamThrottleConfigImportOutcome.failed);
    expect(
      controller.exportAiStreamThrottleConfig(),
      containsPair('throttle_enabled', original['throttle_enabled']),
    );
    expect(
      controller.exportAiStreamThrottleConfig(),
      containsPair('auto_mode', original['auto_mode']),
    );
    expect(
      controller.exportAiStreamThrottleConfig(),
      containsPair('duration_seconds', original['duration_seconds']),
    );
    expect(
      controller.persistenceIssue?.kind,
      SettingsPersistenceIssueKind.saveFailed,
    );
    controller.dispose();
  });

  test('v4 migration removes obsolete placeholders without mutating input', () {
    final source = <String, Object?>{
      'version': 1,
      'template_overrides': <String, Object?>{'legacy': true},
      'cloud_sync': <String, Object?>{'enabled': false},
    };

    final migrated = migrateAiStreamThrottleConfig(source);

    expect(migrated['version'], aiStreamThrottleConfigSchemaVersion);
    expect(aiStreamThrottleConfigSchemaVersion, 4);
    expect(migrated, isNot(contains('template_overrides')));
    expect(migrated, isNot(contains('cloud_sync')));
    expect(source, contains('template_overrides'));
    expect(source, contains('cloud_sync'));
  });
}

class _MemorySettingsStore extends SettingsStore {
  _MemorySettingsStore({this.saveError});

  final Object? saveError;
  AppSettingsSnapshot snapshot = AppSettingsSnapshot.defaults();
  int saveCount = 0;

  @override
  String get settingsFilePath => 'memory://settings';

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot next) async {
    saveCount += 1;
    final error = saveError;
    if (error != null) throw error;
    snapshot = next;
  }
}
