import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/service/ai_exposure_proxy_probe.dart';

void main() {
  group('代理配置', () {
    test('兼容旧版字符串节点配置', () {
      final configuration = AiExposureProxyConfiguration.fromJson(
        <String, Object?>{
          'enabled': true,
          'strategy': 'random',
          'rotationEvery': 3,
          'endpoints': <String>['127.0.0.1:8080'],
        },
      );

      expect(configuration.enabled, isTrue);
      expect(configuration.strategy, AiExposureProxyStrategy.random);
      expect(configuration.endpoints.single.url, 'http://127.0.0.1:8080');
      expect(configuration.endpoints.single.enabled, isTrue);
      expect(configuration.inspectionConcurrency, 8);
    });

    test('运行时仅提交启用节点', () {
      final configuration = AiExposureProxyConfiguration(
        enabled: true,
        strategy: AiExposureProxyStrategy.roundRobin,
        rotationEvery: 1,
        bypassLocal: true,
        endpoints: <AiExposureProxyEndpoint>[
          AiExposureProxyEndpoint.parse('127.0.0.1:8080'),
          AiExposureProxyEndpoint.parse(
            '127.0.0.2:8081',
          ).copyWith(enabled: false),
        ],
        inspectionEnabled: true,
        inspectionIntervalMinutes: 15,
      );

      expect(configuration.toRuntimeJson()['endpoints'], <String>[
        'http://127.0.0.1:8080',
      ]);
      expect(configuration.toJson()['inspectionEnabled'], isTrue);
    });

    test('保留节点名称与可配置巡检并发数', () {
      final endpoint = AiExposureProxyEndpoint.parse(
        '127.0.0.1:8080',
      ).copyWith(name: '本地节点');
      final configuration = AiExposureProxyConfiguration(
        enabled: false,
        strategy: AiExposureProxyStrategy.fixed,
        rotationEvery: 1,
        bypassLocal: true,
        endpoints: <AiExposureProxyEndpoint>[endpoint],
        inspectionConcurrency: 16,
      );
      final restored = AiExposureProxyConfiguration.fromJson(
        configuration.toJson(),
      );
      expect(restored.inspectionConcurrency, 16);
      expect(restored.endpoints.single.name, '本地节点');
      expect(restored.endpoints.single.displayName, '本地节点');
    });

    test('延迟历史保持固定上限', () {
      var endpoint = AiExposureProxyEndpoint.parse('127.0.0.1:8080');
      for (
        var index = 0;
        index < kAiExposureProxyLatencySampleLimit + 5;
        index++
      ) {
        endpoint = endpoint.withSample(
          AiExposureProxyProbeSample(
            checkedAt: DateTime.utc(2026, 8, 2, 0, 0, index),
            latencyMs: index,
            statusCode: 204,
          ),
        );
      }

      expect(endpoint.samples, hasLength(kAiExposureProxyLatencySampleLimit));
      expect(endpoint.samples.first.latencyMs, 5);
      expect(endpoint.samples.last.latencyMs, 28);
    });

    test('服务偏好保留巡检配置与历史', () {
      final defaults = AiExposurePreferences.defaults();
      final endpoint =
          AiExposureProxyEndpoint.parse(
            'user:secret@127.0.0.1:8080',
          ).withSample(
            AiExposureProxyProbeSample(
              checkedAt: DateTime.utc(2026, 8, 2),
              latencyMs: 86,
              statusCode: 204,
            ),
          );
      final preferences = AiExposurePreferences(
        enabledSources: defaults.enabledSources,
        defaultConcurrency: defaults.defaultConcurrency,
        defaultValidationMode: defaults.defaultValidationMode,
        defaultGptAssisted: defaults.defaultGptAssisted,
        useBundledEngine: defaults.useBundledEngine,
        externalAddress: defaults.externalAddress,
        proxyConfiguration: AiExposureProxyConfiguration(
          enabled: true,
          strategy: AiExposureProxyStrategy.fixed,
          rotationEvery: 1,
          bypassLocal: true,
          endpoints: <AiExposureProxyEndpoint>[endpoint],
          inspectionEnabled: true,
        ),
      );

      final restored = AiExposurePreferences.fromJson(preferences.toJson());
      expect(restored.proxyConfiguration.inspectionEnabled, isTrue);
      expect(
        restored.proxyConfiguration.endpoints.single.latestSample?.latencyMs,
        86,
      );
      expect(
        restored.proxyConfiguration.endpoints.single.maskedUrl,
        'http://user:******@127.0.0.1:8080',
      );
    });
  });

  test('代理探测记录真实响应延迟并发送认证头', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requestHead = Completer<String>();
    server.listen((socket) {
      final received = <int>[];
      socket.listen((chunk) async {
        received.addAll(chunk);
        final text = ascii.decode(received, allowInvalid: true);
        if (!text.contains('\r\n\r\n') || requestHead.isCompleted) return;
        requestHead.complete(text);
        socket.add(ascii.encode('HTTP/1.1 204 No Content\r\n\r\n'));
        await socket.flush();
        await socket.close();
      });
    });

    try {
      final endpoint = AiExposureProxyEndpoint.parse(
        'user:secret@127.0.0.1:${server.port}',
      );
      final sample = await const AiExposureProxyProbe().inspect(endpoint);

      expect(sample.reachable, isTrue);
      expect(sample.statusCode, 204);
      expect(sample.latencyMs, isNotNull);
      expect(
        await requestHead.future,
        contains(
          'Proxy-Authorization: Basic ${base64Encode(utf8.encode('user:secret'))}',
        ),
      );
    } finally {
      await server.close();
    }
  });
}
