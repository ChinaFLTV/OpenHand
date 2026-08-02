import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/data/ai_exposure_preferences_store.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/service/ai_exposure_proxy_probe.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('冷启动后自动执行首轮定时巡检', () async {
    final probe = _TrackingProxyProbe();
    final store = _MemoryPreferencesStore();
    final controller = ServicesController(
      preferencesStore: store,
      initialPreferences: _preferences(
        _configuration(_endpoints(1), inspectionEnabled: true),
      ),
      proxyProbe: probe,
      proxyInspectionFirstRunDelay: Duration.zero,
    );
    addTearDown(controller.shutdown);

    await probe.firstCall.future.timeout(const Duration(seconds: 1));
    await _waitUntilIdle(controller);

    expect(probe.calls, 1);
    expect(
      controller.proxyConfiguration.endpoints.single.latestSample,
      isNotNull,
    );
    expect(store.sampleSaveCount, 1);
  });

  test('重复巡检调用不会与当前任务重叠', () async {
    final blocker = Completer<void>();
    final probe = _TrackingProxyProbe(blocker: blocker);
    final controller = ServicesController(
      preferencesStore: _MemoryPreferencesStore(),
      initialPreferences: _preferences(_configuration(_endpoints(1))),
      proxyProbe: probe,
    );
    addTearDown(controller.shutdown);

    final first = controller.inspectAllProxies();
    await probe.firstCall.future.timeout(const Duration(seconds: 1));

    expect(await controller.inspectAllProxies(), isFalse);
    controller.cancelProxyInspection();
    blocker.complete();
    expect(await first, isTrue);
    expect(probe.maxActive, 1);
  });

  test('配置变更会丢弃旧巡检的未提交结果', () async {
    final blocker = Completer<void>();
    final probe = _TrackingProxyProbe(blocker: blocker);
    final store = _MemoryPreferencesStore();
    final controller = ServicesController(
      preferencesStore: store,
      initialPreferences: _preferences(_configuration(_endpoints(1))),
      proxyProbe: probe,
    );
    addTearDown(controller.shutdown);

    final inspection = controller.inspectAllProxies();
    await probe.firstCall.future.timeout(const Duration(seconds: 1));
    final replacement = <AiExposureProxyEndpoint>[
      const AiExposureProxyEndpoint(url: 'http://127.0.0.1:30000'),
    ];

    expect(
      await controller.updateProxyConfiguration(_configuration(replacement)),
      isTrue,
    );
    blocker.complete();

    expect(await inspection, isFalse);
    expect(
      controller.proxyConfiguration.endpoints.single.url,
      replacement.single.url,
    );
    expect(controller.proxyConfiguration.endpoints.single.latestSample, isNull);
  });

  test('万级节点巡检限制并发并采用批量检查点', () async {
    final probe = _TrackingProxyProbe();
    final store = _MemoryPreferencesStore();
    final controller = ServicesController(
      preferencesStore: store,
      initialPreferences: _preferences(_configuration(_endpoints(10000))),
      proxyProbe: probe,
    );
    addTearDown(controller.shutdown);

    expect(await controller.inspectAllProxies(concurrency: 32), isTrue);

    expect(probe.calls, 10000);
    expect(probe.maxActive, 32);
    expect(store.sampleSaveCount, inInclusiveRange(2, 21));
    expect(
      controller.proxyConfiguration.endpoints.every(
        (endpoint) => endpoint.latestSample != null,
      ),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('配置 JSON 不再重复保存独立巡检样本', () {
    final sample = AiExposureProxyProbeSample(
      checkedAt: DateTime.utc(2026, 8, 3),
      latencyMs: 1,
      statusCode: 204,
    );
    final preferences = _preferences(
      _configuration(<AiExposureProxyEndpoint>[
        AiExposureProxyEndpoint(
          url: 'http://127.0.0.1:10000',
          samples: <AiExposureProxyProbeSample>[sample],
        ),
      ]),
    );

    final json = preferences.toJson(
      includeProxyStatistics: false,
      includeProxySamples: false,
    );
    final proxy = json['proxy']! as Map<String, Object?>;
    final endpoints = proxy['endpoints']! as List<Object?>;

    expect(endpoints.single, isNot(contains('samples')));
  });

  test('检查点写入失败后停止巡检且不无限重试', () async {
    final store = _MemoryPreferencesStore(sampleSaveFailuresRemaining: 1);
    final controller = ServicesController(
      preferencesStore: store,
      initialPreferences: _preferences(_configuration(_endpoints(1000))),
      proxyProbe: _TrackingProxyProbe(),
    );
    addTearDown(controller.shutdown);

    expect(await controller.inspectAllProxies(concurrency: 32), isFalse);
    expect(store.sampleSaveCount, 1);
    expect(controller.proxyInspectionBusy, isFalse);
  });

  test('旧配置中的巡检样本会迁移到独立表', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'openhand_proxy_samples_',
    );
    final databasePath = p.join(directory.path, 'migration.db');
    final legacyDatabase = await databaseFactoryFfiNoIsolate.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE ai_exposure_proxy_statistics (
              endpoint_url TEXT PRIMARY KEY,
              statistics_json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    final sample = AiExposureProxyProbeSample(
      checkedAt: DateTime.utc(2026, 8, 3),
      latencyMs: 8,
      statusCode: 204,
    );
    final preferences = _preferences(
      _configuration(<AiExposureProxyEndpoint>[
        AiExposureProxyEndpoint(
          url: 'http://127.0.0.1:10000',
          samples: <AiExposureProxyProbeSample>[sample],
        ),
      ]),
    );
    await legacyDatabase.insert('app_settings', <String, Object?>{
      'key': 'ai_exposure_preferences_v1',
      'value': jsonEncode(preferences.toJson()),
    });
    await legacyDatabase.close();

    final databaseService = await DatabaseService.initialize(
      databasePath: databasePath,
      useNoIsolateFactory: true,
    );
    addTearDown(() async {
      await databaseService.close();
      await directory.delete(recursive: true);
    });
    final loaded = await AiExposurePreferencesStore().load();
    final sampleRows = await databaseService.database.query(
      'ai_exposure_proxy_samples',
    );
    final settingRows = await databaseService.database.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: const <Object?>['ai_exposure_preferences_v1'],
    );
    final storedSettings = jsonDecode(settingRows.single['value']! as String);
    final storedProxy = storedSettings['proxy'] as Map<String, Object?>;
    final storedEndpoints = storedProxy['endpoints'] as List<Object?>;

    expect(databaseService.database.getVersion(), completion(14));
    expect(
      loaded.proxyConfiguration.endpoints.single.samples.single.latencyMs,
      8,
    );
    expect(sampleRows, hasLength(1));
    expect(storedEndpoints.single, isNot(contains('samples')));
  });
}

Future<void> _waitUntilIdle(ServicesController controller) async {
  while (controller.proxyInspectionBusy) {
    await Future<void>.delayed(Duration.zero);
  }
}

AiExposurePreferences _preferences(
  AiExposureProxyConfiguration configuration,
) => AiExposurePreferences(
  enabledSources: const <AiExposureSource>{AiExposureSource.manual},
  defaultConcurrency: 1,
  defaultValidationMode: AiExposureValidationMode.passive,
  defaultGptAssisted: false,
  useBundledEngine: true,
  externalAddress: 'http://127.0.0.1:37821',
  proxyConfiguration: configuration,
);

AiExposureProxyConfiguration _configuration(
  List<AiExposureProxyEndpoint> endpoints, {
  bool inspectionEnabled = false,
}) => AiExposureProxyConfiguration(
  enabled: false,
  strategy: AiExposureProxyStrategy.roundRobin,
  rotationEvery: 1,
  bypassLocal: true,
  endpoints: endpoints,
  inspectionEnabled: inspectionEnabled,
  inspectionConcurrency: 32,
);

List<AiExposureProxyEndpoint> _endpoints(int count) =>
    List<AiExposureProxyEndpoint>.generate(
      count,
      (index) =>
          AiExposureProxyEndpoint(url: 'http://127.0.0.1:${10000 + index}'),
      growable: false,
    );

final class _MemoryPreferencesStore extends AiExposurePreferencesStore {
  _MemoryPreferencesStore({this.sampleSaveFailuresRemaining = 0});

  int saveCount = 0;
  int sampleSaveCount = 0;
  int sampleSaveFailuresRemaining;
  AiExposurePreferences? lastSaved;

  @override
  Future<void> save(AiExposurePreferences preferences) async {
    saveCount++;
    lastSaved = preferences;
  }

  @override
  Future<void> saveProxySamples(List<AiExposureProxyEndpoint> endpoints) async {
    sampleSaveCount++;
    if (sampleSaveFailuresRemaining > 0) {
      sampleSaveFailuresRemaining--;
      throw StateError('模拟巡检样本写入失败');
    }
  }
}

final class _TrackingProxyProbe extends AiExposureProxyProbe {
  _TrackingProxyProbe({this.blocker});

  final Completer<void>? blocker;
  final Completer<void> firstCall = Completer<void>();
  int calls = 0;
  int active = 0;
  int maxActive = 0;

  @override
  Future<AiExposureProxyProbeSample> inspect(
    AiExposureProxyEndpoint endpoint,
  ) async {
    calls++;
    active++;
    if (!firstCall.isCompleted) firstCall.complete();
    if (active > maxActive) maxActive = active;
    try {
      if (blocker != null) {
        await blocker!.future;
      } else {
        await Future<void>.delayed(Duration.zero);
      }
      return AiExposureProxyProbeSample(
        checkedAt: DateTime.now(),
        latencyMs: 1,
        statusCode: 204,
      );
    } finally {
      active--;
    }
  }
}
