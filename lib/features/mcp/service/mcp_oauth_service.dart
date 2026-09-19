import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/net/bounded_server_bind.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/mcp_server.dart';
import 'mcp_tool_discovery_exception.dart';

const kMcpOAuthConfigKey = 'oauth';
const _requestTimeout = Duration(seconds: 15);
const _authorizationTimeout = Duration(minutes: 3);
const _expiryMargin = Duration(seconds: 60);

enum McpOAuthStatus { required, authorizing, authorized, expired }

extension McpOAuthConfig on McpServer {
  Map get oauthConfig => extraFields[kMcpOAuthConfigKey] is Map
      ? extraFields[kMcpOAuthConfigKey] as Map
      : const {};
  bool get usesOAuth =>
      type != McpServerType.stdio && oauthConfig['enabled'] == true;
  String get oauthClientId => oauthConfig['clientId'] is String
      ? (oauthConfig['clientId'] as String).trim()
      : '';
  String get oauthScope => oauthConfig['scope'] is String
      ? (oauthConfig['scope'] as String).trim()
      : '';
  String get oauthKey => sha256
      .convert(utf8.encode(jsonEncode([url.trim(), oauthClientId, oauthScope])))
      .toString();
}

class McpOAuthRequiredException extends McpToolDiscoveryException {
  const McpOAuthRequiredException([
    super.message = '此 MCP 服务需要 OAuth 授权，请点击授权按钮。',
  ]);
}

/// 凭证独立保存在本机数据库，不写入 MCP 配置或导出文件。
class McpOAuthService extends ChangeNotifier {
  McpOAuthService({
    Future<Map<String, dynamic>?> Function(String)? read,
    Future<void> Function(String, Map<String, dynamic>?)? write,
    http.Client Function()? clientFactory,
    Future<bool> Function(String)? openBrowser,
  }) : _read = read ?? _readDatabase,
       _write = write ?? _writeDatabase,
       _clientFactory =
           clientFactory ?? SystemProxyResolver.instance.createHttpClient,
       _openBrowser = openBrowser ?? openHttpUrlWithSystemBrowser;

  static final instance = McpOAuthService();
  final Future<Map<String, dynamic>?> Function(String) _read;
  final Future<void> Function(String, Map<String, dynamic>?) _write;
  final http.Client Function() _clientFactory;
  final Future<bool> Function(String) _openBrowser;
  final _records = <String, Map<String, dynamic>?>{};
  final _loads = <String, Future<void>>{};
  final _refreshes = <String, Future<Map<String, dynamic>>>{};
  final _pending = <String, Completer<String>>{};
  final _authorizationClients = <String, http.Client>{};
  final _rejected = <String>{};
  final _invalidations = <String, int>{};
  final _challenges = <String, String>{};

  static Future<Map<String, dynamic>?> _readDatabase(String key) async {
    final rows = await DatabaseService.instance.database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['mcp_oauth_$key'],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
  }

  static Future<void> _writeDatabase(
    String key,
    Map<String, dynamic>? value,
  ) async {
    final db = DatabaseService.instance.database;
    if (value == null) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['mcp_oauth_$key'],
      );
    } else {
      await db.insert('app_settings', {
        'key': 'mcp_oauth_$key',
        'value': jsonEncode(value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> load(McpServer server) async {
    final key = server.oauthKey;
    if (_records.containsKey(key)) return;
    await (_loads[key] ??= (() async {
      final record = await _read(key);
      if (_records.length >= kMcpMaxServerCount) {
        final evict = _records.keys
            .where(
              (item) =>
                  !_pending.containsKey(item) && !_refreshes.containsKey(item),
            )
            .firstOrNull;
        if (evict != null) {
          _records.remove(evict);
          _rejected.remove(evict);
        }
      }
      _records[key] = record;
      notifyListeners();
    })()).whenComplete(() => _loads.remove(key));
  }

  McpOAuthStatus status(McpServer server) {
    final key = server.oauthKey;
    if (_pending.containsKey(key)) return McpOAuthStatus.authorizing;
    final record = _records[key];
    if (record == null) return McpOAuthStatus.required;
    if (_rejected.contains(key) ||
        (record['expires_at'] is num &&
            DateTime.now().millisecondsSinceEpoch >=
                (record['expires_at'] as num))) {
      return McpOAuthStatus.expired;
    }
    return McpOAuthStatus.authorized;
  }

  bool _valid(Map<String, dynamic> record) {
    final refreshAt = record['refresh_at'] ?? record['expires_at'];
    return record['access_token'] is String &&
        (refreshAt == null ||
            (refreshAt is num &&
                DateTime.now().millisecondsSinceEpoch < refreshAt));
  }

  Future<Map<String, String>> headers(
    McpServer server,
    Map<String, String> headers,
  ) async {
    if (!server.usesOAuth) return headers;
    await load(server);
    final key = server.oauthKey;
    var record = _records[key];
    if (record == null || _pending.containsKey(key)) {
      throw const McpOAuthRequiredException();
    }
    if (_rejected.contains(key) || !_valid(record)) {
      if (record['refresh_token'] == null) {
        throw const McpOAuthRequiredException('OAuth 授权已失效，请重新授权。');
      }
      record = await (_refreshes[key] ??= _refresh(
        server,
        record,
      )).whenComplete(() => _refreshes.remove(key));
    }
    return {
      for (final entry in headers.entries)
        if (entry.key.toLowerCase() != 'authorization') entry.key: entry.value,
      'Authorization': 'Bearer ${record['access_token']}',
    };
  }

  Future<T> request<T>(
    McpServer server,
    Map<String, String> configured,
    Future<T> Function(Map<String, String>) send,
  ) async {
    final firstHeaders = await headers(server, configured);
    try {
      return await send(firstHeaders);
    } on McpOAuthRequiredException {
      if (!server.usesOAuth || !_rejected.contains(server.oauthKey)) rethrow;
      // 仅身份验证拒绝可重试一次，工具执行后的业务错误不会重放。
      try {
        return await send(await headers(server, configured));
      } on McpOAuthRequiredException {
        final previous = _records[server.oauthKey];
        if (previous != null &&
            _rejected.contains(server.oauthKey) &&
            !_pending.containsKey(server.oauthKey)) {
          final expired = {...previous, 'expires_at': 0, 'refresh_at': 0}
            ..remove('refresh_token');
          await _write(server.oauthKey, expired);
          _records[server.oauthKey] = expired;
          notifyListeners();
        }
        rethrow;
      }
    }
  }

  void rejected(Uri uri, Map<String, String> headers, String? challenge) {
    if (challenge != null) {
      if (_challenges.length >= kMcpMaxServerCount) {
        _challenges.remove(_challenges.keys.first);
      }
      _challenges[uri.toString()] = challenge;
    }
    final auth = headers.entries
        .where((e) => e.key.toLowerCase() == 'authorization')
        .firstOrNull
        ?.value;
    for (final entry in _records.entries) {
      if (auth != null && auth == 'Bearer ${entry.value?['access_token']}') {
        _rejected.add(entry.key);
      }
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> _refresh(
    McpServer server,
    Map<String, dynamic> previous,
  ) async {
    final client = _clientFactory();
    final generation = _invalidations[server.oauthKey];
    try {
      final token = await _token(client, previous, {
        'grant_type': 'refresh_token',
        'refresh_token': previous['refresh_token'] as String,
        'resource': previous['resource'] as String? ?? server.url.trim(),
      });
      if (_invalidations[server.oauthKey] != generation) {
        throw const McpOAuthRequiredException('授权已变更，请重试。');
      }
      final record = {...previous, ...token};
      await _write(server.oauthKey, record);
      _records[server.oauthKey] = record;
      _rejected.remove(server.oauthKey);
      notifyListeners();
      return record;
    } on _OAuthHttpError catch (error) {
      if (_invalidations[server.oauthKey] != generation) {
        throw const McpOAuthRequiredException('授权已变更，请重试。');
      }
      if (error.code == 'invalid_grant' || error.code == 'invalid_client') {
        final record = {...previous, 'expires_at': 0, 'refresh_at': 0}
          ..remove('refresh_token');
        await _write(server.oauthKey, record);
        _records[server.oauthKey] = record;
        _rejected.add(server.oauthKey);
        notifyListeners();
        throw const McpOAuthRequiredException('OAuth 授权已失效，请重新授权。');
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  void cancel(McpServer server) {
    final pending = _pending[server.oauthKey];
    if (pending == null) return;
    _invalidations.update(
      server.oauthKey,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _authorizationClients[server.oauthKey]?.close();
    if (!pending.isCompleted) {
      pending.completeError(const McpOAuthRequiredException('已取消 OAuth 授权。'));
    }
  }

  Future<void> forget(McpServer server) async {
    cancel(server);
    _invalidations.update(
      server.oauthKey,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    await _refreshes[server.oauthKey]?.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    await _write(server.oauthKey, null);
    _records[server.oauthKey] = null;
    _rejected.remove(server.oauthKey);
    notifyListeners();
  }

  Future<void> authorize(McpServer server) async {
    final key = server.oauthKey;
    if (_pending.containsKey(key)) return;
    if (_pending.length >= 4) {
      throw const McpOAuthRequiredException('请先完成正在进行的授权。');
    }
    _invalidations.update(key, (value) => value + 1, ifAbsent: () => 1);
    final generation = _invalidations[key];
    final completion = Completer<String>();
    _pending[key] = completion;
    // 立即监听取消与超时，防止发现端点阶段出现未处理的异步错误。
    final codeFuture = completion.future.timeout(_authorizationTimeout);
    unawaited(codeFuture.then<void>((_) {}, onError: (Object _) {}));
    final client = _clientFactory();
    _authorizationClients[key] = client;
    final deadline = startSafeTimer(_authorizationTimeout, () {
      if (!completion.isCompleted) {
        completion.completeError(TimeoutException('授权超时'));
      }
      client.close();
    });
    unawaited(
      codeFuture.then<void>(
        (_) {},
        onError: (Object _) {
          client.close();
        },
      ),
    );
    HttpServer? listener;
    StreamSubscription<HttpRequest>? subscription;
    notifyListeners();
    try {
      await _refreshes[key]?.then<void>((_) {}, onError: (Object _) {});
      if (completion.isCompleted) await codeFuture;
      final resource = _safeUri(server.url.trim());
      final metadata = await _discover(client, resource);
      if (completion.isCompleted) await codeFuture;
      listener = await bindHttpServerBounded(
        InternetAddress.loopbackIPv4,
        0,
        timeout: _requestTimeout,
      );
      listener.idleTimeout = _requestTimeout;
      final redirect = 'http://127.0.0.1:${listener.port}/oauth/callback';
      final verifier = _random();
      final state = _random();
      final issuer = metadata['issuer'] as String;
      subscription = listener.listen((request) async {
        final params = request.uri.queryParameters;
        if (request.method != 'GET' ||
            request.uri.path != '/oauth/callback' ||
            params['state'] != state ||
            (params['iss'] != null && params['iss'] != issuer)) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('授权回调无效，请返回应用重试。');
        } else if (!completion.isCompleted) {
          request.response.headers.contentType = ContentType.text;
          request.response.headers.set('Cache-Control', 'no-store');
          if (params['error'] != null || (params['code'] ?? '').isEmpty) {
            completion.completeError(
              const McpOAuthRequiredException('授权未完成，请返回应用重新授权。'),
            );
            request.response.write('授权未完成，请返回 OpenHand。');
          } else {
            completion.complete(params['code']!);
            request.response.write('已收到授权，请返回 OpenHand。');
          }
        }
        try {
          await request.response.close();
        } on SocketException {
          /* 浏览器提前断开不影响已经收到的授权结果。 */
        }
      });
      var registration = <String, dynamic>{
        'client_id': server.oauthClientId,
        'token_endpoint_auth_method': 'none',
      };
      if (server.oauthClientId.isEmpty) {
        final endpoint = metadata['registration_endpoint'];
        if (endpoint is! String) {
          throw const McpOAuthRequiredException('授权服务不支持自动注册，请在编辑弹窗填写客户端 ID。');
        }
        final supportedMethods =
            metadata['token_endpoint_auth_methods_supported'];
        final registrationMethod = supportedMethods is List
            ? const [
                'none',
                'client_secret_post',
                'client_secret_basic',
              ].where(supportedMethods.contains).firstOrNull
            : 'none';
        if (registrationMethod == null) {
          throw const McpOAuthRequiredException('授权服务未提供可用的客户端鉴权方式。');
        }
        registration = await _json(
          client,
          _safeUri(endpoint),
          body: jsonEncode({
            'client_name': 'OpenHand',
            'redirect_uris': [redirect],
            'grant_types': ['authorization_code', 'refresh_token'],
            'response_types': ['code'],
            'token_endpoint_auth_method': registrationMethod,
          }),
          jsonBody: true,
        );
        registration.putIfAbsent(
          'token_endpoint_auth_method',
          () => registrationMethod,
        );
      }
      if ((registration['client_id'] as String? ?? '').isEmpty) {
        throw const McpOAuthRequiredException('授权服务未返回客户端 ID。');
      }
      final record = {
        'client_id': registration['client_id'],
        if (registration['client_secret'] is String)
          'client_secret': registration['client_secret'],
        'token_endpoint_auth_method':
            registration['token_endpoint_auth_method'],
        'token_endpoint': metadata['token_endpoint'],
        'resource': metadata['_resource'],
      };
      final scope = server.oauthScope.isNotEmpty
          ? server.oauthScope
          : metadata['_scope'] as String? ?? '';
      final authorization =
          _safeUri(metadata['authorization_endpoint'] as String).replace(
            queryParameters: {
              'response_type': 'code',
              'client_id': registration['client_id'] as String,
              'redirect_uri': redirect,
              'state': state,
              'resource': metadata['_resource'] as String,
              'code_challenge': base64Url
                  .encode(sha256.convert(ascii.encode(verifier)).bytes)
                  .replaceAll('=', ''),
              'code_challenge_method': 'S256',
              if (scope.isNotEmpty) 'scope': scope,
            },
          );
      if (completion.isCompleted) await codeFuture;
      if (!await _openBrowser(authorization.toString())) {
        throw const McpOAuthRequiredException('无法打开系统浏览器，请检查默认浏览器设置。');
      }
      final code = await codeFuture;
      final tokens = await _token(client, record, {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
        'resource': metadata['_resource'] as String,
      });
      if (_invalidations[key] != generation) {
        throw const McpOAuthRequiredException('已取消 OAuth 授权。');
      }
      await _write(key, {...record, ...tokens});
      if (_invalidations[key] != generation) {
        await _write(key, null);
        throw const McpOAuthRequiredException('已取消 OAuth 授权。');
      }
      _records[key] = {...record, ...tokens};
      _rejected.remove(key);
    } on TimeoutException {
      throw const McpOAuthRequiredException('OAuth 授权超时，请重新授权。');
    } finally {
      if (!completion.isCompleted) completion.complete('');
      deadline.cancel();
      await subscription?.cancel();
      await listener?.close(force: true);
      client.close();
      _pending.remove(key);
      _authorizationClients.remove(key);
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _discover(
    http.Client client,
    Uri resource,
  ) async {
    var challenge = _challenges[resource.toString()];
    if (challenge == null) {
      final probe = await client
          .send(
            http.Request('GET', resource)
              ..followRedirects = false
              ..headers['Accept'] = 'application/json, text/event-stream',
          )
          .timeout(_requestTimeout);
      challenge = probe.headers['www-authenticate'];
      await probe.stream.listen(null).cancel().timeout(_requestTimeout);
    }
    final advertised = challenge == null
        ? null
        : RegExp('resource_metadata="([^"]+)"').firstMatch(challenge)?.group(1);
    Map<String, dynamic>? protected;
    final paths = {
      if (advertised != null) _safeUri(advertised),
      resource.replace(
        path:
            '/.well-known/oauth-protected-resource${resource.path == '/' ? '' : resource.path}',
        query: '',
        fragment: '',
      ),
      resource.replace(
        path: '/.well-known/oauth-protected-resource',
        query: '',
        fragment: '',
      ),
    };
    for (final uri in paths) {
      try {
        protected = await _json(client, uri);
        break;
      } on _OAuthHttpError catch (error) {
        if (error.status != 404) rethrow;
      }
    }
    if (protected == null || protected['resource'] is! String) {
      throw const McpOAuthRequiredException('MCP 服务未提供匹配的 OAuth 资源元数据。');
    }
    final canonicalResource = _safeUri(protected['resource'] as String);
    final canonicalPath = canonicalResource.path.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (canonicalResource.origin != resource.origin ||
        (resource.path != canonicalPath &&
            !resource.path.startsWith('$canonicalPath/')) ||
        (canonicalResource.hasQuery &&
            canonicalResource.query != resource.query)) {
      throw const McpOAuthRequiredException('OAuth 资源标识与 MCP 服务不匹配。');
    }
    final issuers = protected['authorization_servers'];
    if (issuers is! List || issuers.isEmpty || issuers.first is! String) {
      throw const McpOAuthRequiredException('MCP 服务未提供授权服务器。');
    }
    final issuer = _safeUri(issuers.first as String);
    final path = issuer.path == '/' ? '' : issuer.path;
    final candidates = {
      issuer.replace(path: '/.well-known/oauth-authorization-server$path'),
      issuer.replace(path: '/.well-known/openid-configuration$path'),
      issuer.replace(path: '$path/.well-known/openid-configuration'),
    };
    for (final uri in candidates) {
      Map<String, dynamic> metadata;
      try {
        metadata = await _json(client, uri);
      } on _OAuthHttpError catch (error) {
        if (error.status == 404) continue;
        rethrow;
      }
      if (metadata['issuer'] != issuer.toString()) {
        throw const McpOAuthRequiredException('OAuth 授权服务器身份不匹配。');
      }
      if (metadata['code_challenge_methods_supported'] is! List ||
          !(metadata['code_challenge_methods_supported'] as List).contains(
            'S256',
          )) {
        throw const McpOAuthRequiredException('授权服务不支持安全的 PKCE S256。');
      }
      _safeUri(metadata['authorization_endpoint'] as String? ?? '');
      _safeUri(metadata['token_endpoint'] as String? ?? '');
      final scopes = protected['scopes_supported'];
      return {
        ...metadata,
        '_resource': canonicalResource.toString(),
        '_scope': scopes is List ? scopes.whereType<String>().join(' ') : '',
      };
    }
    throw const McpOAuthRequiredException('无法发现 OAuth 授权端点。');
  }

  Future<Map<String, dynamic>> _token(
    http.Client client,
    Map<String, dynamic> record,
    Map<String, String> fields,
  ) async {
    final method = record['token_endpoint_auth_method'] ?? 'none';
    final secret = record['client_secret'];
    final headers = <String, String>{};
    final body = {...fields, 'client_id': record['client_id'] as String};
    if (method == 'client_secret_post' && secret is String) {
      body['client_secret'] = secret;
    } else if (method == 'client_secret_basic' && secret is String) {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${Uri.encodeQueryComponent(body['client_id']!)}:${Uri.encodeQueryComponent(secret)}'))}';
    } else if (method != 'none') {
      throw const McpOAuthRequiredException('授权服务要求的客户端鉴权方式暂不支持。');
    }
    final token = await _json(
      client,
      _safeUri(record['token_endpoint'] as String),
      body: body,
      headers: headers,
    );
    final access = token['access_token'];
    if (access is! String ||
        access.isEmpty ||
        !RegExp(r'^[A-Za-z0-9\-._~+/]+=*$').hasMatch(access) ||
        (token['token_type'] as String? ?? '').toLowerCase() != 'bearer') {
      throw const McpOAuthRequiredException('授权服务返回了无效的访问令牌。');
    }
    final expires = token['expires_in'];
    if (expires != null &&
        (expires is! num || !expires.isFinite || expires <= 0)) {
      throw const McpOAuthRequiredException('授权服务返回了无效的令牌有效期。');
    }
    return {
      'access_token': access,
      if (token['refresh_token'] is String)
        'refresh_token': token['refresh_token'],
      'refresh_at': expires is num
          ? DateTime.now().millisecondsSinceEpoch +
                (expires * 1000 -
                        min(_expiryMargin.inMilliseconds, expires * 100))
                    .round()
          : null,
      'expires_at': expires is num
          ? DateTime.now().millisecondsSinceEpoch + (expires * 1000).round()
          : null,
    };
  }

  Future<Map<String, dynamic>> _json(
    http.Client client,
    Uri uri, {
    Object? body,
    bool jsonBody = false,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(body == null ? 'GET' : 'POST', uri)
      ..followRedirects = false;
    request.headers.addAll({'Accept': 'application/json', ...headers});
    if (jsonBody) {
      request.headers['Content-Type'] = 'application/json';
      request.body = body as String;
    } else if (body != null) {
      request.bodyFields = body as Map<String, String>;
    }
    final response = await client.send(request).timeout(_requestTimeout);
    final text = await readBoundedByteStreamText(
      response.stream,
      maxBytes: 256 * 1024,
      idleTimeout: _requestTimeout,
      totalTimeout: _requestTimeout,
    );
    Map<String, dynamic>? result;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) result = decoded;
    } on FormatException {
      if (response.statusCode < 400) {
        throw const McpOAuthRequiredException('OAuth 服务返回了无效的数据。');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _OAuthHttpError(response.statusCode, result?['error'] as String?);
    }
    if (result == null) {
      throw const McpOAuthRequiredException('OAuth 服务返回了无效的数据。');
    }
    return result;
  }

  static Uri _safeUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                (uri.host == '127.0.0.1' ||
                    uri.host == '::1' ||
                    uri.host == 'localhost')))) {
      throw const McpOAuthRequiredException('OAuth 端点必须使用 HTTPS，本机回调除外。');
    }
    return uri;
  }

  static String _random() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

class _OAuthHttpError extends McpToolDiscoveryException {
  _OAuthHttpError(this.status, this.code)
    : super('OAuth 请求失败（HTTP $status），请稍后重试。');
  final int status;
  final String? code;
}
