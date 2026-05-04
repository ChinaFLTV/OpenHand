import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  test('workspace file policy keeps backward-compatible defaults', () {
    const config = WebMessagePlatformConfig();

    expect(config.workspaceFilesEnabled, isTrue);
    expect(config.workspaceFileWriteEnabled, isTrue);
    expect(config.workspaceFileMaxBytes, 1024 * 1024);
    expect(config.workspaceFileAllowedExtensions, isEmpty);
    expect(config.sessionManagementEnabled, isTrue);
    expect(config.uploadCacheRetentionDays, 7);
    expect(config.uploadCacheMaxBytes, 512 * 1024 * 1024);
  });

  test('gateway operation policy round-trips through json', () {
    const config = WebMessagePlatformConfig(
      sessionManagementEnabled: false,
      workspaceFilesEnabled: false,
      workspaceFileWriteEnabled: false,
      workspaceFileMaxBytes: 2 * 1024 * 1024,
      workspaceFileAllowedExtensions: <String>['.dart', '.md'],
      uploadCacheRetentionDays: 14,
      uploadCacheMaxBytes: 64 * 1024 * 1024,
    );

    final decoded = WebMessagePlatformConfig.fromJson(config.toJson());

    expect(decoded.sessionManagementEnabled, isFalse);
    expect(decoded.workspaceFilesEnabled, isFalse);
    expect(decoded.workspaceFileWriteEnabled, isFalse);
    expect(decoded.workspaceFileMaxBytes, 2 * 1024 * 1024);
    expect(decoded.workspaceFileAllowedExtensions, <String>['.dart', '.md']);
    expect(decoded.uploadCacheRetentionDays, 14);
    expect(decoded.uploadCacheMaxBytes, 64 * 1024 * 1024);
  });

  test('upload cache retention and size are clamped', () {
    final low = WebMessagePlatformConfig.fromJson(<String, Object?>{
      'upload_cache_retention_days': -1,
      'upload_cache_max_bytes': 1,
    });
    final high = WebMessagePlatformConfig.fromJson(<String, Object?>{
      'upload_cache_retention_days': 365,
      'upload_cache_max_bytes': 20 * 1024 * 1024 * 1024,
    });

    expect(low.uploadCacheRetentionDays, 1);
    expect(low.uploadCacheMaxBytes, 1024 * 1024);
    expect(high.uploadCacheRetentionDays, 180);
    expect(high.uploadCacheMaxBytes, 10 * 1024 * 1024 * 1024);
  });

  test('workspace file extensions are normalized and deduplicated', () {
    final config = WebMessagePlatformConfig.fromJson(<String, Object?>{
      'workspace_file_allowed_extensions': <Object?>[
        'dart',
        '.DART',
        ' md ',
        '*.json',
        'ts-js',
        '',
      ],
    });

    expect(config.workspaceFileAllowedExtensions, <String>[
      '.dart',
      '.md',
      '.json',
      '.ts-js',
    ]);
  });
}
