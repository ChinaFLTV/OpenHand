part of 'machine_containers.dart';

const machineContainerTelemetryTimeout = Duration(seconds: 12);
const machineContainerTelemetryBudget = Duration(seconds: 90);
const machineContainerTelemetryEventLimit = 200;

dynamic _machineTelemetryField(Map item, String path) {
  dynamic value = item;
  for (final key in path.split('.')) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value;
}

// 分组字段合并为紧凑表格，完整响应仍可单独查看。
MachineMaintenanceReadout _machineTelemetryReadout(
  String output,
  String section,
) {
  final report = MachineMaintenanceReadout.parse(output, section);
  if (report.groups.isEmpty) return report;
  return MachineMaintenanceReadout(
    ['名称', '数值'],
    [
      ...report.rows,
      for (final group in report.groups.entries)
        for (final row in group.value.rows)
          ['${group.key} / ${row.first}', row.last],
    ],
    fields: true,
    issue: report.issue,
    raw: report.raw,
  );
}

class MachineContainerTelemetryQuery {
  const MachineContainerTelemetryQuery(this.id, this.label, this.arguments);
  final String id, label;
  final List<String> arguments;

  MachineMaintenanceReadout parse(String output) {
    if (id == 'metadata') {
      final document = jsonDecode(output);
      if (document is! Map || document.isEmpty) {
        throw const FormatException('运行时元数据响应无效。');
      }
      final fields = {
        '名称': ['Name', 'host.hostname'],
        'UUID / ID': ['ID'],
        '服务版本': ['ServerVersion', 'version.Version'],
        '系统版本': ['OperatingSystem', 'host.distribution.distribution'],
        '内核版本': ['KernelVersion', 'host.kernel'],
        '架构': ['Architecture', 'host.arch'],
        '逻辑处理器': ['NCPU', 'host.cpus'],
        '内存总量': ['MemTotal', 'host.memTotal'],
        '容器': ['Containers', 'store.containerStore.number'],
        '运行中容器': ['ContainersRunning', 'store.containerStore.running'],
        '暂停容器': ['ContainersPaused', 'store.containerStore.paused'],
        '未运行': ['ContainersStopped', 'store.containerStore.stopped'],
        '镜像': ['Images', 'store.imageStore.number'],
        '存储驱动': ['Driver', 'store.graphDriverName'],
        '存储目录': ['DockerRootDir', 'store.graphRoot'],
        '控制组驱动': ['CgroupDriver', 'host.cgroupManager'],
        '控制组版本': ['CgroupVersion', 'host.cgroupVersion'],
        '默认运行时': ['DefaultRuntime', 'host.ociRuntime.name'],
        '可用运行时': ['Runtimes'],
        '日志驱动': ['LoggingDriver', 'host.logDriver'],
        '服务恢复时保持容器运行': ['LiveRestoreEnabled'],
        '安全选项': ['SecurityOptions', 'host.security'],
        '插件': ['Plugins', 'plugins'],
        '状态条件': ['status.conditions'],
        '运行规格': ['config'],
        '提醒': ['Warnings'],
      };
      final rows = <List<String>>[];
      for (final entry in fields.entries) {
        final value = entry.value
            .map((path) => _machineTelemetryField(document, path))
            .where((value) => value != null)
            .firstOrNull;
        if (value != null) {
          rows.add([
            entry.key,
            value is Map || value is List ? jsonEncode(value) : '$value',
          ]);
        }
      }
      return rows.isEmpty
          ? _machineTelemetryReadout(output, 'container_metadata')
          : MachineMaintenanceReadout(['名称', '数值'], rows, fields: true);
    }
    if (id == 'readiness') {
      final ready = output.trim() == 'ok';
      if (!ready) throw const FormatException('Kubernetes API 就绪检查未通过。');
      return const MachineMaintenanceReadout(
        ['名称', '数值'],
        [
          ['就绪', '就绪'],
        ],
        fields: true,
      );
    }
    if (const {
      'nodes',
      'workloads',
      'services',
      'storage',
      'storage_claims',
      'quotas',
      'events',
      'namespaces',
      'storage_classes',
    }.contains(id)) {
      final document = jsonDecode(output);
      if (document is! Map || document['items'] is! List) {
        throw const FormatException('Kubernetes 资源响应格式无效。');
      }
      final items = (document['items'] as List).cast<Map>();
      if (id == 'events') {
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          items[i] = {
            ...item,
            'lastTimestamp':
                item['series']?['lastObservedTime'] ??
                item['lastTimestamp'] ??
                item['eventTime'] ??
                item['metadata']?['creationTimestamp'],
            'count': item['series']?['count'] ?? item['count'],
          };
        }
        items.sort(
          (a, b) => '${b['lastTimestamp'] ?? ''}'.compareTo(
            '${a['lastTimestamp'] ?? ''}',
          ),
        );
      }

      final columns = switch (id) {
        'nodes' => {
          '名称': 'metadata.name',
          'CPU 容量': 'status.capacity.cpu',
          'CPU 可分配': 'status.allocatable.cpu',
          '内存容量': 'status.capacity.memory',
          '内存可分配': 'status.allocatable.memory',
          'Pod 容量': 'status.allocatable.pods',
          '容器运行时': 'status.nodeInfo.containerRuntimeVersion',
          '系统版本': 'status.nodeInfo.osImage',
          '内核版本': 'status.nodeInfo.kernelVersion',
          '架构': 'status.nodeInfo.architecture',
        },
        'workloads' => {
          '类型': 'kind',
          '命名空间': 'metadata.namespace',
          '名称': 'metadata.name',
          '期望副本': 'spec.replicas',
          '就绪副本': 'status.readyReplicas',
          '可用副本': 'status.availableReplicas',
          '目标节点数': 'status.desiredNumberScheduled',
          '就绪节点数': 'status.numberReady',
          '成功次数': 'status.succeeded',
          '失败次数': 'status.failed',
          '创建时间': 'metadata.creationTimestamp',
        },
        'services' => {
          '类型': 'kind',
          '命名空间': 'metadata.namespace',
          '名称': 'metadata.name',
          '网络模式': 'spec.type',
          '地址': 'spec.clusterIP',
          '端口': 'spec.ports',
          '网络端点': 'endpoints',
          '网络规则': 'spec.rules',
          '外部地址': 'status.loadBalancer.ingress',
          '创建时间': 'metadata.creationTimestamp',
        },
        'storage' || 'storage_claims' => {
          '类型': 'kind',
          '命名空间': 'metadata.namespace',
          '名称': 'metadata.name',
          '状态': 'status.phase',
          '存储类': 'spec.storageClassName',
          '容量': 'spec.capacity',
          '请求资源': 'spec.resources.requests',
          '访问模式': 'spec.accessModes',
          '回收策略': 'spec.persistentVolumeReclaimPolicy',
          '创建时间': 'metadata.creationTimestamp',
        },
        'quotas' => {
          '类型': 'kind',
          '命名空间': 'metadata.namespace',
          '名称': 'metadata.name',
          '资源上限': 'status.hard',
          '已用资源': 'status.used',
          '资源限制': 'spec.limits',
        },
        'namespaces' => {
          '名称': 'metadata.name',
          '状态': 'status.phase',
          '标签': 'metadata.labels',
          '创建时间': 'metadata.creationTimestamp',
        },
        'storage_classes' => {
          '名称': 'metadata.name',
          '存储驱动': 'provisioner',
          '回收策略': 'reclaimPolicy',
          '卷绑定模式': 'volumeBindingMode',
          '允许扩容': 'allowVolumeExpansion',
          '参数': 'parameters',
        },
        _ => {
          '命名空间': 'metadata.namespace',
          '名称': 'involvedObject.name',
          '类型': 'type',
          '描述': 'reason',
          '诊断说明': 'message',
          '次数': 'count',
          '时间': 'lastTimestamp',
        },
      };
      String value(dynamic raw) => raw == null
          ? '—'
          : raw is Map || raw is List
          ? jsonEncode(raw)
          : '$raw';
      final rows = <List<String>>[];
      for (final item in items.take(
        id == 'events' ? machineContainerTelemetryEventLimit : items.length,
      )) {
        final row = [
          for (final path in columns.values)
            value(_machineTelemetryField(item, path)),
        ];
        if (id == 'nodes') {
          final conditions =
              _machineTelemetryField(item, 'status.conditions') as List? ??
              const [];
          final ready = conditions
              .whereType<Map>()
              .where((c) => c['type'] == 'Ready')
              .firstOrNull;
          row.insert(1, switch (ready?['status']) {
            'True' => '就绪',
            'False' => '未就绪',
            _ => '${ready?['status'] ?? '—'}',
          });
          row.add(value(conditions));
          row.add(value(_machineTelemetryField(item, 'status.addresses')));
        }
        rows.add(row);
      }
      return MachineMaintenanceReadout(
        id == 'nodes'
            ? ['名称', '就绪', ...columns.keys.skip(1), '健康检查', '地址']
            : columns.keys.toList(),
        rows,
      );
    }
    if (const {
      'version',
      'networks',
      'metrics',
      'disk',
      'node_metrics',
      'pod_metrics',
    }.contains(id)) {
      final report = _machineTelemetryReadout(
        output,
        const {'metrics', 'node_metrics', 'pod_metrics'}.contains(id)
            ? 'container_metrics'
            : 'containers',
      );
      if (report.issue != null || report.raw) {
        throw const FormatException('容器遥测响应格式未识别。');
      }
      if (output.trim().isEmpty &&
          const {'version', 'node_metrics'}.contains(id)) {
        throw const FormatException('容器遥测响应为空。');
      }
      if (id == 'node_metrics' || id == 'pod_metrics') {
        return MachineMaintenanceReadout([
          for (final header in report.headers)
            switch (header) {
              'NAME' => '名称',
              'CPU%' => 'CPU 使用率',
              _ => header,
            },
        ], report.rows);
      }
      return report;
    }
    throw ArgumentError.value(id, 'id', '未知容器遥测项目');
  }
}

extension MachineContainerTelemetry on MachineContainerClient {
  List<MachineContainerTelemetryQuery> get telemetryQueries {
    List<String> scoped(List<String> args) => [
      ...args,
      if (scope.isEmpty) '-A' else ...['-n', scope],
    ];
    if (runtime == MachineContainerRuntime.kubernetes) {
      return [
        const MachineContainerTelemetryQuery('version', '版本', [
          'version',
          '-o',
          'json',
        ]),
        const MachineContainerTelemetryQuery('readiness', 'API 服务健康', [
          'get',
          '--raw=/readyz',
        ]),
        const MachineContainerTelemetryQuery('nodes', '节点信息', [
          'get',
          'nodes',
          '-o',
          'json',
        ]),
        const MachineContainerTelemetryQuery('namespaces', '命名空间', [
          'get',
          'namespaces',
          '-o',
          'json',
        ]),
        const MachineContainerTelemetryQuery('node_metrics', '节点资源采样', [
          'top',
          'nodes',
        ]),
        MachineContainerTelemetryQuery(
          'pod_metrics',
          '实时资源采样',
          scoped(['top', 'pods', '--containers']),
        ),
        MachineContainerTelemetryQuery(
          'workloads',
          '工作负载',
          scoped([
            'get',
            'deployments,statefulsets,daemonsets,jobs,cronjobs',
            '-o',
            'json',
          ]),
        ),
        MachineContainerTelemetryQuery(
          'services',
          '服务与网络',
          scoped(['get', 'services,endpointslices,ingresses', '-o', 'json']),
        ),
        const MachineContainerTelemetryQuery('storage', '持久存储', [
          'get',
          'persistentvolumes',
          '-o',
          'json',
        ]),
        const MachineContainerTelemetryQuery('storage_classes', '存储类', [
          'get',
          'storageclasses',
          '-o',
          'json',
        ]),
        MachineContainerTelemetryQuery(
          'storage_claims',
          '存储声明',
          scoped(['get', 'persistentvolumeclaims', '-o', 'json']),
        ),
        MachineContainerTelemetryQuery(
          'quotas',
          '资源配额',
          scoped(['get', 'resourcequotas,limitranges', '-o', 'json']),
        ),
        MachineContainerTelemetryQuery(
          'events',
          '告警事件',
          scoped([
            'get',
            'events',
            '--field-selector=type=Warning',
            '-o',
            'json',
          ]),
        ),
      ];
    }
    return [
      MachineContainerTelemetryQuery(
        'metadata',
        '运行时元数据与状态',
        metadataArguments,
      ),
      if (runtime != MachineContainerRuntime.cri)
        MachineContainerTelemetryQuery('version', '版本', [
          'version',
          if (runtime != MachineContainerRuntime.containerd) ...[
            '--format',
            runtime == MachineContainerRuntime.podman ? 'json' : '{{json .}}',
          ],
        ]),
      MachineContainerTelemetryQuery('metrics', '实时资源采样', metricsArguments),
      if (supportsResources) ...[
        MachineContainerTelemetryQuery('disk', '磁盘占用与回收', [
          'system',
          'df',
          if (runtime != MachineContainerRuntime.containerd) ...[
            '--format',
            runtime == MachineContainerRuntime.podman ? 'json' : '{{json .}}',
          ],
        ]),
        MachineContainerTelemetryQuery('networks', '网络', [
          'network',
          'ls',
          '--format',
          runtime == MachineContainerRuntime.podman ? 'json' : '{{json .}}',
        ]),
      ],
    ];
  }
}
