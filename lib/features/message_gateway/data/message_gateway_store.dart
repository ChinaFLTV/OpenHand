import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
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

  static const int _maxConfigFileBytes = 4 * kBytesPerMiB;
  static const String _allowedBuiltinToolNamesKey =
      'allowed_builtin_tool_names';
  static const String _retiredBuiltinToolNamePrefix = 'agent';
  static const Set<String> _retiredConfigKeys = <String>{
    'allowed_agent_ids',
    'agents_enabled',
  };

  final String filePath;
  String? _expectedContent;
  bool _hasLoadedSnapshot = false;

  Future<WebMessagePlatformConfig> load() async {
    final file = File(filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await regularFileExistsBounded(file)) {
      _expectedContent = null;
      _hasLoadedSnapshot = true;
      return const WebMessagePlatformConfig();
    }
    final raw = await readBoundedFileString(
      file,
      maxBytes: _maxConfigFileBytes,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('消息网关配置根节点必须为对象。');
    }
    final source = stringKeyedMapFromValue(decoded);
    final migrated = _removeRetiredConfig(source);
    final config = WebMessagePlatformConfig.fromJson(source);
    validateCanonicalJsonSubset(
      source,
      config.toJson(),
      path: 'message_gateway',
    );
    _expectedContent = raw;
    _hasLoadedSnapshot = true;
    if (migrated) {
      try {
        await save(config);
      } catch (error, stack) {
        silentLog('message_gateway_store', '清理已下线消息网关配置', error, stack);
      }
    }
    return config;
  }

  bool _removeRetiredConfig(Map<String, Object?> source) {
    var changed = false;
    for (final key in _retiredConfigKeys) {
      if (!source.containsKey(key)) continue;
      source.remove(key);
      changed = true;
    }
    final rawToolNames = source[_allowedBuiltinToolNamesKey];
    if (rawToolNames is! List) return changed;
    final filtered = <Object?>[];
    for (final item in rawToolNames) {
      final name = '$item'.trim();
      const suffixIndex = _retiredBuiltinToolNamePrefix.length;
      final lower = name.toLowerCase();
      final isRetired =
          lower.startsWith(_retiredBuiltinToolNamePrefix) &&
          name.length > suffixIndex &&
          name.codeUnitAt(suffixIndex) >= 0x41 &&
          name.codeUnitAt(suffixIndex) <= 0x5A;
      if (isRetired) {
        changed = true;
      } else {
        filtered.add(item);
      }
    }
    if (filtered.length != rawToolNames.length) {
      source[_allowedBuiltinToolNamesKey] = filtered;
    }
    return changed;
  }

  Future<void> save(WebMessagePlatformConfig config) async {
    if (!_hasLoadedSnapshot) {
      throw StateError('消息网关配置缺少可信快照。');
    }
    final file = File(filePath);
    final exists = await regularFileExistsBounded(file);
    if (_expectedContent == null) {
      if (exists) {
        throw StateError('消息网关配置已被外部修改。');
      }
    } else {
      if (!exists) {
        throw StateError('消息网关配置已被外部删除。');
      }
      final current = await readBoundedFileString(
        file,
        maxBytes: _maxConfigFileBytes,
      );
      if (current != _expectedContent) {
        throw StateError('消息网关配置已被外部修改。');
      }
    }
    final content = '${prettyPrintJson(config.toJson())}\n';
    if (utf8.encode(content).length > _maxConfigFileBytes) {
      throw const FileSystemException('消息网关配置超过大小上限。');
    }
    await writeFileAtomically(file, content);
    _expectedContent = content;
  }
}
