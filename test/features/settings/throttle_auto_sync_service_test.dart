import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/settings/service/throttle_auto_sync_service.dart';
import 'package:openhand/features/settings/service/throttle_cloud_sync_service.dart';

void main() {
  test('canonical signatures sort nested JSON and escape delimiters', () {
    final first = ThrottleAutoSyncService.signatureForConfig(<String, Object?>{
      'nested': <String, Object?>{
        'b': <Object?>[
          1,
          <String, Object?>{'z': 'x', 'a': 'y'},
        ],
        'a': 'q',
      },
      'version': 3,
      'exported_at': 'old',
    });
    final reordered = ThrottleAutoSyncService.signatureForConfig(
      <String, Object?>{
        'exported_at': 'new',
        'version': 4,
        'nested': <String, Object?>{
          'a': 'q',
          'b': <Object?>[
            1,
            <String, Object?>{'a': 'y', 'z': 'x'},
          ],
        },
      },
    );
    final delimiterValue = ThrottleAutoSyncService.signatureForConfig(
      <String, Object?>{'a': '1;b=2'},
    );
    final separateFields = ThrottleAutoSyncService.signatureForConfig(
      <String, Object?>{'a': '1', 'b': 2},
    );

    expect(first, reordered);
    expect(delimiterValue, isNot(separateFields));
  });

  test(
    'pull requests take priority and duplicate pushes are coalesced',
    () async {
      final store = _MemorySettingsStore(
        AppSettingsSnapshot.defaults().copyWith(
          aiStreamThrottleCloudSyncEndpoint: 'https://sync.example/config',
          aiStreamThrottleConfigUpdatedAtMs: 100,
        ),
      );
      final controller = await SettingsController.create(store: store);
      final cloud = _ControlledCloudSyncService(blockFirstPull: true);
      final service = ThrottleAutoSyncService(
        settingsController: controller,
        cloudSyncService: cloud,
        bootPullDelay: Duration.zero,
        pushDebounce: Duration.zero,
        cloudChangeDebounce: Duration.zero,
      )..start();

      await cloud.firstPullStarted.future;
      await controller.updateAiStreamMaxCharsPerSecond(12);
      await controller.updateAiStreamMaxCharsPerSecond(13);
      cloud.emitChange();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cloud.releaseFirstPull();

      await _waitUntil(() => cloud.operations.length >= 3);
      expect(cloud.operations, <String>['pull', 'pull', 'push']);
      expect(cloud.maxConcurrentOperations, 1);

      await service.dispose();
      await cloud.dispose();
      controller.dispose();
    },
  );

  test(
    'dispose cancels the logical wait and detaches future triggers',
    () async {
      final store = _MemorySettingsStore(
        AppSettingsSnapshot.defaults().copyWith(
          aiStreamThrottleCloudSyncEndpoint: 'https://sync.example/config',
        ),
      );
      final controller = await SettingsController.create(store: store);
      final cloud = _ControlledCloudSyncService(blockFirstPull: true);
      final service = ThrottleAutoSyncService(
        settingsController: controller,
        cloudSyncService: cloud,
        bootPullDelay: Duration.zero,
        pushDebounce: Duration.zero,
        disposeTimeout: const Duration(milliseconds: 20),
      )..start();

      await cloud.firstPullStarted.future;
      await service.dispose().timeout(const Duration(milliseconds: 100));
      await controller.updateAiStreamMaxCharsPerSecond(14);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(cloud.operations, <String>['pull']);
      cloud.releaseFirstPull();
      await _waitUntil(() => cloud.activeOperations == 0);
      await cloud.dispose();
      controller.dispose();
    },
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 1)) {
      fail('Timed out waiting for asynchronous operation.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _MemorySettingsStore extends SettingsStore {
  _MemorySettingsStore(this.snapshot);

  AppSettingsSnapshot snapshot;

  @override
  String get settingsFilePath => 'memory://settings';

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot next) async {
    snapshot = next;
  }
}

class _ControlledCloudSyncService extends ThrottleCloudSyncService {
  _ControlledCloudSyncService({required this.blockFirstPull})
    : super(registerCloudChangeHandler: false);

  final bool blockFirstPull;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Completer<void> firstPullStarted = Completer<void>();
  final Completer<void> _firstPullBarrier = Completer<void>();
  final List<String> operations = <String>[];
  int activeOperations = 0;
  int maxConcurrentOperations = 0;
  bool _firstPull = true;

  @override
  Stream<void> get cloudChanges => _changes.stream;

  void emitChange() => _changes.add(null);

  void releaseFirstPull() {
    if (!_firstPullBarrier.isCompleted) _firstPullBarrier.complete();
  }

  @override
  Future<ThrottleCloudSyncResult> pull({
    required ThrottleCloudSyncProvider provider,
    required String endpoint,
    required String token,
    String gistId = '',
  }) async {
    operations.add('pull');
    _beginOperation();
    try {
      if (_firstPull) {
        _firstPull = false;
        if (!firstPullStarted.isCompleted) firstPullStarted.complete();
        if (blockFirstPull) await _firstPullBarrier.future;
      }
      return ThrottleCloudSyncResult.success(config: <String, Object?>{});
    } finally {
      activeOperations -= 1;
    }
  }

  @override
  Future<ThrottleCloudSyncResult> push({
    required ThrottleCloudSyncProvider provider,
    required String endpoint,
    required String token,
    required Map<String, Object?> config,
    int updatedAtMs = 0,
    String gistId = '',
  }) async {
    operations.add('push');
    _beginOperation();
    try {
      return ThrottleCloudSyncResult.success();
    } finally {
      activeOperations -= 1;
    }
  }

  void _beginOperation() {
    activeOperations += 1;
    if (activeOperations > maxConcurrentOperations) {
      maxConcurrentOperations = activeOperations;
    }
  }

  @override
  Future<void> dispose() async {
    if (!_changes.isClosed) await _changes.close();
    await super.dispose();
  }
}
