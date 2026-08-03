import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/service/ai_exposure_proxy_probe.dart';

void main() {
  test('CONNECT 成功时记录网关与转发均可用', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requests = _serveProxy(server, const <String?>[
      'HTTP/1.1 200 Connection Established\r\n\r\n',
    ]);

    final sample = await const AiExposureProxyProbe().inspect(
      AiExposureProxyEndpoint.parse(
        'http://user:pass@127.0.0.1:${server.port}',
      ),
    );
    final received = await requests;

    expect(sample.reachable, isTrue);
    expect(sample.gatewayReachable, isTrue);
    expect(sample.statusCode, 200);
    expect(received.single, startsWith('CONNECT cp.cloudflare.com:443'));
    expect(
      received.single,
      contains('Proxy-Authorization: Basic dXNlcjpwYXNz'),
    );
  });

  test('407 响应明确归类为认证失败', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requests = _serveProxy(server, const <String?>[
      'HTTP/1.1 407 Proxy Authentication Required\r\n\r\n',
    ]);

    final sample = await const AiExposureProxyProbe().inspect(
      AiExposureProxyEndpoint.parse('http://127.0.0.1:${server.port}'),
    );
    await requests;

    expect(sample.reachable, isFalse);
    expect(sample.gatewayReachable, isTrue);
    expect(sample.statusCode, 407);
    expect(sample.failure, AiExposureProxyProbeFailure.authentication);
    expect(sample.error, contains('代理认证失败'));
  });

  test('空响应保留网关可达结论并归类为协议失败', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requests = _serveProxy(server, const <String?>[null, null]);

    final sample = await const AiExposureProxyProbe().inspect(
      AiExposureProxyEndpoint.parse('http://127.0.0.1:${server.port}'),
    );
    await requests;

    expect(sample.reachable, isFalse);
    expect(sample.gatewayReachable, isTrue);
    expect(sample.failure, AiExposureProxyProbeFailure.protocol);
    expect(sample.error, contains('未返回协议响应'));
  });

  test('首个探测目标被拒后使用备用目标', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requests = _serveProxy(server, const <String?>[
      'HTTP/1.1 403 Forbidden\r\n\r\n',
      'HTTP/1.1 200 Connection Established\r\n\r\n',
    ]);

    final sample = await const AiExposureProxyProbe().inspect(
      AiExposureProxyEndpoint.parse('http://127.0.0.1:${server.port}'),
    );
    final received = await requests;

    expect(sample.reachable, isTrue);
    expect(received, hasLength(2));
    expect(
      received.last,
      startsWith('CONNECT connectivitycheck.gstatic.com:443'),
    );
  });

  test('探测阶段字段可持久化并兼容旧成功样本', () {
    final sample = AiExposureProxyProbeSample(
      checkedAt: DateTime.utc(2026, 8, 3),
      gatewayReachable: true,
      failure: AiExposureProxyProbeFailure.access,
      statusCode: 403,
      error: '代理拒绝转发',
    );

    final restored = AiExposureProxyProbeSample.fromJson(sample.toJson());
    final legacy = AiExposureProxyProbeSample.fromJson(<String, Object?>{
      'checkedAt': '2026-08-03T00:00:00.000Z',
      'latencyMs': 42,
      'statusCode': 204,
    });
    final legacyFailure = AiExposureProxyProbeSample.fromJson(<String, Object?>{
      'checkedAt': '2026-08-03T00:00:00.000Z',
      'statusCode': 407,
      'error': '代理认证失败',
    });

    expect(restored.gatewayReachable, isTrue);
    expect(restored.failure, AiExposureProxyProbeFailure.access);
    expect(legacy.gatewayReachable, isTrue);
    expect(legacy.reachable, isTrue);
    expect(legacyFailure.gatewayReachable, isTrue);
  });
}

Future<List<String>> _serveProxy(
  ServerSocket server,
  List<String?> responses,
) async {
  final iterator = StreamIterator<Socket>(server);
  final requests = <String>[];
  try {
    for (final response in responses) {
      expect(await iterator.moveNext(), isTrue);
      final socket = iterator.current;
      final request = await socket.first.timeout(const Duration(seconds: 2));
      requests.add(utf8.decode(request));
      if (response != null) {
        socket.add(ascii.encode(response));
        await socket.flush();
      }
      socket.destroy();
    }
    return requests;
  } finally {
    await iterator.cancel();
    await server.close();
  }
}
