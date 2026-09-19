import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'mcp_oauth',
  source: _checks,
);

const _checks = '''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:openhand/features/mcp/widgets/mcp_oauth_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http/io_client.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/service/mcp_oauth_service.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

const server = McpServer(name: '通用服务', type: McpServerType.streamableHttp,
  enabled: true, url: 'https://resource.example/mcp',
  extraFields: {'oauth': {'enabled': true}});

class _RealHttpOverrides extends HttpOverrides {}

class Fixture {
  Map<String, dynamic>? saved;
  int refreshes = 0;
  bool invalidGrant = false;
  bool pkce = true;
  String authMethod = 'none';
  String resourceId = server.url;
  bool wrongIssuer = false;
  bool cancelBrowser = false;
  Completer<void>? refreshGate;
  final refreshStarted = Completer<void>();
  Uri? browserUrl;
  late final McpOAuthService oauth = McpOAuthService(
    read: (_) async => saved,
    write: (_, value) async { saved = value; },
    clientFactory: () => MockClient(handle),
    openBrowser: (value) async {
      browserUrl = Uri.parse(value);
      if (cancelBrowser) { oauth.cancel(server); return true; }
      final params = browserUrl!.queryParameters;
      expect(params['resource'], resourceId);
      expect(params['code_challenge_method'], 'S256');
      final callback = Uri.parse(params['redirect_uri']!);
      final client = HttpOverrides.runWithHttpOverrides(() => IOClient(HttpClient()), _RealHttpOverrides());
      try {
        final invalid = await client.get(callback.replace(queryParameters: {'state': '伪造状态', 'code': 'stolen'}));
        expect(invalid.statusCode, 400);
        await client.get(callback.replace(queryParameters: {'state': params['state']!, 'code': 'accepted', 'iss': 'https://issuer.example'}));
      } finally { client.close(); }
      return true;
    },
  );

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/mcp') return http.Response('', 401, headers: {'www-authenticate': 'Bearer resource_metadata="https://resource.example/.well-known/oauth-protected-resource/mcp"'});
    if (request.url.path.startsWith('/.well-known/oauth-protected-resource')) {
      return json({'resource': resourceId, 'authorization_servers': ['https://issuer.example'], 'scopes_supported': ['files:read']});
    }
    if (request.url.path == '/.well-known/oauth-authorization-server') return http.Response('', 404);
    if (request.url.path == '/.well-known/openid-configuration') return json({
      'issuer': wrongIssuer ? 'https://wrong.example' : 'https://issuer.example',
      'authorization_endpoint': 'https://login.example/authorize',
      'token_endpoint': 'https://issuer.example/token',
      'registration_endpoint': 'https://issuer.example/register',
      'code_challenge_methods_supported': pkce ? ['S256'] : ['plain'],
      'token_endpoint_auth_methods_supported': [authMethod],
    });
    if (request.url.path == '/register') {
      expect(jsonDecode(request.body)['redirect_uris'].single, startsWith('http://127.0.0.1:'));
      expect(jsonDecode(request.body)['token_endpoint_auth_method'], authMethod);
      return json({'client_id': 'registered', 'token_endpoint_auth_method': authMethod, if (authMethod != 'none') 'client_secret': 'registered-secret'});
    }
    if (request.url.path == '/token') {
      final body = request.bodyFields;
      if (authMethod == 'client_secret_post') expect(body['client_secret'], 'registered-secret');
      if (authMethod == 'client_secret_basic') expect(request.headers['authorization'], 'Basic '+base64Encode(utf8.encode('registered:registered-secret')));
      expect(body['resource'], resourceId);
      if (body['grant_type'] == 'refresh_token') {
        refreshes++;
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        await refreshGate?.future;
        if (invalidGrant) return json({'error': 'invalid_grant'}, 400);
        return json({'access_token': 'rotated', 'refresh_token': 'refresh2', 'token_type': 'Bearer', 'expires_in': 3600});
      }
      expect(body['code'], 'accepted');
      expect(base64Url.encode(sha256.convert(ascii.encode(body['code_verifier']!)).bytes).replaceAll('=', ''), browserUrl!.queryParameters['code_challenge']);
      return json({'access_token': 'initial', 'refresh_token': 'refresh1', 'token_type': 'Bearer', 'expires_in': 3600});
    }
    throw StateError('意外的请求路径');
  }

  http.Response json(Map value, [int status = 200]) => http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'});
}

void main() {

  test('标准资源发现、OpenID 回退、跨域授权端点及 PKCE 回调完整贯通', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    expect(f.oauth.status(server), McpOAuthStatus.authorized);
    final headers = await f.oauth.headers(server, {'authorization': 'obsolete', 'X-Test': 'ok'});
    expect(headers, {'Authorization': 'Bearer initial', 'X-Test': 'ok'});
    expect(server.extraFields.toString(), isNot(contains('initial')));
  });

  test('并发刷新合并，刷新令牌轮换保留并持久化', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    f.oauth.rejected(Uri.parse(server.url), {'Authorization': 'Bearer initial'}, null);
    final results = await Future.wait(List.generate(8, (_) => f.oauth.headers(server, {})));
    expect(f.refreshes, 1);
    expect(results.every((h) => h['Authorization'] == 'Bearer rotated'), isTrue);
    expect(f.saved!['refresh_token'], 'refresh2');
  });

  test('刷新令牌被撤销后停止自动刷新，明确要求重新授权', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    f.invalidGrant = true;
    f.oauth.rejected(Uri.parse(server.url), {'Authorization': 'Bearer initial'}, null);
    await expectLater(f.oauth.headers(server, {}), throwsA(isA<McpOAuthRequiredException>()));
    await expectLater(f.oauth.headers(server, {}), throwsA(isA<McpOAuthRequiredException>()));
    expect(f.refreshes, 1);
    expect(f.oauth.status(server), McpOAuthStatus.expired);
  });

  test('身份验证拒绝仅重试一次，不产生无限重放', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    var attempts = 0;
    await expectLater(f.oauth.request<void>(server, {}, (headers) async {
      attempts++;
      f.oauth.rejected(Uri.parse(server.url), headers, null);
      throw const McpOAuthRequiredException();
    }), throwsA(isA<McpOAuthRequiredException>()));
    expect(attempts, 2);
    expect(f.refreshes, 1);
    await expectLater(f.oauth.headers(server, {}), throwsA(isA<McpOAuthRequiredException>()));
    expect(f.refreshes, 1);
  });

  test('清除授权阻止进行中的刷新重新写回凭证', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    f.refreshGate = Completer<void>();
    f.oauth.rejected(Uri.parse(server.url), {'Authorization': 'Bearer initial'}, null);
    final refresh = f.oauth.headers(server, {});
    final assertion = expectLater(refresh, throwsA(isA<McpOAuthRequiredException>()));
    await f.refreshStarted.future.timeout(const Duration(seconds: 2));
    final forgotten = f.oauth.forget(server);
    f.refreshGate!.complete();
    await assertion;
    await forgotten;
    expect(f.saved, isNull);
    expect(f.oauth.status(server), McpOAuthStatus.required);
  });

  test('拒绝缺少 S256 或身份不匹配的授权服务器', () async {
    for (final f in [Fixture()..pkce = false, Fixture()..wrongIssuer = true]) {
      await expectLater(f.oauth.authorize(server), throwsA(isA<McpOAuthRequiredException>()));
      expect(f.browserUrl, isNull);
      expect(f.saved, isNull);
    }
  });

  test('取消浏览器授权会结束等待且不保存凭证', () async {
    final f = Fixture()..cancelBrowser = true;
    await expectLater(f.oauth.authorize(server), throwsA(isA<McpOAuthRequiredException>()));
    expect(f.saved, isNull);
    expect(f.oauth.status(server), McpOAuthStatus.required);
  });

  test('更换资源或客户端不会复用原来的授权', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    final changed = server.copyWith(url: 'https://other.example/mcp');
    expect(f.oauth.status(changed), McpOAuthStatus.required);
    expect(changed.oauthKey, isNot(server.oauthKey));
    expect(server.copyWith(name: '改名').oauthKey, server.oauthKey);
  });

  test('健康检查将 HTTP 401 分类为身份验证失败', () async {
    final service = DefaultMcpToolDiscoveryService(client: MockClient((_) async => http.Response('', 401)));
    final result = await service.checkHealth(server.copyWith(extraFields: {}));
    expect(result.requiresAuthorization, isTrue);
    expect(result.isHealthy, isFalse);
    service.dispose();
  });
  test('使用服务声明的规范资源标识进行授权和刷新', () async {
    final f = Fixture()..resourceId = 'https://resource.example';
    await f.oauth.authorize(server);
    f.oauth.rejected(Uri.parse(server.url), {'Authorization': 'Bearer initial'}, null);
    await f.oauth.headers(server, {});
    expect(f.saved!['resource'], f.resourceId);
  });

  test('拒绝指向其他来源的资源声明', () async {
    final f = Fixture()..resourceId = 'https://other.example';
    await expectLater(f.oauth.authorize(server), throwsA(isA<McpOAuthRequiredException>()));
    expect(f.browserUrl, isNull);
  });

  test('兼容自动注册返回的两种客户端密钥鉴权方式', () async {
    for (final method in ['client_secret_post', 'client_secret_basic']) {
      final f = Fixture()..authMethod = method;
      await f.oauth.authorize(server);
      expect(f.oauth.status(server), McpOAuthStatus.authorized);
    }
  });

  test('SSE 消息端点跨来源时不会泄露原始凭证', () async {
    final events = StreamController<List<int>>();
    var posts = 0;
    final client = MockClient.streaming((request, body) async {
      if (request.method == 'GET') {
        scheduleMicrotask(() => events.add(utf8.encode('event: endpoint\\ndata: https://messages.example/rpc\\n\\n')));
        return http.StreamedResponse(events.stream, 200, headers: {'content-type': 'text/event-stream'}, request: request);
      }
      posts++;
      expect(request.url.host, 'messages.example');
      expect(request.headers['authorization'], isNull);
      return http.StreamedResponse(const Stream.empty(), 401, request: request);
    });
    final service = DefaultMcpToolDiscoveryService(client: client);
    try {
      final result = await service.checkHealth(server.copyWith(type: McpServerType.sse, extraFields: {}, headers: {'Authorization': 'Bearer private'}));
      expect(result.requiresAuthorization, isTrue);
      expect(posts, 1);
    } finally {
      service.dispose();
      client.close();
      await events.close();
    }
  });

  testWidgets('授权卡片在窄屏与宽屏均无溢出，状态及动作可见', (tester) async {
    final fontPath = Platform.environment['OPENHAND_TEST_FONT'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('测试字体')..addFont(File(fontPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
        final iconPath = Platform.environment['OPENHAND_TEST_ICON_FONT'];
        if (iconPath != null) {
          await (FontLoader('MaterialIcons')..addFont(File(iconPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
        }
      });
    }
    final f = Fixture();
    f.saved = {'access_token': 'valid', 'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch};
    await f.oauth.load(server);
    for (final width in [360.0, 820.0]) {
      await tester.binding.setSurfaceSize(Size(width, 500));
      await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: fontPath == null ? null : '测试字体'), home: Scaffold(body: RepaintBoundary(
        key: const ValueKey('截图'), child: Padding(padding: const EdgeInsets.all(16),
          child: McpOAuthPanel(server: server, service: f.oauth),
        ),
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('OAuth · 授权有效'), findsOneWidget);
      expect(find.text('重新授权'), findsOneWidget);
      if (width == 820 && fontPath != null) {
        await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('截图')));
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        await File('/tmp/openhand-oauth-panel.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        });
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
}
''';
