import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../app/support/system_proxy.dart';
import '../../../shared/net/abortable_http_request.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/util/byte_size_format.dart';
import '../model/mcp_market.dart';

/// 每类请求只保留最新一次；关闭市场时终止所有在途请求。
class McpMarketClient {
  McpMarketClient({http.Client? httpClient})
    : _client = httpClient ?? SystemProxyResolver.instance.createHttpClient(),
      _ownsClient = httpClient == null;

  static const int defaultPageSize = 24;
  static const int maxResponseBytes = 2 * kBytesPerMiB;
  static const Duration _timeout = Duration(seconds: 15);
  static const String _host = 'api.skillhub.cn';
  static const String _basePath = '/api/v1/mcp';

  final http.Client _client;
  final bool _ownsClient;
  final Map<String, Completer<void>> _requests = {};
  bool _closed = false;

  Future<List<(String, int)>> categories() async {
    final json = await _json('categories', ['categories']);
    return (json['items'] as List)
        .map((item) {
          final map = item as Map;
          return (map['key'] as String, (map['count'] as num).toInt());
        })
        .where((item) => item.$1.isNotEmpty)
        .toList(growable: false);
  }

  Future<McpMarketPage> search({
    required int page,
    required int pageSize,
    required String keyword,
    required String category,
  }) async => McpMarketPage.fromJson(
    await _json(
      'search',
      ['servers'],
      {
        'page': '${page.clamp(1, 1000000)}',
        'pageSize': '${pageSize.clamp(1, 200)}',
        'sortBy': 'updated_at',
        'order': 'desc',
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        if (category.isNotEmpty) 'category': category,
      },
    ),
  );

  Future<McpMarketServer> detail(String slug) async =>
      McpMarketServer.fromJson(await _json('detail', ['servers', slug]));

  Future<String> readme(String slug) =>
      _get('readme', ['servers', slug, 'readme']);

  void cancel(String scope) {
    final previous = _requests.remove(scope);
    if (previous != null && !previous.isCompleted) previous.complete();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final scope in _requests.keys.toList()) {
      cancel(scope);
    }
    if (_ownsClient) _client.close();
  }

  Future<Map<String, Object?>> _json(
    String scope,
    List<String> path, [
    Map<String, String>? query,
  ]) async {
    final decoded = jsonDecode(await _get(scope, path, query));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('MCP 市场响应格式不正确。');
    }
    return decoded;
  }

  Future<String> _get(
    String scope,
    List<String> path, [
    Map<String, String>? query,
  ]) async {
    if (_closed) throw StateError('MCP 市场已关闭。');
    cancel(scope);
    final abort = Completer<void>();
    _requests[scope] = abort;
    final uri = Uri.https(_host, _basePath).replace(
      pathSegments: ['api', 'v1', 'mcp', ...path],
      queryParameters: query,
    );
    try {
      final response = await sendAbortableHttpRequest(
        client: _client,
        request: http.Request('GET', uri)
          ..headers['Accept'] = scope == 'readme'
              ? 'text/plain'
              : 'application/json',
        connectionTimeout: _timeout,
        cancelSignal: abort.future,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.listen(null).cancel();
        throw StateError('MCP 市场请求失败（${response.statusCode}）。');
      }
      return await readBoundedByteStreamText(
        response.stream,
        maxBytes: maxResponseBytes,
        idleTimeout: _timeout,
        totalTimeout: _timeout,
      );
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_requests[scope], abort)) _requests.remove(scope);
    }
  }
}
