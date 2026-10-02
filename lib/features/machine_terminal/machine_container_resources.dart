part of 'machine_containers.dart';

const machineContainerSearchLimit = 50;
const machineContainerFormRowLimit = 64;
const machineContainerOperationOutputLimit = 32768;
const machineContainerImageTimeout = Duration(minutes: 15);
const _machineContainerFormCharacterLimit = 32768;

typedef MachineContainerOperationRunner =
    Future<String> Function(
      String command, {
      required Duration timeout,
      void Function(String)? onOutput,
      bool Function()? isCancelled,
    });

enum MachineContainerResourceKind { images, volumes }

enum MachineImageTransferStage { preparing, download, upload, import }

typedef MachineImageTransferProgress =
    void Function(MachineImageTransferStage stage, int received, int total);

typedef MachineContainerImagePuller =
    Future<({String output, String image})> Function(
      MachineContainerClient client,
      String image, {
      required Duration timeout,
      void Function(String)? onOutput,
      MachineImageTransferProgress? onProgress,
      bool Function()? isCancelled,
    });

class MachineContainerResource {
  const MachineContainerResource({
    required this.id,
    required this.name,
    this.tag = '',
    this.created = '',
    this.size = '',
    this.driver = '',
    this.sharedSize = '',
    this.uniqueSize = '',
    this.platform = '',
    this.digest = '',
    this.mountpoint = '',
    this.scope = '',
    this.labels = '',
    this.options = '',
    this.layers,
    this.references,
    this.raw = const {},
  });
  final String id,
      name,
      tag,
      created,
      size,
      driver,
      sharedSize,
      uniqueSize,
      platform,
      digest,
      mountpoint,
      scope,
      labels,
      options;
  final int? references, layers;
  final Map<String, dynamic> raw;
  String get reference => name.isEmpty || name == '<none>'
      ? id
      : tag.isEmpty || tag == '<none>'
      ? name
      : '$name:$tag';
}

/// 统一运行时与公开仓库的字段，保留“未知”和真实零值的区别。
class MachineContainerImageSearchResult {
  const MachineContainerImageSearchResult({
    required this.name,
    this.description = '',
    this.stars,
    this.pulls,
    this.official,
    this.iconUrl,
    this.hubRepository,
  });

  factory MachineContainerImageSearchResult.fromJson(
    Map<String, dynamic> row, {
    bool allowUnqualifiedHub = true,
  }) {
    final name =
        '${row['Name'] ?? row['name'] ?? row['repo_name'] ?? row['slug'] ?? ''}'
            .trim();
    int? count(Object? value) {
      final number = int.tryParse('$value');
      return number != null && number >= 0 ? number : null;
    }

    final flag = row['IsOfficial'] ?? row['Official'] ?? row['is_official'];
    final official = switch ('$flag'.trim().toLowerCase()) {
      'true' || '1' || '[ok]' || '*' => true,
      'false' || '0' || '' => false,
      _ => null,
    };
    final logo = row['logo_url'] ?? row['Icon'] ?? row['icon_url'];
    final icon = Uri.tryParse(
      '${logo is Map ? logo['small'] ?? logo['large'] : logo ?? ''}',
    );
    final index = '${row['Index'] ?? row['Registry'] ?? ''}';
    final qualified =
        name.contains('/') &&
        (name.split('/').first.contains('.') ||
            name.split('/').first.contains(':'));
    return MachineContainerImageSearchResult(
      name: name,
      description:
          '${row['Description'] ?? row['description'] ?? row['short_description'] ?? ''}',
      stars: count(
        row['StarCount'] ?? row['Stars'] ?? row['star_count'] ?? row['stars'],
      ),
      pulls: count(row['PullCount'] ?? row['pull_count']),
      official: official,
      iconUrl:
          icon != null &&
              icon.scheme == 'https' &&
              icon.host.isNotEmpty &&
              icon.userInfo.isEmpty
          ? icon.toString()
          : null,
      hubRepository: machineDockerHubRepository(
        !qualified && index.isNotEmpty ? '$index/$name' : name,
        allowUnqualified: allowUnqualifiedHub,
      ),
    );
  }

  final String name, description;
  final int? stars, pulls;
  final bool? official;
  final String? iconUrl, hubRepository;

  MachineContainerImageSearchResult withMetadata(
    MachineContainerImageSearchResult metadata,
  ) => MachineContainerImageSearchResult(
    name: name,
    description: description,
    stars: metadata.stars ?? stars,
    pulls: metadata.pulls ?? pulls,
    official: metadata.official ?? official,
    iconUrl: metadata.iconUrl ?? iconUrl,
    hubRepository: hubRepository,
  );
}

String? machineDockerHubRepository(
  String name, {
  bool allowUnqualified = true,
}) {
  var reference = name;
  const hosts = ['docker.io/', 'index.docker.io/', 'registry-1.docker.io/'];
  final host = hosts.where(reference.startsWith).firstOrNull;
  if (host != null) {
    reference = reference.substring(host.length);
  } else if (!allowUnqualified) {
    return null;
  }
  final parts = reference.split('/');
  if (parts.length == 1) parts.insert(0, 'library');
  if (parts.length != 2 ||
      parts.any(
        (part) => !RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$').hasMatch(part),
      ) ||
      parts.first.contains('.') ||
      parts.first == 'localhost') {
    return null;
  }
  return parts.join('/');
}

bool machineContainerValidImageTag(String tag) =>
    RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$').hasMatch(tag);

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
  bool get supportsImageSearch => supportsResources;

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
      String value(String key) => machineContainerMetadataText(row[key]);
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
        final usage = row['UsageData'];
        final referenceText = value(images ? 'Containers' : 'Links');
        final references = int.tryParse(
          referenceText.isNotEmpty
              ? referenceText
              : !images && usage is Map
              ? '${usage['RefCount'] ?? ''}'
              : '',
        );
        final platform = row['Platform'];
        final os = machineContainerMetadataText(
          row['Os'] ?? row['OS'] ?? (platform is Map ? platform['os'] : null),
        );
        final arch = machineContainerMetadataText(
          row['Architecture'] ??
              (platform is Map ? platform['architecture'] : null),
        );
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
          size: value('Size').isNotEmpty
              ? value('Size')
              : !images && usage is Map
              ? machineContainerMetadataText(usage['Size'])
              : '',
          driver: value('Driver'),
          sharedSize: value('SharedSize'),
          uniqueSize: value('UniqueSize'),
          platform: [
            os,
            arch,
            value('Variant'),
          ].where((part) => part.isNotEmpty).join('/'),
          digest: value('Digest').isNotEmpty
              ? value('Digest')
              : value('RepoDigests'),
          mountpoint: value('Mountpoint'),
          scope: value('Scope'),
          labels: value('Labels'),
          options: value('Options'),
          layers: row['Layers'] is List ? (row['Layers'] as List).length : null,
          references: references != null && references >= 0 ? references : null,
          raw: row,
        );
      });
    }).toList();
    yield parse();
    if (rows.isEmpty) return;
    if (images) {
      // 多个标签共用镜像标识，只按唯一标识批量读取列表所需字段。
      final ids = rows
          .map((row) => _containerImageReference('${row['ID'] ?? row['Id']}'))
          .toSet()
          .toList();
      for (
        var offset = 0;
        offset < ids.length;
        offset += _machineContainerInspectBatchSize
      ) {
        if (isCancelled?.call() ?? false) return;
        final batch = ids
            .skip(offset)
            .take(_machineContainerInspectBatchSize)
            .toList();
        final output = await execute([
          'image',
          'inspect',
          '--format',
          '{{json .Id}}\t{{json .Os}}\t{{json .Architecture}}\t{{json .RepoDigests}}\t{{json .RootFS.Layers}}',
          ...batch,
        ]);
        if (isCancelled?.call() ?? false) return;
        final details = <String, Map<String, dynamic>>{};
        for (final line
            in output.split('\n').where((line) => line.trim().isNotEmpty)) {
          final fields = line.split('\t');
          if (fields.length != 5) throw const FormatException('镜像列表补充字段格式无效。');
          final values = fields.map(jsonDecode).toList();
          if (values[0] is! String ||
              values[1] is! String ||
              values[2] is! String ||
              values[3] != null && values[3] is! List ||
              values[4] != null && values[4] is! List) {
            throw const FormatException('镜像列表补充字段类型无效。');
          }
          details[(values[0] as String).replaceFirst('sha256:', '')] = {
            'Os': values[1],
            'Architecture': values[2],
            'RepoDigests': values[3],
            'Layers': values[4],
          };
        }
        if (batch.any(
          (id) => !details.containsKey(id.replaceFirst('sha256:', '')),
        )) {
          throw const FormatException('镜像列表补充字段缺少对应镜像。');
        }
        rows = [
          for (final row in rows)
            {
              ...row,
              ...?details['${row['ID'] ?? row['Id']}'.replaceFirst(
                'sha256:',
                '',
              )],
            },
        ];
        yield parse();
      }
    }
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
            if (byName.containsKey(row[key]))
              for (final field
                  in images
                      ? ['Containers', 'SharedSize', 'UniqueSize']
                      : ['Size', 'Links'])
                if (byName[row[key]]!.containsKey(field))
                  field: byName[row[key]]![field],
          },
      ];
      yield parse();
    }
  }

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
