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
  final statuses = docker.parse('''
{"ID":"up-1","Names":"服务","Status":"Up 2 minutes"}
{"ID":"paused-1","Names":"暂停服务","Status":"Up 2 minutes (Paused)"}
''');
  check(
    statuses.first.running && statuses.last.state == 'paused',
    '只有 Status 的客户端未识别运行和暂停状态',
  );
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
  final discoveryCalls = <String>[];
  Future<String> autoRun(String command) async {
    discoveryCalls.add(command);
    if (command.startsWith("'docker'")) {
      return command.contains("'context' 'show'") ? 'default' : '';
    }
    if (command.startsWith("'kubectl'")) {
      return command.contains("'current-context'")
          ? '生产集群'
          : jsonEncode({
              'items': [pod],
            });
    }
    throw StateError('不应探测已有数据之后的运行时。');
  }

  final detected = await discoverMachineContainers(run: autoRun);
  check(
    detected.client.runtime == MachineContainerRuntime.kubernetes &&
        detected.entries.length == 3,
    '空 Docker 列表阻断了 Kubernetes 发现',
  );
  check(detected.client.contextName == '生产集群', 'Kubernetes 上下文未保留');
  check(discoveryCalls.length == 4, '有数据后仍在重复探测运行时');
  discoveryCalls.clear();
  await discoverMachineContainers(
    run: autoRun,
    probe: (_) async => throw StateError('已连接运行时不应重新发现。'),
    preferred: detected.client,
  );
  check(discoveryCalls.length == 1, '刷新没有复用已有运行时');

  for (final legacy in [false, true]) {
    final selected = await discoverMachineContainers(
      runtime: MachineContainerRuntime.docker,
      run: (command) async {
        if (command.contains("'context' 'show'")) {
          if (legacy) {
            throw StateError("docker: 'context' is not a docker command.");
          }
          return 'default';
        }
        check(!command.contains("'--context'"), '默认上下文覆盖了 DOCKER_HOST');
        return '{"ID":"legacy-1","Names":"服务","State":"running"}';
      },
    );
    check(selected.entries.single.running, '旧版 Docker 的列表被上下文探测阻断');
  }

  final namespaced = await discoverMachineContainers(
    run: (command) async {
      if (!command.startsWith("'nerdctl'")) {
        throw StateError('command not found');
      }
      if (command.contains("'namespace' 'ls' '-q'")) return 'default\nk8s.io\n';
      return command.contains("'--namespace' 'k8s.io'")
          ? '{"ID":"worker-1","Names":"工作负载","State":"running"}'
          : '';
    },
  );
  check(
    namespaced.client.scope == 'k8s.io' && namespaced.entries.length == 1,
    'containerd 的非默认命名空间未被发现',
  );
  check(
    namespaced.client.command(['info']).contains("'--namespace' 'k8s.io'"),
    '后续操作丢失 containerd 命名空间',
  );

  final embedded = await discoverMachineContainers(
    run: (command) async {
      if (!command.startsWith("'k3s' 'kubectl'")) {
        throw StateError('command not found');
      }
      return command.contains("'current-context'")
          ? 'default'
          : jsonEncode({
              'items': [pod],
            });
    },
  );
  check(
    embedded.client.launcher.join(' ') == 'k3s kubectl' &&
        embedded.entries.length == 3,
    'K3s 内置客户端未被发现',
  );
  check(
    embedded.client
        .execCommand(embedded.entries[1], 'pwd')
        .startsWith("'k3s' 'kubectl'"),
    '容器操作丢失已探测的命令入口',
  );

  var cancelled = false;
  var cancellationCalls = 0;
  try {
    await discoverMachineContainers(
      run: (_) async {
        cancellationCalls++;
        cancelled = true;
        return 'default';
      },
      isCancelled: () => cancelled,
    );
    throw StateError('取消后不应继续返回结果。');
  } on StateError catch (error) {
    check(error.message == '容器采集已取消。', '取消原因被吞掉');
  }
  check(cancellationCalls == 1, '取消后仍在发送命令');

  var explicitCalls = 0;
  try {
    await discoverMachineContainers(
      runtime: MachineContainerRuntime.docker,
      run: (command) async {
        explicitCalls++;
        check(command.startsWith("'docker'"), '显式选择的运行时被静默切换');
        throw StateError('permission denied');
      },
    );
    throw StateError('所有查询失败不应返回空容器列表。');
  } on MachineContainerDiscoveryException catch (error) {
    check(
      error.issues.keys.single == 'docker' &&
          error.issues.values.single.contains('permission denied'),
      '运行时诊断丢失原始原因',
    );
  }
  check(explicitCalls == 2, '显式选择存在重复查询');

  for (final client in [kube, cri]) {
    for (final invalid in ['', '{}', '{"error":"unavailable"}']) {
      rejected = false;
      try {
        client.parse(invalid);
      } on FormatException {
        rejected = true;
      }
      check(rejected, '结构无效的响应被误判为空列表');
    }
  }
  final podman = MachineContainerClient(
    runtime: MachineContainerRuntime.podman,
    run: (_) async => '',
  );
  check(
    podman
            .parse('[{"Id":"podman-1","Names":["web"],"State":"running"}]')
            .single
            .name ==
        'web',
    'Podman 名称数组未规范化',
  );
  final config = <String, dynamic>{
    'Id': 'abc123456789',
    'Name': '/worker',
    'Image': 'sha256:pinned-image',
    'Config': {
      'Image': 'app:latest',
      'Hostname': 'abc123456789',
      'User': '1000:1000',
      'WorkingDir': '/work dir',
      'Env': ["VALUE=空格'\";\$(printf 不应执行)\n第二行"],
      'Labels': {'应用': '测试'},
      'Entrypoint': ['/entry point', '--mode'],
      'Cmd': ['serve', '--name=a b'],
      'Tty': true,
      'ExposedPorts': {'80/tcp': {}},
      'Healthcheck': {
        'Test': ['CMD-SHELL', 'test -f /ready'],
        'Interval': 1000000000,
        'Retries': 3,
      },
    },
    'HostConfig': {
      'PortBindings': {
        '80/tcp': [
          {'HostIp': '::1', 'HostPort': '8080'},
        ],
      },
      'Binds': ['/host dir:/data:ro'],
      'Tmpfs': {'/tmp': 'size=64m'},
      'Mounts': [
        {
          'Type': 'volume',
          'Source': 'cache',
          'Target': '/cache',
          'VolumeOptions': {'NoCopy': true},
        },
      ],
      'NetworkMode': 'app-network',
      'RestartPolicy': {'Name': 'on-failure', 'MaximumRetryCount': 5},
      'Memory': 536870912,
      'NanoCpus': 1500000000,
      'ReadonlyRootfs': true,
      'SecurityOpt': ['no-new-privileges'],
      'Dns': ['1.1.1.1'],
      'Sysctls': {'net.ipv4.ip_forward': '1'},
      'ConsoleSize': [0, 0],
      'LogConfig': {
        'Type': 'json-file',
        'Config': {'max-size': '10m'},
      },
    },
    'Mounts': [
      {
        'Type': 'bind',
        'Source': '/host dir',
        'Destination': '/data',
        'RW': false,
      },
      {'Type': 'volume', 'Name': 'cache', 'Destination': '/cache'},
      {'Type': 'tmpfs', 'Destination': '/tmp'},
      {'Type': 'volume', 'Name': 'anonymous', 'Destination': '/state'},
      {
        'Type': 'bind',
        'Source': '/path,a',
        'Destination': '/comma',
        'RW': true,
      },
    ],
    'NetworkSettings': {
      'Networks': {
        'app-network': {
          'Aliases': ['worker', 'abc123456789', 'web'],
          'IPAddress': '172.20.0.99',
          'IPAMConfig': {'IPv4Address': '172.20.0.10'},
        },
      },
    },
  };
  final args = machineContainerRunArguments(config);
  String option(String name) => args[args.indexOf(name) + 1];
  check(option('--publish') == '[::1]:8080:80/tcp', 'IPv6 端口映射错误');
  check(option('--entrypoint') == '/entry point', '入口命令丢失');
  check(
    args.sublist(args.indexOf('sha256:pinned-image')).join('|') ==
        'sha256:pinned-image|--mode|serve|--name=a b',
    '入口参数与启动参数顺序错误',
  );
  check(
    !args.contains('app:latest') && !args.contains('--hostname'),
    '命令使用了可变标签或自动生成的主机名',
  );
  check(
    args.where((a) => a == '--volume').length == 1 &&
        args.where((a) => a == '--mount').length == 3,
    '挂载重复或丢失',
  );
  check(
    args.contains('type=bind,"source=/path,a",target=/comma'),
    '挂载 CSV 转义错误',
  );
  check(
    option('--restart') == 'on-failure:5' && option('--cpus') == '1.5',
    '重启策略或资源限制丢失',
  );
  check(
    option('--ip') == '172.20.0.10' && !args.contains('172.20.0.99'),
    '动态地址被误当作固定配置',
  );
  check(option('--network-alias') == 'web', '自定义网络别名丢失');
  if (!Platform.isWindows) {
    final copied = docker.command(args, readable: true);
    final output = await Process.run('/bin/sh', [
      '-c',
      r'docker() { printf "%s\000" "$@"; }; ' + copied,
    ]);
    final actual = '${output.stdout}'.split('\u0000')..removeLast();
    check(
      jsonEncode(actual) == jsonEncode(['--context', '测试环境', ...args]),
      '复制命令未完整保留参数或存在 Shell 注入',
    );
  }
  final windows = MachineContainerClient(
    runtime: MachineContainerRuntime.docker,
    run: (_) async => '',
    windows: true,
  );
  check(
    windows.command(['run', "a'b"], readable: true) ==
        "& 'docker' 'run' 'a''b'",
    'Windows 剪贴板命令不是可读 PowerShell',
  );
  check(
    windows.command(['inspect', 'abc']).contains('-EncodedCommand'),
    'Windows 远程执行封装被破坏',
  );
  for (final change in [
    {
      'DeviceRequests': [
        {'Driver': 'nvidia'},
      ],
    },
    {
      'VolumesFrom': ['other'],
    },
    {
      'Links': ['other:alias'],
    },
  ]) {
    try {
      machineContainerRunArguments({
        ...config,
        'HostConfig': {...config['HostConfig'] as Map, ...change},
      });
      throw StateError('不完整的运行配置不应被复制。');
    } on MachineContainerConfigException catch (e) {
      check(e.code == 'incomplete', '配置拒绝原因错误');
    }
  }
  final emptyEntrypoint = machineContainerRunArguments({
    ...config,
    'Config': {'Image': 'app', 'Entrypoint': null, 'Cmd': []},
  });
  check(
    emptyEntrypoint[emptyEntrypoint.indexOf('--entrypoint') + 1].isEmpty,
    '空入口没有清除镜像默认入口',
  );
  final readCalls = <String>[];
  var historyFails = false;
  final reader = docker.copyWith(
    run: (command) async {
      readCalls.add(command);
      if (command.contains("'run' '--help'")) {
        return '${args.where((a) => a.startsWith('--')).join(' ')} ';
      }
      if (command.contains("'image' 'inspect'")) {
        return '[{"Id":"sha256:pinned-image","Size":1024,"RepoTags":["app:old"]}]';
      }
      if (command.contains("'image' 'history'")) {
        if (historyFails) throw StateError('模拟构建历史不可读');
        return '{"CreatedBy":"RUN true","Size":"1kB","CreatedAt":"2026-10-01T08:00:00Z"}';
      }
      return jsonEncode([config]);
    },
  );
  check(
    await reader.runCommand(containers.first) ==
        docker.command(args, readable: true),
    '复制命令未读取实际配置',
  );
  readCalls.clear();
  final imageReport =
      jsonDecode(await reader.imageDetails(containers.first)) as Map;
  check(
    imageReport['image']['Id'] == 'sha256:pinned-image' &&
        imageReport['history'].length == 1,
    '镜像详情未合并历史',
  );
  check(
    readCalls.length == 3 &&
        readCalls.skip(1).every((c) => c.endsWith("'sha256:pinned-image'")),
    '镜像查询未固定创建时的镜像',
  );
  check(
    readCalls.every((c) => !c.contains("'run'") && !c.contains("'pull'")),
    '读取详情意外执行了容器命令',
  );
  historyFails = true;
  final partial = jsonDecode(await reader.imageDetails(containers.first));
  check(
    partial['image']['Id'] == 'sha256:pinned-image' &&
        partial['historyError'] != null,
    '历史失败丢失了镜像详情',
  );
  var cancelledImage = false;
  var imageCalls = 0;
  final cancelling = docker.copyWith(
    run: (_) async {
      imageCalls++;
      cancelledImage = true;
      return jsonEncode([config]);
    },
  );
  try {
    await cancelling.imageDetails(
      containers.first,
      isCancelled: () => cancelledImage,
    );
  } on MachineContainerConfigException catch (e) {
    check(e.code == 'cancelled', '镜像取消原因错误');
  }
  check(imageCalls == 1, '关闭镜像弹窗后仍继续查询');
  final kubeImage = kube.copyWith(run: (_) async => jsonEncode(pod));
  final reference = jsonDecode(await kubeImage.imageDetails(entries[1]));
  check(
    reference['referenceOnly'] == true &&
        reference['image']['Image'] == 'app:v1',
    'Kubernetes 镜像引用报告错误',
  );
  check(
    !kube.actions(entries[1]).contains('复制 run 命令') &&
        !cri.actions(criRows.single).contains('复制 run 命令'),
    '不兼容运行时暴露了 run 命令',
  );
  check(podman.actions(containers.last).contains('复制 run 命令'), '已停止容器缺少复制入口');

  final liveId = Platform.environment['OPENHAND_CONTAINER_VERIFY_ID'];
  if (liveId != null) {
    final live = MachineContainerClient(
      runtime: MachineContainerRuntime.docker,
      run: (command) async {
        final result = await Process.run('/bin/sh', [
          '-c',
          command,
        ]).timeout(const Duration(seconds: 15));
        if (result.exitCode != 0) throw StateError('本机 Docker 只读查询失败。');
        return '${result.stdout}';
      },
    );
    final entry = MachineContainerEntry(
      id: liveId,
      name: '本机验证',
      state: 'running',
    );
    final command = await live.runCommand(entry);
    final report = jsonDecode(await live.imageDetails(entry));
    check(
      command.contains("'run' '--detach'") && report['image']['Id'] != null,
      '本机容器只读验证失败',
    );
    stdout.writeln('本机 Docker 配置还原、镜像 ID 查询与构建历史验证通过，未执行生成的命令。');
  }
  stdout.writeln('容器解析、自动发现、旧版客户端、命名空间、取消、状态菜单、作用域与输出限制检查通过。');
}
