import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_gateway_runtime.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  test('traffic sample round-trips every bounded minute metric', () {
    final sample = WebGatewayTrafficSample(
      minute: DateTime.utc(2026, 7, 15, 9, 30),
      success: 12,
      blocked: 2,
      failed: 1,
      inboundBytes: 2048,
      outboundBytes: 4096,
      avgLatencyMs: 48,
      p95LatencyMs: 120,
    );

    final restored = WebGatewayTrafficSample.fromJson(sample.toJson());

    expect(restored.minute, sample.minute);
    expect(restored.total, 15);
    expect(restored.inboundBytes, 2048);
    expect(restored.outboundBytes, 4096);
    expect(restored.avgLatencyMs, 48);
    expect(restored.p95LatencyMs, 120);
  });

  test('runtime snapshot preserves MCP-parity operations metrics', () {
    final snapshot = WebGatewayRuntimeSnapshot.fromJson(<String, Object?>{
      'state': 'running',
      'active_requests': 2,
      'current_connections': 5,
      'total_requests': 20,
      'total_errors': 6,
      'blocked_requests': 4,
      'file_mutation_count': 3,
      'ip_distribution': <String, int>{'127.0.0.1': 10},
      'peer_distribution': <String, int>{'127.0.0.1:52140': 10},
      'client_distribution': <String, int>{
        'Chrome 138.0.0.0 · macOS 10.15.7': 8,
      },
      'request_distribution': <String, int>{'/api/sessions/:sessionId': 7},
      'protocol_distribution': <String, int>{'HTTP': 9, 'SSE': 1},
      'traffic_series': <Map<String, Object?>>[
        WebGatewayTrafficSample(
          minute: DateTime.utc(2026, 7, 15, 9, 30),
          success: 8,
          blocked: 1,
          failed: 1,
        ).toJson(),
      ],
    });

    final restored = WebGatewayRuntimeSnapshot.fromJson(snapshot.toJson());

    expect(restored.currentConnections, 5);
    expect(restored.successTotal, 14);
    expect(restored.effectiveBlockedTotal, 4);
    expect(restored.failedRequests, 2);
    expect(restored.fileMutationCount, 3);
    expect(restored.ipDistribution, <String, int>{'127.0.0.1': 10});
    expect(restored.peerDistribution, <String, int>{'127.0.0.1:52140': 10});
    expect(restored.effectivePeerDistribution, restored.peerDistribution);
    expect(restored.clientDistribution, <String, int>{
      'Chrome 138.0.0.0 · macOS 10.15.7': 8,
    });
    expect(restored.requestDistribution, <String, int>{
      '/api/sessions/:sessionId': 7,
    });
    expect(restored.protocolDistribution, <String, int>{'HTTP': 9, 'SSE': 1});
    expect(restored.trafficSeries.single.total, 10);
  });

  test(
    'legacy and inconsistent snapshots fall back without negative totals',
    () {
      final snapshot = WebGatewayRuntimeSnapshot.fromJson(<String, Object?>{
        'active_requests': 2,
        'active_sse_subscriptions': 3,
        'total_requests': 10,
        'total_errors': 12,
        'blocked_requests': 20,
        'ip_distribution': <String, int>{'127.0.0.1': 8, '::1': 2},
      });

      expect(snapshot.currentConnections, 5);
      expect(snapshot.successTotal, 0);
      expect(snapshot.effectiveBlockedTotal, 10);
      expect(snapshot.failedRequests, 0);
      expect(snapshot.peerDistribution, <String, int>{
        '127.0.0.1:*': 8,
        '[::1]:*': 2,
      });
      expect(snapshot.effectivePeerDistribution, snapshot.peerDistribution);
      expect(snapshot.trafficSeries, isEmpty);
    },
  );

  test('runtime snapshot bounds persisted traffic history to 12 minutes', () {
    final rows = List<Map<String, Object?>>.generate(
      20,
      (index) => WebGatewayTrafficSample(
        minute: DateTime.utc(2026, 7, 15, 9, index),
        success: index,
      ).toJson(),
    );

    final snapshot = WebGatewayRuntimeSnapshot.fromJson(<String, Object?>{
      'traffic_series': rows,
    });

    expect(
      snapshot.trafficSeries,
      hasLength(webGatewayOpsTrafficWindowMinutes),
    );
    expect(snapshot.trafficSeries.first.success, 8);
    expect(snapshot.trafficSeries.last.success, 19);
  });

  test('metric route normalization bounds dynamic and asset cardinality', () {
    expect(
      webGatewayNormalizeMetricRoute(
        '/api/sessions/thread-123/messages/message-456/feedback',
      ),
      '/api/sessions/:sessionId/messages/:messageId/feedback',
    );
    expect(
      webGatewayNormalizeMetricRoute(
        '/api/sessions/thread-123/write-approvals/approval-456',
      ),
      '/api/sessions/:sessionId/write-approvals/:approvalId',
    );
    expect(
      webGatewayNormalizeMetricRoute('/chunks/index-abcd1234.js'),
      '/chunks/:asset',
    );
    expect(
      webGatewayNormalizeMetricRoute('/threads/thread-123'),
      '/threads/:threadId',
    );
  });

  test('distribution compaction emits one consistent other bucket', () {
    final compacted = webGatewayCompactDistribution(<String, int>{
      'a': 10,
      'b': 9,
      'c': 8,
      'd': 7,
      'e': 6,
      'other': 5,
      '其他': 4,
    }, otherLabel: '其他');

    expect(compacted, hasLength(5));
    expect(compacted.where((entry) => entry.key == '其他'), hasLength(1));
    expect(compacted.last.key, '其他');
    expect(compacted.last.value, 15);
    expect(compacted.fold<int>(0, (sum, entry) => sum + entry.value), 49);
  });

  test('snapshot parsing bounds untrusted distribution cardinality', () {
    final values = <String, int>{
      for (var index = 0; index < 300; index++) 'client-$index': 1,
    };
    final peers = <String, int>{
      for (var index = 0; index < 300; index++) '127.0.0.1:${10000 + index}': 1,
    };

    final snapshot = WebGatewayRuntimeSnapshot.fromJson(<String, Object?>{
      'client_distribution': values,
      'peer_distribution': peers,
    });

    expect(snapshot.clientDistribution, hasLength(256));
    expect(snapshot.clientDistribution['other'], 45);
    expect(snapshot.peerDistribution, hasLength(128));
    expect(snapshot.peerDistribution['other'], 173);
  });

  test('blocked status classification matches access and capacity policy', () {
    expect(webGatewayIsBlockedStatusCode(401), isTrue);
    expect(webGatewayIsBlockedStatusCode(403), isTrue);
    expect(webGatewayIsBlockedStatusCode(429), isTrue);
    expect(webGatewayIsBlockedStatusCode(400), isFalse);
    expect(webGatewayIsBlockedStatusCode(500), isFalse);
    expect(
      webGatewayRequestOutcomeForStatus(204),
      WebGatewayRequestOutcome.success,
    );
    expect(
      webGatewayRequestOutcomeForStatus(302),
      WebGatewayRequestOutcome.success,
    );
    expect(
      webGatewayRequestOutcomeForStatus(403),
      WebGatewayRequestOutcome.blocked,
    );
    expect(
      webGatewayRequestOutcomeForStatus(404),
      WebGatewayRequestOutcome.failed,
    );
    expect(
      webGatewayRequestOutcomeForStatus(500),
      WebGatewayRequestOutcome.failed,
    );
    expect(
      webGatewayRequestOutcomeForStatus(0),
      WebGatewayRequestOutcome.failed,
    );
    expect(
      webGatewayShouldCollectRequestMetrics(
        method: 'GET',
        path: '/api/ops',
        statusCode: 200,
      ),
      isFalse,
    );
    expect(
      webGatewayShouldCollectRequestMetrics(
        method: 'GET',
        path: '/api/ops',
        statusCode: 401,
      ),
      isTrue,
    );
  });

  test('web tablet login source keeps client telemetry identity', () {
    expect(
      WebGatewayLoginSource.fromStorage('WEB_TABLET'),
      WebGatewayLoginSource.webTablet,
    );
  });

  test('source endpoint includes ports and brackets IPv6 safely', () {
    expect(
      webGatewayFormatRemoteEndpoint('127.0.0.1', 52140),
      '127.0.0.1:52140',
    );
    expect(webGatewayFormatRemoteEndpoint('::1', 52140), '[::1]:52140');
    expect(webGatewayFormatRemoteEndpoint('10.0.0.8', 0), '10.0.0.8');
    expect(webGatewayFormatRemoteEndpoint('', 52140), 'unknown');
  });

  test('client UA summary keeps browser and operating system versions', () {
    expect(
      webGatewaySummarizeClientUserAgent(
        userAgent:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/138.0.0.0 Safari/537.36',
      ),
      'Chrome 138.0.0.0 · macOS 10.15.7',
    );
    expect(
      webGatewaySummarizeClientUserAgent(
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 Chrome/138.0.0.0 Safari/537.36 '
            'Edg/138.0.0.0',
      ),
      'Edge 138.0.0.0 · Windows NT 10.0',
    );
    expect(
      webGatewaySummarizeClientUserAgent(
        userAgent: '',
        browserName: 'Firefox',
        browserVersion: '140.0',
        osName: 'Linux',
      ),
      'Firefox 140.0 · Linux',
    );
  });
}
