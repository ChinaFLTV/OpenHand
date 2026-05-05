import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  group('WebMessagePlatformConfig runtime apply flags', () {
    test('默认开启冷启动自启动与配置自动重载', () {
      const config = WebMessagePlatformConfig();

      expect(config.autoStartOnLaunch, isTrue);
      expect(config.autoReloadOnChange, isTrue);
    });

    test('JSON 兼容旧配置，显式 false 才关闭', () {
      final implicit = WebMessagePlatformConfig.fromJson(
        const <String, Object?>{},
      );
      final explicit = WebMessagePlatformConfig.fromJson(
        const <String, Object?>{
          'auto_start_on_launch': false,
          'auto_reload_on_change': false,
        },
      );

      expect(implicit.autoStartOnLaunch, isTrue);
      expect(implicit.autoReloadOnChange, isTrue);
      expect(explicit.autoStartOnLaunch, isFalse);
      expect(explicit.autoReloadOnChange, isFalse);
      expect(explicit.toJson()['auto_start_on_launch'], isFalse);
      expect(explicit.toJson()['auto_reload_on_change'], isFalse);
    });
  });

  group('WebMessagePlatformConfig workspace files', () {
    test('默认开放浏览读取，但默认不支持文件操作', () {
      const config = WebMessagePlatformConfig();

      expect(config.workspaceFilesEnabled, isTrue);
      expect(config.workspaceFileWriteEnabled, isFalse);
    });

    test('JSON 未声明操作权限时保持默认 false，显式 true 才开启', () {
      final implicit = WebMessagePlatformConfig.fromJson(
        const <String, Object?>{},
      );
      final explicit = WebMessagePlatformConfig.fromJson(
        const <String, Object?>{'workspace_file_write_enabled': true},
      );

      expect(implicit.workspaceFilesEnabled, isTrue);
      expect(implicit.workspaceFileWriteEnabled, isFalse);
      expect(explicit.workspaceFileWriteEnabled, isTrue);
      expect(explicit.toJson()['workspace_file_write_enabled'], isTrue);
    });
  });
}
