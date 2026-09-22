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
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http/io_client.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/service/mcp_oauth_service.dart';
import 'package:openhand/features/mcp/service/mcp_oauth_callback_page.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

const server = McpServer(name: '通用服务', type: McpServerType.streamableHttp,
  enabled: true, url: 'https://resource.example/mcp',
  extraFields: {'oauth': {'enabled': true}});

class _RealHttpOverrides extends HttpOverrides {}

class _TrackedClient extends http.BaseClient {
  _TrackedClient(this.inner);
  final http.Client inner;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => inner.send(request);
  @override
  void close() { closed = true; inner.close(); }
}

class _PanelOAuth extends McpOAuthService {
  McpOAuthStatus value = McpOAuthStatus.authorized;
  bool supportsRefresh = false;
  bool refreshing = false;
  Completer<void>? refreshGate;
  @override
  bool canRefresh(McpServer server) => supportsRefresh;
  @override
  bool isRefreshing(McpServer server) => refreshing;
  @override
  Future<void> refresh(McpServer server) async {
    refreshing = true;
    notifyListeners();
    await refreshGate?.future;
    refreshing = false;
    notifyListeners();
  }
  void update(McpOAuthStatus status) {
    value = status;
    notifyListeners();
  }
  @override
  Future<void> load(McpServer server) async {}
  @override
  McpOAuthStatus status(McpServer server) => value;
}

class Fixture {
  Map<String, dynamic>? saved;
  int refreshes = 0;
  bool invalidGrant = false;
  bool issueRefreshToken = true;
  bool rotateRefreshToken = true;
  bool refreshUnavailable = false;
  bool pkce = true;
  String authMethod = 'none';
  String resourceId = server.url;
  bool wrongIssuer = false;
  bool cancelBrowser = false;
  bool disposeBrowser = false;
  Completer<void>? refreshGate;
  final refreshStarted = Completer<void>();
  final clients = <_TrackedClient>[];
  Uri? browserUrl;
  late final McpOAuthService oauth = McpOAuthService(
    read: (_) async => saved,
    write: (_, value) async { saved = value; },
    clientFactory: () {
      final client = _TrackedClient(MockClient(handle));
      clients.add(client);
      return client;
    },
    openBrowser: (value) async {
      browserUrl = Uri.parse(value);
      if (cancelBrowser) { oauth.cancel(server); return true; }
      if (disposeBrowser) { oauth.dispose(); return true; }
      final params = browserUrl!.queryParameters;
      expect(params['resource'], resourceId);
      expect(params['code_challenge_method'], 'S256');
      final callback = Uri.parse(params['redirect_uri']!);
      final client = HttpOverrides.runWithHttpOverrides(() => IOClient(HttpClient()), _RealHttpOverrides());
      try {
        final invalid = await client.get(callback.replace(queryParameters: {'state': '伪造状态', 'code': 'stolen'}));
        expect(invalid.statusCode, 400);
        expect(invalid.headers['content-type'], contains('text/html'));
        expect(invalid.headers['cache-control'], 'no-store');
        expect(invalid.headers['referrer-policy'], 'no-referrer');
        expect(invalid.headers['content-security-policy'], contains("default-src 'none'"));
        expect(invalid.body, contains('此授权回调无效'));
        expect(invalid.body, isNot(contains('stolen')));
        final result = await client.get(callback.replace(queryParameters: {'state': params['state']!, 'code': 'accepted', 'iss': 'https://issuer.example'}));
        expect(result.body, contains('授权信息已接收'));
        expect(result.body, contains('history.replaceState'));
        expect(result.body, isNot(contains(params['state']!)));
        expect(result.body, isNot(contains('code=accepted')));
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
        if (refreshUnavailable) return json({'error': 'temporarily_unavailable'}, 503);
        if (invalidGrant) return json({'error': 'invalid_grant'}, 400);
        return json({'access_token': 'rotated', if (rotateRefreshToken) 'refresh_token': 'refresh2', 'token_type': 'Bearer', 'expires_in': 3600});
      }
      expect(body['code'], 'accepted');
      expect(base64Url.encode(sha256.convert(ascii.encode(body['code_verifier']!)).bytes).replaceAll('=', ''), browserUrl!.queryParameters['code_challenge']);
      return json({'access_token': 'initial', if (issueRefreshToken) 'refresh_token': 'refresh1', 'token_type': 'Bearer', 'expires_in': 3600});
    }
    throw StateError('意外的请求路径');
  }

  http.Response json(Map value, [int status = 200]) => http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'});
}

void main() {

  test('清除授权后忽略迟到的数据库读取，不恢复旧令牌', () async {
    final reading = Completer<Map<String, dynamic>?>();
    final oauth = McpOAuthService(read: (_) => reading.future, write: (_, _) async {});
    addTearDown(oauth.dispose);
    final loading = oauth.load(server);
    await oauth.forget(server);
    reading.complete({'access_token': 'obsolete'});
    await loading;
    expect(oauth.status(server), McpOAuthStatus.required);
    await expectLater(oauth.headers(server, {}), throwsA(isA<McpOAuthRequiredException>()));
  });

  test('服务释放后拒绝迟到的读取及新操作，重复释放安全', () async {
    final reading = Completer<Map<String, dynamic>?>();
    final oauth = McpOAuthService(read: (_) => reading.future);
    final loading = oauth.load(server);
    final assertion = expectLater(loading, throwsA(isA<StateError>()));
    oauth.dispose();
    reading.complete({'access_token': 'obsolete'});
    await assertion;
    expect(oauth.status(server), McpOAuthStatus.required);
    await expectLater(oauth.load(server), throwsA(isA<StateError>()));
    await expectLater(oauth.authorize(server), throwsA(isA<StateError>()));
    await expectLater(oauth.forget(server), throwsA(isA<StateError>()));
    oauth.dispose();
  });

  test('服务释放回收刷新客户端，迟到刷新不写回凭证', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    f.refreshGate = Completer<void>();
    final refreshing = f.oauth.refresh(server);
    final assertion = expectLater(refreshing, throwsA(isA<StateError>()));
    await f.refreshStarted.future;
    expect(f.clients.last.closed, isFalse);
    f.oauth.dispose();
    expect(f.clients.every((client) => client.closed), isTrue);
    f.refreshGate!.complete();
    await assertion;
    expect(f.saved!['access_token'], 'initial');
  });

  test('等待浏览器授权时释放服务，取消回调等待并回收客户端', () async {
    final f = Fixture()..disposeBrowser = true;
    await expectLater(f.oauth.authorize(server), throwsA(isA<StateError>()));
    expect(f.clients.every((client) => client.closed), isTrue);
    expect(f.oauth.status(server), McpOAuthStatus.required);
    expect(f.saved, isNull);
  });

  test('网络客户端初始化失败不留下占用中的授权任务', () async {
    var attempts = 0;
    final oauth = McpOAuthService(clientFactory: () {
      attempts++;
      throw StateError('模拟网络初始化失败');
    });
    addTearDown(oauth.dispose);
    for (var index = 0; index < 2; index++) {
      await expectLater(oauth.authorize(server), throwsA(isA<StateError>()));
      expect(oauth.status(server), McpOAuthStatus.required);
    }
    expect(attempts, 2);
  });

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

  test('有效令牌可手动刷新，并与自动刷新合并', () async {
    final f = Fixture();
    await f.oauth.authorize(server);
    expect(f.oauth.canRefresh(server), isTrue);
    f.refreshGate = Completer<void>();
    final manual = f.oauth.refresh(server);
    await f.refreshStarted.future;
    expect(f.oauth.isRefreshing(server), isTrue);
    final duplicate = f.oauth.refresh(server);
    final automatic = f.oauth.headers(server, {});
    f.refreshGate!.complete();
    await Future.wait([manual, duplicate]);
    expect((await automatic)['Authorization'], 'Bearer rotated');
    expect(f.refreshes, 1);
    expect(f.oauth.isRefreshing(server), isFalse);
  });

  test('临近到期自动刷新，服务未轮换时保留刷新令牌', () async {
    final f = Fixture()..rotateRefreshToken = false;
    await f.oauth.authorize(server);
    f.saved!['refresh_at'] = 0;
    final restored = McpOAuthService(read: (_) async => f.saved,
      write: (_, value) async { f.saved = value; }, clientFactory: () => MockClient(f.handle));
    addTearDown(restored.dispose);
    expect((await restored.headers(server, {}))['Authorization'], 'Bearer rotated');
    expect(f.refreshes, 1);
    expect(f.saved!['refresh_token'], 'refresh1');
  });

  test('未签发刷新令牌时保留尚未到期的访问令牌并拒绝手动刷新', () async {
    final f = Fixture()..issueRefreshToken = false;
    await f.oauth.authorize(server);
    f.saved!['refresh_at'] = 0;
    final restored = McpOAuthService(read: (_) async => f.saved,
      write: (_, value) async { f.saved = value; }, clientFactory: () => MockClient(f.handle));
    addTearDown(restored.dispose);
    await restored.load(server);
    expect(restored.canRefresh(server), isFalse);
    expect((await restored.headers(server, {}))['Authorization'], 'Bearer initial');
    await expectLater(restored.refresh(server), throwsA(isA<McpOAuthRequiredException>()));
    expect(f.refreshes, 0);
  });

  test('刷新暂时失败保留有效授权，结束忙碌状态并允许重试', () async {
    final f = Fixture()..refreshUnavailable = true;
    await f.oauth.authorize(server);
    await expectLater(f.oauth.refresh(server), throwsA(isA<Exception>()));
    expect(f.oauth.isRefreshing(server), isFalse);
    expect(f.oauth.status(server), McpOAuthStatus.authorized);
    expect(f.oauth.canRefresh(server), isTrue);
    f.refreshUnavailable = false;
    await f.oauth.refresh(server);
    expect(f.refreshes, 2);
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

  test('回调页面继承主题、关闭动效并转义服务名称', () async {
    final output = Platform.environment['OPENHAND_CALLBACK_PREVIEW'];
    for (final dark in [false, true]) {
      final colors = (dark ? OpenHandTheme.dark(OpenHandThemePreset.tundraGreen) : OpenHandTheme.light(OpenHandThemePreset.tundraGreen)).colorScheme;
      final page = McpOAuthCallbackPage(colors: colors, animation: const DialogAnimationSettings(entranceStyle: DialogAnimationStyle.none, exitStyle: DialogAnimationStyle.none));
      for (final status in McpOAuthCallbackStatus.values) {
        final html = await page.render(status: status, serverName: '<script>危险名称</script>', nonce: 'nonce-test');
        expect(html, contains('--duration:0ms'));
        expect(html, contains(dark ? 'color-scheme:dark' : 'color-scheme:light'));
        expect(html, contains('&lt;script&gt;'));
        expect(html, isNot(contains('<script>危险名称</script>')));
        expect(html, isNot(contains('https://')));
        expect(html, contains('prefers-reduced-motion'));
        expect(html, isNot(contains('gradient(')));
        expect(html, contains('<img class="brand-mark" src="data:image/png;base64,'));
        if (output != null) {
          await Directory(output).create(recursive: true);
          await File(output+'/'+(dark ? 'dark' : 'light')+'-'+status.name+'.html').writeAsString(
            await McpOAuthCallbackPage(colors: colors).render(status: status, serverName: '云端工作空间 MCP', nonce: 'nonce-preview'),
          );
        }
      }
    }
  });

  testWidgets('刷新按钮按能力显示，刷新期间禁用并在成功后重连', (tester) async {
    final oauth = _PanelOAuth()..supportsRefresh = true;
    var reconnects = 0;
    for (final width in [360.0, 820.0, 1100.0]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpWidget(MaterialApp(theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
        home: Scaffold(body: McpOAuthPanel(server: server, service: oauth,
          onAuthorized: () => reconnects++))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('刷新令牌'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(FilledButton, '刷新令牌')),
        tester.getSize(find.widgetWithText(FilledButton, '重新授权')));
    }
    oauth.refreshGate = Completer<void>();
    await tester.tap(find.text('刷新令牌'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '正在刷新')).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '重新授权')).onPressed, isNull);
    oauth.refreshGate!.complete();
    await tester.pumpAndSettle();
    expect(reconnects, 1);
    oauth.supportsRefresh = false;
    oauth.update(McpOAuthStatus.expired);
    await tester.pumpAndSettle();
    expect(find.text('刷新令牌'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    oauth.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('授权操作保留退场、屏蔽旧点击，并支持快速反向与减少动态效果', (tester) async {
    final oauth = _PanelOAuth();
    Widget panel({bool reduceMotion = false, double scale = 1}) => MaterialApp(
      theme: OpenHandTheme.light(OpenHandThemePreset.tundraGreen),
      home: MediaQuery(data: MediaQueryData(disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(scale)), child: Scaffold(body:
        McpOAuthPanel(server: server, service: oauth))),
    );
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    oauth.update(McpOAuthStatus.required);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('清除本机授权'), findsOneWidget);
    expect(find.text('清除本机授权').hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('清除本机授权'), findsNothing);
    for (final status in [McpOAuthStatus.authorizing, McpOAuthStatus.authorized,
        McpOAuthStatus.authorizing, McpOAuthStatus.required]) {
      oauth.update(status);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.pumpWidget(panel(reduceMotion: true));
    oauth.update(McpOAuthStatus.authorized);
    await tester.pumpAndSettle();
    oauth.update(McpOAuthStatus.required);
    await tester.pump();
    await tester.pump();
    expect(find.text('清除本机授权'), findsNothing);
    await tester.binding.setSurfaceSize(const Size(360, 700));
    oauth.update(McpOAuthStatus.authorized);
    await tester.pumpWidget(panel(scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    oauth.dispose();
    await tester.binding.setSurfaceSize(null);
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
    final baseTheme = OpenHandTheme.light(OpenHandThemePreset.tundraGreen);
    final theme = fontPath == null ? baseTheme : baseTheme.copyWith(textTheme: baseTheme.textTheme.apply(fontFamily: '测试字体'));
    final oauth = _PanelOAuth();
    for (final supportsRefresh in [false, true]) {
    oauth.supportsRefresh = supportsRefresh;
    for (final status in [McpOAuthStatus.authorized, McpOAuthStatus.authorizing]) {
    oauth.value = status;
    for (final width in [360.0, 820.0, 1100.0]) {
      await tester.binding.setSurfaceSize(Size(width, 500));
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: RepaintBoundary(
        key: const ValueKey('截图'), child: Padding(padding: const EdgeInsets.all(16),
          child: McpOAuthPanel(server: server, service: oauth),
        ),
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final busy = status == McpOAuthStatus.authorizing;
      final title = find.text(busy ? 'OAuth · 等待浏览器授权' : 'OAuth · 授权有效');
      final subtitle = find.text(busy ? '请在系统浏览器中完成授权，完成后自动连接。' : supportsRefresh ? '支持自动刷新，也可手动更新访问令牌。' : '当前授权未提供刷新令牌，失效后需重新授权。');
      final primary = tester.getRect(find.widgetWithText(FilledButton, busy ? '授权进行中' : '重新授权'));
      final secondary = tester.getRect(find.widgetWithText(FilledButton, busy ? '取消授权' : '清除本机授权'));
      expect(primary.size, secondary.size);
      expect(primary.height, lessThanOrEqualTo(40));
      if (width >= (supportsRefresh && !busy ? 932 : 752)) {
        expect(primary.left, greaterThan(tester.getRect(subtitle).right));
        expect(primary.center.dy, closeTo((tester.getRect(title).top + tester.getRect(subtitle).bottom) / 2, 1));
        expect(primary.center.dy, secondary.center.dy);
      } else {
        expect(primary.top, greaterThan(tester.getRect(subtitle).bottom));
      }
      if (width == 1100 && fontPath != null) {
        await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('截图')));
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        await File('/tmp/openhand-oauth-panel-'+status.name+'-'+supportsRefresh.toString()+'.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        });
      }
    }
    }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    oauth.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
''';
