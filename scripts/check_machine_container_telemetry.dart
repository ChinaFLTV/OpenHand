import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_containers.dart';
import 'package:openhand/features/machine_terminal/machine_maintenance_readout.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  check(
    machineMaintenanceCollectionIssue(
          'Error from server (Forbidden): nodes is forbidden',
          'containers',
        ) ==
        'permission',
    'Kubernetes 权限拒绝未归类',
  );
  MachineContainerClient client(MachineContainerRuntime runtime) =>
      MachineContainerClient(
        runtime: runtime,
        run: (_) async => '',
        contextName: '测试上下文',
        scope: '测试命名空间',
      );
  final kube = client(MachineContainerRuntime.kubernetes);
  final plan = kube.telemetryQueries;
  check(plan.map((item) => item.id).toSet().length == plan.length, '采集项目标识重复');
  for (final item in plan) {
    final command = kube.command(item.arguments);
    check(command.contains("'--context' '测试上下文'"), '采集丢失上下文');
    check(command.contains("'--request-timeout=10s'"), 'Kubernetes 请求未限时');
    check(
      !RegExp(
        "'(create|delete|apply|patch|scale|prune)'|'secrets'",
      ).hasMatch(command),
      '遥测采集混入写操作或凭据查询',
    );
  }
  for (final id in [
    'workloads',
    'services',
    'storage_claims',
    'quotas',
    'events',
    'pod_metrics',
  ]) {
    final item = plan.firstWhere((item) => item.id == id);
    check(item.arguments.contains('测试命名空间'), '作用域采集未限制命名空间');
  }
  final all = kube.copyWith(scope: '').telemetryQueries;
  check(
    all.firstWhere((item) => item.id == 'workloads').arguments.contains('-A'),
    '全命名空间采集未生效',
  );
  final nodes = plan
      .firstWhere((item) => item.id == 'nodes')
      .parse(
        jsonEncode({
          'items': [
            {
              'metadata': {'name': 'node-1'},
              'status': {
                'capacity': {'cpu': '8', 'memory': '16Gi'},
                'allocatable': {
                  'cpu': '7500m',
                  'memory': '15Gi',
                  'pods': '110',
                },
                'conditions': [
                  {
                    'type': 'Ready',
                    'status': 'False',
                    'reason': 'KubeletNotReady',
                  },
                ],
                'nodeInfo': {'containerRuntimeVersion': 'containerd://2.0'},
              },
            },
            {
              'metadata': {'name': 'node-2'},
              'status': {},
            },
          ],
        }),
      );
  check(
    nodes.rows.first[1] == '未就绪' && nodes.rows.first[2] == '8',
    '节点状态或容量解析错误',
  );
  check(
    nodes.rows.first[3] == '7500m' && nodes.rows.last[1] == '—',
    '缺失值被伪造或可分配量丢失',
  );
  check(
    nodes.rows.every((row) => row.length == nodes.headers.length),
    '节点表头与数据列未对齐',
  );
  final workload = plan
      .firstWhere((item) => item.id == 'workloads')
      .parse(
        jsonEncode({
          'items': [
            {
              'kind': 'Deployment',
              'metadata': {'name': 'api', 'namespace': '生产'},
              'spec': {'replicas': 3},
              'status': {'readyReplicas': 0, 'availableReplicas': 0},
            },
          ],
        }),
      );
  check(
    workload.rows.single[3] == '3' && workload.rows.single[4] == '0',
    '副本零值与缺失值混淆',
  );
  for (final item in plan.where(
    (item) => !const [
      'version',
      'readiness',
      'node_metrics',
      'pod_metrics',
    ].contains(item.id),
  )) {
    check(item.parse('{"items":[]}').rows.isEmpty, '合法空资源列表被识别为采集失败');
    var rejected = false;
    try {
      item.parse('{"items":{}}');
    } on FormatException {
      rejected = true;
    }
    check(rejected, '无效资源结构未拒绝');
  }
  final events = plan
      .firstWhere((item) => item.id == 'events')
      .parse(
        jsonEncode({
          'items': List.generate(
            230,
            (index) => {
              'metadata': {'namespace': '生产'},
              'involvedObject': {'name': 'pod-$index'},
              'lastTimestamp': DateTime.utc(
                2026,
                10,
              ).add(Duration(minutes: index)).toIso8601String(),
              'count': 2,
              'type': 'Warning',
              'reason': 'BackOff',
              'message': '测试事件',
            },
          ),
        }),
      );
  check(
    events.rows.length == machineContainerTelemetryEventLimit &&
        events.rows.first[1] == 'pod-229',
    '事件未按时间限量保留',
  );
  final modern = plan
      .firstWhere((item) => item.id == 'events')
      .parse(
        jsonEncode({
          'items': [
            {
              'metadata': {'creationTimestamp': '2026-10-01T00:00:00Z'},
              'eventTime': '2026-10-01T01:00:00Z',
              'series': {
                'lastObservedTime': '2026-10-02T02:00:00Z',
                'count': 12,
              },
            },
          ],
        }),
      );
  check(
    modern.rows.single[5] == '12' &&
        modern.rows.single[6] == '2026-10-02T02:00:00Z',
    '现代事件系列时间或累计次数遗漏',
  );
  final ready = plan.firstWhere((item) => item.id == 'readiness');
  check(ready.parse('ok\n').rows.single.last == '就绪', 'API 就绪检查失败');
  var rejected = false;
  try {
    ready.parse('[-]etcd failed');
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'API 失败被伪装为健康');
  final top = plan
      .firstWhere((item) => item.id == 'node_metrics')
      .parse(
        'NAME    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%\nnode-1  500m         6%     2048Mi          12%\n',
      );
  check(
    top.rows.single[1] == '500m' &&
        top.rows.single.length == top.headers.length,
    '节点资源单位丢失或列错位',
  );
  for (final runtime in MachineContainerRuntime.values.where(
    (runtime) => runtime != MachineContainerRuntime.kubernetes,
  )) {
    final queries = client(runtime).telemetryQueries;
    check(
      queries.any((item) => item.id == 'metadata') &&
          queries.any((item) => item.id == 'metrics'),
      '运行时缺少基础遥测',
    );
    if (runtime == MachineContainerRuntime.cri) {
      check(!queries.any((item) => item.id == 'disk'), 'CRI 提供了不支持的磁盘查询');
    }
  }
  final metadata = client(
    MachineContainerRuntime.docker,
  ).telemetryQueries.first;
  final docker = metadata.parse(
    '{"Name":"引擎","NCPU":8,"MemTotal":17179869184,"ContainersRunning":0,"Driver":"overlay2","LiveRestoreEnabled":false}',
  );
  check(
    docker.rows.any((row) => row[0] == '运行中容器' && row[1] == '0'),
    '运行时零值遗漏',
  );
  check(docker.rows.any((row) => row[1] == 'false'), '布尔元数据丢失');
  final podman = metadata.parse(
    '{"host":{"cpus":4,"memTotal":8589934592,"cgroupVersion":"v2"},"store":{"containerStore":{"running":2}}}',
  );
  check(
    podman.rows.any((row) => row[0] == '逻辑处理器' && row[1] == '4'),
    'Podman 元数据未归一化',
  );
  final cri = metadata.parse(
    '{"status":{"conditions":[{"type":"RuntimeReady","status":true}]}}',
  );
  check(cri.rows.single.first == '状态条件', 'CRI 就绪条件未展示');
  if (Platform.environment['CONTAINER_TELEMETRY_REAL'] != null) {
    for (final item in client(
      MachineContainerRuntime.docker,
    ).copyWith(scope: '', contextName: 'desktop-linux').telemetryQueries) {
      final process = await Process.start('docker', [
        '--context',
        'desktop-linux',
        ...item.arguments,
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      try {
        check(
          await process.exitCode.timeout(machineContainerTelemetryTimeout) == 0,
          '真实 Docker 采集失败：${item.id}',
        );
        item.parse(await output);
      } finally {
        process.kill();
        await errors;
      }
    }
  }
  stdout.writeln('容器运行时与 Kubernetes 遥测命令、作用域、结构、零值、健康检查、事件限量检查通过。');
}
