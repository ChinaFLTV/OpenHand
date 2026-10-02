import 'dart:async';
import 'dart:convert';

import '../../shared/util/platform_shell.dart';
import 'machine_maintenance_readout.dart';

part 'machine_container_inspection.dart';
part 'machine_container_resources.dart';
part 'machine_container_telemetry.dart';

const machineContainerOutputLimit = 2 * 1024 * 1024;
const machineContainerProbeTimeout = Duration(seconds: 6);
const machineContainerDiscoveryTimeout = Duration(seconds: 40);
const _machineContainerNamespaceLimit = 8;
const _machineContainerInspectBatchSize = 64;
final _machineContainerBytePattern = RegExp(
  r'^(\d+(?:\.\d+)?)\s*((?:[kmgtpe]i?)?b)?$',
  caseSensitive: false,
);

typedef MachineContainerListDetails = ({String startedAt, String ports});
typedef MachineContainerUsage = ({
  double? cpuPercent,
  double? memoryPercent,
  String memoryUsage,
  String networkIO,
  String blockIO,
  int? processes,
});

/// 运行时占位值统一为空；保留用户标签、列表和实际零值。
String machineContainerMetadataText(Object? value) {
  if (value == null) return '';
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }
  if (value is List) return value.join(', ');
  final text = '$value'.trim();
  return const {
        'n/a',
        'null',
        '<none>',
        '<no value>',
        '--',
        '—',
      }.contains(text.toLowerCase())
      ? ''
      : text;
}

/// 区分运行时报告的十进制与二进制容量，不将未知或负值当作零。
double? machineContainerByteCount(Object? value) {
  final text = machineContainerMetadataText(value);
  final match = _machineContainerBytePattern.firstMatch(text);
  if (match == null) return null;
  final amount = double.tryParse(match[1]!);
  final unit = (match[2] ?? 'b').toLowerCase();
  final exponent = 'bkmgtpe'.indexOf(unit[0]);
  var factor = 1.0;
  for (var index = 0; index < exponent; index++) {
    factor *= unit.contains('i') ? 1024 : 1000;
  }
  final bytes = (amount ?? double.nan) * factor;
  return bytes.isFinite && bytes >= 0 ? bytes : null;
}

enum MachineContainerRuntime {
  docker('Docker', 'docker'),
  podman('Podman', 'podman'),
  kubernetes('Kubernetes', 'kubectl'),
  containerd('containerd · nerdctl', 'nerdctl'),
  cri('containerd / CRI', 'crictl');

  const MachineContainerRuntime(this.label, this.executable);
  final String label, executable;
}

typedef MachineContainerSelection = ({
  MachineContainerClient client,
  List<MachineContainerEntry> entries,
});

class MachineContainerDiscoveryException implements Exception {
  const MachineContainerDiscoveryException(this.issues);
  final Map<String, String> issues;

  @override
  String toString() =>
      issues.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');
}

/// 先复用已确认的连接；首次自动识别优先选择有记录的运行时。
Future<MachineContainerSelection> discoverMachineContainers({
  required Future<String> Function(String) run,
  Future<String> Function(String)? probe,
  MachineContainerClient? preferred,
  MachineContainerRuntime? runtime,
  String scope = '',
  bool windows = false,
  bool Function()? isCancelled,
}) async {
  final elapsed = Stopwatch()..start();
  void checkCancelled() {
    if (isCancelled?.call() ?? false) throw StateError('容器采集已取消。');
  }

  Future<String> query(String command, {bool connected = false}) async {
    checkCancelled();
    if (elapsed.elapsed >= machineContainerDiscoveryTimeout) {
      throw TimeoutException('容器运行时识别超时。');
    }
    final result = await (connected ? run : probe ?? run)(command);
    checkCancelled();
    return result;
  }

  final runtimes = runtime == null
      ? [
          MachineContainerRuntime.docker,
          MachineContainerRuntime.kubernetes,
          MachineContainerRuntime.podman,
          MachineContainerRuntime.containerd,
          MachineContainerRuntime.cri,
        ]
      : [runtime];
  final candidates = [
    if (preferred != null)
      preferred.copyWith(run: (command) => query(command, connected: true)),
    for (final candidate in runtimes)
      MachineContainerClient(
        runtime: candidate,
        run: (command) => query(command, connected: runtime != null),
        scope: runtime == null ? '' : scope,
        windows: windows,
      ),
    if (!windows && runtime == null)
      for (final candidate in [
        MachineContainerRuntime.kubernetes,
        MachineContainerRuntime.cri,
      ])
        MachineContainerClient(
          runtime: candidate,
          run: query,
          launcher: ['k3s', candidate.executable],
        ),
  ];
  final issues = <String, String>{};
  final attempted = <(MachineContainerRuntime, String, String)>{};
  MachineContainerSelection? empty;
  try {
    for (var client in candidates) {
      checkCancelled();
      final executable = client.launcher.isEmpty
          ? client.runtime.executable
          : client.launcher.join(' ');
      if (!attempted.add((client.runtime, executable, client.scope))) continue;
      if (elapsed.elapsed >= machineContainerDiscoveryTimeout) break;
      try {
        client = await client.resolveContext();
        final entries = client.parse(
          await client.execute(client.listArguments),
        );
        final selection = (client: client.copyWith(run: run), entries: entries);
        if (entries.isNotEmpty ||
            runtime != null ||
            preferred != null && client.runtime == preferred.runtime) {
          return selection;
        }
        empty ??= selection;
        if (client.runtime == MachineContainerRuntime.containerd &&
            scope.isEmpty) {
          final namespaces = (await client.execute(['namespace', 'ls', '-q']))
              .split('\n')
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty && name != 'default')
              .toSet()
              .take(_machineContainerNamespaceLimit);
          for (final namespace in namespaces) {
            final scoped = client.copyWith(scope: namespace);
            final rows = scoped.parse(
              await scoped.execute(scoped.listArguments),
            );
            if (rows.isNotEmpty) {
              return (client: scoped.copyWith(run: run), entries: rows);
            }
          }
        }
      } on Exception catch (error) {
        issues[executable] = '$error';
      } on StateError catch (error) {
        issues[executable] = '$error';
      }
    }
    checkCancelled();
    if (empty != null) return empty;
    throw MachineContainerDiscoveryException(issues);
  } finally {
    elapsed.stop();
  }
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
    this.launcher = const [],
    this.inheritDockerHost = false,
  });
  final MachineContainerRuntime runtime;
  final Future<String> Function(String command) run;
  final String scope, contextName;
  final bool windows;
  final List<String> launcher;
  final bool inheritDockerHost;

  MachineContainerClient copyWith({
    Future<String> Function(String command)? run,
    String? scope,
    String? contextName,
    bool? inheritDockerHost,
  }) => MachineContainerClient(
    runtime: runtime,
    run: run ?? this.run,
    scope: scope ?? this.scope,
    contextName: contextName ?? this.contextName,
    windows: windows,
    launcher: launcher,
    inheritDockerHost: inheritDockerHost ?? this.inheritDockerHost,
  );

  String command(List<String> arguments, {bool readable = false}) {
    final args = [
      if (launcher.isEmpty) runtime.executable else ...launcher,
      if (runtime == MachineContainerRuntime.docker &&
          contextName.isNotEmpty &&
          !inheritDockerHost) ...[
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
      final script =
          "& ${args.map((a) => "'${escapePowerShellSingleQuotedString(a)}'").join(' ')}";
      return readable
          ? script
          : powerShellEncodedCommand('$script; exit \$LASTEXITCODE');
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

  /// 上下文查询只是可选能力，旧版客户端不支持时仍以实际列表查询为准。
  Future<MachineContainerClient> resolveContext() async {
    if (contextName.isNotEmpty ||
        (runtime != MachineContainerRuntime.docker &&
            runtime != MachineContainerRuntime.kubernetes)) {
      return this;
    }
    String name;
    try {
      name = (await execute(
        runtime == MachineContainerRuntime.docker
            ? ['context', 'show']
            : ['config', 'current-context'],
      )).trim();
    } on Exception {
      return this;
    } on StateError {
      return this;
    }
    if (name.isEmpty || name.contains(RegExp(r'[\r\n\x00-\x1f]'))) {
      return this;
    }
    return copyWith(
      contextName: name,
      // 默认上下文不能覆盖目标终端通过 DOCKER_HOST 选定的连接。
      inheritDockerHost:
          runtime == MachineContainerRuntime.docker && name == 'default',
    );
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

  /// 只批量读取列表需要的字段，避免逐容器查询和传输环境变量等完整配置。
  Stream<Map<String, MachineContainerListDetails>> listDetails(
    List<MachineContainerEntry> entries, {
    bool Function()? isCancelled,
  }) async* {
    if (!supportsRunCommand) return;
    final containers = entries.where((entry) => !entry.isPod).toList();
    for (
      var offset = 0;
      offset < containers.length;
      offset += _machineContainerInspectBatchSize
    ) {
      if (isCancelled?.call() ?? false) return;
      final batch = containers
          .skip(offset)
          .take(_machineContainerInspectBatchSize)
          .toList();
      for (final entry in batch) {
        _validate(entry);
      }
      final output = await execute([
        'inspect',
        '--format',
        '{{json .Id}}\t{{json .State.StartedAt}}\t{{json .HostConfig.PortBindings}}',
        ...batch.map((entry) => entry.id),
      ]);
      if (isCancelled?.call() ?? false) return;
      final details = <String, MachineContainerListDetails>{};
      for (final line
          in output.split('\n').where((line) => line.trim().isNotEmpty)) {
        final fields = line.split('\t');
        if (fields.length != 3) throw const FormatException('容器列表补充字段格式无效。');
        final id = jsonDecode(fields[0]);
        final started = jsonDecode(fields[1]);
        final bindings = jsonDecode(fields[2]);
        if (id is! String ||
            started is! String ||
            bindings != null && bindings is! Map) {
          throw const FormatException('容器列表补充字段类型无效。');
        }
        final ports = <String>[];
        for (final binding in (bindings as Map? ?? const {}).entries) {
          for (final port in binding.value as List? ?? const []) {
            final hostPort = '${port['HostPort'] ?? ''}';
            if (hostPort.isEmpty) continue;
            var ip = '${port['HostIp'] ?? ''}';
            if (ip.contains(':') && !ip.startsWith('[')) ip = '[$ip]';
            ports.add('${ip.isEmpty ? '' : '$ip:'}$hostPort->${binding.key}');
          }
        }
        details[id] = (
          startedAt: started.startsWith('0001-01-01') ? '' : started,
          ports: ports.join(', '),
        );
      }
      if (batch.any((entry) => !details.containsKey(entry.id))) {
        throw const FormatException('容器列表补充字段缺少对应容器。');
      }
      yield details;
    }
  }

  /// 将同一轮资源采样按完整标识、短标识或唯一名称关联，缺失值不伪装为零。
  Map<String, MachineContainerUsage> usageSamples(
    String output,
    List<MachineContainerEntry> entries,
  ) {
    if (!supportsRunCommand || output.trim().isEmpty) return {};
    final decoded = output.trim().startsWith('[')
        ? jsonDecode(output) as List
        : output
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .map(jsonDecode);
    final identities = <String, String?>{};
    for (final entry in entries) {
      for (final key in {
        entry.id,
        entry.id.length > 12 ? entry.id.substring(0, 12) : entry.id,
        entry.name,
      }) {
        if (key.isEmpty) continue;
        identities[key] =
            identities.containsKey(key) && identities[key] != entry.id
            ? null
            : entry.id;
      }
    }
    final result = <String, MachineContainerUsage>{};
    for (final row in decoded) {
      if (row is! Map) throw const FormatException('容器资源采样格式无效。');
      final rawId =
          row['ID'] ??
          row['Id'] ??
          row['id'] ??
          row['ContainerID'] ??
          row['Container'];
      final id = rawId != null
          ? identities['$rawId']
          : identities['${row['Name'] ?? row['name'] ?? ''}'];
      final raw =
          row['CPUPerc'] ??
          row['CPU'] ??
          row['CPUPercent'] ??
          row['cpu_percent'] ??
          row['cpu'];
      if (id == null) continue;
      double? percent(Object? value) {
        final parsed = double.tryParse(
          '${value ?? ''}'.replaceAll('%', '').trim(),
        );
        return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
      }

      final processes = int.tryParse(
        '${row['PIDs'] ?? row['Pids'] ?? row['pids'] ?? ''}',
      );
      result[id] = (
        cpuPercent: percent(raw),
        memoryPercent: percent(
          row['MemPerc'] ?? row['MemPercent'] ?? row['MemoryPercent'],
        ),
        memoryUsage: machineContainerMetadataText(
          row['MemUsage'] ?? row['MemoryUsage'],
        ),
        networkIO: machineContainerMetadataText(
          row['NetIO'] ?? row['NetworkIO'],
        ),
        blockIO: machineContainerMetadataText(row['BlockIO']),
        processes: processes != null && processes >= 0 ? processes : null,
      );
    }
    return result;
  }

  Map<String, double> cpuPercentages(
    String output,
    List<MachineContainerEntry> entries,
  ) => {
    for (final sample in usageSamples(output, entries).entries)
      if (sample.value.cpuPercent != null) sample.key: sample.value.cpuPercent!,
  };

  List<MachineContainerEntry> parse(String output, {bool pods = false}) {
    final trimmed = output.trim();
    final structured =
        runtime == MachineContainerRuntime.kubernetes ||
        runtime == MachineContainerRuntime.cri;
    if (trimmed.isEmpty) {
      if (structured) throw const FormatException('容器列表响应为空。');
      return [];
    }
    dynamic decoded;
    if (structured || trimmed.startsWith('[')) {
      decoded = jsonDecode(trimmed);
    } else {
      decoded = trimmed
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map(jsonDecode)
          .toList();
    }
    final result = <MachineContainerEntry>[];
    String value(dynamic value) => value is List
        ? value.map((item) => item.toString()).join(', ')
        : value?.toString() ?? '';
    if (structured &&
        (decoded is! Map ||
            decoded[runtime == MachineContainerRuntime.kubernetes || pods
                    ? 'items'
                    : 'containers']
                is! List)) {
      throw const FormatException('容器列表响应格式无效。');
    }
    if (runtime == MachineContainerRuntime.kubernetes) {
      for (final item in (decoded['items'] as List? ?? [])) {
        if (item is! Map) throw const FormatException('Pod 列表条目格式无效。');
        final m = Map<String, dynamic>.from(item['metadata'] as Map? ?? {});
        final status = item['status'] as Map? ?? {};
        final spec = item['spec'] as Map? ?? {};
        final namespace = value(m['namespace']);
        final name = value(m['name']);
        final uid = value(m['uid']);
        if (name.isEmpty || uid.isEmpty || namespace.isEmpty) {
          throw const FormatException('Pod 列表缺少身份字段。');
        }
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
        if (raw is! Map) throw const FormatException('容器列表条目格式无效。');
        final m = Map<String, dynamic>.from(raw);
        final meta = m['metadata'] as Map? ?? {};
        final image = m['image'];
        final id = value(m['ID'] ?? m['Id'] ?? m['id']);
        final state = value(m['State'] ?? m['Status'] ?? m['state']);
        if (id.isEmpty) throw const FormatException('容器列表缺少身份字段。');
        result.add(
          MachineContainerEntry(
            id: id,
            name: value(m['Names'] ?? m['Name'] ?? meta['name'] ?? m['id']),
            state: switch (state.toLowerCase()) {
              final status when status.startsWith('up ') =>
                status.contains('(paused)') ? 'paused' : 'running',
              final status when status.startsWith('exited ') => 'exited',
              _ => state,
            },
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
      '查看镜像详情',
      if (supportsRunCommand) '复制 run 命令',
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
