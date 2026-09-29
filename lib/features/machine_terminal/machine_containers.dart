import 'dart:convert';

import '../../shared/util/platform_shell.dart';

const machineContainerOutputLimit = 2 * 1024 * 1024;

enum MachineContainerRuntime {
  docker('Docker', 'docker'),
  podman('Podman', 'podman'),
  kubernetes('Kubernetes', 'kubectl'),
  containerd('containerd · nerdctl', 'nerdctl'),
  cri('containerd / CRI', 'crictl');

  const MachineContainerRuntime(this.label, this.executable);
  final String label, executable;
}

class MachineContainerEntry {
  const MachineContainerEntry({
    required this.id,
    required this.name,
    required this.state,
    this.namespace = '',
    this.pod = '',
    this.image = '',
    this.node = '',
    this.created = '',
    this.restarts = '',
    this.ready = '',
    this.ports = '',
    this.isPod = false,
    this.metadata = const {},
  });
  final String id,
      name,
      state,
      namespace,
      pod,
      image,
      node,
      created,
      restarts,
      ready,
      ports;
  final bool isPod;
  final Map<String, dynamic> metadata;
  bool get running =>
      const ['running', 'container_running'].contains(state.toLowerCase());
}

/// 运行时命令统一按实参引用，作用域在一次操作期间保持不变。
class MachineContainerClient {
  const MachineContainerClient({
    required this.runtime,
    required this.run,
    this.scope = '',
    this.contextName = '',
    this.windows = false,
  });
  final MachineContainerRuntime runtime;
  final Future<String> Function(String command) run;
  final String scope, contextName;
  final bool windows;

  String command(List<String> arguments) {
    final args = [
      runtime.executable,
      if (runtime == MachineContainerRuntime.docker &&
          contextName.isNotEmpty) ...[
        '--context',
        contextName,
      ],
      if (runtime == MachineContainerRuntime.cri) ...[
        '--timeout=10s',
        if (scope.isNotEmpty) ...['--runtime-endpoint', scope],
      ],
      if (runtime == MachineContainerRuntime.kubernetes) ...[
        '--request-timeout=10s',
        if (contextName.isNotEmpty) ...['--context', contextName],
      ],
      if (runtime == MachineContainerRuntime.containerd) ...[
        '--namespace',
        scope.isEmpty ? 'default' : scope,
      ],
      ...arguments,
    ];
    if (args.any((arg) => arg.contains('\u0000'))) {
      throw ArgumentError('命令参数包含无效字符。');
    }
    if (windows) {
      return powerShellEncodedCommand(
        "& ${args.map((a) => "'${escapePowerShellSingleQuotedString(a)}'").join(' ')}; exit \$LASTEXITCODE",
      );
    }
    return args.map(posixShellQuote).join(' ');
  }

  Future<String> execute(List<String> args) async {
    final output = await run(command(args));
    if (output.length > machineContainerOutputLimit) {
      throw const FormatException('容器报告超过读取上限，请缩小命名空间后重试。');
    }
    return output;
  }

  List<String> get listArguments => switch (runtime) {
    MachineContainerRuntime.kubernetes => [
      'get',
      'pods',
      if (scope.isEmpty) '-A' else ...['-n', scope],
      '-o',
      'json',
      '--chunk-size=200',
    ],
    MachineContainerRuntime.cri => ['ps', '-a', '-o', 'json'],
    _ => ['ps', '-a', '--no-trunc', '--format', '{{json .}}'],
  };
  List<String> get metadataArguments => switch (runtime) {
    MachineContainerRuntime.kubernetes => ['version', '-o', 'json'],
    MachineContainerRuntime.cri => ['info'],
    _ => ['info', '--format', '{{json .}}'],
  };
  List<String> get metricsArguments => switch (runtime) {
    MachineContainerRuntime.kubernetes => [
      'top',
      'pods',
      if (scope.isEmpty) '-A' else ...['-n', scope],
      '--containers',
    ],
    MachineContainerRuntime.cri => ['stats', '-o', 'json'],
    _ => ['stats', '--no-stream', '--format', '{{json .}}'],
  };

  List<MachineContainerEntry> parse(String output, {bool pods = false}) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return [];
    dynamic decoded;
    if (runtime == MachineContainerRuntime.kubernetes ||
        runtime == MachineContainerRuntime.cri ||
        trimmed.startsWith('[')) {
      decoded = jsonDecode(trimmed);
    } else {
      decoded = trimmed
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map(jsonDecode)
          .toList();
    }
    final result = <MachineContainerEntry>[];
    String value(dynamic value) => value?.toString() ?? '';
    if (runtime == MachineContainerRuntime.kubernetes) {
      for (final item in (decoded['items'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(item['metadata'] as Map? ?? {});
        final status = item['status'] as Map? ?? {};
        final spec = item['spec'] as Map? ?? {};
        final namespace = value(m['namespace']);
        final name = value(m['name']);
        final uid = value(m['uid']);
        final statuses = <dynamic>[
          ...?status['containerStatuses'],
          ...?status['initContainerStatuses'],
          ...?status['ephemeralContainerStatuses'],
        ];
        result.add(
          MachineContainerEntry(
            id: uid,
            name: name,
            namespace: namespace,
            isPod: true,
            state: value(status['phase']),
            node: value(spec['nodeName']),
            created: value(m['creationTimestamp']),
            ready:
                '${(status['containerStatuses'] as List? ?? []).where((s) => s['ready'] == true).length}/${(spec['containers'] as List? ?? []).length}',
            restarts:
                '${statuses.fold<int>(0, (sum, s) => sum + ((s['restartCount'] as num?)?.toInt() ?? 0))}',
            metadata: Map<String, dynamic>.from(item),
          ),
        );
        for (final container in <dynamic>[
          ...?spec['containers'],
          ...?spec['initContainers'],
          ...?spec['ephemeralContainers'],
        ]) {
          final matches = statuses.where((s) => s['name'] == container['name']);
          final cs = matches.isEmpty
              ? <String, dynamic>{}
              : matches.first as Map;
          final state = cs['state'] as Map? ?? {};
          result.add(
            MachineContainerEntry(
              id: uid,
              pod: name,
              namespace: namespace,
              name: value(container['name']),
              image: value(container['image']),
              state: state.keys.firstOrNull?.toString() ?? 'unknown',
              node: value(spec['nodeName']),
              created: value(m['creationTimestamp']),
              ready: value(cs['ready']),
              restarts: value(cs['restartCount']),
              metadata: {'spec': container, 'status': cs},
            ),
          );
        }
      }
    } else {
      final items = decoded is List
          ? decoded
          : decoded[pods ? 'items' : 'containers'] as List? ?? [];
      for (final raw in items) {
        final m = Map<String, dynamic>.from(raw as Map);
        final meta = m['metadata'] as Map? ?? {};
        final image = m['image'];
        result.add(
          MachineContainerEntry(
            id: value(m['ID'] ?? m['Id'] ?? m['id']),
            name: value(m['Names'] ?? m['Name'] ?? meta['name'] ?? m['id']),
            state: value(m['State'] ?? m['Status'] ?? m['state']),
            image: value(image is Map ? image['image'] : m['Image'] ?? image),
            created: value(m['CreatedAt'] ?? m['createdAt']),
            ports: value(m['Ports']),
            namespace: value(meta['namespace']),
            pod: value(m['podSandboxId']),
            isPod: pods,
            metadata: m,
          ),
        );
      }
    }
    return result;
  }

  List<String> actions(MachineContainerEntry entry) {
    if (entry.isPod) {
      return [
        '详情',
        '日志',
        '终端',
        '文件管理',
        if (runtime == MachineContainerRuntime.kubernetes) '事件',
        if (runtime == MachineContainerRuntime.cri) '停止',
        '删除',
      ];
    }
    return [
      '详情',
      '日志',
      if (entry.running) ...['终端', '文件管理'],
      if (runtime != MachineContainerRuntime.kubernetes) ...[
        if (entry.running)
          '停止'
        else if (!entry.state.toLowerCase().contains('paused') &&
            (runtime != MachineContainerRuntime.cri ||
                entry.state.toLowerCase() == 'container_created'))
          '启动',
        if (runtime != MachineContainerRuntime.cri) ...[
          '重启',
          if (entry.state.toLowerCase().contains('paused'))
            '恢复'
          else if (entry.running)
            '暂停',
        ],
        if (!entry.running && !entry.state.toLowerCase().contains('paused'))
          '删除',
      ],
    ];
  }

  void _validate(MachineContainerEntry e) {
    for (final value in [
      e.id,
      if (runtime == MachineContainerRuntime.kubernetes) ...[
        e.namespace,
        e.isPod ? e.name : e.pod,
        if (!e.isPod) e.name,
      ],
    ]) {
      if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.:/-]*$').hasMatch(value)) {
        throw ArgumentError('容器标识无效，请刷新后重试。');
      }
    }
  }

  List<String> inspectArguments(MachineContainerEntry e) =>
      runtime == MachineContainerRuntime.kubernetes
      ? [
          'get',
          'pod',
          e.isPod ? e.name : e.pod,
          '-n',
          e.namespace,
          '-o',
          'json',
        ]
      : [
          runtime == MachineContainerRuntime.cri && e.isPod
              ? 'inspectp'
              : 'inspect',
          e.id,
        ];

  Future<String> inspect(MachineContainerEntry e) {
    _validate(e);
    return execute(inspectArguments(e));
  }

  Future<String> logs(MachineContainerEntry e) => execute(
    runtime == MachineContainerRuntime.kubernetes
        ? [
            'logs',
            e.pod,
            '-n',
            e.namespace,
            '-c',
            e.name,
            '--tail=300',
            '--timestamps=true',
          ]
        : ['logs', '--tail=300', '--timestamps', e.id],
  );

  /// Pod 名称可能被控制器复用，操作前必须核验 UID。
  Future<void> verify(MachineContainerEntry e) async {
    _validate(e);
    if (runtime != MachineContainerRuntime.kubernetes) return;
    final current = jsonDecode(await inspect(e));
    if (current['metadata']?['uid'] != e.id) {
      throw StateError('Pod 已重建，请刷新后操作。');
    }
  }

  String execCommand(
    MachineContainerEntry e,
    String script, {
    bool tty = false,
  }) {
    _validate(e);
    if (e.isPod || !e.running) throw StateError('请选择运行中的具体容器。');
    return command(
      runtime == MachineContainerRuntime.kubernetes
          ? [
              'exec',
              '-i',
              if (tty) '-t',
              e.pod,
              '-n',
              e.namespace,
              '-c',
              e.name,
              '--',
              '/bin/sh',
              '-c',
              script,
            ]
          : ['exec', '-i', if (tty) '-t', e.id, '/bin/sh', '-c', script],
    );
  }

  Future<String> act(MachineContainerEntry e, String action) async {
    if (!actions(e).contains(action)) throw StateError('当前状态不支持此操作。');
    await verify(e);
    if (runtime == MachineContainerRuntime.kubernetes) {
      if (action != '删除' || !e.isPod) throw StateError('Kubernetes 不支持此直接操作。');
      return execute([
        'delete',
        'pod',
        e.name,
        '-n',
        e.namespace,
        '--wait=false',
      ]);
    }
    final verb = switch (action) {
      '启动' => 'start',
      '停止' => e.isPod ? 'stopp' : 'stop',
      '重启' => 'restart',
      '暂停' => 'pause',
      '恢复' => 'unpause',
      '删除' => e.isPod ? 'rmp' : 'rm',
      _ => throw ArgumentError('未知容器操作。'),
    };
    return execute([verb, e.id]);
  }
}
