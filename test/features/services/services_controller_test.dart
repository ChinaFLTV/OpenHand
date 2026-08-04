import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/model/plugin_info.dart';
import 'package:openhand/features/plugin_service/plugin_service_controller.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/service/ai_jungler_client.dart';
import 'package:openhand/features/services/service/ai_jungler_runtime.dart';
import 'package:openhand/features/services/services_controller.dart';

void main() {
  test('插件状态高频变化时仅同步当前状态与最新状态', () async {
    final client = _BlockingAiJunglerClient();
    final runtime = _TestAiJunglerRuntime(client);
    final plugins = _TestPluginServiceController();
    final controller = ServicesController(
      runtime: runtime,
      proxyInspectionFirstRunDelay: const Duration(days: 1),
    );
    addTearDown(() async {
      client.unblockAll();
      runtime.disconnect();
      await controller.shutdown();
      plugins.dispose();
      client.close();
    });

    controller.attachPluginServiceController(plugins);
    await _waitUntil(() => client.updateCalls == 1);

    for (var revision = 1; revision <= 20; revision++) {
      plugins.emitRevision(revision);
    }
    expect(client.updateCalls, 1);

    client.release(0);
    await _waitUntil(() => client.updateCalls == 2);
    client.release(1);
    await _waitUntil(() => client.statusCalls == 2);
    await Future<void>.delayed(Duration.zero);

    expect(client.updateCalls, 2);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('等待异步条件完成超时。');
}

final class _TestPluginServiceController extends PluginServiceController {
  int _revision = 0;

  @override
  PluginInfo? pluginById(String id) {
    if (id != PluginCatalogIds.nodejs) return null;
    return PluginInfo(
      id: id,
      name: 'Node.js',
      description: '测试插件',
      status: PluginStatus.installed,
      installPath: '/node/$_revision',
    );
  }

  void emitRevision(int revision) {
    _revision = revision;
    notifyListeners();
  }
}

final class _TestAiJunglerRuntime extends AiJunglerRuntime {
  _TestAiJunglerRuntime(this._testClient);

  _BlockingAiJunglerClient? _testClient;

  @override
  AiJunglerClient? get client => _testClient;

  @override
  Stream<String> get logs => const Stream<String>.empty();

  @override
  Stream<int> get exits => const Stream<int>.empty();

  void disconnect() => _testClient = null;
}

final class _BlockingAiJunglerClient extends AiJunglerClient {
  _BlockingAiJunglerClient()
    : super(baseUri: Uri.parse('http://127.0.0.1'), accessToken: 'test');

  static const _componentStatus = AiExposureDependencyComponentStatus(
    configured: false,
    connected: false,
    message: '',
  );

  final List<Completer<void>> _gates = <Completer<void>>[];
  bool _unblocked = false;
  int updateCalls = 0;
  int statusCalls = 0;

  @override
  Future<void> updateDependencies({
    String? postgresqlUrl,
    String? redisUrl,
    Map<String, Object?>? playwright,
  }) async {
    updateCalls++;
    if (_unblocked) return;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
  }

  @override
  Future<AiExposureDependencyStatus> dependencyStatus() async {
    statusCalls++;
    return const AiExposureDependencyStatus(
      postgresql: _componentStatus,
      redis: _componentStatus,
      playwright: _componentStatus,
    );
  }

  void release(int index) => _gates[index].complete();

  void unblockAll() {
    _unblocked = true;
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}
