import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
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
    final config = WebMessagePlatformConfig.fromJson(source);
    validateCanonicalJsonSubset(
      source,
      config.toJson(),
      path: 'message_gateway',
    );
    _expectedContent = raw;
    _hasLoadedSnapshot = true;
    return config;
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
