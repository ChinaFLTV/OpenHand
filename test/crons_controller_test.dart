import 'dart:async';
import 'dart:io';

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

  test('超时智能体锁在有界保留期后恢复调度', () async {
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-timeout-lock-recovery',
      name: '超时锁恢复测试',
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

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await controller.runNow(entry.id);
    expect(calls, 2);
  });

  test('超时智能体不长期占用全局并发配额', () async {
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

    await controller.runNow(entries.last.id);
    expect(calls, maxConcurrentJobs + 1);

    for (final completion in completions.values) {
      if (!completion.isCompleted) {
        completion.complete(const AgentHandlerResult());
      }
    }
    await Future<void>.delayed(Duration.zero);
  });

  test('运行状态通知不会同步重入重复启动', () async {
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-reentrant-start',
      name: '重入启动测试',
      scriptType: CronScriptType.agent,
      cronExpression: '0 0 1 1 *',
    );
    expect(await controller.addCron(entry), isTrue);

    final completion = Completer<AgentHandlerResult>();
    var calls = 0;
    var requested = false;
    controller.registerAgentHandler((_) {
      calls++;
      return completion.future;
    });
    void listener() {
      final current = controller.entries.firstWhere(
        (item) => item.id == entry.id,
      );
      if (!requested && current.status == CronJobStatus.running) {
        requested = true;
        unawaited(controller.runNow(entry.id));
      }
    }

    controller.addListener(listener);
    addTearDown(() => controller.removeListener(listener));
    final run = controller.runNow(entry.id);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    completion.complete(const AgentHandlerResult());
    await run;
  });

  test('禁用任务后旧执行结果不会回写', () async {
    final store = _MemoryCronsStore();
    final controller = await CronsController.create(store: store);
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-disable-stale-result',
      name: '禁用失效测试',
      scriptType: CronScriptType.agent,
      cronExpression: '0 0 1 1 *',
    );
    expect(await controller.addCron(entry), isTrue);

    final completion = Completer<AgentHandlerResult>();
    controller.registerAgentHandler((_) => completion.future);
    final run = controller.runNow(entry.id);
    await Future<void>.delayed(Duration.zero);
    expect(
      await controller.toggleCronEnabled(entry.id, enabled: false),
      isTrue,
    );

    completion.complete(const AgentHandlerResult(stdout: '过期结果'));
    await run;

    final current = controller.entries.firstWhere(
      (item) => item.id == entry.id,
    );
    expect(current.status, CronJobStatus.paused);
    expect(controller.historyFor(entry.id), isEmpty);
    expect(store.historyFor(entry.id), isEmpty);
  });

  test('重新启用等待中的智能体任务保持运行状态', () async {
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-reenable-status',
      name: '重新启用状态测试',
      scriptType: CronScriptType.agent,
      cronExpression: '0 0 1 1 *',
    );
    expect(await controller.addCron(entry), isTrue);

    final completion = Completer<AgentHandlerResult>();
    var calls = 0;
    controller.registerAgentHandler((_) {
      calls++;
      return completion.future;
    });
    final run = controller.runNow(entry.id);
    await Future<void>.delayed(Duration.zero);

    expect(
      await controller.toggleCronEnabled(entry.id, enabled: false),
      isTrue,
    );
    expect(await controller.toggleCronEnabled(entry.id, enabled: true), isTrue);
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.running,
    );

    await controller.runNow(entry.id);
    expect(calls, 1);

    completion.complete(const AgentHandlerResult());
    await run;
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.idle,
    );
  });

  test('删除任务后旧执行结果不会重新写入历史', () async {
    final store = _MemoryCronsStore();
    final controller = await CronsController.create(store: store);
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-delete-stale-result',
      name: '删除失效测试',
      scriptType: CronScriptType.agent,
      cronExpression: '0 0 1 1 *',
    );
    expect(await controller.addCron(entry), isTrue);

    final completion = Completer<AgentHandlerResult>();
    controller.registerAgentHandler((_) => completion.future);
    final run = controller.runNow(entry.id);
    await Future<void>.delayed(Duration.zero);
    expect(await controller.deleteCron(entry.id), isTrue);

    completion.complete(const AgentHandlerResult(stdout: '已删除任务的结果'));
    await run;

    expect(controller.entries.where((item) => item.id == entry.id), isEmpty);
    expect(controller.historyFor(entry.id), isEmpty);
    expect(store.historyFor(entry.id), isEmpty);
  });

  test('刷新后旧执行不占用新运行周期配额', () async {
    const maxConcurrentJobs = 8;
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    final entries = List<CronEntry>.generate(
      maxConcurrentJobs + 1,
      (index) => CronEntry(
        id: 'agent-refresh-cap-$index',
        name: '刷新配额测试 $index',
        scriptType: CronScriptType.agent,
        cronExpression: '0 0 1 1 *',
      ),
    );
    for (final entry in entries) {
      expect(await controller.addCron(entry), isTrue);
    }

    final completions = <Completer<AgentHandlerResult>>[];
    var calls = 0;
    controller.registerAgentHandler((_) {
      calls++;
      final completion = Completer<AgentHandlerResult>();
      completions.add(completion);
      return completion.future;
    });
    final previousRuns = entries
        .take(maxConcurrentJobs)
        .map((entry) => controller.runNow(entry.id))
        .toList();
    await Future<void>.delayed(Duration.zero);
    expect(calls, maxConcurrentJobs);

    await controller.refresh();
    final currentRun = controller.runNow(entries.last.id);
    await Future<void>.delayed(Duration.zero);
    expect(calls, maxConcurrentJobs + 1);

    for (final completion in completions) {
      completion.complete(const AgentHandlerResult());
    }
    await Future.wait(<Future<void>>[...previousRuns, currentRun]);
  });

  test('刷新不会重复启动同一智能体任务', () async {
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-refresh-single-flight',
      name: '刷新单飞测试',
      scriptType: CronScriptType.agent,
      cronExpression: '0 0 1 1 *',
    );
    expect(await controller.addCron(entry), isTrue);

    final completion = Completer<AgentHandlerResult>();
    var calls = 0;
    controller.registerAgentHandler((_) {
      calls++;
      return calls == 1
          ? completion.future
          : Future<AgentHandlerResult>.value(const AgentHandlerResult());
    });
    final firstRun = controller.runNow(entry.id);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    await controller.refresh();
    await controller.runNow(entry.id);
    expect(calls, 1);
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.running,
    );

    completion.complete(const AgentHandlerResult());
    await firstRun;
    await controller.runNow(entry.id);
    expect(calls, 2);
  });

  test('刷新后新进程任务不会被旧句柄阻塞', () async {
    if (Platform.isWindows) return;

    final controller = await CronsController.create(store: _MemoryCronsStore());
    var disposed = false;
    addTearDown(() {
      if (!disposed) controller.dispose();
    });
    const entry = CronEntry(
      id: 'process-refresh-restart',
      name: '进程刷新测试',
      scriptContent: 'trap "" TERM; while :; do :; done',
      cronExpression: '0 0 1 1 *',
      timeoutSeconds: 30,
    );
    expect(await controller.addCron(entry), isTrue);

    final firstRun = controller.runNow(entry.id);
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.running,
    );

    await controller.refresh();
    final secondRun = controller.runNow(entry.id);
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.running,
    );

    controller.dispose();
    disposed = true;
    await Future.wait(<Future<void>>[
      firstRun,
      secondRun,
    ]).timeout(const Duration(seconds: 3));
  });

  test('更新运行中的智能体任务保持真实运行状态', () async {
    final controller = await CronsController.create(store: _MemoryCronsStore());
    addTearDown(controller.dispose);
    const entry = CronEntry(
      id: 'agent-update-status',
      name: '更新状态测试',
      scriptType: CronScriptType.agent,
      cronExpression: '0 0 1 1 *',
    );
    expect(await controller.addCron(entry), isTrue);

    final completion = Completer<AgentHandlerResult>();
    var calls = 0;
    controller.registerAgentHandler((_) {
      calls++;
      return completion.future;
    });
    final run = controller.runNow(entry.id);
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.running,
    );

    expect(
      await controller.updateCron(entry.copyWith(name: '更新后的状态测试')),
      isTrue,
    );
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.running,
    );

    await controller.runNow(entry.id);
    expect(calls, 1);

    completion.complete(const AgentHandlerResult());
    await run;
    expect(
      controller.entries.firstWhere((item) => item.id == entry.id).status,
      CronJobStatus.idle,
    );
  });
}

class _MemoryCronsStore extends CronsStore {
  List<CronEntry> _entries = <CronEntry>[];
  final List<CronExecutionRecord> _history = <CronExecutionRecord>[];

  List<CronExecutionRecord> historyFor(String cronId) {
    return _history.where((record) => record.cronId == cronId).toList();
  }

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
  Future<void> insertHistory(CronExecutionRecord record) async {
    _history.add(record);
  }

  @override
  Future<void> deleteHistoryForCron(String cronId) async {
    _history.removeWhere((record) => record.cronId == cronId);
  }

  @override
  Future<void> pruneHistory(String cronId, {int keep = 100}) async {
    final records = historyFor(cronId);
    if (records.length <= keep) return;
    _history.removeWhere((record) => record.cronId == cronId);
    _history.addAll(records.take(keep));
  }
}
