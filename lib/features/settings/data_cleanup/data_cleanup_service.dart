/// 设计要点：
/// 1. **所有耗时的文件系统遍历都在 [compute] 里跑**——通过把任务抛进
///    后台 isolate，主 isolate 不会被磁盘 IO 阻塞，避免 ANR / 卡顿。
/// 2. **每个 isolate 任务都有 silentLog 兜底**——单个目录不可读不会让
///    整个测算失败，结果中只是少计算一些字节。
/// 3. **数据库访问留在主 isolate**——sqflite_common_ffi 的 Database
///    句柄不能跨 isolate；所以 DB 体积探测使用主 isolate 上一次很快的
///    `LENGTH(...)` 聚合查询。
/// 4. **清理顺序在 [cleanAll] 中固定**：先抹掉派生数据（多媒体/缓存/日志），
///    最后再删 sessions。这样即便中途崩溃，残留也不会引用已经被删的
///    附件文件。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../ai/index.dart';
import '../../crons/crons_controller.dart';
import '../../hooks/hooks_controller.dart';
import '../../instructions/instructions_controller.dart';
import '../../mcp/mcp_controller.dart';
import '../../memory/memory_controller.dart';
import '../../message_gateway/index.dart' show MessageGatewayController;
import '../../skills/skills_controller.dart';
import 'data_cleanup_models.dart';

/// 数据清理 service：纯实例化（无全局状态），由 UI 层按需创建。
class DataCleanupService {
  DataCleanupService({
    required this._aiSessionController,
    required this._cronsController,
    required this._hooksController,
    required this._instructionsController,
    required this._memoryController,
    required this._mcpController,
    required this._messageGatewayController,
    required this._skillsController,
    required this._settingsController,
  });

  final AiSessionController _aiSessionController;
  final CronsController _cronsController;
  final HooksController _hooksController;
  final InstructionsController _instructionsController;
  final MemoryController _memoryController;
  final McpController _mcpController;
  final MessageGatewayController _messageGatewayController;
  final SkillsController _skillsController;
  final SettingsController _settingsController;
  // 体积探测
  /// 多媒体附件总大小：扫描每个会话目录下的 `attachments/` 子目录、
  /// 旧版 `~/.openhand/sessions/attachments/`、旧临时 `openhand_media`
  /// 以及持久网络多媒体缓存 `~/.openhand/cache/media/`。
  Future<DataCleanupSizeReport> measureMultimedia() async {
    final attachmentsReport = await compute(
      _isolateMeasureAttachments,
      OpenHandPaths.defaultSessionsDirectoryPath(),
    );
    final mediaCacheReport = await MediaCacheService.measureCache();
    return DataCleanupSizeReport(
      bytes: attachmentsReport.bytes + mediaCacheReport.bytes,
      itemCount:
          (attachmentsReport.itemCount ?? 0) + mediaCacheReport.fileCount,
    );
  }

  /// 会话本身（非附件）：sqlite 行体积估算 + 旧版 `session-*.json`。
  Future<DataCleanupSizeReport> measureSessions() async {
    final dbReport = await _measureSessionsDb();
    final fsReport = await compute(
      _isolateMeasureSessionsExcludingAttachments,
      OpenHandPaths.defaultSessionsDirectoryPath(),
    );
    return dbReport + fsReport;
  }

  /// 应用缓存目录。多媒体缓存由 [measureMultimedia] 单独统计，避免
  /// `wipeAll` 汇总时重复计入。
  Future<DataCleanupSizeReport> measureAppCache() {
    return compute(_isolateMeasureDirectoryExcluding, <String>[
      OpenHandPaths.defaultCacheDirectoryPath(),
      MediaCacheService.cacheDirectoryPath,
    ]);
  }

  /// 日志数据：cron 历史行体积 + 日志目录。
  Future<DataCleanupSizeReport> measureLogs() async {
    final dbReport = await _measureCronHistoryDb();
    final fsReport = await compute(
      _isolateMeasureDirectory,
      OpenHandPaths.defaultLogsDirectoryPath(),
    );
    return dbReport + fsReport;
  }

  /// 用户记忆条目：sqlite `memories` 表的行数 + LENGTH 估算。
  Future<DataCleanupSizeReport> measureUserMemory() async {
    try {
      final db = DatabaseService.instance.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt, '
        'COALESCE(SUM('
        'LENGTH(CAST(id AS BLOB)) '
        '+ LENGTH(CAST(type AS BLOB)) '
        '+ LENGTH(CAST(created_at AS BLOB)) '
        '+ LENGTH(CAST(content AS BLOB)) '
        '+ LENGTH(CAST(title AS BLOB)) '
        '+ LENGTH(CAST(tags_json AS BLOB))'
        '), 0) AS bytes '
        'FROM memories',
      );
      if (rows.isEmpty) {
        return DataCleanupSizeReport.empty;
      }
      final row = rows.first;
      return DataCleanupSizeReport(
        bytes: (row['bytes'] as int?) ?? 0,
        itemCount: (row['cnt'] as int?) ?? 0,
      );
    } catch (error, stack) {
      silentLog('data_cleanup', '统计用户记忆', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }

  /// MCP 配置文件大小。
  Future<DataCleanupSizeReport> measureMcpConfig() {
    return compute(_isolateMeasureFile, _settingsController.mcpServersFilePath);
  }

  Future<DataCleanupSizeReport> measureMcpOpsCache() async {
    final report = await _mcpController.measureOpsRuntimeData();
    return DataCleanupSizeReport(
      bytes: report.bytes,
      itemCount: report.itemCount,
    );
  }

  Future<DataCleanupSizeReport> measureWebGatewayOpsCache() async {
    final report = await _messageGatewayController.measureOpsCache();
    return DataCleanupSizeReport(
      bytes: report.bytes,
      itemCount: report.itemCount,
    );
  }

  /// Hooks 配置：sqlite `hooks` 表的行数 + LENGTH 估算。
  Future<DataCleanupSizeReport> measureHooks() async {
    try {
      final db = DatabaseService.instance.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt, '
        'COALESCE(SUM('
        'LENGTH(IFNULL(label, \'\')) '
        '+ LENGTH(IFNULL(script_path, \'\')) '
        '+ LENGTH(IFNULL(script_content, \'\')) '
        '+ LENGTH(IFNULL(event, \'\'))'
        '), 0) AS bytes '
        'FROM hooks',
      );
      if (rows.isEmpty) return DataCleanupSizeReport.empty;
      final row = rows.first;
      return DataCleanupSizeReport(
        bytes: (row['bytes'] as int?) ?? 0,
        itemCount: (row['cnt'] as int?) ?? 0,
      );
    } catch (error, stack) {
      silentLog('data_cleanup', '统计 Hooks', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }

  /// 定时任务：仅统计「非系统」cron_jobs 行（保留 Hermes Talker 等
  /// `system` 标签的内置条目）。bytes 通过 LENGTH 聚合估算；带 system
  /// 标签的行通过 `tags NOT LIKE '%system%'` 排除。
  Future<DataCleanupSizeReport> measureCrons() async {
    try {
      final db = DatabaseService.instance.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt, '
        'COALESCE(SUM('
        'LENGTH(IFNULL(name, \'\')) '
        '+ LENGTH(IFNULL(description, \'\')) '
        '+ LENGTH(IFNULL(script_content, \'\')) '
        '+ LENGTH(IFNULL(script_path, \'\')) '
        '+ LENGTH(IFNULL(cron_expression, \'\')) '
        '+ LENGTH(IFNULL(environment, \'\'))'
        '), 0) AS bytes '
        'FROM cron_jobs '
        "WHERE COALESCE(tags, '') NOT LIKE '%system%'",
      );
      if (rows.isEmpty) return DataCleanupSizeReport.empty;
      final row = rows.first;
      return DataCleanupSizeReport(
        bytes: (row['bytes'] as int?) ?? 0,
        itemCount: (row['cnt'] as int?) ?? 0,
      );
    } catch (error, stack) {
      silentLog('data_cleanup', '统计定时任务', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }

  /// 用户自定义指令：sqlite `user_instructions` 表的行数 + LENGTH 估算。
  Future<DataCleanupSizeReport> measureInstructions() async {
    try {
      final db = DatabaseService.instance.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt, '
        'COALESCE(SUM('
        'LENGTH(IFNULL(name, \'\')) '
        '+ LENGTH(IFNULL(body, \'\')) '
        '+ LENGTH(IFNULL(description, \'\')) '
        '+ LENGTH(IFNULL(apply_to, \'\')) '
        '+ LENGTH(IFNULL(notes_json, \'\')) '
        '+ LENGTH(IFNULL(task_types_json, \'\')) '
        '+ LENGTH(IFNULL(keywords_json, \'\'))'
        '), 0) AS bytes '
        'FROM user_instructions',
      );
      if (rows.isEmpty) return DataCleanupSizeReport.empty;
      final row = rows.first;
      return DataCleanupSizeReport(
        bytes: (row['bytes'] as int?) ?? 0,
        itemCount: (row['cnt'] as int?) ?? 0,
      );
    } catch (error, stack) {
      silentLog('data_cleanup', '统计用户指令', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }

  /// 技能目录体积。
  Future<DataCleanupSizeReport> measureSkillsDirectory() {
    return compute(
      _isolateMeasureDirectory,
      _settingsController.skillsStoragePath,
    );
  }

  /// LSP 安装目录体积。
  Future<DataCleanupSizeReport> measureLspDirectory() {
    return compute(
      _isolateMeasureDirectory,
      OpenHandPaths.defaultLspDirectoryPath(),
    );
  }

  /// 文件变动 ledger 体积（`~/.openhand/file_history/`）。
  /// 阶段 ⑦a：itemCount 用 ledger 自带的 statsSnapshot 报回 record 行数，
  /// 让 UI 主卡片 subtitle 直接显示 N 项，且与高级控制头部数字一致。
  Future<DataCleanupSizeReport> measureMutationLedger() async {
    final results = await Future.wait([
      compute(
        _isolateMeasureDirectory,
        p.join(OpenHandPaths.defaultRootDirectoryPath(), 'file_history'),
      ),
      AiFileMutationLedger().statsSnapshot(),
    ]);
    final dirReport = results[0] as DataCleanupSizeReport;
    final stats = results[1] as LedgerStatsSnapshot;
    return DataCleanupSizeReport(
      bytes: dirReport.bytes,
      itemCount: stats.recordCount,
    );
  }

  // 清理动作
  /// 删除所有附件目录里的文件 + 网络多媒体缓存。会话行本身保留——
  /// 附件引用变成"找不到文件"，UI 层会自动降级展示。
  Future<void> cleanMultimedia() async {
    await compute(
      _isolateDeleteAttachments,
      OpenHandPaths.defaultSessionsDirectoryPath(),
    );
    // 清空网络多媒体本地缓存。
    await MediaCacheService.clearCache();
  }

  /// 清空所有会话（DB + 磁盘 JSON），并触发 controller 重新加载。
  Future<void> cleanSessions() async {
    await _aiSessionController.store.clearAll();
    await _aiSessionController.refresh();
  }

  /// 清空应用缓存目录。
  Future<void> cleanAppCache() async {
    // WebSearch 持久化缓存内部维护写入串行队列；先在主 isolate 走它的
    // clearAll() 让 index.json 失效，再 compute() 把残余目录一并清空，
    // 避免删除时序与新写入互踩。
    await WebSearchCacheStore.instance.clearAll();
    await WebSearchTelemetryStore.instance.clearAll();
    await WebFetchCacheStore.instance.clearAll();
    await WebFetchTelemetryStore.instance.clearAll();
    await compute(_isolateDeleteDirectoryContentsExcluding, <String>[
      OpenHandPaths.defaultCacheDirectoryPath(),
      MediaCacheService.cacheDirectoryPath,
    ]);
  }

  /// 清空 cron 执行历史 + 日志目录。
  Future<void> cleanLogs() async {
    await _cronsController.clearAllHistory();
    await compute(
      _isolateDeleteDirectoryContents,
      OpenHandPaths.defaultLogsDirectoryPath(),
    );
  }

  /// 清空用户记忆条目（含用户画像）。由 controller 串行化整表删除，
  /// 防止与 AI/UI 写入交错，并同步更新可信内存快照。
  Future<void> cleanUserMemory() async {
    if (!await _memoryController.clearAll()) {
      throw StateError('用户记忆控制器拒绝清理操作。');
    }
  }

  /// 清空全部 Hooks 条目（sqlite `hooks` 表整表删除），并让 controller
  /// 重新加载（变成空列表）。
  Future<void> cleanHooks() async {
    try {
      if (!await _hooksController.clearAll()) {
        throw StateError('Hooks 控制器拒绝清理操作。');
      }
    } catch (error, stack) {
      silentLog('data_cleanup', '清理 Hooks', error, stack);
      // controller 路径异常时兜底直接走 DB，再 refresh 一次。
      try {
        final db = DatabaseService.instance.database;
        await db.delete('hooks');
        await _hooksController.refresh();
      } catch (error2, stack2) {
        silentLog('data_cleanup', '清理 Hooks 兜底', error2, stack2);
      }
    }
  }

  /// 清空全部「非系统」cron 任务（Hermes Talker 自主学习、MCP 关键词索引
  /// 等带 `system` 标签的内置条目会被保留）。controller 内部已负责取消
  /// 调度、清理历史缓存。
  Future<void> cleanCrons() async {
    try {
      await _cronsController.clearAllNonSystemCrons();
    } catch (error, stack) {
      silentLog('data_cleanup', '清理定时任务', error, stack);
    }
  }

  /// 清空全部用户自定义指令条目。
  Future<void> cleanInstructions() async {
    try {
      if (!await _instructionsController.clearAll()) {
        throw StateError('用户指令控制器拒绝清理操作。');
      }
    } catch (error, stack) {
      silentLog('data_cleanup', '清理用户指令', error, stack);
      // controller 路径异常时兜底直接走 DB，再 refresh 一次。
      try {
        final db = DatabaseService.instance.database;
        await db.delete('user_instructions');
        await _instructionsController.refresh();
      } catch (error2, stack2) {
        silentLog('data_cleanup', '清理用户指令兜底', error2, stack2);
      }
    }
  }

  /// 删除 MCP Server 配置文件，然后让 controller 重新加载（变成空列表）。
  Future<void> cleanMcpConfig() async {
    final path = _settingsController.mcpServersFilePath;
    await compute(_isolateDeleteFile, path);
    try {
      await _mcpController.refresh();
    } catch (error, stack) {
      silentLog('data_cleanup', '清理 MCP 配置后刷新', error, stack);
    }
  }

  Future<void> cleanMcpOpsCache() async {
    await _mcpController.clearOpsRuntimeData();
  }

  Future<void> cleanWebGatewayOpsCache() async {
    await _messageGatewayController.cleanupOpsCache();
  }

  /// 清空技能目录内容（保留目录本身），并让 controller 重新扫描。
  Future<void> cleanSkillsDirectory() async {
    await compute(
      _isolateDeleteDirectoryContents,
      _settingsController.skillsStoragePath,
    );
    try {
      await _skillsController.refresh();
    } catch (error, stack) {
      silentLog('data_cleanup', '清理技能目录后刷新', error, stack);
    }
  }

  /// 清空 LSP 安装目录。下次使用对应语言时会触发重新下载。
  Future<void> cleanLspDirectory() {
    return compute(
      _isolateDeleteDirectoryContents,
      OpenHandPaths.defaultLspDirectoryPath(),
    );
  }

  /// 清空文件变动 ledger（所有会话的 jsonl + state +
  /// blob）。调用后卡片侧 undo/redo 会退化为 metadata-only 列表。
  Future<void> cleanMutationLedger() async {
    try {
      await AiFileMutationLedger().clearAll();
    } catch (error, stack) {
      silentLog('data_cleanup', '清理文件变动账本', error, stack);
    }
  }

  /// 顺序执行所有分类的清理。任何分支抛异常都会被 silentLog 吞掉，
  /// 后续分类继续执行；最终的总错误数通过返回的 `errors` 暴露给 UI。
  Future<int> cleanAll() async {
    int errors = 0;
    Future<void> runStep(String name, Future<void> Function() step) async {
      try {
        await step();
      } catch (error, stack) {
        errors++;
        silentLog('data_cleanup', '执行全部清理/$name', error, stack);
      }
    }

    await runStep('多媒体', cleanMultimedia);
    await runStep('应用缓存', cleanAppCache);
    await runStep('日志', cleanLogs);
    await runStep('用户记忆', cleanUserMemory);
    await runStep('MCP 配置', cleanMcpConfig);
    await runStep('MCP 运维缓存', cleanMcpOpsCache);
    await runStep('Web 网关运维缓存', cleanWebGatewayOpsCache);
    await runStep('Hooks', cleanHooks);
    await runStep('定时任务', cleanCrons);
    await runStep('用户指令', cleanInstructions);
    await runStep('技能目录', cleanSkillsDirectory);
    await runStep('LSP 目录', cleanLspDirectory);
    await runStep('文件变动账本', cleanMutationLedger);
    // 会话放在最后清理：上面的步骤即便意外失败，残留附件引用也已经
    // 失效，但 sessions 表仍在；如果反过来先清 sessions，再清附件失败，
    // 用户看到的是"会话没了，但附件目录还在占空间"。
    await runStep('会话', cleanSessions);
    return errors;
  }

  // DB 体积估算（主 isolate）
  Future<DataCleanupSizeReport> _measureSessionsDb() async {
    try {
      final db = DatabaseService.instance.database;
      final rows = await db.rawQuery(
        'SELECT '
        '(SELECT COUNT(*) FROM sessions) AS sessions_cnt, '
        '(SELECT COUNT(*) FROM messages) AS messages_cnt, '
        '(SELECT COALESCE(SUM('
        'LENGTH(IFNULL(content, \'\')) '
        '+ LENGTH(IFNULL(metadata_json, \'\')) '
        '+ LENGTH(IFNULL(usage_json, \'\'))'
        '), 0) FROM messages) AS messages_bytes, '
        '(SELECT COALESCE(SUM('
        'LENGTH(IFNULL(metadata_json, \'\')) '
        '+ LENGTH(IFNULL(environment_json, \'\')) '
        '+ LENGTH(IFNULL(statistics_json, \'\')) '
        '+ LENGTH(IFNULL(recent_errors_json, \'\')) '
        '+ LENGTH(IFNULL(todo_items_json, \'\')) '
        '+ LENGTH(IFNULL(plan_history_json, \'\'))'
        '), 0) FROM sessions) AS sessions_bytes',
      );
      if (rows.isEmpty) {
        return DataCleanupSizeReport.empty;
      }
      final row = rows.first;
      final sessionsCnt = (row['sessions_cnt'] as int?) ?? 0;
      final messagesBytes = (row['messages_bytes'] as int?) ?? 0;
      final sessionsBytes = (row['sessions_bytes'] as int?) ?? 0;
      return DataCleanupSizeReport(
        bytes: messagesBytes + sessionsBytes,
        itemCount: sessionsCnt,
      );
    } catch (error, stack) {
      silentLog('data_cleanup', '统计会话数据库', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }

  Future<DataCleanupSizeReport> _measureCronHistoryDb() async {
    try {
      final size = await _cronsController.store.historyApproxSize();
      return DataCleanupSizeReport(
        bytes: size.approxBytes,
        itemCount: size.rowCount,
      );
    } catch (error, stack) {
      silentLog('data_cleanup', '统计定时任务历史数据库', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }
}

// Isolate worker 函数必须位于顶层或声明为静态，以便序列化。
/// 在 isolate 内统计 sessions 目录下所有 `attachments/` 子目录的体积与
/// 文件数。
const int _maxDataCleanupScanEntries = 1000000;
const int _maxDataCleanupDeleteDepth = 256;
const Duration _dataCleanupScanIdleTimeout = Duration(seconds: 10);
const Duration _dataCleanupScanTotalTimeout = Duration(minutes: 2);
const String _dataCleanupPartialScanError = '目录扫描已在安全上限处停止。';

class _DataCleanupScanBudget {
  _DataCleanupScanBudget()
    : remainingEntries = _maxDataCleanupScanEntries,
      _deadline = MonotonicDeadline(
        _dataCleanupScanTotalTimeout,
        timeoutMessage: '数据清理扫描超时。',
      );

  int remainingEntries;
  final MonotonicDeadline _deadline;
  bool _interrupted = false;

  bool get incomplete =>
      _interrupted || remainingEntries <= 0 || _deadline.isExpired;

  bool get exhausted => remainingEntries <= 0 || _deadline.isExpired;

  void markInterrupted() {
    _interrupted = true;
  }

  Duration nextOperationTimeout() {
    final remainingDuration = remainingDurationForOperation();
    return remainingDuration < _dataCleanupScanIdleTimeout
        ? remainingDuration
        : _dataCleanupScanIdleTimeout;
  }

  Duration remainingDurationForOperation() {
    final remaining = _deadline.remainingOrNull();
    if (remaining == null) {
      _interrupted = true;
      throw _deadline.timeoutException();
    }
    return remaining;
  }

  void consumeEntries(int count) {
    if (count <= 0) return;
    remainingEntries -= count;
  }

  bool takeEntry() {
    if (remainingEntries <= 0 || _deadline.isExpired) {
      return false;
    }
    remainingEntries -= 1;
    return true;
  }
}

Future<bool> _cleanupDirectoryExists(
  Directory directory, {
  _DataCleanupScanBudget? budget,
}) async {
  final timeout = budget?.nextOperationTimeout() ?? _dataCleanupScanIdleTimeout;
  return await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      ).timeout(timeout) ==
      FileSystemEntityType.directory;
}

Future<DataCleanupSizeReport> _isolateMeasureAttachments(
  String sessionsRoot,
) async {
  final root = Directory(sessionsRoot);
  int totalBytes = 0;
  int totalFiles = 0;
  final budget = _DataCleanupScanBudget();
  try {
    if (!await _cleanupDirectoryExists(root, budget: budget)) {
      return DataCleanupSizeReport.empty;
    }
    await for (final entity
        in root.list(followLinks: false).timeout(_dataCleanupScanIdleTimeout)) {
      if (!budget.takeEntry()) break;
      if (entity is! Directory) {
        continue;
      }
      // 该会话子目录里，只算 `attachments/`；旧版顶层 attachments 目录
      // 自身就是一个匹配项（其名字就是 `attachments`）。
      final attachmentsName = p.basename(entity.path);
      if (attachmentsName == 'attachments') {
        final stats = await _walkDirectoryStats(entity, budget: budget);
        totalBytes += stats.bytes;
        totalFiles += stats.files;
        continue;
      }
      final perSession = Directory(p.join(entity.path, 'attachments'));
      if (await _cleanupDirectoryExists(perSession, budget: budget)) {
        final stats = await _walkDirectoryStats(perSession, budget: budget);
        totalBytes += stats.bytes;
        totalFiles += stats.files;
      }
    }
  } catch (error, stack) {
    budget.markInterrupted();
    // 子目录不可读：保留已经累计的部分，避免一棵坏分支吞掉全部统计。
    silentLog('data_cleanup', '遍历附件目录', error, stack);
  }
  return DataCleanupSizeReport(
    bytes: totalBytes,
    itemCount: totalFiles,
    error: budget.incomplete ? _dataCleanupPartialScanError : null,
  );
}

/// 在 isolate 内统计 sessions 目录下"非附件"内容（例如旧版 JSON）。
Future<DataCleanupSizeReport> _isolateMeasureSessionsExcludingAttachments(
  String sessionsRoot,
) async {
  final root = Directory(sessionsRoot);
  int totalBytes = 0;
  final budget = _DataCleanupScanBudget();
  try {
    if (!await _cleanupDirectoryExists(root, budget: budget)) {
      return const DataCleanupSizeReport(bytes: 0);
    }
    await for (final entity
        in root.list(followLinks: false).timeout(_dataCleanupScanIdleTimeout)) {
      if (!budget.takeEntry()) break;
      if (entity is File) {
        // 旧版 `session-*.json`。
        try {
          totalBytes += await entity.length().timeout(
            budget.nextOperationTimeout(),
          );
        } catch (error, stack) {
          budget.markInterrupted();
          // 文件被并发删除等：忽略。
          silentLog('data_cleanup', '读取会话 JSON 大小', error, stack);
        }
        continue;
      }
      if (entity is Directory) {
        final name = p.basename(entity.path);
        if (name == 'attachments') {
          // 附件由多媒体分类负责。
          continue;
        }
        // per-session 子目录：跳过其下的 `attachments/`，统计其它文件。
        await for (final inner
            in entity
                .list(recursive: true, followLinks: false)
                .timeout(_dataCleanupScanIdleTimeout)) {
          if (!budget.takeEntry()) break;
          if (inner is! File) {
            continue;
          }
          if (p.split(inner.path).contains('attachments')) {
            continue;
          }
          try {
            totalBytes += await inner.length().timeout(
              budget.nextOperationTimeout(),
            );
          } catch (error, stack) {
            budget.markInterrupted();
            silentLog('data_cleanup', '读取会话子文件大小', error, stack);
          }
        }
      }
    }
  } catch (error, stack) {
    budget.markInterrupted();
    // 兜底：保留累计。
    silentLog('data_cleanup', '遍历会话并排除附件', error, stack);
  }
  return DataCleanupSizeReport(
    bytes: totalBytes,
    error: budget.incomplete ? _dataCleanupPartialScanError : null,
  );
}

Future<DataCleanupSizeReport> _isolateMeasureDirectory(String dir) async {
  final root = Directory(dir);
  final budget = _DataCleanupScanBudget();
  try {
    if (!await _cleanupDirectoryExists(root, budget: budget)) {
      return DataCleanupSizeReport.empty;
    }
    final stats = await _walkDirectoryStats(root, budget: budget);
    return DataCleanupSizeReport(
      bytes: stats.bytes,
      itemCount: stats.files,
      error: budget.incomplete ? _dataCleanupPartialScanError : null,
    );
  } catch (error, stack) {
    silentLog('data_cleanup', '检查待统计目录', error, stack);
    return DataCleanupSizeReport.unknown;
  }
}

Future<DataCleanupSizeReport> _isolateMeasureDirectoryExcluding(
  List<String> args,
) async {
  if (args.isEmpty) return DataCleanupSizeReport.empty;
  final root = Directory(args.first);
  final excludedRoots = args.skip(1).map(p.normalize).toList(growable: false);
  final budget = _DataCleanupScanBudget();
  try {
    if (!await _cleanupDirectoryExists(root, budget: budget)) {
      return DataCleanupSizeReport.empty;
    }
    final stats = await _walkDirectoryStats(
      root,
      excludedRoots: excludedRoots,
      budget: budget,
    );
    return DataCleanupSizeReport(
      bytes: stats.bytes,
      itemCount: stats.files,
      error: budget.incomplete ? _dataCleanupPartialScanError : null,
    );
  } catch (error, stack) {
    silentLog('data_cleanup', '检查带排除项的待统计目录', error, stack);
    return DataCleanupSizeReport.unknown;
  }
}

Future<DataCleanupSizeReport> _isolateMeasureFile(String path) async {
  final file = File(path);
  try {
    if (!await regularFileExistsBounded(
      file,
      timeout: _dataCleanupScanIdleTimeout,
      followLinks: false,
    )) {
      return DataCleanupSizeReport.empty;
    }
    return DataCleanupSizeReport(
      bytes: await file.length().timeout(_dataCleanupScanIdleTimeout),
      itemCount: 1,
    );
  } catch (error, stack) {
    silentLog('data_cleanup', '读取文件大小', error, stack);
    return DataCleanupSizeReport.unknown;
  }
}

Future<void> _isolateDeleteFile(String path) async {
  if (!_isSafeDeleteTarget(path)) {
    return;
  }
  final budget = _DataCleanupScanBudget();
  try {
    await _deletePathWithinCleanupBudget(
      path,
      allowedRoot: p.dirname(path),
      budget: budget,
    );
  } catch (error, stack) {
    // 上层会通过 controller refresh 兜底，单文件删除失败不致命。
    silentLog('data_cleanup', '删除文件', error, stack);
  }
}

Future<void> _isolateDeleteAttachments(String sessionsRoot) async {
  if (!_isSafeDeleteTarget(sessionsRoot)) {
    return;
  }
  final root = Directory(sessionsRoot);
  final budget = _DataCleanupScanBudget();
  try {
    if (!await _cleanupDirectoryExists(root, budget: budget)) return;
    await for (final entity
        in root.list(followLinks: false).timeout(_dataCleanupScanIdleTimeout)) {
      if (!budget.takeEntry()) break;
      if (entity is! Directory) {
        continue;
      }
      final name = p.basename(entity.path);
      if (name == 'attachments') {
        await _safeDeleteDirectoryAndRecreate(
          entity,
          budget: budget,
          allowedRoot: root.path,
        );
        if (budget.incomplete) break;
        continue;
      }
      final perSession = Directory(p.join(entity.path, 'attachments'));
      if (await _cleanupDirectoryExists(perSession, budget: budget)) {
        await _safeDeleteDirectoryAndRecreate(
          perSession,
          budget: budget,
          allowedRoot: root.path,
        );
        if (budget.incomplete) break;
      }
    }
  } catch (error, stack) {
    // 兜底：保持已删除部分，剩余目录可下次再清。
    silentLog('data_cleanup', '删除附件目录', error, stack);
  }
}

Future<void> _isolateDeleteDirectoryContents(String dir) async {
  if (!_isSafeDeleteTarget(dir)) {
    return;
  }
  final root = Directory(dir);
  final budget = _DataCleanupScanBudget();
  try {
    if (!await _cleanupDirectoryExists(root, budget: budget)) return;
    await _safeDeleteDirectoryAndRecreate(root, budget: budget);
  } catch (error, stack) {
    silentLog('data_cleanup', '检查待清理目录', error, stack);
  }
}

Future<void> _isolateDeleteDirectoryContentsExcluding(List<String> args) async {
  if (args.isEmpty) return;
  final dir = args.first;
  if (!_isSafeDeleteTarget(dir)) {
    return;
  }
  final root = Directory(dir);
  try {
    if (!await _cleanupDirectoryExists(root)) return;
    final excludedRoots = args.skip(1).map(p.normalize).toList(growable: false);
    await _deleteDirectoryContentsExcludingBounded(root, excludedRoots);
  } catch (error, stack) {
    silentLog('data_cleanup', '检查带排除项的待清理目录', error, stack);
  }
}

/// 防误删兜底：拒绝任何看起来像系统根 / HOME 根 / OpenHand 根的路径。
/// 即使上层逻辑出 bug 把 `/` 或 `~/.openhand` 传进来，也不会引发灾难。
///
/// **注意**：这里**不**强制路径必须在 `~/.openhand` 之下，因为技能目录、
/// LSP 安装目录可能被用户改到任意位置（例如外置硬盘）。我们只在路径明显
/// 危险时才拒绝。
bool _isSafeDeleteTarget(String path) {
  if (path.trim().isEmpty) {
    return false;
  }
  final normalized = p.normalize(path);
  if (!p.isAbsolute(normalized)) {
    return false;
  }
  // 单字符根、相对当前目录、或 path-segment 数量过少的路径一律拒绝。
  if (normalized == '/' ||
      normalized == '\\' ||
      normalized == '.' ||
      normalized == '..' ||
      normalized == '~') {
    return false;
  }
  // HOME / OpenHand root 一律拒绝（避免把整个 ~/.openhand 干掉导致 db 句柄崩溃）。
  final home = OpenHandPaths.environmentHomeDirectoryPath();
  if (home != null) {
    final normalizedHome = p.normalize(home);
    if (normalized == normalizedHome) {
      return false;
    }
  }
  final openhandRoot = p.normalize(OpenHandPaths.defaultRootDirectoryPath());
  if (normalized == openhandRoot) {
    return false;
  }
  // path 段数 < 2 通常意味着接近根目录（例如 "/usr"），过于危险。
  final segments = p.split(normalized).where((s) => s.isNotEmpty).toList();
  if (segments.length < 2) {
    return false;
  }
  return true;
}

Future<void> _safeDeleteDirectoryAndRecreate(
  Directory dir, {
  _DataCleanupScanBudget? budget,
  String? allowedRoot,
}) async {
  final activeBudget = budget ?? _DataCleanupScanBudget();
  try {
    await _deletePathWithinCleanupBudget(
      dir.path,
      allowedRoot: allowedRoot ?? dir.path,
      budget: activeBudget,
    );
  } catch (error, stack) {
    // 删除失败时仍尝试 recreate：保持调用方期望的"目录存在"语义。
    silentLog('data_cleanup', '删除目录', error, stack);
  }
  try {
    await createDirectoryBounded(
      dir,
      timeout: activeBudget.nextOperationTimeout(),
    );
  } catch (error, stack) {
    // recreate 失败也不抛——下游写入时会自行重试。
    silentLog('data_cleanup', '重建目录', error, stack);
  }
}

Future<BoundedDeleteResult> _deletePathWithinCleanupBudget(
  String path, {
  required String allowedRoot,
  required _DataCleanupScanBudget budget,
}) async {
  if (budget.exhausted) {
    budget.markInterrupted();
    throw TimeoutException('数据清理的删除时间额度已耗尽。');
  }
  final remaining = budget.remainingDurationForOperation();
  final operationTimeout = remaining < _dataCleanupScanIdleTimeout
      ? remaining
      : _dataCleanupScanIdleTimeout;
  try {
    final result = await deletePathBounded(
      p.absolute(path),
      policy: BoundedDeletePolicy(
        maxEntries: budget.remainingEntries,
        maxDepth: _maxDataCleanupDeleteDepth,
        directoryIdleTimeout: operationTimeout,
        operationTimeout: operationTimeout,
        totalTimeout: remaining,
      ),
      allowedRoot: p.absolute(allowedRoot),
    );
    budget.consumeEntries(result.plannedEntries);
    return result;
  } on BoundedDeleteException catch (error) {
    budget.consumeEntries(error.plannedEntries);
    if (error.reason == BoundedDeleteFailureReason.entryLimitExceeded ||
        error.reason == BoundedDeleteFailureReason.depthLimitExceeded ||
        error.reason == BoundedDeleteFailureReason.timeout) {
      budget.markInterrupted();
    }
    rethrow;
  }
}

class _DirStats {
  const _DirStats({required this.bytes, required this.files});
  final int bytes;
  final int files;
}

Future<_DirStats> _walkDirectoryStats(
  Directory dir, {
  List<String> excludedRoots = const <String>[],
  _DataCleanupScanBudget? budget,
}) async {
  int bytes = 0;
  int files = 0;
  final activeBudget = budget ?? _DataCleanupScanBudget();
  try {
    await for (final entity
        in dir
            .list(recursive: true, followLinks: false)
            .timeout(_dataCleanupScanIdleTimeout)) {
      if (!activeBudget.takeEntry()) break;
      if (entity is! File) {
        continue;
      }
      if (_isExcludedPath(entity.path, excludedRoots)) {
        continue;
      }
      try {
        bytes += await entity.length().timeout(
          activeBudget.nextOperationTimeout(),
        );
        files++;
      } catch (error, stack) {
        activeBudget.markInterrupted();
        // 文件并发被删 / 权限不足：跳过。
        silentLog('data_cleanup', '读取遍历项大小', error, stack);
      }
    }
  } catch (error, stack) {
    activeBudget.markInterrupted();
    // 列表失败：返回已经累计的部分。
    silentLog('data_cleanup', '遍历目录列表', error, stack);
  }
  return _DirStats(bytes: bytes, files: files);
}

bool _isExcludedPath(String path, List<String> excludedRoots) {
  if (excludedRoots.isEmpty) return false;
  final normalized = p.normalize(path);
  for (final root in excludedRoots) {
    if (root.isEmpty) continue;
    if (normalized == root || p.isWithin(root, normalized)) {
      return true;
    }
  }
  return false;
}

bool _containsExcludedPath(Directory dir, List<String> excludedRoots) {
  if (excludedRoots.isEmpty) return false;
  final normalized = p.normalize(dir.path);
  for (final root in excludedRoots) {
    if (root.isEmpty) continue;
    if (normalized == root || p.isWithin(normalized, root)) {
      return true;
    }
  }
  return false;
}

Future<void> _deleteDirectoryContentsExcludingBounded(
  Directory root,
  List<String> excludedRoots,
) async {
  final budget = _DataCleanupScanBudget();
  final pending = <Directory>[root];
  while (pending.isNotEmpty && !budget.exhausted) {
    final directory = pending.removeLast();
    try {
      await for (final entity
          in directory
              .list(followLinks: false)
              .timeout(budget.nextOperationTimeout())) {
        if (!budget.takeEntry()) return;
        if (_isExcludedPath(entity.path, excludedRoots)) continue;
        if (entity is Directory &&
            _containsExcludedPath(entity, excludedRoots)) {
          pending.add(entity);
          continue;
        }
        try {
          await _deletePathWithinCleanupBudget(
            entity.path,
            allowedRoot: root.path,
            budget: budget,
          );
        } catch (error, stack) {
          silentLog('data_cleanup', '删除排除项之外的目录项', error, stack);
          if (budget.incomplete) return;
        }
      }
    } catch (error, stack) {
      budget.markInterrupted();
      silentLog('data_cleanup', '列出排除项之外的目录内容', error, stack);
      return;
    }
  }
}
