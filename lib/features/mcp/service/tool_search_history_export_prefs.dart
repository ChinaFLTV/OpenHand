import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';

/// 轻量 KV：记忆 ToolSearch 历史导出对话框上次落地目录，下次自动开在那。
///
/// 复用 `app_settings` 表（key/value），避免给 [AppSettingsSnapshot] 9 步管线
/// 再加一个纯 UX 字段。设置 view 上提供 Reset 按钮调用 [clear]。
class ToolSearchHistoryExportPrefs {
  const ToolSearchHistoryExportPrefs._();

  static const String _kLastDirKey = 'tool_search_history_export_last_dir';
  static const int _maxDirectoryCharacters = 16 * kBytesPerKiB;
  static const int _maxDirectoryBytes = 64 * kBytesPerKiB;

  static Database get _db => DatabaseService.instance.database;

  /// 上次成功导出落地的目录路径；不存在时返回 null。
  static Future<String?> readLastDir() async {
    try {
      final rows = await _db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[_kLastDirKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _normalizeDirectory(rows.first['value']);
    } catch (error, stack) {
      silentLog('tool_search_history_export_prefs', '读取上次目录', error, stack);
      return null;
    }
  }

  /// 写入 / 覆盖上次导出目录；空字符串等同于 [clear]。
  static Future<void> writeLastDir(String dir) async {
    try {
      final trimmed = _normalizeDirectory(dir);
      if (trimmed == null) {
        await clear();
        return;
      }
      await _db.insert('app_settings', <String, Object?>{
        'key': _kLastDirKey,
        'value': trimmed,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (error, stack) {
      silentLog('tool_search_history_export_prefs', '写入上次目录', error, stack);
    }
  }

  static String? _normalizeDirectory(Object? value) {
    if (value is! String) throw const FormatException('导出目录类型无效。');
    final normalized = nullIfBlank(value);
    if (normalized == null) return null;
    if (normalized.length > _maxDirectoryCharacters ||
        utf8ByteLength(normalized) > _maxDirectoryBytes ||
        normalized.contains('\u0000')) {
      throw const FormatException('导出目录路径无效。');
    }
    return normalized;
  }

  /// 清除已记忆的目录（Settings 中的 Reset 按钮）。
  static Future<void> clear() async {
    try {
      await _db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[_kLastDirKey],
      );
    } catch (error, stack) {
      silentLog('tool_search_history_export_prefs', '清理目录偏好', error, stack);
    }
  }
}
