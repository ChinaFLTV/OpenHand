import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_containers.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final calls = <String>[];
  final docker = MachineContainerClient(
    runtime: MachineContainerRuntime.docker,
    contextName: '测试环境',
    run: (command) async {
      calls.add(command);
      return '';
    },
  );
  final containers = docker.parse('''
{"ID":"abc123","Names":"服务","State":"running","Image":"image:v1","Ports":"80/tcp"}
{"ID":"def456","Names":"暂停服务","State":"paused"}
''');
  check(containers.length == 2 && containers.first.running, 'Docker 列表解析失败');
  check(docker.actions(containers.first).contains('文件管理'), '运行容器缺少文件入口');
  check(!docker.actions(containers.last).contains('删除'), '暂停容器不应提供直接删除');
  check(docker.actions(containers.last).contains('恢复'), '暂停容器缺少恢复');
  await docker.act(containers.first, '停止');
  check(
    calls.single.contains("'--context' '测试环境' 'stop' 'abc123'"),
    '操作丢失连接上下文',
  );
  var rejected = false;
  try {
    docker.execCommand(
      const MachineContainerEntry(id: '--help', name: '', state: 'running'),
      'pwd',
    );
  } on ArgumentError {
    rejected = true;
  }
  check(rejected, '无效标识未被拒绝');
  const dangerous = "引号' 空格;\$(printf 错误)\n换行";
  if (!Platform.isWindows) {
    final command = docker.command([dangerous]);
    final quoted = command.substring(command.lastIndexOf(" '引号") + 1);
    final result = await Process.run('/bin/sh', ['-c', 'printf %s $quoted']);
    check(result.stdout == dangerous, '命令参数转义不完整');
  }
  final pod = {
    'metadata': {'name': 'pod-1', 'uid': 'uid-1', 'namespace': 'default'},
    'spec': {
      'nodeName': 'node-1',
      'containers': [
        {'name': 'app', 'image': 'app:v1'},
      ],
      'initContainers': [
        {'name': 'init', 'image': 'init:v1'},
      ],
    },
    'status': {
      'phase': 'Running',
      'containerStatuses': [
        {
          'name': 'app',
          'ready': true,
          'restartCount': 3,
          'state': {'running': {}},
        },
      ],
      'initContainerStatuses': [
        {
          'name': 'init',
          'ready': true,
          'state': {'terminated': {}},
        },
      ],
    },
  };
  var currentUid = 'uid-1';
  final kube = MachineContainerClient(
    runtime: MachineContainerRuntime.kubernetes,
    contextName: '集群',
    run: (command) async => jsonEncode({
      'metadata': {'uid': currentUid},
    }),
  );
  final entries = kube.parse(
    jsonEncode({
      'items': [pod],
    }),
  );
  check(entries.length == 3 && entries.first.ready == '1/1', 'Pod 就绪计数混入初始化容器');
  check(entries[1].running && entries[1].restarts == '3', '容器状态解析失败');
  check(!kube.actions(entries[1]).contains('停止'), 'Kubernetes 不应提供单容器停止');
  check(
    kube.execCommand(entries[1], 'pwd').contains("'-c' 'app' '--' '/bin/sh'"),
    '执行命令未指定 Pod 容器',
  );
  await kube.verify(entries.first);
  currentUid = 'uid-2';
  rejected = false;
  try {
    await kube.verify(entries.first);
  } on StateError {
    rejected = true;
  }
  check(rejected, '重建 Pod 身份未拦截');
  final cri = MachineContainerClient(
    runtime: MachineContainerRuntime.cri,
    run: (_) async => '',
  );
  final criRows = cri.parse(
    '{"containers":[{"id":"cri-1","metadata":{"name":"服务"},"state":"CONTAINER_EXITED","image":{"image":"app:v1"}}]}',
  );
  check(
    criRows.single.image == 'app:v1' &&
        !cri.actions(criRows.single).contains('启动'),
    'CRI 已退出容器不可重新启动',
  );
  final oversized = MachineContainerClient(
    runtime: MachineContainerRuntime.docker,
    run: (_) async => 'x' * (machineContainerOutputLimit + 1),
  );
  rejected = false;
  try {
    await oversized.execute(['info']);
  } on FormatException {
    rejected = true;
  }
  check(rejected, '超大报告未限制');
  stdout.writeln('容器解析、状态菜单、作用域引用、Pod 身份与输出限制检查通过。');
}
