import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  group('WebMessagePlatformConfig', () {
    test('normalized clamps numeric limits with shared range policy', () {
      const config = WebMessagePlatformConfig(
        listenPort: -1,
        maxConcurrentRequests: 999999,
        singleMessageTokenLimit: 1,
        maxMessagesPerSession: 999999,
        workspaceFileMaxBytes: 1,
        uploadCacheRetentionDays: 999,
        uploadCacheMaxBytes: 1,
        healthCheck: WebGatewayHealthCheckConfig(
          timeoutMs: 1,
          expectedStatusCode: 999,
        ),
        logConfig: WebGatewayLogConfig(
          fileMaxBytes: 1,
          rotationDays: 999,
          maxFiles: 999,
          lazyReadPageSize: 1,
        ),
      );

      final normalized = config.normalized();

      expect(normalized.listenPort, kWebGatewayMinListenPort);
      expect(
        normalized.maxConcurrentRequests,
        kWebGatewayMaxConcurrentRequests,
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
      expect(
        normalized.uploadCacheRetentionDays,
        kWebGatewayMaxUploadCacheRetentionDays,
      );
      expect(normalized.uploadCacheMaxBytes, kWebGatewayMinUploadCacheMaxBytes);
      expect(normalized.healthCheck.timeoutMs, kWebGatewayMinHealthTimeoutMs);
      expect(
        normalized.healthCheck.expectedStatusCode,
        kWebGatewayMaxHealthStatusCode,
      );
      expect(normalized.logConfig.fileMaxBytes, kWebGatewayMinLogFileMaxBytes);
      expect(normalized.logConfig.rotationDays, kWebGatewayMaxLogRotationDays);
      expect(normalized.logConfig.maxFiles, kWebGatewayMaxLogMaxFiles);
      expect(
        normalized.logConfig.lazyReadPageSize,
        kWebGatewayMinLogLazyReadPageSize,
      );
    });

    test('fromJson falls back and normalizes malformed lists', () {
      final config = WebMessagePlatformConfig.fromJson(<String, Object?>{
        'listen_port': 'bad',
        'workspace_file_allowed_extensions': ' .TXT, png;../bad ',
        'allowed_message_types': <Object?>['text', 'unknown'],
        'allowed_conversation_modes': <Object?>['normal', 'bad'],
      });

      expect(config.listenPort, kWebGatewayDefaultListenPort);
      expect(config.workspaceFileAllowedExtensions, <String>[
        '.txt',
        '.png',
        '.bad',
      ]);
      expect(config.allowedMessageTypes, <WebGatewayMessageType>{
        WebGatewayMessageType.text,
      });
      expect(config.allowedConversationModes, <WebGatewayConversationMode>{
        WebGatewayConversationMode.normal,
      });
    });
  });
}
