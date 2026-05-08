/// 2026-04-26 — 数据清理 service。
///
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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/data/database_service.dart';
import '../../ai/ai_session_controller.dart';
import '../../ai/service/ai_file_mutation_ledger.dart';
import '../../ai/service/web_fetch/web_fetch_cache_store.dart';
import '../../ai/service/web_fetch/web_fetch_telemetry_store.dart';
import '../../ai/service/web_search/web_search_cache_store.dart';
import '../../ai/service/web_search/web_search_telemetry_store.dart';
import '../../crons/crons_controller.dart';
import '../../mcp/mcp_controller.dart';
import '../../memory/memory_controller.dart';
import '../../skills/skills_controller.dart';
import 'data_cleanup_models.dart';

/// 数据清理 service：纯实例化（无全局状态），由 UI 层按需创建。
class DataCleanupService {
  DataCleanupService({
    required AiSessionController aiSessionController,
    required CronsController cronsController,
    required MemoryController memoryController,
    required McpController mcpController,
    required SkillsController skillsController,
    required SettingsController settingsController,
  }) : _aiSessionController = aiSessionController,
       _cronsController = cronsController,
       _memoryController = memoryController,
       _mcpController = mcpController,
       _skillsController = skillsController,
       _settingsController = settingsController;

  final AiSessionController _aiSessionController;
  final CronsController _cronsController;
  final MemoryController _memoryController;
  final McpController _mcpController;
  final SkillsController _skillsController;
  final SettingsController _settingsController;

  // ---------------------------------------------------------------------------
  // 体积探测
  // ---------------------------------------------------------------------------

  /// 多媒体附件总大小：扫描每个会话目录下的 `attachments/` 子目录 +
  /// 旧版 `~/.openhand/sessions/attachments/` 的统一目录。
  Future<DataCleanupSizeReport> measureMultimedia() {
    final root = OpenHandPaths.defaultSessionsDirectoryPath();
    return compute(_isolateMeasureAttachments, root);
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

  /// 应用缓存目录。
  Future<DataCleanupSizeReport> measureAppCache() {
    return compute(
      _isolateMeasureDirectory,
      OpenHandPaths.defaultCacheDirectoryPath(),
    );
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
        'LENGTH(IFNULL(content, \'\')) '
        '+ LENGTH(IFNULL(title, \'\')) '
        '+ LENGTH(IFNULL(tags_json, \'\'))'
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
      silentLog('data_cleanup', 'measureUserMemory', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }

  /// MCP 配置文件大小。
  Future<DataCleanupSizeReport> measureMcpConfig() {
    return compute(
      _isolateMeasureFile,
      _settingsController.mcpServersFilePath,
    );
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

  /// 2026-05-03 文件变动 ledger 体积（`~/.openhand/file_history/`）。
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

  /// 所有分类合计。计算独立分支的并集，**不会**重复加和。
  Future<DataCleanupSizeReport> measureAll() async {
    final results = await Future.wait<DataCleanupSizeReport>(<
      Future<DataCleanupSizeReport>
    >[
      measureMultimedia(),
      measureSessions(),
      measureAppCache(),
      measureLogs(),
      measureUserMemory(),
      measureMcpConfig(),
      measureSkillsDirectory(),
      measureLspDirectory(),
      measureMutationLedger(),
    ]);
    return results.fold<DataCleanupSizeReport>(
      DataCleanupSizeReport.empty,
      (acc, item) => acc + item,
    );
  }

  // ---------------------------------------------------------------------------
  // 清理动作
  // ---------------------------------------------------------------------------

  /// 删除所有附件目录里的文件。会话行本身保留——附件引用变成"找不到
  /// 文件"，UI 层会自动降级展示。
  Future<void> cleanMultimedia() {
    return compute(
      _isolateDeleteAttachments,
      OpenHandPaths.defaultSessionsDirectoryPath(),
    );
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
    await compute(
      _isolateDeleteDirectoryContents,
      OpenHandPaths.defaultCacheDirectoryPath(),
    );
  }

  /// 清空 cron 执行历史 + 日志目录。
  Future<void> cleanLogs() async {
    await _cronsController.clearAllHistory();
    await compute(
      _isolateDeleteDirectoryContents,
      OpenHandPaths.defaultLogsDirectoryPath(),
    );
  }

  /// 清空用户记忆条目（含用户画像）。直接走数据库整表删除，然后让
  /// controller 重新加载，避免逐行 delete 的 N 次 IO。
  Future<void> cleanUserMemory() async {
    try {
      final db = DatabaseService.instance.database;
      await db.delete('memories');
    } catch (error, stack) {
      silentLog('data_cleanup', 'cleanUserMemory/delete', error, stack);
    }
    try {
      await _memoryController.refresh();
    } catch (error, stack) {
      silentLog('data_cleanup', 'cleanUserMemory/refresh', error, stack);
    }
  }

  /// 删除 MCP Server 配置文件，然后让 controller 重新加载（变成空列表）。
  Future<void> cleanMcpConfig() async {
    final path = _settingsController.mcpServersFilePath;
    await compute(_isolateDeleteFile, path);
    try {
      await _mcpController.refresh();
    } catch (error, stack) {
      silentLog('data_cleanup', 'cleanMcpConfig/refresh', error, stack);
    }
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
      silentLog('data_cleanup', 'cleanSkillsDirectory/refresh', error, stack);
    }
  }

  /// 清空 LSP 安装目录。下次使用对应语言时会触发重新下载。
  Future<void> cleanLspDirectory() {
    return compute(
      _isolateDeleteDirectoryContents,
      OpenHandPaths.defaultLspDirectoryPath(),
    );
  }

  /// 2026-05-03 清空文件变动 ledger（所有会话的 jsonl + state +
  /// blob）。调用后卡片侧 undo/redo 会退化为 metadata-only 列表。
  Future<void> cleanMutationLedger() async {
    try {
      await AiFileMutationLedger().clearAll();
    } catch (error, stack) {
      silentLog('data_cleanup', 'cleanMutationLedger', error, stack);
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
        silentLog('data_cleanup', 'cleanAll/$name', error, stack);
      }
    }

    await runStep('multimedia', cleanMultimedia);
    await runStep('appCache', cleanAppCache);
    await runStep('logs', cleanLogs);
    await runStep('userMemory', cleanUserMemory);
    await runStep('mcpConfig', cleanMcpConfig);
    await runStep('skillsDirectory', cleanSkillsDirectory);
    await runStep('lspDirectory', cleanLspDirectory);
    await runStep('mutationLedger', cleanMutationLedger);
    // 会话放在最后清理：上面的步骤即便意外失败，残留附件引用也已经
    // 失效，但 sessions 表仍在；如果反过来先清 sessions，再清附件失败，
    // 用户看到的是"会话没了，但附件目录还在占空间"。
    await runStep('sessions', cleanSessions);
    return errors;
  }

  // ---------------------------------------------------------------------------
  // DB 体积估算（主 isolate）
  // ---------------------------------------------------------------------------

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
      silentLog('data_cleanup', 'measureSessionsDb', error, stack);
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
      silentLog('data_cleanup', 'measureCronHistoryDb', error, stack);
      return DataCleanupSizeReport.unknown;
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate worker functions（必须是顶层或静态以便序列化）
// ---------------------------------------------------------------------------

/// 在 isolate 内统计 sessions 目录下所有 `attachments/` 子目录的体积与
/// 文件数。
DataCleanupSizeReport _isolateMeasureAttachments(String sessionsRoot) {
  final root = Directory(sessionsRoot);
  if (!root.existsSync()) {
    return DataCleanupSizeReport.empty;
  }
  int totalBytes = 0;
  int totalFiles = 0;
  try {
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      // 该会话子目录里，只算 `attachments/`；旧版顶层 attachments 目录
      // 自身就是一个匹配项（其名字就是 `attachments`）。
      final attachmentsName = p.basename(entity.path);
      if (attachmentsName == 'attachments') {
        final stats = _walkDirectoryStats(entity);
        totalBytes += stats.bytes;
        totalFiles += stats.files;
        continue;
      }
      final perSession = Directory(p.join(entity.path, 'attachments'));
      if (perSession.existsSync()) {
        final stats = _walkDirectoryStats(perSession);
        totalBytes += stats.bytes;
        totalFiles += stats.files;
      }
    }
  } catch (_) {
    // 子目录不可读：保留已经累计的部分，避免一棵坏分支吞掉全部统计。
  }
  return DataCleanupSizeReport(bytes: totalBytes, itemCount: totalFiles);
}

/// 在 isolate 内统计 sessions 目录下"非附件"内容（例如旧版 JSON）。
DataCleanupSizeReport _isolateMeasureSessionsExcludingAttachments(
  String sessionsRoot,
) {
  final root = Directory(sessionsRoot);
  if (!root.existsSync()) {
    return const DataCleanupSizeReport(bytes: 0);
  }
  int totalBytes = 0;
  try {
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is File) {
        // 旧版 `session-*.json`。
        try {
          totalBytes += entity.lengthSync();
        } catch (_) {
          // 文件被并发删除等：忽略。
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
        for (final inner in entity.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (inner is! File) {
            continue;
          }
          if (p.split(inner.path).contains('attachments')) {
            continue;
          }
          try {
            totalBytes += inner.lengthSync();
          } catch (_) {
            // ignore
          }
        }
      }
    }
  } catch (_) {
    // 兜底：保留累计。
  }
  return DataCleanupSizeReport(bytes: totalBytes);
}

DataCleanupSizeReport _isolateMeasureDirectory(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) {
    return DataCleanupSizeReport.empty;
  }
  final stats = _walkDirectoryStats(root);
  return DataCleanupSizeReport(bytes: stats.bytes, itemCount: stats.files);
}

DataCleanupSizeReport _isolateMeasureFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return DataCleanupSizeReport.empty;
  }
  try {
    return DataCleanupSizeReport(bytes: file.lengthSync(), itemCount: 1);
  } catch (_) {
    return DataCleanupSizeReport.unknown;
  }
}

void _isolateDeleteFile(String path) {
  if (!_isSafeDeleteTarget(path)) {
    return;
  }
  final file = File(path);
  if (!file.existsSync()) {
    return;
  }
  try {
    file.deleteSync();
  } catch (_) {
    // ignore — caller will fall back to controller refresh.
  }
}

void _isolateDeleteAttachments(String sessionsRoot) {
  if (!_isSafeDeleteTarget(sessionsRoot)) {
    return;
  }
  final root = Directory(sessionsRoot);
  if (!root.existsSync()) {
    return;
  }
  try {
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = p.basename(entity.path);
      if (name == 'attachments') {
        _safeDeleteDirectoryAndRecreate(entity);
        continue;
      }
      final perSession = Directory(p.join(entity.path, 'attachments'));
      if (perSession.existsSync()) {
        _safeDeleteDirectoryAndRecreate(perSession);
      }
    }
  } catch (_) {
    // 兜底：保持已删除部分，剩余目录可下次再清。
  }
}

void _isolateDeleteDirectoryContents(String dir) {
  if (!_isSafeDeleteTarget(dir)) {
    return;
  }
  final root = Directory(dir);
  if (!root.existsSync()) {
    return;
  }
  try {
    for (final entity in root.listSync(followLinks: false)) {
      try {
        if (entity is Directory) {
          entity.deleteSync(recursive: true);
        } else {
          entity.deleteSync();
        }
      } catch (_) {
        // 单个文件删除失败：忽略，继续下一个。
      }
    }
  } catch (_) {
    // 列表失败：忽略。
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
  // 单字符根、相对当前目录、或 path-segment 数量过少的路径一律拒绝。
  if (normalized == '/' ||
      normalized == '\\' ||
      normalized == '.' ||
      normalized == '..' ||
      normalized == '~') {
    return false;
  }
  // HOME / OpenHand root 一律拒绝（避免把整个 ~/.openhand 干掉导致 db 句柄崩溃）。
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
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

void _safeDeleteDirectoryAndRecreate(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } catch (_) {
    // 删除失败时仍尝试 recreate：保持调用方期望的"目录存在"语义。
  }
  try {
    dir.createSync(recursive: true);
  } catch (_) {
    // recreate 失败也不抛——下游写入时会自行重试。
  }
}

class _DirStats {
  const _DirStats({required this.bytes, required this.files});
  final int bytes;
  final int files;
}

_DirStats _walkDirectoryStats(Directory dir) {
  int bytes = 0;
  int files = 0;
  try {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      try {
        bytes += entity.lengthSync();
        files++;
      } catch (_) {
        // 文件并发被删 / 权限不足：跳过。
      }
    }
  } catch (_) {
    // 列表失败：返回已经累计的部分。
  }
  return _DirStats(bytes: bytes, files: files);
}
