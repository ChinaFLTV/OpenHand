import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/data/message_gateway_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late String configPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_message_gateway_store_test_',
    );
    configPath = p.join(tempDir.path, 'web_message_platform.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load normalizes persisted json config values', () async {
    await File(configPath).writeAsString('''
{
  "enabled": "yes",
  "listen_port": "8849",
  "allowed_template_ids": [" chat ", null, "", "CHAT", "agent"],
  "health_check": {
    "enabled": "no",
    "timeout_ms": "50"
  }
}
''');

    final config = await MessageGatewayStore(filePath: configPath).load();

    expect(config.enabled, isTrue);
    expect(config.listenPort, 8849);
    expect(config.allowedTemplateIds, <String>['chat', 'agent']);
    expect(config.healthCheck.enabled, isFalse);
    expect(config.healthCheck.timeoutMs, 250);
  });

  test('load falls back to default config for malformed json roots', () async {
    await File(configPath).writeAsString('[1, 2]');

    final config = await MessageGatewayStore(filePath: configPath).load();

    expect(config.enabled, isFalse);
    expect(config.listenPort, 8848);
  });
}
