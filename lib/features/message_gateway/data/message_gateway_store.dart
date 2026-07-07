import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/input_value_parsing.dart';
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
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await file.exists()) {
      return const WebMessagePlatformConfig();
    }
    try {
      final raw = await file.readAsString();
      final decoded = optionalStringKeyedMapFromJsonText(raw);
      if (decoded != null) {
        return WebMessagePlatformConfig.fromJson(decoded);
      }
    } catch (error, stack) {
      silentLog('message_gateway_store', 'load config', error, stack);
    }
    return const WebMessagePlatformConfig();
  }

  Future<void> save(WebMessagePlatformConfig config) async {
    final file = File(filePath);
    try {
      await writeFileAtomically(
        file,
        '${prettyPrintJson(config.toJson())}\n',
      );
    } catch (error, stack) {
      silentLog('message_gateway_store', 'save config', error, stack);
      rethrow;
    }
  }
}
