import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_containers.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final calls = <String>[];
  var usageFails = false, cancel = false;
  final client = MachineContainerClient(
    runtime: MachineContainerRuntime.docker,
    contextName: '目标机器',
    run: (command) async {
      calls.add(command);
      if (command.contains("'image' 'ls'")) {
        return '{"ID":"sha256:fixed","Repository":"registry.local:5000/app","Tag":"v1","CreatedAt":"2026-10-01T01:02:03Z","Size":"20MB","Containers":"N/A"}';
      }
      if (command.contains("'volume' 'ls'")) {
        return '{"Name":"data","Driver":"local"}';
      }
      if (command.contains("'volume' 'inspect'")) {
        return '[{"Name":"data","CreatedAt":"2026-10-01T01:02:03Z","Mountpoint":"/volumes/data"}]';
      }
      if (command.contains("'system' 'df'")) {
        if (command.contains('.Images')) {
          return '[{"ID":"sha256:fixed","Repository":"other-tag","Containers":"2"}]';
        }
        if (usageFails) throw StateError('模拟容量统计失败');
        return '[{"Name":"data","Size":"123MB","Links":"1"}]';
      }
      if (command.contains("'image' 'inspect'")) {
        return '[{"Id":"sha256:fixed","Size":20000000}]';
      }
      if (command.contains("'image' 'history'")) return '';
      if (command.contains("'search'")) {
        return List.generate(
          60,
          (i) => jsonEncode({
            'Name': 'app-$i',
            'Description': '测试',
            'StarCount': i,
          }),
        ).join('\n');
      }
      return '';
    },
  );
  final images =
      (await client.resources(MachineContainerResourceKind.images).toList())
          .last;
  check(
    images.single.reference == 'registry.local:5000/app:v1' &&
        images.single.references == 2,
    '镜像标签、仓库端口或引用数错误',
  );
  final stages = await client
      .resources(MachineContainerResourceKind.volumes)
      .toList();
  check(
    stages.length == 3 &&
        stages[0].single.size.isEmpty &&
        stages[1].single.created.isNotEmpty &&
        stages[2].single.size == '123MB',
    '卷信息未分阶段更新',
  );
  check(
    stages.last.single.raw['Mountpoint'] == '/volumes/data' &&
        stages.last.single.references == 1,
    '容量合并覆盖了卷元数据',
  );
  usageFails = true;
  final partial = <List<MachineContainerResource>>[];
  try {
    await for (final rows in client.resources(
      MachineContainerResourceKind.volumes,
    )) {
      partial.add(rows);
    }
  } on StateError catch (error) {
    check('$error'.contains('容量'), '容量异常原因丢失');
  }
  check(
    partial.length == 2 && partial.last.single.created.isNotEmpty,
    '容量失败丢失了已加载信息',
  );
  final before = calls.length;
  await for (final _ in client.resources(
    MachineContainerResourceKind.volumes,
    isCancelled: () => cancel,
  )) {
    cancel = true;
  }
  check(calls.length == before + 1, '关闭面板后继续采集卷详情');
  final results = await client.searchImages('nginx');
  check(
    results.length == machineContainerSearchLimit &&
        calls.last.contains("'--limit' '50'"),
    '仓库搜索未限量',
  );
  final details =
      jsonDecode(await client.inspectImageReference('sha256:fixed')) as Map;
  check(details['image']['Id'] == 'sha256:fixed', '本地镜像无法直接查看详情');
  check(
    client
            .removeResourceArguments(
              MachineContainerResourceKind.images,
              images.single,
            )
            .join('|') ==
        'image|rm|sha256:fixed',
    '删除镜像未固定标识或强制删除',
  );
  check(
    client
            .removeResourceArguments(
              MachineContainerResourceKind.volumes,
              stages.last.single,
            )
            .join('|') ==
        'volume|rm|data',
    '数据卷删除命令错误',
  );
  check(
    client
            .createVolumeArguments(
              'data',
              labels: {'app': 'worker'},
              options: {'type': 'tmpfs'},
            )
            .join('|') ==
        'volume|create|--label|app=worker|--opt|type=tmpfs|data',
    '创建卷配置丢失',
  );

  const spec = MachineContainerCreateSpec(
    image: 'registry.local:5000/app:v1',
    name: 'test',
    ports: [
      {'address': '::1', 'host': '8080', 'container': '80', 'protocol': 'tcp'},
    ],
    environment: {'VALUE': "测试'\";\$(printf 不应执行)\n换行"},
    mounts: [
      {
        'source': '/data,a',
        'target': '/data',
        'type': 'bind',
        'readonly': 'true',
      },
    ],
    restart: 'unless-stopped',
    cpus: '1.5',
    memory: '512m',
    entrypoint: '/entry point',
    arguments: ['serve', '--option=a b'],
  );
  final args = spec.commandArguments();
  check(
    args.contains('[::1]:8080:80/tcp') &&
        args.contains('type=bind,"source=/data,a",target=/data,readonly'),
    '端口与挂载转义错误',
  );
  check(
    args.first == 'run' &&
        args.contains('--detach') &&
        args.sublist(args.indexOf('registry.local:5000/app:v1')).join('|') ==
            'registry.local:5000/app:v1|serve|--option=a b',
    '创建并启动的参数顺序错误',
  );
  if (!Platform.isWindows) {
    final result = await Process.run('/bin/sh', [
      '-c',
      r'docker() { printf "%s\000" "$@"; }; ' + client.command(args),
    ]);
    final actual = '${result.stdout}'.split('\u0000')..removeLast();
    check(
      jsonEncode(actual) == jsonEncode(['--context', '目标机器', ...args]),
      '创建配置存在 Shell 注入或参数被改写',
    );
  }
  check(
    const MachineContainerCreateSpec(
          image: 'nginx',
          start: false,
        ).commandArguments().first ==
        'create',
    '仅创建被错误启动',
  );
  for (final invalid in [
    const MachineContainerCreateSpec(image: '--help'),
    const MachineContainerCreateSpec(image: 'nginx', name: 'bad name'),
    const MachineContainerCreateSpec(image: 'nginx', cpus: 'NaN'),
    const MachineContainerCreateSpec(
      image: 'nginx',
      ports: [
        {'address': '999.1.1.1', 'container': '80'},
      ],
    ),
    const MachineContainerCreateSpec(image: 'nginx', memory: '0m'),
    const MachineContainerCreateSpec(
      image: 'nginx',
      ports: [
        {'container': '65536'},
      ],
    ),
    const MachineContainerCreateSpec(
      image: 'nginx',
      ports: [
        {'container': '80', 'protocol': 'shell'},
      ],
    ),
    const MachineContainerCreateSpec(
      image: 'nginx',
      environment: {'BAD=KEY': 'value'},
    ),
    const MachineContainerCreateSpec(
      image: 'nginx',
      mounts: [
        {'source': 'data', 'target': 'relative'},
      ],
    ),
    const MachineContainerCreateSpec(image: 'nginx', arguments: ['\u0000']),
  ]) {
    var rejected = false;
    try {
      invalid.commandArguments();
    } on MachineContainerConfigException {
      rejected = true;
    }
    check(rejected, '无效容器配置未被拒绝');
  }
  final unsupported = MachineContainerClient(
    runtime: MachineContainerRuntime.kubernetes,
    run: (_) async => throw StateError('不应执行'),
  );
  check(
    !unsupported.supportsResources && !unsupported.supportsImageSearch,
    '不兼容运行时暴露了管理入口',
  );
  try {
    await unsupported.resources(MachineContainerResourceKind.images).toList();
    throw StateError('未阻止不兼容查询');
  } on MachineContainerConfigException catch (error) {
    check(error.code == 'resourceUnsupported', '兼容性错误不明确');
  }

  if (Platform.environment['OPENHAND_VERIFY_CONTAINER_RESOURCES'] == '1') {
    final live = MachineContainerClient(
      runtime: MachineContainerRuntime.docker,
      run: (command) async {
        final result = await Process.run('/bin/sh', [
          '-c',
          command,
        ]).timeout(const Duration(seconds: 30));
        if (result.exitCode != 0) throw StateError('本机资源只读验证失败');
        return '${result.stdout}';
      },
    );
    final images =
        (await live.resources(MachineContainerResourceKind.images).toList())
            .last;
    final volumes =
        (await live.resources(MachineContainerResourceKind.volumes).toList())
            .last;
    check(
      images.every((row) => row.id.isNotEmpty) &&
          volumes.every((row) => row.name.isNotEmpty),
      '本机资源标识缺失',
    );
    stdout.writeln('本机镜像列表、数据卷元数据与容量验证通过，未执行下载或任何变更。');
  }
  stdout.writeln('镜像、数据卷、分批更新、取消、搜索限制、创建参数、转义及兼容性检查通过。');
}
