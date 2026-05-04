import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  test('workspace file policy keeps backward-compatible defaults', () {
    const config = WebMessagePlatformConfig();

    expect(config.workspaceFilesEnabled, isTrue);
    expect(config.workspaceFileWriteEnabled, isTrue);
    expect(config.workspaceFileMaxBytes, 1024 * 1024);
    expect(config.workspaceFileAllowedExtensions, isEmpty);
  });

  test('workspace file policy round-trips through json', () {
    const config = WebMessagePlatformConfig(
      workspaceFilesEnabled: false,
      workspaceFileWriteEnabled: false,
      workspaceFileMaxBytes: 2 * 1024 * 1024,
      workspaceFileAllowedExtensions: <String>['.dart', '.md'],
    );

    final decoded = WebMessagePlatformConfig.fromJson(config.toJson());

    expect(decoded.workspaceFilesEnabled, isFalse);
    expect(decoded.workspaceFileWriteEnabled, isFalse);
    expect(decoded.workspaceFileMaxBytes, 2 * 1024 * 1024);
    expect(decoded.workspaceFileAllowedExtensions, <String>['.dart', '.md']);
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
