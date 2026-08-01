import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/model/plugin_info.dart';
import 'package:openhand/features/plugin_service/service/plugin_scanner_service.dart';

void main() {
  test('插件目录包含服务依赖的 PostgreSQL 与 Redis', () {
    final plugins = PluginScannerService.knownPluginPlaceholders();
    final postgresql = plugins.firstWhere(
      (plugin) => plugin.id == PluginCatalogIds.postgresql,
    );
    final redis = plugins.firstWhere(
      (plugin) => plugin.id == PluginCatalogIds.redis,
    );

    expect(postgresql.name, 'PostgreSQL');
    expect(redis.name, 'Redis');
    expect(postgresql.supportsInstall, isFalse);
    expect(redis.supportsInstall, isFalse);
    expect(postgresql.supportsUninstall, isFalse);
    expect(redis.supportsUninstall, isFalse);
    expect(postgresql.metadata['external_service'], isTrue);
    expect(redis.metadata['external_service'], isTrue);
  });
}
