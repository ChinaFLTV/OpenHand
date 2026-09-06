/// 这里不包含 Flutter 依赖，可直接用于 isolate。UI 层通过本文件获取
/// 数据清理的分类元数据与体积统计模型。
library;

/// 数据清理分类。每一项都对应"全局设置 → 应用数据 → 数据清理"面板里的
/// 一行。**枚举顺序就是 UI 顺序**，`wipeAll` 必须放在最后。
enum DataCleanupCategory {
  /// 多媒体附件与远程媒体缓存（图片、视频、音频、文档等）。
  multimedia,

  /// 本地语音识别/朗读模型、共享隔离运行环境与下载缓存。
  speechResources,

  /// 会话本身：sqlite 中的 `sessions` / `messages` 行 + 旧版 JSON 文件。
  /// 不包含附件，附件由 [multimedia] 单独管理，保证两个分类互不重叠。
  sessions,

  /// 应用缓存目录（`~/.openhand/cache/`，不含单独归类的媒体与语音缓存）。
  appCache,

  /// 日志数据：cron 执行历史 + `~/.openhand/logs/`。
  logs,

  /// 用户记忆条目（sqlite `memories` 表 + 用户画像）。
  userMemory,

  /// MCP Server 配置文件（`~/.openhand/mcp/mcp_servers.json`）。
  mcpConfig,

  /// MCP 运维弹窗持久化的监控趋势与审计日志。
  mcpOpsCache,

  /// Web 消息网关运维弹窗持久化的监控趋势与日志回溯。
  webGatewayOpsCache,

  /// Hooks 钩子配置（sqlite `hooks` 表）。
  hooks,

  /// 定时任务（sqlite `cron_jobs` 表）。系统内置条目（如 Hermes Talker
  /// 自主学习、MCP 关键词索引）会被自动保留。
  crons,

  /// 用户自定义指令条目（sqlite `user_instructions` 表）。
  instructions,

  /// 技能目录（默认 `~/.openhand/skills/`，可被设置覆盖）。
  skillsDirectory,

  /// LSP 安装目录（默认 `~/.openhand/lsp/`），由托管下载器写入。
  lspDirectory,

  /// 文件变动 ledger（默认 `~/.openhand/file_history/`）：保存所有工具
  /// 写操作的 before/after 快照与 jsonl ledger，支撑卡片侧的撤销/重做。
  fileMutationLedger,

  /// 一键清空：上述所有分类的并集。
  ///
  /// **不会**删除 sqlite 数据库文件本身；当前设置也保存在该数据库中。
  /// 删除文件会让运行中进程的 DB 句柄失效，从而触发硬崩溃。
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

/// 语音资源按用途拆分后的占用报告，总量只由三个互斥分支求和。
class SpeechDataCleanupSizeReport {
  const SpeechDataCleanupSizeReport({
    required this.recognitionModels,
    required this.synthesisModels,
    required this.sharedResources,
  });

  final DataCleanupSizeReport recognitionModels;
  final DataCleanupSizeReport synthesisModels;
  final DataCleanupSizeReport sharedResources;

  DataCleanupSizeReport get total =>
      recognitionModels + synthesisModels + sharedResources;
}
