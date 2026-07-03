import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  group('webGatewayNormalizeWorkspaceFileExtensions', () {
    test('normalizes mixed delimiter input and removes duplicates', () {
      expect(
        webGatewayNormalizeWorkspaceFileExtensions(
          ' .TXT, md\njsonl；bad ext;TXT; .tar-gz ',
        ),
        <String>['.txt', '.md', '.jsonl', '.badext', '.tar-gz'],
      );
    });

    test('normalizes config json extensions with the same rules', () {
      final config = WebMessagePlatformConfig.fromJson(<String, Object?>{
        'workspace_file_allowed_extensions': <String>[
          ' .TXT ',
          'txt',
          '.md!',
          '',
        ],
      });

      expect(config.workspaceFileAllowedExtensions, <String>['.txt', '.md']);
    });
  });
}
