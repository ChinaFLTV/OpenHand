import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../model/web_message_platform_config.dart';

class MessageGatewayStore {
  MessageGatewayStore({String? filePath})
    : filePath =
          filePath ??
          p.join(
            OpenHandPaths.defaultMessageGatewayDirectoryPath(),
            'web_message_platform.json',
          );

  final String filePath;

  Future<WebMessagePlatformConfig> load() async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const WebMessagePlatformConfig();
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return WebMessagePlatformConfig.fromJson(
          Map<String, Object?>.from(decoded),
        );
      }
    } catch (error, stack) {
      silentLog('message_gateway_store', 'load config', error, stack);
    }
    return const WebMessagePlatformConfig();
  }

  Future<void> save(WebMessagePlatformConfig config) async {
    final file = File(filePath);
    try {
      await file.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString('${encoder.convert(config.toJson())}\n');
    } catch (error, stack) {
      silentLog('message_gateway_store', 'save config', error, stack);
      rethrow;
    }
  }
}
