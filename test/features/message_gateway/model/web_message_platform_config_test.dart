import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  group('WebMessagePlatformConfig.normalized', () {
    test('clamps direct constructor values before runtime use', () {
      final normalized = const WebMessagePlatformConfig(
        description: '',
        listenHost: '',
        listenPort: 999999,
        username: '',
        maxConcurrentRequests: 0,
        singleMessageTokenLimit: 1,
        maxMessagesPerSession: 999999,
        workspaceFileMaxBytes: 1,
        workspaceFileAllowedExtensions: <String>[
          ' TXT ',
          '.md',
          '../unsafe',
          '',
        ],
        uploadCacheRetentionDays: 9999,
        uploadCacheMaxBytes: 1,
        healthCheck: WebGatewayHealthCheckConfig(
          path: '',
          method: '',
          queryParameters: <String, String>{' keep ': ' value '},
          timeoutMs: 1,
          expectedStatusCode: 99,
          responseContains: ' ok ',
        ),
        logConfig: WebGatewayLogConfig(
          fileMaxBytes: 1,
          rotationDays: 999,
          maxFiles: 999,
          levels: <String>[' info ', 'INFO', '', 'warn'],
          lazyReadPageSize: 999999,
        ),
      ).normalized();

      expect(
        normalized.description,
        WebMessagePlatformConfig.defaultDescription,
      );
      expect(normalized.listenHost, '0.0.0.0');
      expect(normalized.listenPort, kWebGatewayMaxListenPort);
      expect(normalized.username, 'openhand');
      expect(
        normalized.maxConcurrentRequests,
        kWebGatewayMinConcurrentRequests,
      );
      expect(
        normalized.singleMessageTokenLimit,
        kWebGatewayMinSingleMessageTokenLimit,
      );
      expect(
        normalized.maxMessagesPerSession,
        kWebGatewayMaxMessagesPerSession,
      );
      expect(
        normalized.workspaceFileMaxBytes,
        kWebGatewayMinWorkspaceFileMaxBytes,
      );
      expect(normalized.workspaceFileAllowedExtensions, const <String>[
        '.txt',
        '.md',
        '.unsafe',
      ]);
      expect(
        normalized.uploadCacheRetentionDays,
        kWebGatewayMaxUploadCacheRetentionDays,
      );
      expect(normalized.uploadCacheMaxBytes, kWebGatewayMinUploadCacheMaxBytes);
      expect(normalized.healthCheck.path, '/api/health');
      expect(normalized.healthCheck.method, 'GET');
      expect(normalized.healthCheck.timeoutMs, kWebGatewayMinHealthTimeoutMs);
      expect(
        normalized.healthCheck.expectedStatusCode,
        kWebGatewayMinHealthStatusCode,
      );
      expect(normalized.healthCheck.queryParameters, const <String, String>{
        'keep': 'value',
      });
      expect(normalized.healthCheck.responseContains, 'ok');
      expect(normalized.logConfig.fileMaxBytes, kWebGatewayMinLogFileMaxBytes);
      expect(normalized.logConfig.rotationDays, kWebGatewayMaxLogRotationDays);
      expect(normalized.logConfig.maxFiles, kWebGatewayMaxLogMaxFiles);
      expect(
        normalized.logConfig.lazyReadPageSize,
        kWebGatewayMaxLogLazyReadPageSize,
      );
      expect(normalized.logConfig.levels, const <String>['info', 'warn']);
    });

    test('toJson emits normalized nested config values', () {
      final json = const WebMessagePlatformConfig(
        listenPort: -1,
        healthCheck: WebGatewayHealthCheckConfig(timeoutMs: 999999),
        logConfig: WebGatewayLogConfig(maxFiles: 0),
      ).toJson();

      expect(json['listen_port'], kWebGatewayMinListenPort);
      expect(
        (json['health_check'] as Map<String, Object?>)['timeout_ms'],
        kWebGatewayMaxHealthTimeoutMs,
      );
      expect(
        (json['log_config'] as Map<String, Object?>)['max_files'],
        kWebGatewayMinLogMaxFiles,
      );
    });
  });
}
