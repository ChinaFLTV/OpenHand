part of 'machine_containers.dart';

const _machineContainerHistoryLimit = 512;

class MachineContainerConfigException implements Exception {
  const MachineContainerConfigException(this.code, [this.details = '']);
  final String code, details;
  @override
  String toString() => '容器配置读取失败：$code${details.isEmpty ? '' : ' · $details'}';
}

Map<String, dynamic> _containerInspectObject(String output) {
  final decoded = jsonDecode(output);
  final object = decoded is List && decoded.length == 1
      ? decoded.single
      : decoded;
  if (object is! Map<String, dynamic> || object.isEmpty) {
    throw const MachineContainerConfigException('invalid');
  }
  return object;
}

String _containerImageReference(dynamic value) {
  if (value is! String ||
      value.isEmpty ||
      value.startsWith('-') ||
      value.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    throw const MachineContainerConfigException('image');
  }
  return value;
}

extension MachineContainerInspection on MachineContainerClient {
  bool get supportsRunCommand => const {
    MachineContainerRuntime.docker,
    MachineContainerRuntime.podman,
    MachineContainerRuntime.containerd,
  }.contains(runtime);

  Future<String> runCommand(
    MachineContainerEntry entry, {
    bool Function()? isCancelled,
  }) async {
    if (!supportsRunCommand || entry.isPod) {
      throw const MachineContainerConfigException('unsupported');
    }
    final data = _containerInspectObject(await inspect(entry));
    if (isCancelled?.call() ?? false) {
      throw const MachineContainerConfigException('cancelled');
    }
    final List<String> args;
    try {
      args = machineContainerRunArguments(data);
    } on TypeError {
      throw const MachineContainerConfigException('invalid');
    }
    // 客户端版本和运行时支持的参数不同，复制前以目标 CLI 的帮助信息核验。
    final help = await execute(['run', '--help']);
    final supported = RegExp(
      r'(?:^|\s)(--[a-zA-Z0-9-]+)(?=[=,\s])',
      multiLine: true,
    ).allMatches(help).map((match) => match[1]!).toSet();
    final unsupported = <String>[];
    for (var i = 1; i < args.length && args[i].startsWith('--'); i++) {
      final flag = args[i];
      if (!supported.contains(flag)) unsupported.add(flag);
      if (!const {
        '--detach',
        '--tty',
        '--interactive',
        '--privileged',
        '--read-only',
        '--rm',
        '--init',
        '--oom-kill-disable',
        '--publish-all',
        '--no-healthcheck',
      }.contains(flag)) {
        i++;
      }
    }
    if (unsupported.isNotEmpty) {
      throw MachineContainerConfigException(
        'incomplete',
        unsupported.join(', '),
      );
    }
    if (isCancelled?.call() ?? false) {
      throw const MachineContainerConfigException('cancelled');
    }
    return command(args, readable: true);
  }

  /// 使用容器实际镜像 ID，避免可变标签指向另一镜像；历史查询失败仍保留元数据。
  Future<String> imageDetails(
    MachineContainerEntry entry, {
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() ?? false) {
        throw const MachineContainerConfigException('cancelled');
      }
    }

    checkCancelled();
    if (entry.isPod) throw const MachineContainerConfigException('image');
    final container = _containerInspectObject(await inspect(entry));
    checkCancelled();
    if (runtime == MachineContainerRuntime.kubernetes) {
      if (container['metadata']?['uid'] != entry.id) {
        throw const MachineContainerConfigException('stale');
      }
      final spec = container['spec'] as Map? ?? const {};
      final status = container['status'] as Map? ?? const {};
      final specs = [
        ...?spec['containers'] as List?,
        ...?spec['initContainers'] as List?,
        ...?spec['ephemeralContainers'] as List?,
      ].whereType<Map>();
      final states = [
        ...?status['containerStatuses'] as List?,
        ...?status['initContainerStatuses'] as List?,
        ...?status['ephemeralContainerStatuses'] as List?,
      ].whereType<Map>();
      final selected = specs
          .where((item) => item['name'] == entry.name)
          .firstOrNull;
      final selectedState = states
          .where((item) => item['name'] == entry.name)
          .firstOrNull;
      if (selected == null) {
        throw const MachineContainerConfigException('stale');
      }
      return jsonEncode({
        'referenceOnly': true,
        'image': {
          'Image': selected['image'],
          'ImageID': selectedState?['imageID'],
          'imagePullPolicy': selected['imagePullPolicy'],
          'nodeName': spec['nodeName'],
          'namespace': entry.namespace,
          'name': entry.name,
        },
      });
    }
    final status = container['status'] as Map? ?? const {};
    final containerConfig = container['Config'] as Map? ?? const {};
    final statusImage = status['image'] as Map? ?? const {};
    final reference = _containerImageReference(
      runtime == MachineContainerRuntime.cri
          ? status['imageRef'] ?? statusImage['image'] ?? entry.image
          : container['Image'] ??
                container['ImageID'] ??
                containerConfig['Image'] ??
                entry.image,
    );
    return inspectImageReference(reference, isCancelled: isCancelled);
  }

  Future<String> inspectImageReference(
    String imageReference, {
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() ?? false) {
        throw const MachineContainerConfigException('cancelled');
      }
    }

    checkCancelled();
    final reference = _containerImageReference(imageReference);
    final image = _containerInspectObject(
      await execute(
        runtime == MachineContainerRuntime.cri
            ? ['inspecti', reference]
            : ['image', 'inspect', reference],
      ),
    );
    checkCancelled();
    final imageStatus = image['status'] as Map? ?? const {};
    final identity = runtime == MachineContainerRuntime.cri
        ? imageStatus['id']
        : image['Id'] ?? image['ID'];
    if (identity is! String || identity.isEmpty) {
      throw const MachineContainerConfigException('invalid');
    }
    final report = <String, dynamic>{'image': image, 'reference': reference};
    if (runtime != MachineContainerRuntime.cri) {
      try {
        final output = await execute([
          'image',
          'history',
          if (runtime == MachineContainerRuntime.docker) '--human=false',
          '--no-trunc',
          '--format',
          '{{json .}}',
          reference,
        ]);
        final trimmed = output.trim();
        final rows = trimmed.isEmpty
            ? <dynamic>[]
            : trimmed.startsWith('[')
            ? jsonDecode(trimmed) as List
            : trimmed
                  .split('\n')
                  .where((line) => line.trim().isNotEmpty)
                  .take(_machineContainerHistoryLimit + 1)
                  .map(jsonDecode)
                  .toList();
        if (rows.any((row) => row is! Map)) {
          throw const FormatException('镜像历史格式无效。');
        }
        report['history'] = rows.take(_machineContainerHistoryLimit).toList();
        report['historyLimited'] = rows.length > _machineContainerHistoryLimit;
      } on Exception catch (error) {
        report['historyError'] = '$error';
      } on StateError catch (error) {
        report['historyError'] = '$error';
      }
    }
    return jsonEncode(report);
  }
}

/// 还原 inspect 中的常用启动配置；已知不能等价表达的配置明确拒绝。
List<String> machineContainerRunArguments(Map<String, dynamic> data) {
  final config = data['Config'];
  final host = data['HostConfig'];
  if (config is! Map || host is! Map) {
    throw const MachineContainerConfigException('invalid');
  }
  final args = <String>['run', '--detach'];
  void option(String flag, dynamic value) {
    if (value != null && '$value'.isNotEmpty) args.addAll([flag, '$value']);
  }

  void repeated(String flag, dynamic values) {
    if (values == null) return;
    if (values is! List) throw const MachineContainerConfigException('invalid');
    for (final value in values) {
      option(flag, value);
    }
  }

  void pairs(String flag, dynamic values) {
    if (values == null) return;
    if (values is! Map) throw const MachineContainerConfigException('invalid');
    for (final entry in values.entries) {
      option(flag, '${entry.key}=${entry.value ?? ''}');
    }
  }

  bool configured(dynamic value) =>
      value != null &&
      value != false &&
      value != 0 &&
      value != '' &&
      !(value is List && value.isEmpty) &&
      !(value is Map && value.isEmpty);
  final unsupported = <String>[
    for (final key in [
      'DeviceRequests',
      'VolumesFrom',
      'Links',
      'ConsoleSize',
      'CpuRealtimePeriod',
      'CpuRealtimeRuntime',
      'CpuCount',
      'CpuPercent',
      'IOMaximumIOps',
      'IOMaximumBandwidth',
      'KernelMemory',
      'KernelMemoryTCP',
      'BlkioWeightDevice',
      'BlkioDeviceReadBps',
      'BlkioDeviceWriteBps',
      'BlkioDeviceReadIOps',
      'BlkioDeviceWriteIOps',
    ])
      if (configured(host[key]) &&
          !(key == 'ConsoleSize' && (host[key] as List).every((n) => n == 0)))
        key,
    if (configured(data['Pod'])) 'Pod',
  ];
  final networks =
      (data['NetworkSettings'] as Map?)?['Networks'] as Map? ?? const {};
  if (networks.length > 1) unsupported.add('Networks');
  final health = config['Healthcheck'] as Map?;
  final test = health?['Test'] as List? ?? const [];
  if (test.isNotEmpty && !const ['NONE', 'CMD-SHELL'].contains(test.first)) {
    unsupported.add('Healthcheck.Test');
  }
  if (unsupported.isNotEmpty) {
    throw MachineContainerConfigException('incomplete', unsupported.join(', '));
  }

  final id = '${data['Id'] ?? data['ID'] ?? ''}';
  final name = '${data['Name'] ?? ''}'.replaceFirst(RegExp('^/'), '');
  option('--name', name);
  final hostname = config['Hostname'];
  if (hostname != null && !id.startsWith('$hostname')) {
    option('--hostname', hostname);
  }
  for (final field in const {
    'Domainname': '--domainname',
    'User': '--user',
    'WorkingDir': '--workdir',
    'StopSignal': '--stop-signal',
    'StopTimeout': '--stop-timeout',
    'MacAddress': '--mac-address',
  }.entries) {
    option(field.value, config[field.key]);
  }
  for (final field in const {
    'Tty': '--tty',
    'OpenStdin': '--interactive',
  }.entries) {
    if (config[field.key] == true) args.add(field.value);
  }
  repeated('--env', config['Env']);
  pairs('--label', config['Labels']);
  for (final field in const {
    'Privileged': '--privileged',
    'ReadonlyRootfs': '--read-only',
    'AutoRemove': '--rm',
    'Init': '--init',
    'OomKillDisable': '--oom-kill-disable',
    'PublishAllPorts': '--publish-all',
  }.entries) {
    if (host[field.key] == true) args.add(field.value);
  }
  for (final field in const {
    'NetworkMode': '--network',
    'IpcMode': '--ipc',
    'PidMode': '--pid',
    'UTSMode': '--uts',
    'UsernsMode': '--userns',
    'CgroupnsMode': '--cgroupns',
    'CgroupParent': '--cgroup-parent',
    'Isolation': '--isolation',
  }.entries) {
    final value = host[field.key];
    if (value != 'default') option(field.value, value);
  }
  for (final field in const {
    'Memory': '--memory',
    'MemorySwap': '--memory-swap',
    'MemoryReservation': '--memory-reservation',
    'MemorySwappiness': '--memory-swappiness',
    'CpuShares': '--cpu-shares',
    'CpuPeriod': '--cpu-period',
    'CpuQuota': '--cpu-quota',
    'CpusetCpus': '--cpuset-cpus',
    'CpusetMems': '--cpuset-mems',
    'PidsLimit': '--pids-limit',
    'ShmSize': '--shm-size',
    'OomScoreAdj': '--oom-score-adj',
    'BlkioWeight': '--blkio-weight',
  }.entries) {
    final value = host[field.key];
    if (configured(value) || field.key == 'MemorySwappiness' && value == 0) {
      option(field.value, value);
    }
  }
  if (host['NanoCpus'] is num && host['NanoCpus'] != 0) {
    option('--cpus', (host['NanoCpus'] as num) / 1000000000);
  }
  final restart = host['RestartPolicy'] as Map? ?? const {};
  if (configured(restart['Name']) && restart['Name'] != 'no') {
    option(
      '--restart',
      '${restart['Name']}${restart['Name'] == 'on-failure' && configured(restart['MaximumRetryCount']) ? ':${restart['MaximumRetryCount']}' : ''}',
    );
  }
  for (final field in const {
    'Dns': '--dns',
    'DnsOptions': '--dns-option',
    'DnsSearch': '--dns-search',
    'ExtraHosts': '--add-host',
    'GroupAdd': '--group-add',
    'CapAdd': '--cap-add',
    'CapDrop': '--cap-drop',
    'SecurityOpt': '--security-opt',
    'DeviceCgroupRules': '--device-cgroup-rule',
  }.entries) {
    repeated(field.value, host[field.key]);
  }
  pairs('--sysctl', host['Sysctls']);
  pairs('--storage-opt', host['StorageOpt']);
  final logging = host['LogConfig'] as Map? ?? const {};
  option('--log-driver', logging['Type']);
  pairs('--log-opt', logging['Config']);
  for (final limit in host['Ulimits'] as List? ?? const []) {
    option('--ulimit', '${limit['Name']}=${limit['Soft']}:${limit['Hard']}');
  }
  for (final device in host['Devices'] as List? ?? const []) {
    option(
      '--device',
      '${device['PathOnHost']}:${device['PathInContainer']}:${device['CgroupPermissions']}',
    );
  }
  final bindings = host['PortBindings'] as Map? ?? const {};
  for (final binding in bindings.entries) {
    for (final port in binding.value as List? ?? const []) {
      var ip = '${port['HostIp'] ?? ''}';
      if (ip.contains(':') && !ip.startsWith('[')) ip = '[$ip]';
      final hostPort = '${port['HostPort'] ?? ''}';
      option(
        '--publish',
        '${ip.isEmpty ? '' : '$ip:'}${ip.isEmpty && hostPort.isEmpty ? '' : '$hostPort:'}${binding.key}',
      );
    }
  }
  for (final port in (config['ExposedPorts'] as Map? ?? const {}).keys) {
    option('--expose', port);
  }

  final binds = host['Binds'] as List? ?? const [];
  repeated('--volume', binds);
  final tmpfs = host['Tmpfs'] as Map? ?? const {};
  for (final mount in tmpfs.entries) {
    option(
      '--tmpfs',
      '${mount.key}${configured(mount.value) ? ':${mount.value}' : ''}',
    );
  }
  final specified = host['Mounts'] as List? ?? const [];
  final targets = <String>{
    for (final item in specified) '${item['Target'] ?? item['Destination']}',
    ...tmpfs.keys.cast<String>(),
  };
  final mounts = [
    ...specified,
    for (final item in data['Mounts'] as List? ?? const [])
      if (!targets.contains(item['Destination']) &&
          !binds.any(
            (bind) =>
                '$bind'.endsWith(':${item['Destination']}') ||
                '$bind'.contains(':${item['Destination']}:'),
          ))
        item,
  ];
  for (final mount in mounts) {
    final type = '${mount['Type']}';
    final target = mount['Target'] ?? mount['Destination'];
    if (!const ['bind', 'volume', 'tmpfs'].contains(type) ||
        target is! String ||
        target.isEmpty) {
      throw const MachineContainerConfigException('incomplete', 'Mounts');
    }
    final source = type == 'volume'
        ? mount['Name'] ?? mount['Source']
        : mount['Source'];
    final fields = <String>[
      'type=$type',
      if (configured(source)) 'source=$source',
      'target=$target',
      if (mount['ReadOnly'] == true || mount['RW'] == false) 'readonly',
    ];
    final bindOptions = mount['BindOptions'] as Map? ?? const {};
    final volumeOptions = mount['VolumeOptions'] as Map? ?? const {};
    final tmpfsOptions = mount['TmpfsOptions'] as Map? ?? const {};
    final propagation = bindOptions['Propagation'] ?? mount['Propagation'];
    if (type == 'bind' && configured(propagation)) {
      fields.add('bind-propagation=$propagation');
    }
    if (bindOptions['NonRecursive'] == true) fields.add('bind-nonrecursive');
    if (volumeOptions['NoCopy'] == true) fields.add('volume-nocopy');
    if (configured(volumeOptions['Subpath'])) {
      fields.add('volume-subpath=${volumeOptions['Subpath']}');
    }
    if (configured(volumeOptions['DriverConfig']) ||
        configured(volumeOptions['Labels']) ||
        bindOptions.keys.any(
          (key) => !const ['Propagation', 'NonRecursive'].contains(key),
        )) {
      throw const MachineContainerConfigException(
        'incomplete',
        'Mounts.Options',
      );
    }
    if (configured(tmpfsOptions['SizeBytes'])) {
      fields.add('tmpfs-size=${tmpfsOptions['SizeBytes']}');
    }
    if (configured(tmpfsOptions['Mode'])) {
      fields.add(
        'tmpfs-mode=${(tmpfsOptions['Mode'] as num).toInt().toRadixString(8)}',
      );
    }
    option(
      '--mount',
      fields
          .map(
            (f) => f.contains(RegExp('[,"\r\n]'))
                ? '"${f.replaceAll('"', '""')}"'
                : f,
          )
          .join(','),
    );
  }
  if (networks.length == 1 &&
      !const [
        'host',
        'none',
        'bridge',
        'default',
      ].contains(host['NetworkMode'])) {
    final network = networks.values.single as Map;
    for (final alias in network['Aliases'] as List? ?? const []) {
      if (alias != name && !id.startsWith('$alias')) {
        option('--network-alias', alias);
      }
    }
    final ipam = network['IPAMConfig'] as Map? ?? const {};
    option('--ip', ipam['IPv4Address']);
    option('--ip6', ipam['IPv6Address']);
    repeated('--link-local-ip', ipam['LinkLocalIPs']);
  }
  if (test.isNotEmpty) {
    if (test.first == 'NONE') {
      args.add('--no-healthcheck');
    } else {
      if (test.length != 2) {
        throw const MachineContainerConfigException('invalid');
      }
      option('--health-cmd', test[1]);
      for (final field in const {
        'Interval': '--health-interval',
        'Timeout': '--health-timeout',
        'StartPeriod': '--health-start-period',
        'StartInterval': '--health-start-interval',
      }.entries) {
        if (configured(health![field.key])) {
          option(field.value, '${health[field.key]}ns');
        }
      }
      if (configured(health!['Retries'])) {
        option('--health-retries', health['Retries']);
      }
    }
  }
  final entrypoint = config['Entrypoint'] as List? ?? const [];
  final command = config['Cmd'] as List? ?? const [];
  option('--entrypoint', entrypoint.isEmpty ? null : entrypoint.first);
  if (entrypoint.isEmpty) args.addAll(['--entrypoint', '']);
  // 固定镜像 ID 能保留创建时使用的内容；标签只作为缺少 ID 时的兼容回退。
  args.add(
    _containerImageReference(
      data['Image'] ?? data['ImageID'] ?? config['Image'],
    ),
  );
  args.addAll([...entrypoint.skip(1), ...command].cast<String>());
  if (args.any((value) => value.contains('\u0000'))) {
    throw const MachineContainerConfigException('invalid');
  }
  return args;
}
