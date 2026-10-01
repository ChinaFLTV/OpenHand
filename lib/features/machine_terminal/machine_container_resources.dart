part of 'machine_containers.dart';

const machineContainerSearchLimit = 50;
const machineContainerFormRowLimit = 64;
const machineContainerOperationOutputLimit = 32768;
const _machineContainerFormCharacterLimit = 32768;

typedef MachineContainerOperationRunner =
    Future<String> Function(
      String command, {
      required Duration timeout,
      void Function(String)? onOutput,
      bool Function()? isCancelled,
    });

enum MachineContainerResourceKind { images, volumes }

class MachineContainerResource {
  const MachineContainerResource({
    required this.id,
    required this.name,
    this.tag = '',
    this.created = '',
    this.size = '',
    this.driver = '',
    this.references,
    this.raw = const {},
  });
  final String id, name, tag, created, size, driver;
  final int? references;
  final Map<String, dynamic> raw;
  String get reference => name.isEmpty || name == '<none>'
      ? id
      : tag.isEmpty || tag == '<none>'
      ? name
      : '$name:$tag';
}

List<Map<String, dynamic>> _containerResourceObjects(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return [];
  final rows = trimmed.startsWith('[')
      ? jsonDecode(trimmed) as List
      : trimmed
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map(jsonDecode);
  return rows.map((row) {
    if (row is! Map<String, dynamic>) {
      throw const FormatException('容器资源响应格式无效。');
    }
    return row;
  }).toList();
}

extension MachineContainerResources on MachineContainerClient {
  bool get supportsResources => supportsRunCommand;
  bool get supportsImageSearch =>
      runtime == MachineContainerRuntime.docker ||
      runtime == MachineContainerRuntime.podman;

  Stream<List<MachineContainerResource>> resources(
    MachineContainerResourceKind kind, {
    bool Function()? isCancelled,
  }) async* {
    if (!supportsResources) {
      throw const MachineContainerConfigException('resourceUnsupported');
    }
    if (isCancelled?.call() ?? false) return;
    final images = kind == MachineContainerResourceKind.images;
    var rows = _containerResourceObjects(
      await execute([
        images ? 'image' : 'volume',
        'ls',
        if (images) '--no-trunc',
        '--format',
        '{{json .}}',
      ]),
    );
    if (isCancelled?.call() ?? false) return;
    List<MachineContainerResource> parse() => rows.expand((row) {
      String value(String key) => '${row[key] ?? ''}';
      final id = images
          ? value('ID').isNotEmpty
                ? value('ID')
                : value('Id')
          : value('Name');
      if (id.isEmpty) throw const FormatException('容器资源缺少标识。');
      final names = row['Names'] ?? row['RepoTags'];
      final refs =
          images &&
              value('Repository').isEmpty &&
              names is List &&
              names.isNotEmpty
          ? names.cast<String>()
          : <String>[''];
      return refs.map((ref) {
        final colon = ref.lastIndexOf(':');
        final tagged = colon > ref.lastIndexOf('/');
        return MachineContainerResource(
          id: id,
          name: images
              ? ref.isNotEmpty
                    ? tagged
                          ? ref.substring(0, colon)
                          : ref
                    : value('Repository')
              : value('Name'),
          tag: images
              ? ref.isNotEmpty && tagged
                    ? ref.substring(colon + 1)
                    : value('Tag')
              : '',
          created: value('CreatedAt').isNotEmpty
              ? value('CreatedAt')
              : value('Created'),
          size: value('Size'),
          driver: value('Driver'),
          references: int.tryParse(
            '${row[images ? 'Containers' : 'Links'] ?? ''}',
          ),
          raw: row,
        );
      });
    }).toList();
    yield parse();
    if (rows.isEmpty) return;
    // 分批补充卷元数据，容量统计失败时保留已加载的列表与元数据。
    for (
      var offset = 0;
      !images && offset < rows.length;
      offset += _machineContainerInspectBatchSize
    ) {
      if (isCancelled?.call() ?? false) return;
      final batch = rows.skip(offset).take(_machineContainerInspectBatchSize);
      final names = batch
          .map((row) => _resourceName('${row['Name'] ?? ''}'))
          .toList();
      final details = _containerResourceObjects(
        await execute(['volume', 'inspect', ...names]),
      );
      if (isCancelled?.call() ?? false) return;
      final byName = {for (final row in details) row['Name']: row};
      if (names.any((name) => !byName.containsKey(name))) {
        throw const FormatException('数据卷详情缺少对应记录。');
      }
      rows = [
        for (final row in rows) {...row, ...?byName[row['Name']]},
      ];
      yield parse();
    }
    if (runtime == MachineContainerRuntime.docker) {
      if (isCancelled?.call() ?? false) return;
      final usage = _containerResourceObjects(
        await execute([
          'system',
          'df',
          '-v',
          '--format',
          images ? '{{json .Images}}' : '{{json .Volumes}}',
        ]),
      );
      if (isCancelled?.call() ?? false) return;
      final key = images ? 'ID' : 'Name';
      final byName = {for (final row in usage) row[key]: row};
      rows = [
        for (final row in rows)
          {
            ...row,
            if (images && byName.containsKey(row[key]))
              'Containers': byName[row[key]]!['Containers'],
            if (!images) ...?byName[row[key]],
          },
      ];
      yield parse();
    }
  }

  Future<List<Map<String, dynamic>>> searchImages(String query) async {
    if (!supportsImageSearch) {
      throw const MachineContainerConfigException('resourceUnsupported');
    }
    final term = query.trim();
    if (term.isEmpty ||
        term.length > 128 ||
        term.startsWith('-') ||
        term.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const MachineContainerConfigException('form', '搜索');
    }
    return _containerResourceObjects(
      await execute([
        'search',
        '--limit',
        '$machineContainerSearchLimit',
        '--no-trunc',
        '--format',
        '{{json .}}',
        term,
      ]),
    ).take(machineContainerSearchLimit).toList();
  }

  List<String> pullArguments(String image) => [
    'pull',
    _containerImageReference(image.trim()),
  ];
  List<String> removeResourceArguments(
    MachineContainerResourceKind kind,
    MachineContainerResource resource,
  ) => [
    kind == MachineContainerResourceKind.images ? 'image' : 'volume',
    'rm',
    kind == MachineContainerResourceKind.images
        ? _containerImageReference(resource.id)
        : _resourceName(resource.name),
  ];
  Future<String> volumeDetails(String name) =>
      execute(['volume', 'inspect', _resourceName(name)]);
  List<String> createVolumeArguments(
    String name, {
    String driver = '',
    Map<String, String> labels = const {},
    Map<String, String> options = const {},
  }) {
    if (!supportsResources) {
      throw const MachineContainerConfigException('resourceUnsupported');
    }
    if (labels.length > machineContainerFormRowLimit ||
        options.length > machineContainerFormRowLimit) {
      throw const MachineContainerConfigException('form', '参数');
    }
    final args = <String>['volume', 'create'];
    if (driver.trim().isNotEmpty) {
      args.addAll(['--driver', _containerImageReference(driver.trim())]);
    }
    for (final entries in [('--label', labels), ('--opt', options)]) {
      for (final entry in entries.$2.entries) {
        if (entry.key.isEmpty ||
            entry.key.contains(RegExp(r'[=\x00\r\n]')) ||
            entry.value.contains('\u0000')) {
          throw const MachineContainerConfigException('form', '参数');
        }
        args.addAll([entries.$1, '${entry.key}=${entry.value}']);
      }
    }
    args.add(_resourceName(name.trim()));
    if (args.fold<int>(0, (total, arg) => total + arg.length) >
        _machineContainerFormCharacterLimit) {
      throw const MachineContainerConfigException('form', '参数');
    }
    return args;
  }
}

String _resourceName(String value) {
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$').hasMatch(value) ||
      value.length > 255) {
    throw const MachineContainerConfigException('form', '名称');
  }
  return value;
}

class MachineContainerCreateSpec {
  const MachineContainerCreateSpec({
    required this.image,
    this.name = '',
    this.start = true,
    this.ports = const [],
    this.environment = const {},
    this.mounts = const [],
    this.restart = 'no',
    this.network = '',
    this.user = '',
    this.directory = '',
    this.entrypoint = '',
    this.arguments = const [],
    this.cpus = '',
    this.memory = '',
  });
  final String image,
      name,
      restart,
      network,
      user,
      directory,
      entrypoint,
      cpus,
      memory;
  final bool start;
  final List<Map<String, String>> ports, mounts;
  final Map<String, String> environment;
  final List<String> arguments;

  List<String> commandArguments() {
    if (ports.length > machineContainerFormRowLimit ||
        mounts.length > machineContainerFormRowLimit ||
        environment.length > machineContainerFormRowLimit) {
      throw const MachineContainerConfigException('form', '参数');
    }
    final args = <String>[start ? 'run' : 'create', if (start) '--detach'];
    if (name.trim().isNotEmpty) {
      args.addAll(['--name', _resourceName(name.trim())]);
    }
    if (!const {
      'no',
      'always',
      'unless-stopped',
      'on-failure',
    }.contains(restart)) {
      throw const MachineContainerConfigException('form', '重启策略');
    }
    args.addAll(['--restart', restart]);
    for (final pair in [
      ('--network', network),
      ('--user', user),
      ('--workdir', directory),
      ('--entrypoint', entrypoint),
    ]) {
      if (pair.$2.trim().isNotEmpty) args.addAll([pair.$1, pair.$2.trim()]);
    }
    if (cpus.trim().isNotEmpty) {
      final count = double.tryParse(cpus.trim());
      if (count == null || !count.isFinite || count <= 0) {
        throw const MachineContainerConfigException('form', 'CPU');
      }
      args.addAll(['--cpus', cpus.trim()]);
    }
    if (memory.trim().isNotEmpty) {
      if (!RegExp(r'^[1-9][0-9]*[bkmgBKMG]?$').hasMatch(memory.trim())) {
        throw const MachineContainerConfigException('form', '内存');
      }
      args.addAll(['--memory', memory.trim()]);
    }
    for (final port in ports) {
      final host = port['host']?.trim() ?? '';
      final target = port['container']?.trim() ?? '';
      final protocol = port['protocol'] ?? 'tcp';
      var address = port['address']?.trim() ?? '';
      if (address.isNotEmpty) {
        try {
          if (address.contains(':')) {
            Uri.parseIPv6Address(
              address.startsWith('[') && address.endsWith(']')
                  ? address.substring(1, address.length - 1)
                  : address,
            );
          } else {
            Uri.parseIPv4Address(address);
          }
        } on FormatException {
          throw const MachineContainerConfigException('form', '端口');
        }
      }
      bool validPort(String value) =>
          (int.tryParse(value) ?? 0) > 0 &&
          (int.tryParse(value) ?? 65536) <= 65535;
      if (!validPort(target) ||
          host.isNotEmpty && !validPort(host) ||
          !const {'tcp', 'udp', 'sctp'}.contains(protocol) ||
          address.contains(RegExp(r'[^0-9a-fA-F.:\[\]]'))) {
        throw const MachineContainerConfigException('form', '端口');
      }
      if (address.contains(':') && !address.startsWith('[')) {
        address = '[$address]';
      }
      args.addAll([
        '--publish',
        '${address.isEmpty ? '' : '$address:'}${host.isEmpty && address.isEmpty ? '' : '$host:'}$target/$protocol',
      ]);
    }
    for (final entry in environment.entries) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(entry.key)) {
        throw const MachineContainerConfigException('form', '环境变量');
      }
      args.addAll(['--env', '${entry.key}=${entry.value}']);
    }
    for (final mount in mounts) {
      final source = mount['source']?.trim() ?? '';
      final target = mount['target']?.trim() ?? '';
      final type = mount['type'] ?? 'volume';
      if (source.isEmpty ||
          target.isEmpty ||
          !const {'volume', 'bind'}.contains(type)) {
        throw const MachineContainerConfigException('form', '挂载');
      }
      if (type == 'volume') _resourceName(source);
      if (!target.startsWith('/') &&
          !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(target)) {
        throw const MachineContainerConfigException('form', '挂载');
      }
      final fields = [
        'type=$type',
        'source=$source',
        'target=$target',
        if (mount['readonly'] == 'true') 'readonly',
      ];
      args.addAll([
        '--mount',
        fields
            .map(
              (field) => field.contains(RegExp('[,"\r\n]'))
                  ? '"${field.replaceAll('"', '""')}"'
                  : field,
            )
            .join(','),
      ]);
    }
    args.add(_containerImageReference(image.trim()));
    args.addAll(arguments);
    if (args.any((arg) => arg.contains('\u0000')) ||
        args.fold<int>(0, (total, arg) => total + arg.length) >
            _machineContainerFormCharacterLimit) {
      throw const MachineContainerConfigException('form', '参数');
    }
    return args;
  }
}
