import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../shared/net/http_response_utils.dart';
import '../../shared/util/async_concurrency.dart';
import 'machine_containers.dart';

const machineImageRegistryTimeout = Duration(seconds: 12);
const machineImageRegistryResponseLimit = 4 * 1024 * 1024;
const machineImageTagPageSize = 50;
const machineImageTagPageLimit = 20;

typedef MachineImageTagPage = ({List<String> tags, bool hasMore});

/// 公开仓库请求统一使用调用方提供的网络路由，并支持关闭面板时取消。
class MachineImageRegistry {
  MachineImageRegistry({
    required this.clientFactory,
    Future<Map<String, dynamic>> Function(Uri)? read,
  }) : _readOverride = read;

  final HttpClient Function() clientFactory;
  final Future<Map<String, dynamic>> Function(Uri)? _readOverride;
  final _clients = <HttpClient>{};
  final _iconRequests = <String, Future<Uint8List>>{};
  final _iconSlots = OpenHandAsyncSemaphore(
    4,
    maxWaiters: machineContainerSearchLimit,
  );
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    cancelPending();
  }

  void cancelPending() {
    _iconSlots.cancelWaiters();
    _iconRequests.clear();
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }

  Future<Map<String, dynamic>> _read(Uri uri) async {
    if (_disposed) throw StateError('镜像仓库查询已关闭。');
    if (_readOverride != null) return _readOverride(uri);
    final client = clientFactory();
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

  Future<Uint8List> icon(String url) => _iconRequests.putIfAbsent(
    url,
    () => _iconSlots.withPermit(() => _loadIcon(url)),
  );

  Future<Uint8List> _loadIcon(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('镜像图标地址无效。');
    }
    if (_disposed) throw StateError('镜像仓库查询已关闭。');
    final client = clientFactory();
    _clients.add(client);
    try {
      return await fetchBoundedHttpBytes(
        client: client,
        uri: uri,
        maxBytes: 512 * 1024,
        openTimeout: machineImageRegistryTimeout,
        idleTimeout: machineImageRegistryTimeout,
        totalTimeout: machineImageRegistryTimeout,
        expectedPrimaryType: 'image',
      );
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<Map<String, MachineContainerImageSearchResult>> searchMetadata(
    String query, {
    bool logos = false,
  }) async {
    final term = query.trim();
    if (term.isEmpty ||
        term.length > 128 ||
        term.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const MachineContainerConfigException('form', '搜索');
    }
    final data = await _read(
      Uri.https(
        'hub.docker.com',
        logos ? '/api/search/v3/catalog/search' : '/v2/search/repositories/',
        logos
            ? {
                'query': term,
                'from': '0',
                'size': '$machineContainerSearchLimit',
              }
            : {'query': term, 'page_size': '$machineContainerSearchLimit'},
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
