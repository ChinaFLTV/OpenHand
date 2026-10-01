import 'dart:convert';
import 'dart:io';

import '../../shared/net/http_response_utils.dart';
import 'machine_containers.dart';

const machineImageRegistryTimeout = Duration(seconds: 12);
const machineImageRegistryResponseLimit = 4 * 1024 * 1024;
const machineImageTagPageSize = 50;
const machineImageTagPageLimit = 20;

typedef MachineImageTagPage = ({List<String> tags, bool hasMore});

/// 只补充 Docker Hub 公开信息；拉取仍交给目标机器上的运行时与凭据。
class MachineImageRegistry {
  MachineImageRegistry({Future<Map<String, dynamic>> Function(Uri)? read})
    : _readOverride = read;

  final Future<Map<String, dynamic>> Function(Uri)? _readOverride;
  final _clients = <HttpClient>{};
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    cancelPending();
  }

  void cancelPending() {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }

  Future<Map<String, dynamic>> _read(Uri uri) async {
    if (_disposed) throw StateError('镜像仓库查询已关闭。');
    if (_readOverride != null) return _readOverride(uri);
    final client = HttpClient();
    _clients.add(client);
    try {
      final bytes = await fetchBoundedHttpBytes(
        client: client,
        uri: uri,
        maxBytes: machineImageRegistryResponseLimit,
        openTimeout: machineImageRegistryTimeout,
        idleTimeout: machineImageRegistryTimeout,
        totalTimeout: machineImageRegistryTimeout,
        expectedPrimaryType: 'application',
      );
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('镜像仓库响应格式无效。');
      }
      return value;
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<Map<String, MachineContainerImageSearchResult>> searchMetadata(
    String query, {
    bool logos = false,
  }) async {
    final data = await _read(
      Uri.https(
        'hub.docker.com',
        logos ? '/api/search/v3/catalog/search' : '/v2/search/repositories/',
        logos
            ? {
                'query': query,
                'from': '0',
                'size': '$machineContainerSearchLimit',
              }
            : {'query': query, 'page_size': '$machineContainerSearchLimit'},
      ),
    );
    final results = data['results'];
    if (results is! List) throw const FormatException('镜像仓库缺少搜索结果。');
    final metadata = <String, MachineContainerImageSearchResult>{};
    for (final row in results.take(machineContainerSearchLimit)) {
      if (row is! Map<String, dynamic>) continue;
      // 目录可能含软件名称与扩展，必须按镜像仓库标识匹配，不能按标题合并。
      final entry = MachineContainerImageSearchResult.fromJson(
        logos
            ? {'Name': row['slug'] ?? row['id'], 'logo_url': row['logo_url']}
            : row,
      );
      if (entry.hubRepository != null) metadata[entry.hubRepository!] = entry;
    }
    return metadata;
  }

  Future<MachineImageTagPage> tags(
    String repository, {
    String filter = '',
    int page = 1,
  }) async {
    final canonical = machineDockerHubRepository(repository);
    if (canonical == null ||
        canonical != repository ||
        page < 1 ||
        page > machineImageTagPageLimit ||
        filter.length > 128) {
      throw const FormatException('镜像仓库或标签查询参数无效。');
    }
    final parts = canonical.split('/');
    final data = await _read(
      Uri.https(
        'hub.docker.com',
        '/v2/namespaces/${parts[0]}/repositories/${parts[1]}/tags',
        {
          'page_size': '$machineImageTagPageSize',
          'page': '$page',
          if (filter.isNotEmpty) 'name': filter,
        },
      ),
    );
    final results = data['results'];
    if (results is! List) throw const FormatException('镜像仓库缺少标签列表。');
    return (
      tags: results
          .whereType<Map>()
          .map((row) => '${row['name'] ?? ''}')
          .where(machineContainerValidImageTag)
          .take(machineImageTagPageSize)
          .toSet()
          .toList(),
      hasMore:
          page < machineImageTagPageLimit && '${data['next'] ?? ''}'.isNotEmpty,
    );
  }
}
