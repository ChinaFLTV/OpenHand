import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/dingtalk_message_gateway.dart';

class DingTalkMessageGatewayStore {
  DingTalkMessageGatewayStore({String? filePath})
    : filePath =
          filePath ??
          p.join(
            OpenHandPaths.defaultMessageGatewayDirectoryPath(),
            'dingtalk.json',
          );

  static const int _maxBytes = 512 * kBytesPerKiB;
  final String filePath;
  String? _expectedContent;
  bool _loaded = false;

  Future<DingTalkGatewaySettings> load() async {
    final file = File(filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await regularFileExistsBounded(file)) {
      _loaded = true;
      _expectedContent = null;
      return const DingTalkGatewaySettings();
    }
    final raw = await readBoundedFileString(file, maxBytes: _maxBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('钉钉网关配置必须为对象。');
    _loaded = true;
    _expectedContent = raw;
    return DingTalkGatewaySettings.fromJson(stringKeyedMapFromValue(decoded));
  }

  Future<void> save(DingTalkGatewaySettings value) async {
    if (!_loaded) throw StateError('钉钉网关配置缺少可信快照。');
    final file = File(filePath);
    final exists = await regularFileExistsBounded(file);
    if (_expectedContent == null ? exists : !exists) {
      throw StateError('钉钉网关配置已被外部修改。');
    }
    if (_expectedContent != null &&
        await readBoundedFileString(file, maxBytes: _maxBytes) !=
            _expectedContent) {
      throw StateError('钉钉网关配置已被外部修改。');
    }
    final content =
        '${const JsonEncoder.withIndent('  ').convert(value.normalized().toJson())}\n';
    await writeFileAtomically(file, content);
    _expectedContent = content;
  }
}
