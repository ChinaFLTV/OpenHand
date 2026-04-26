/// 2026-04-26 — 数据清理模块的纯模型 / 工具函数。
///
/// 这里**不**包含任何 Flutter 依赖，方便在 isolate（`compute()`）以及单元
/// 测试里安全使用。UI 层（`_settings_data_cleanup.dart`）只通过这个文件
/// 拿到分类元数据与人类友好的字节数格式化结果。
library;

/// 数据清理分类。每一项都对应"全局设置 → 应用数据 → 数据清理"面板里的
/// 一行。**枚举顺序就是 UI 顺序**，`wipeAll` 必须放在最后。
enum DataCleanupCategory {
  /// 多媒体附件文件（图片、文档等会话附件）。
  multimedia,

  /// 会话本身：sqlite 中的 `sessions` / `messages` 行 + 旧版 JSON 文件。
  /// 不包含附件，附件由 [multimedia] 单独管理，保证两个分类互不重叠。
  sessions,

  /// 应用缓存目录（`~/.openhand/cache/`）。
  appCache,

  /// 日志数据：cron 执行历史 + `~/.openhand/logs/`。
  logs,

  /// 用户记忆条目（sqlite `memories` 表 + 用户画像）。
  userMemory,

  /// MCP Server 配置文件（`~/.openhand/mcp/mcp_servers.json`）。
  mcpConfig,

  /// 技能目录（默认 `~/.openhand/skills/`，可被设置覆盖）。
  skillsDirectory,

  /// LSP 安装目录（默认 `~/.openhand/lsp/`），由托管下载器写入。
  lspDirectory,

  /// 一键清空：上述所有分类的并集。
  ///
  /// **不会**删除 sqlite 数据库文件本身或 `~/.openhand/settings.json`，
  /// 否则会让正在运行的进程的 DB 句柄失效，从而触发硬崩溃。
  wipeAll,
}

/// 单个分类的体积探测结果。
class DataCleanupSizeReport {
  const DataCleanupSizeReport({
    required this.bytes,
    this.itemCount,
    this.error,
  });

  /// 占用磁盘 / 估算的字节数。失败时为 0。
  final int bytes;

  /// 可选的"条数"统计（例如 sessions 行数、文件个数）。`null` 表示
  /// 该分类没有可读的条数概念。
  final int? itemCount;

  /// 探测过程中遇到的人类可读错误。`null` 表示成功。
  final String? error;

  static const DataCleanupSizeReport empty = DataCleanupSizeReport(
    bytes: 0,
    itemCount: 0,
  );

  static const DataCleanupSizeReport unknown = DataCleanupSizeReport(bytes: 0);

  DataCleanupSizeReport operator +(DataCleanupSizeReport other) {
    final combinedItems = (itemCount == null && other.itemCount == null)
        ? null
        : (itemCount ?? 0) + (other.itemCount ?? 0);
    final combinedError = error ?? other.error;
    return DataCleanupSizeReport(
      bytes: bytes + other.bytes,
      itemCount: combinedItems,
      error: combinedError,
    );
  }
}

/// 把字节数渲染为人类友好的字符串。`1500` → `'1.46 KB'`。
///
/// 阈值规则：
/// - `< 1 KB` 直接展示原始字节数；
/// - `>= 100` 时不保留小数；
/// - `[10, 100)` 保留 1 位小数；
/// - `< 10` 保留 2 位小数。
///
/// 这样即便单位跳变也不会出现 `1024.00 KB` 这种丑陋数字。
String formatHumanBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = <String>['KB', 'MB', 'GB', 'TB', 'PB'];
  double size = bytes / 1024.0;
  int unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024.0;
    unitIndex++;
  }
  final fractionDigits = size >= 100
      ? 0
      : (size >= 10 ? 1 : 2);
  return '${size.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}
