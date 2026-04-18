import 'dart:io';

import 'package:path/path.dart' as p;

/// 文件追踪器服务，用于检测脏写（dirty write）
/// 
/// 核心机制：
/// 1. Read 时记录 lastReadTime（读取时刻的文件 modTime）
/// 2. Edit/Write 前检查当前 modTime > lastReadTime → 文件已被外部修改
/// 3. 防止 AI 覆盖用户手动修改的内容
class AiFileTrackerService {
  AiFileTrackerService();

  /// 文件路径 → 读取时的 modTime 快照
  final Map<String, DateTime> _lastReadTimes = <String, DateTime>{};

  /// 记录文件读取时间
  /// 
  /// 在 Read 工具执行成功后调用
  Future<void> recordFileRead(String filePath) async {
    final normalizedPath = p.normalize(filePath);
    final file = File(normalizedPath);
    if (!await file.exists()) return;
    final stat = await file.stat();
    _lastReadTimes[normalizedPath] = stat.modified;
  }

  /// 批量记录文件读取时间
  Future<void> recordFilesRead(Iterable<String> filePaths) async {
    for (final path in filePaths) {
      await recordFileRead(path);
    }
  }

  /// 检查文件是否可以安全写入（未被外部修改）
  /// 
  /// 返回值：
  /// - null: 可以安全写入
  /// - String: 错误消息，说明文件已被外部修改
  Future<String?> validateSafeToWrite(String filePath) async {
    final normalizedPath = p.normalize(filePath);
    final file = File(normalizedPath);
    
    // 文件不存在 → 新文件，可以写入
    if (!await file.exists()) return null;
    
    // 从未读取过 → 不应该直接修改
    final lastReadTime = _lastReadTimes[normalizedPath];
    if (lastReadTime == null) {
      // 这个检查由 previouslyReadFiles 机制处理
      // 这里只处理时间戳检查
      return null;
    }
    
    final stat = await file.stat();
    final currentModTime = stat.modified;
    
    // If the current modTime is after the lastReadTime, the file was modified
    // externally.  We apply a small tolerance (2 seconds) because some file
    // systems (e.g. FAT32, HFS+) have limited timestamp resolution and the
    // modTime written back by our own atomic write may round differently.
    if (currentModTime.isAfter(lastReadTime.add(const Duration(seconds: 2)))) {
      final timeDiff = currentModTime.difference(lastReadTime);
      return 'File was modified externally after last read (${_formatDuration(timeDiff)} ago). '
             'Re-read the file before editing to avoid overwriting external changes: $filePath';
    }
    
    return null;
  }

  /// 清除指定文件的追踪记录
  void clearFileTracking(String filePath) {
    final normalizedPath = p.normalize(filePath);
    _lastReadTimes.remove(normalizedPath);
  }

  /// 清除所有追踪记录（会话重置时调用）
  void clearAllTracking() {
    _lastReadTimes.clear();
  }

  /// 更新文件的 lastReadTime（写入后需要更新）
  Future<void> updateAfterWrite(String filePath) async {
    // 写入后重新记录时间，因为我们自己的写入是可信的
    await recordFileRead(filePath);
  }

  /// 获取追踪的文件数量（调试用）
  int get trackedFileCount => _lastReadTimes.length;

  /// 检查文件是否被追踪
  bool isTracked(String filePath) {
    final normalizedPath = p.normalize(filePath);
    return _lastReadTimes.containsKey(normalizedPath);
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) return '${duration.inDays}d';
    if (duration.inHours > 0) return '${duration.inHours}h';
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }
}
