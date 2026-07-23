import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/cron_config.dart';
import 'package:openhand/features/crons/crons_controller.dart';
import 'package:openhand/features/crons/data/crons_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('超时智能体任务完成前保持单飞锁', () async {
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-timeout-lock',
      name: '超时锁测试',
      scriptType: CronScriptType.agent,
      cronExpression: '0 0 1 1 *',
      timeoutSeconds: 1,
    );
    expect(await controller.addCron(entry), isTrue);

    final firstCompletion = Completer<AgentHandlerResult>();
    var calls = 0;
    controller.registerAgentHandler((_) {
      calls++;
      return calls == 1
          ? firstCompletion.future
          : Future<AgentHandlerResult>.value(const AgentHandlerResult());
    });

    await controller.runNow(entry.id);
    expect(calls, 1);

    await controller.runNow(entry.id);
    expect(calls, 1);

    firstCompletion.complete(const AgentHandlerResult());
    await Future<void>.delayed(Duration.zero);

    await controller.runNow(entry.id);
    expect(calls, 2);
  });

  test('多个超时智能体任务不突破全局并发上限', () async {
    const maxConcurrentJobs = 8;
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    final entries = List<CronEntry>.generate(
      maxConcurrentJobs + 1,
      (index) => CronEntry(
        id: 'agent-timeout-cap-$index',
        name: '并发上限测试 $index',
        scriptType: CronScriptType.agent,
        cronExpression: '0 0 1 1 *',
        timeoutSeconds: 1,
      ),
    );
    for (final entry in entries) {
      expect(await controller.addCron(entry), isTrue);
    }

    final completions = <String, Completer<AgentHandlerResult>>{
      for (final entry in entries) entry.id: Completer<AgentHandlerResult>(),
    };
    var calls = 0;
    controller.registerAgentHandler((entry) {
      calls++;
      return completions[entry.id]!.future;
    });

    await Future.wait(entries.map((entry) => controller.runNow(entry.id)));
    expect(calls, maxConcurrentJobs);

    completions[entries.first.id]!.complete(const AgentHandlerResult());
    await Future<void>.delayed(Duration.zero);

    await controller.runNow(entries.last.id);
    expect(calls, maxConcurrentJobs + 1);

    for (final completion in completions.values) {
      if (!completion.isCompleted) {
        completion.complete(const AgentHandlerResult());
      }
    }
    await Future<void>.delayed(Duration.zero);
  });
}

class _MemoryCronsStore extends CronsStore {
  List<CronEntry> _entries = <CronEntry>[];

  @override
  Future<void> ensureTable() async {}

  @override
  Future<List<CronEntry>> loadAll() async => List<CronEntry>.of(_entries);

  @override
  Future<void> saveAll(List<CronEntry> entries) async {
    _entries = List<CronEntry>.of(entries);
  }

  @override
  Future<void> updateRuntimeState(CronEntry entry) async {
    final index = _entries.indexWhere((current) => current.id == entry.id);
    if (index >= 0) _entries[index] = entry;
  }

  @override
  Future<void> insertHistory(CronExecutionRecord record) async {}

  @override
  Future<void> pruneHistory(String cronId, {int keep = 100}) async {}
}
