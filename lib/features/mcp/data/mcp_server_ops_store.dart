import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/mcp_server_ops.dart';

class McpServerOpsStore {
  McpServerOpsStore({required String storageDirectoryPath})
    : _filePath = p.join(storageDirectoryPath, 'mcp_server_ops.json');

  static const String _configKey = 'config';

  final String _filePath;

  String get filePath => _filePath;

  Future<McpOpsConfig> loadConfig() async {
    final file = File(_filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await file.exists()) {
      const config = McpOpsConfig();
      await saveConfig(config);
      return config;
    }
    final raw = await file.readAsString();
    final decoded = optionalStringKeyedMapFromJsonText(raw);
    if (decoded == null) {
      const config = McpOpsConfig();
      await saveConfig(config);
      return config;
    }
    return McpOpsConfig.fromJson(decoded[_configKey]);
  }

  Future<void> saveConfig(McpOpsConfig config) async {
    final file = File(_filePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final content = prettyPrintJson(<String, Object?>{_configKey: config.toJson()});
    await writeFileAtomically(file, content);
  }
}
