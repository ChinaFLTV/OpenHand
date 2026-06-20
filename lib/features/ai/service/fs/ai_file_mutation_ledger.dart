// 文件变动 ledger（内容寻址 + 撤销/重做 + 级联追踪）。
//
// 存储布局（位于 ~/.openhand/file_history/ 之下）：
//
//   blobs/<sha[0..2]>/<sha>.txt       内容寻址的 UTF-8 文本 blob（去重）
//   sessions/<sessionId>/ledger.jsonl  追加式变动日志，每行一条 MutationRecord
//   sessions/<sessionId>/state.json    {"undone":["<recordId>", ...]}
//
// 核心语义：每次文件级写操作（Write/Edit/MultiEdit/NotebookEdit/DeleteFile/
// Bash 写入/MCP 文件写入等）在工具执行钩子里调用 [recordMutation] 同时落
// before/after 两份内容；撤销 X 时把磁盘文件恢复为 X.before 并把"X 之后所
// 有发生在同一文件上的记录"标记为 undone（级联）；重做 X 时把磁盘文件恢
// 复为 X.after 并仅清除 X 自己的 undone 标志。
//
// 该服务对底层备份缺失/损坏/IO 失败等做兜底：所有读写都走 silentLog，对
// 调用方暴露 success 标志而非抛出，UI 据此显示降级提示。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/unified_diff.dart' as unified_diff;

enum FileMutationKind { create, modify, delete }

class FileMutationRecord {
  const FileMutationRecord({
    required this.recordId,
    required this.sessionId,
    required this.toolCallId,
    required this.toolName,
    required this.filePath,
    required this.kind,
    required this.createdAt,
    required this.beforeSha,
    required this.afterSha,
    required this.beforeSize,
    required this.afterSize,
  });

  final String recordId;
  final String sessionId;
  final String toolCallId;
  final String toolName;
  final String filePath;
  final FileMutationKind kind;
  final DateTime createdAt;
  final String? beforeSha;
  final String? afterSha;
  final int beforeSize;
  final int afterSize;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': recordId,
    'session_id': sessionId,
    'tool_call_id': toolCallId,
    'tool_name': toolName,
    'path': filePath,
    'kind': kind.name,
    'ts': createdAt.toUtc().toIso8601String(),
    'before_sha': beforeSha,
    'after_sha': afterSha,
    'before_size': beforeSize,
    'after_size': afterSize,
  };

  static FileMutationRecord? tryFromJson(
    Map<String, Object?> json, {
    required String sessionId,
  }) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;
    final kindName = '${json['kind'] ?? 'modify'}';
    final kind = FileMutationKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => FileMutationKind.modify,
    );
    return FileMutationRecord(
      recordId: id,
      sessionId: sessionId,
      toolCallId: '${json['tool_call_id'] ?? ''}',
      toolName: '${json['tool_name'] ?? ''}',
      filePath: '${json['path'] ?? ''}',
      kind: kind,
      createdAt:
          DateTime.tryParse('${json['ts'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
      beforeSha: json['before_sha'] as String?,
      afterSha: json['after_sha'] as String?,
      beforeSize: (json['before_size'] as num?)?.toInt() ?? 0,
      afterSize: (json['after_size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// UI 渲染所需的派生状态（由 ledger 在查询时一次性算好）。
class FileMutationView {
  const FileMutationView({
    required this.record,
    required this.directlyUndone,
    required this.cascadeUndone,
    required this.canUndo,
    required this.canRedo,
    required this.lineDelta,
  });

  final FileMutationRecord record;

  /// 用户主动按了"撤销"。
  final bool directlyUndone;

  /// 因为同文件上更早的记录被撤销而被连带失效。
  final bool cascadeUndone;

  /// 当前是否处于可执行"撤销"的状态。
  final bool canUndo;

  /// 当前是否处于可执行"重做"的状态。
  final bool canRedo;

  /// 基于 before/after 快照派生的行级增删统计。快照不可用时为
  /// [FileMutationLineDelta.unavailable]，UI 不应回退显示字节差。
  final FileMutationLineDelta lineDelta;

  bool get isEffectivelyUndone => directlyUndone || cascadeUndone;
}

class FileMutationLineDelta {
  const FileMutationLineDelta({
    required this.addedLines,
    required this.removedLines,
    required this.available,
  });

  const FileMutationLineDelta.unavailable()
    : addedLines = 0,
      removedLines = 0,
      available = false;

  final int addedLines;
  final int removedLines;
  final bool available;

  bool get hasChanges => addedLines > 0 || removedLines > 0;

  FileMutationLineDelta operator +(FileMutationLineDelta other) {
    if (!available && !other.available) {
      return const FileMutationLineDelta.unavailable();
    }
    return FileMutationLineDelta(
      addedLines: addedLines + other.addedLines,
      removedLines: removedLines + other.removedLines,
      available: available || other.available,
    );
  }
}

class _FileMutationUndoState {
  const _FileMutationUndoState({
    required this.directlyUndone,
    required this.cascadeUndone,
    required this.canUndo,
    required this.canRedo,
  });

  final bool directlyUndone;
  final bool cascadeUndone;
  final bool canUndo;
  final bool canRedo;
}

class FileMutationOutcome {
  const FileMutationOutcome._({required this.success, this.errorMessage = ''});
  const FileMutationOutcome.ok() : this._(success: true);
  const FileMutationOutcome.fail(String message)
    : this._(success: false, errorMessage: message);

  final bool success;
  final String errorMessage;
}

/// Ledger 体积统计的轻量值对象。
class LedgerStatsSnapshot {
  const LedgerStatsSnapshot({
    required this.sessionCount,
    required this.recordCount,
    required this.blobCount,
  });

  final int sessionCount;
  final int recordCount;
  final int blobCount;
}

/// 用户可配置的 ledger 行为。持久化到 `<root>/config.json`。
class LedgerConfig {
  const LedgerConfig({
    this.maxVersionsPerFile = defaultMaxVersionsPerFile,
    this.autoCleanupDays = defaultAutoCleanupDays,
    this.miniDiffMaxBytes = defaultMiniDiffMaxBytes,
  });

  /// 每个会话内同一文件保留的最近 N 条变动。<=0 表示不限制。
  final int maxVersionsPerFile;

  /// 自动清理 N 天前的全部变动（启动时触发一次）。<=0 表示禁用。
  final int autoCleanupDays;

  /// mini-diff 切换阈值（KiB）。任一侧 > 此值（且 ≤ maxBytes）
  /// 时 unifiedDiffLineSummary 仅保留 +/- 行；超过 maxBytes 仍走 sha 占
  /// 位摘要。<=0 时退化为永远全量 diff（直到 maxBytes）。
  final int miniDiffMaxBytes;

  static const int defaultMaxVersionsPerFile = 10;
  static const int minMaxVersionsPerFile = 0;
  static const int maxMaxVersionsPerFile = 200;
  static const int defaultAutoCleanupDays = 30;
  static const int minAutoCleanupDays = 0;
  static const int maxAutoCleanupDays = 365;
  static const int defaultMiniDiffMaxBytes =
      unifiedDiffLineSummaryDefaultMiniDiffBytes;
  static const int minMiniDiffMaxBytes = 0;
  static const int maxMiniDiffMaxBytes = 256 * 1024;

  LedgerConfig copyWith({
    int? maxVersionsPerFile,
    int? autoCleanupDays,
    int? miniDiffMaxBytes,
  }) => LedgerConfig(
    maxVersionsPerFile: maxVersionsPerFile ?? this.maxVersionsPerFile,
    autoCleanupDays: autoCleanupDays ?? this.autoCleanupDays,
    miniDiffMaxBytes: miniDiffMaxBytes ?? this.miniDiffMaxBytes,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'max_versions_per_file': maxVersionsPerFile,
    'auto_cleanup_days': autoCleanupDays,
    'mini_diff_max_bytes': miniDiffMaxBytes,
  };

  static LedgerConfig fromJson(Map<String, Object?> json) {
    final maxV =
        (json['max_versions_per_file'] as num?)?.toInt() ??
        defaultMaxVersionsPerFile;
    final days =
        (json['auto_cleanup_days'] as num?)?.toInt() ?? defaultAutoCleanupDays;
    final mini =
        (json['mini_diff_max_bytes'] as num?)?.toInt() ??
        defaultMiniDiffMaxBytes;
    return LedgerConfig(
      maxVersionsPerFile: maxV
          .clamp(minMaxVersionsPerFile, maxMaxVersionsPerFile)
          .toInt(),
      autoCleanupDays: days
          .clamp(minAutoCleanupDays, maxAutoCleanupDays)
          .toInt(),
      miniDiffMaxBytes: mini
          .clamp(minMiniDiffMaxBytes, maxMiniDiffMaxBytes)
          .toInt(),
    );
  }
}

/// 极简 unified diff 行级摘要。共同行标 ` `，删除行 `-`，
/// 新增行 `+`。不做 LCS 最优——目标是粘到 PR/聊天里能一眼看出改了
/// 哪几行；提取成顶层函数便于单测。
///
/// 当任一侧大于 [maxBytes]（默认 256 KiB）时不再做完整逐行
/// 展开，避免在 UI 线程上炸成几万行。返回一行式占位摘要，包含双侧
/// 字节数 + sha256 前 12 位（若提供 [beforeSha]/[afterSha]），便于
/// 之后从 ledger blobs 拉原文核对。
///
/// 在 [miniDiffMaxBytes]（默认 32 KiB） < 任一侧 ≤ [maxBytes]
/// 的中间区间，返回「精简 mini-diff」——只保留 +/- 行，丢弃所有相
/// 同上下文行。这样既能让模型/用户看到差异主体，又把 token 量级压
/// 在数 KB 内，避免大文件在 UI/上下文里被全文 +context 撑爆。
const int unifiedDiffLineSummaryDefaultMaxBytes =
    unified_diff.kUnifiedDiffDefaultMaxBytes;
const int unifiedDiffLineSummaryDefaultMiniDiffBytes =
    unified_diff.kUnifiedDiffDefaultMiniDiffBytes;

String unifiedDiffLineSummary(
  String before,
  String after, {
  int maxBytes = unifiedDiffLineSummaryDefaultMaxBytes,
  int miniDiffMaxBytes = unifiedDiffLineSummaryDefaultMiniDiffBytes,
  String? beforeSha,
  String? afterSha,
}) {
  return unified_diff.unifiedDiffLineSummary(
    before,
    after,
    maxBytes: maxBytes,
    miniDiffMaxBytes: miniDiffMaxBytes,
    beforeSha: beforeSha,
    afterSha: afterSha,
  );
}

class AiFileMutationLedger {
  AiFileMutationLedger({String? rootDirectoryOverride})
    : _rootOverride = rootDirectoryOverride;

  static final RegExp _sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');
  static const Duration _staleAtomicArtifactAge = Duration(days: 1);
  static const int _legacyBlobRecoveryMaxFiles = 2000;
  static const int _blobRecoveryMaxBytes = 16 * 1024 * 1024;
  static const int _lineDeltaConcurrency = 4;

  final String? _rootOverride;
  final Random _rand = Random.secure();
  bool _migratedLegacy = false;
  Map<String, String>? _legacyBlobPathIndex;
  final Set<String> _legacyBlobRecoveryMisses = <String>{};

  // Per-session in-memory caches for records and undone set. The session
  // ledger / state files are mutated only through this class, so we can
  // invalidate the cache reliably whenever this instance writes. Cross-
  // process mutations (extremely rare for app state) would not be reflected,
  // but no such writers exist today; the trade-off saves up to N redundant
  // disk reads when N round summary cards open simultaneously on session
  // resume — each card was previously triggering a full ledger.jsonl scan
  // plus a state.json read.
  final Map<String, List<FileMutationRecord>> _recordsCache =
      <String, List<FileMutationRecord>>{};
  final Map<String, Set<String>> _undoneCache = <String, Set<String>>{};
  final Map<String, Future<FileMutationLineDelta>> _lineDeltaCache =
      <String, Future<FileMutationLineDelta>>{};

  void _invalidateSessionCache(String sessionId) {
    _recordsCache.remove(sessionId);
    _undoneCache.remove(sessionId);
    final prefix = '$sessionId::';
    _lineDeltaCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  void _invalidateAllCaches() {
    _recordsCache.clear();
    _undoneCache.clear();
    _lineDeltaCache.clear();
  }

  String get _root =>
      _rootOverride ??
      p.join(OpenHandPaths.defaultRootDirectoryPath(), 'file_history');

  Directory _blobsDir() => Directory(p.join(_root, 'blobs'));
  Directory _sessionsDir() => Directory(p.join(_root, 'sessions'));
  Directory _sessionDir(String sessionId) =>
      Directory(p.join(_sessionsDir().path, _safeSessionId(sessionId)));
  File _ledgerFile(String sessionId) =>
      File(p.join(_sessionDir(sessionId).path, 'ledger.jsonl'));
  File _stateFile(String sessionId) =>
      File(p.join(_sessionDir(sessionId).path, 'state.json'));

  /// 暴露给 UI 用：点击卡片 header 时把 ledger.jsonl 在系统
  /// 文件管理器里高亮。返回的文件可能尚未存在（会话尚未发生过 mutation）。
  File ledgerFileFor(String sessionId) => _ledgerFile(sessionId);
  File _configFile() => File(p.join(_root, 'config.json'));

  LedgerConfig? _cachedConfig;
  bool _ranAutoCleanup = false;

  Future<LedgerConfig> loadConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;
    try {
      final f = _configFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        if (raw.trim().isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, Object?>;
          _cachedConfig = LedgerConfig.fromJson(json);
          return _cachedConfig!;
        }
      }
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', 'loadConfig', error, stack);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'loadConfig', error, stack);
    }
    _cachedConfig = const LedgerConfig();
    return _cachedConfig!;
  }

  Future<void> saveConfig(LedgerConfig config) async {
    _cachedConfig = config;
    try {
      await _ensureInitialized();
      await writeFileAtomically(_configFile(), jsonEncode(config.toJson()));
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'saveConfig', error, stack);
    }
  }

  Future<void> _ensureInitialized() async {
    try {
      final blobs = _blobsDir();
      if (!await blobs.exists()) await blobs.create(recursive: true);
      final sessions = _sessionsDir();
      if (!await sessions.exists()) await sessions.create(recursive: true);
      if (!_migratedLegacy) {
        _migratedLegacy = true;
        unawaited(_migrateLegacyTempStorage());
      }
      if (!_ranAutoCleanup) {
        _ranAutoCleanup = true;
        // 测试场景下使用了 rootOverride，自动清理会与并发写入抢资源；只在
        // 真实运行（未传 override）路径上启用一次性自动清理。
        if (_rootOverride == null) {
          unawaited(_runAutoCleanupOnce());
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'init', error, stack);
    }
  }

  /// 启动后异步运行：按 [LedgerConfig.autoCleanupDays] 清理过期记录，再按
  /// [LedgerConfig.maxVersionsPerFile] 修剪每个文件的历史。失败仅日志。
  Future<void> _runAutoCleanupOnce() async {
    try {
      final config = await loadConfig();
      if (config.autoCleanupDays > 0) {
        await pruneOlderThan(Duration(days: config.autoCleanupDays));
      }
      if (config.maxVersionsPerFile > 0) {
        await pruneToMaxVersionsPerFile(config.maxVersionsPerFile);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'auto cleanup', error, stack);
    }
  }

  /// 一次性把 [Directory.systemTemp]/.openhand-file-history 的旧扁平结构
  /// 拷贝为 ledger 友好的 blob，丢失的元数据用合成 record 兜底。失败不
  /// 影响主流程，旧目录最终被删除。
  Future<void> _migrateLegacyTempStorage() async {
    try {
      final legacyDir = Directory(
        p.join(Directory.systemTemp.path, '.openhand-file-history'),
      );
      if (!await legacyDir.exists()) return;
      // 旧布局：<hash>/<versionId>.{content,meta.json}
      await for (final entity in legacyDir.list()) {
        if (entity is! Directory) continue;
        await for (final file in entity.list()) {
          if (file is! File || !file.path.endsWith('.content')) continue;
          try {
            final content = await file.readAsString();
            await _writeBlobIfMissing(_sha256Of(content), content);
          } on FileSystemException catch (error, stack) {
            if (!_isMissingFileSystemException(error)) {
              silentLog(
                'ai_file_mutation_ledger',
                'migrate blob',
                error,
                stack,
              );
            }
          } catch (error, stack) {
            silentLog('ai_file_mutation_ledger', 'migrate blob', error, stack);
          }
        }
      }
      try {
        await legacyDir.delete(recursive: true);
      } catch (error, stack) {
        silentLog('ai_file_mutation_ledger', 'delete legacy dir', error, stack);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'migrate legacy', error, stack);
    }
  }

  /// 记录一次文件级变动，同时持久化 before/after 两份内容（去重）。
  Future<FileMutationRecord?> recordMutation({
    required String sessionId,
    required String toolCallId,
    required String toolName,
    required String filePath,
    required FileMutationKind kind,
    required String? beforeContent,
    required String? afterContent,
  }) async {
    if (sessionId.trim().isEmpty || filePath.trim().isEmpty) return null;
    await _ensureInitialized();
    try {
      final sessionDir = _sessionDir(sessionId);
      if (!await sessionDir.exists()) await sessionDir.create(recursive: true);

      String? beforeSha;
      int beforeSize = 0;
      if (beforeContent != null) {
        beforeSha = _sha256Of(beforeContent);
        beforeSize = utf8.encode(beforeContent).length;
        await _writeBlobIfMissing(beforeSha, beforeContent);
      }
      String? afterSha;
      int afterSize = 0;
      if (afterContent != null) {
        afterSha = _sha256Of(afterContent);
        afterSize = utf8.encode(afterContent).length;
        await _writeBlobIfMissing(afterSha, afterContent);
      }

      final recordId =
          '${DateTime.now().toUtc().millisecondsSinceEpoch}_${_randomSuffix()}';
      final record = FileMutationRecord(
        recordId: recordId,
        sessionId: sessionId,
        toolCallId: toolCallId,
        toolName: toolName,
        filePath: p.normalize(filePath),
        kind: kind,
        createdAt: DateTime.now().toUtc(),
        beforeSha: beforeSha,
        afterSha: afterSha,
        beforeSize: beforeSize,
        afterSize: afterSize,
      );
      final ledger = _ledgerFile(sessionId);
      final line = '${jsonEncode(record.toJson())}\n';
      await ledger.writeAsString(line, mode: FileMode.append, flush: true);
      _invalidateSessionCache(sessionId);
      // 写入后按当前配置即时收紧每文件历史数。autoCleanupDays 在启动时已处理。
      try {
        final cfg = await loadConfig();
        if (cfg.maxVersionsPerFile > 0) {
          await _trimSessionFileVersions(
            sessionId,
            record.filePath,
            cfg.maxVersionsPerFile,
          );
        }
      } catch (error, stack) {
        silentLog('ai_file_mutation_ledger', 'post-record trim', error, stack);
      }
      return record;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'recordMutation', error, stack);
      return null;
    }
  }

  Future<List<FileMutationRecord>> recordsForSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return const <FileMutationRecord>[];
    final cached = _recordsCache[sessionId];
    if (cached != null) return cached;
    await _ensureInitialized();
    final ledger = _ledgerFile(sessionId);
    final records = <FileMutationRecord>[];
    try {
      if (!await ledger.exists()) {
        _recordsCache[sessionId] = const <FileMutationRecord>[];
        return const <FileMutationRecord>[];
      }
      final lines = await ledger.readAsLines();
      for (final raw in lines) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        try {
          final json = jsonDecode(trimmed) as Map<String, Object?>;
          final record = FileMutationRecord.tryFromJson(
            json,
            sessionId: sessionId,
          );
          if (record != null) records.add(record);
        } catch (error, stack) {
          silentLog(
            'ai_file_mutation_ledger',
            'parse ledger line',
            error,
            stack,
          );
        }
      }
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', 'read ledger', error, stack);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'read ledger', error, stack);
    }
    records.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final immutable = List<FileMutationRecord>.unmodifiable(records);
    _recordsCache[sessionId] = immutable;
    return immutable;
  }

  Future<List<FileMutationView>> viewsForToolCall({
    required String sessionId,
    required String toolCallId,
  }) async {
    if (toolCallId.trim().isEmpty) return const <FileMutationView>[];
    final all = await recordsForSession(sessionId);
    final undone = await _loadUndoneSet(sessionId);
    final matching = all
        .where((record) => record.toolCallId == toolCallId)
        .toList(growable: false);
    if (matching.isEmpty) return const <FileMutationView>[];
    final undoStates = _buildUndoStates(all, undone);
    return _buildViewsWithLineDeltas(matching, undoStates);
  }

  Future<FileMutationView?> viewForRecord({
    required String sessionId,
    required String recordId,
  }) async {
    final all = await recordsForSession(sessionId);
    final record = all.where((r) => r.recordId == recordId).firstOrNull;
    if (record == null) return null;
    final undone = await _loadUndoneSet(sessionId);
    final undoStates = _buildUndoStates(all, undone);
    return _buildView(
      record,
      undoStates[record.recordId]!,
      lineDelta: await _lineDeltaForRecord(record),
    );
  }

  /// 会话级 history inspector 用：一次性返回当前会话所有记录
  /// 的 view。比"对每条 record 调 viewForRecord"少一次磁盘扫一次 ledger。
  Future<List<FileMutationView>> viewsForSession(String sessionId) async {
    final all = await recordsForSession(sessionId);
    if (all.isEmpty) return const <FileMutationView>[];
    final undone = await _loadUndoneSet(sessionId);
    final undoStates = _buildUndoStates(all, undone);
    return _buildViewsWithLineDeltas(all, undoStates);
  }

  Future<List<FileMutationView>> _buildViewsWithLineDeltas(
    List<FileMutationRecord> records,
    Map<String, _FileMutationUndoState> undoStates,
  ) {
    return runOrderedWithConcurrencyLimit<FileMutationView>(
      itemCount: records.length,
      maxConcurrency: _lineDeltaConcurrency,
      task: (index) async {
        final record = records[index];
        return _buildView(
          record,
          undoStates[record.recordId]!,
          lineDelta: await _lineDeltaForRecord(record),
        );
      },
    );
  }

  FileMutationView _buildView(
    FileMutationRecord record,
    _FileMutationUndoState undoState, {
    required FileMutationLineDelta lineDelta,
  }) {
    return FileMutationView(
      record: record,
      directlyUndone: undoState.directlyUndone,
      cascadeUndone: undoState.cascadeUndone,
      canUndo: undoState.canUndo,
      canRedo: undoState.canRedo,
      lineDelta: lineDelta,
    );
  }

  Map<String, _FileMutationUndoState> _buildUndoStates(
    List<FileMutationRecord> all,
    Set<String> undoneSet,
  ) {
    final undoneFiles = <String>{};
    final states = <String, _FileMutationUndoState>{};
    for (final record in all) {
      final directlyUndone = undoneSet.contains(record.recordId);
      final cascadeUndone = undoneFiles.contains(record.filePath);
      states[record.recordId] = _FileMutationUndoState(
        directlyUndone: directlyUndone && !cascadeUndone,
        cascadeUndone: cascadeUndone,
        canUndo: !directlyUndone && !cascadeUndone,
        canRedo: directlyUndone || cascadeUndone,
      );
      if (directlyUndone) {
        undoneFiles.add(record.filePath);
      }
    }
    return states;
  }

  Future<FileMutationLineDelta> _lineDeltaForRecord(FileMutationRecord record) {
    final cacheKey = <String>[
      record.sessionId,
      record.recordId,
      record.beforeSha ?? '',
      record.afterSha ?? '',
      '${record.beforeSize}',
      '${record.afterSize}',
    ].join('::');
    return _lineDeltaCache.putIfAbsent(
      cacheKey,
      () => _computeLineDeltaForRecord(record),
    );
  }

  Future<FileMutationLineDelta> _computeLineDeltaForRecord(
    FileMutationRecord record,
  ) async {
    try {
      final snapshots = await readSnapshots(record);
      final beforeUnavailable =
          record.beforeSha != null && snapshots.before == null;
      final afterUnavailable =
          record.afterSha != null && snapshots.after == null;
      if (beforeUnavailable || afterUnavailable) {
        return const FileMutationLineDelta.unavailable();
      }
      final stats = unified_diff.unifiedDiffLineStatsFromText(
        snapshots.before ?? '',
        snapshots.after ?? '',
      );
      return FileMutationLineDelta(
        addedLines: stats.addedLines,
        removedLines: stats.removedLines,
        available: true,
      );
    } catch (error, stack) {
      silentLog(
        'ai_file_mutation_ledger',
        'computeLineDeltaForRecord',
        error,
        stack,
      );
      return const FileMutationLineDelta.unavailable();
    }
  }

  /// 撤销：把磁盘恢复到 [recordId] 的 before 状态，并把同文件上 ts >=
  /// recordId 的所有记录都标记 undone（级联）。
  Future<FileMutationOutcome> undoRecord({
    required String sessionId,
    required String recordId,
  }) async {
    await _ensureInitialized();
    try {
      final all = await recordsForSession(sessionId);
      final target = all.where((r) => r.recordId == recordId).firstOrNull;
      if (target == null) {
        return const FileMutationOutcome.fail('record-not-found');
      }

      // 恢复磁盘：before 为 null 表示这是 create，撤销 = 删除磁盘文件。
      final outFile = File(target.filePath);
      if (target.beforeSha == null) {
        if (await outFile.exists()) {
          try {
            await outFile.delete();
          } on FileSystemException catch (error, stack) {
            if (_isMissingFileSystemException(error)) {
              // 已被外部删除时，撤销 create 的目标状态已经达成。
            } else {
              silentLog('ai_file_mutation_ledger', 'undo delete', error, stack);
              return FileMutationOutcome.fail('delete-failed:$error');
            }
          } catch (error, stack) {
            silentLog('ai_file_mutation_ledger', 'undo delete', error, stack);
            return FileMutationOutcome.fail('delete-failed:$error');
          }
        }
      } else {
        final beforeContent = await _readBlob(target.beforeSha!);
        if (beforeContent == null) {
          return const FileMutationOutcome.fail('before-blob-missing');
        }
        try {
          await outFile.parent.create(recursive: true);
          await writeFileAtomically(outFile, beforeContent);
        } catch (error, stack) {
          silentLog('ai_file_mutation_ledger', 'undo write', error, stack);
          return FileMutationOutcome.fail('restore-failed:$error');
        }
      }

      // 级联标记
      final undone = await _loadUndoneSet(sessionId);
      for (final r in all) {
        if (r.filePath != target.filePath) continue;
        if (!r.createdAt.isBefore(target.createdAt)) {
          undone.add(r.recordId);
        }
      }
      await _saveUndoneSet(sessionId, undone);
      return const FileMutationOutcome.ok();
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'undoRecord', error, stack);
      return FileMutationOutcome.fail('$error');
    }
  }

  /// 重做：把磁盘恢复为 [recordId] 的 after，并仅清除自己的 undone 标志。
  Future<FileMutationOutcome> redoRecord({
    required String sessionId,
    required String recordId,
  }) async {
    await _ensureInitialized();
    try {
      final all = await recordsForSession(sessionId);
      final target = all.where((r) => r.recordId == recordId).firstOrNull;
      if (target == null) {
        return const FileMutationOutcome.fail('record-not-found');
      }

      final outFile = File(target.filePath);
      if (target.afterSha == null) {
        // delete 类型：重做 = 删除文件
        if (await outFile.exists()) {
          try {
            await outFile.delete();
          } on FileSystemException catch (error, stack) {
            if (_isMissingFileSystemException(error)) {
              // 已被外部删除时，重做 delete 的目标状态已经达成。
            } else {
              silentLog('ai_file_mutation_ledger', 'redo delete', error, stack);
              return FileMutationOutcome.fail('delete-failed:$error');
            }
          } catch (error, stack) {
            silentLog('ai_file_mutation_ledger', 'redo delete', error, stack);
            return FileMutationOutcome.fail('delete-failed:$error');
          }
        }
      } else {
        final afterContent = await _readBlob(target.afterSha!);
        if (afterContent == null) {
          return const FileMutationOutcome.fail('after-blob-missing');
        }
        try {
          await outFile.parent.create(recursive: true);
          await writeFileAtomically(outFile, afterContent);
        } catch (error, stack) {
          silentLog('ai_file_mutation_ledger', 'redo write', error, stack);
          return FileMutationOutcome.fail('restore-failed:$error');
        }
      }

      final undone = await _loadUndoneSet(sessionId);
      undone.remove(recordId);
      await _saveUndoneSet(sessionId, undone);
      return const FileMutationOutcome.ok();
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'redoRecord', error, stack);
      return FileMutationOutcome.fail('$error');
    }
  }

  Future<String?> readBlob(String sha) => _readBlob(sha);

  /// Reads both ledger snapshots with conservative recovery:
  ///
  /// - primary source: content-addressed blobs;
  /// - missing blob fallback: legacy pre-edit history snapshots by sha;
  /// - final fallback: current disk file only when its sha matches the ledger.
  ///
  /// The current-file check is intentionally hash-gated. Rendering a stale
  /// current file as the historical after/before side is worse than showing an
  /// unavailable snapshot because it creates a plausible but false diff.
  Future<({String? before, String? after})> readSnapshots(
    FileMutationRecord record,
  ) async {
    var before = record.beforeSha == null
        ? null
        : await _readBlob(record.beforeSha!);
    var after = record.afterSha == null
        ? null
        : await _readBlob(record.afterSha!);

    if (before == null && record.beforeSha != null) {
      before = await _readCurrentFileIfShaMatches(
        filePath: record.filePath,
        expectedSha: record.beforeSha!,
        expectedSize: record.beforeSize,
      );
    }
    if (after == null && record.afterSha != null) {
      after = await _readCurrentFileIfShaMatches(
        filePath: record.filePath,
        expectedSha: record.afterSha!,
        expectedSize: record.afterSize,
      );
    }
    return (before: before, after: after);
  }

  // ─────────────────────── 维护 / 数据清理 ───────────────────────

  /// 数据清理卡片用的轻量统计快照。统计 sessions / 记录条数 /
  /// blob 文件数（不含目录）。失败一律 silentLog 并以 0 返回部分项。
  Future<LedgerStatsSnapshot> statsSnapshot() async {
    await _ensureInitialized();
    var sessionCount = 0;
    var recordCount = 0;
    var blobCount = 0;
    try {
      final sessionsRoot = Directory(p.join(_root, 'sessions'));
      if (await sessionsRoot.exists()) {
        await for (final entity in sessionsRoot.list(followLinks: false)) {
          if (entity is! Directory) continue;
          sessionCount += 1;
          try {
            final ledgerFile = File(p.join(entity.path, 'ledger.jsonl'));
            if (!await ledgerFile.exists()) continue;
            final lines = await ledgerFile.readAsLines();
            recordCount += lines.where((l) => l.trim().isNotEmpty).length;
          } on FileSystemException catch (error, stack) {
            if (!_isMissingFileSystemException(error)) {
              silentLog(
                'ai_file_mutation_ledger',
                'statsSnapshot.session',
                error,
                stack,
              );
            }
          } catch (error, stack) {
            silentLog(
              'ai_file_mutation_ledger',
              'statsSnapshot.session',
              error,
              stack,
            );
          }
        }
      }
      final blobsRoot = Directory(p.join(_root, 'blobs'));
      if (await blobsRoot.exists()) {
        await for (final entity in blobsRoot.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File &&
              _blobShaFromFile(blob: entity, shard: entity.parent) != null) {
            blobCount += 1;
          }
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'statsSnapshot', error, stack);
    }
    return LedgerStatsSnapshot(
      sessionCount: sessionCount,
      recordCount: recordCount,
      blobCount: blobCount,
    );
  }

  Future<int> totalSizeBytes() async {
    await _ensureInitialized();
    var total = 0;
    try {
      final root = Directory(_root);
      if (!await root.exists()) return 0;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += (await entity.stat()).size;
          } on FileSystemException catch (error, stack) {
            if (!_isMissingFileSystemException(error)) {
              silentLog('ai_file_mutation_ledger', 'size single', error, stack);
            }
          } catch (error, stack) {
            silentLog('ai_file_mutation_ledger', 'size single', error, stack);
          }
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'totalSizeBytes', error, stack);
    }
    return total;
  }

  Future<void> clearAll() async {
    try {
      final root = Directory(_root);
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'clearAll', error, stack);
    }
  }

  Future<void> clearSession(String sessionId) async {
    try {
      final dir = _sessionDir(sessionId);
      if (await dir.exists()) await dir.delete(recursive: true);
      // 不主动 GC blobs，避免影响其他会话引用；总清理时统一处理。
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'clearSession', error, stack);
    }
    _invalidateSessionCache(sessionId);
    await gcUnreferencedBlobs();
  }

  /// 清理所有非 [keepSessionIds] 列出的会话目录。
  Future<int> clearSessionsExcept(Set<String> keepSessionIds) async {
    var removed = 0;
    try {
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return 0;
      final keep = keepSessionIds.map(_safeSessionId).toSet();
      await for (final entity in sessions.list()) {
        if (entity is! Directory) continue;
        if (keep.contains(p.basename(entity.path))) continue;
        try {
          await entity.delete(recursive: true);
          removed++;
        } catch (error, stack) {
          silentLog(
            'ai_file_mutation_ledger',
            'clearSessionsExcept',
            error,
            stack,
          );
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'clearSessionsExcept', error, stack);
    }
    _invalidateAllCaches();
    await gcUnreferencedBlobs();
    return removed;
  }

  /// 删除最早 `now - retention` 之前的全部会话 ledger（同时回收 blob）。
  Future<int> pruneOlderThan(Duration retention) async {
    var removed = 0;
    final pruned = <String>{};
    try {
      final cutoff = DateTime.now().subtract(retention);
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return 0;
      await for (final entity in sessions.list()) {
        if (entity is! Directory) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            pruned.add(p.basename(entity.path));
            await entity.delete(recursive: true);
            removed++;
          }
        } catch (error, stack) {
          silentLog('ai_file_mutation_ledger', 'pruneOlderThan', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'pruneOlderThan', error, stack);
    }
    for (final sid in pruned) {
      _invalidateSessionCache(sid);
    }
    await gcUnreferencedBlobs();
    return removed;
  }

  /// 仅对单个 (session,file) 做版本截断，避免 [recordMutation] 后扫描全库。
  /// 老条目被物理移除，blob gc 留给下次启动或显式调用。
  Future<void> _trimSessionFileVersions(
    String sessionId,
    String filePath,
    int maxVersionsPerFile,
  ) async {
    if (maxVersionsPerFile <= 0) return;
    final records = await recordsForSession(sessionId);
    final sameFile = records.where((r) => r.filePath == filePath).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (sameFile.length <= maxVersionsPerFile) return;
    final keepIds = sameFile
        .take(maxVersionsPerFile)
        .map((r) => r.recordId)
        .toSet();
    final survivors = <FileMutationRecord>[];
    for (final r in records) {
      if (r.filePath != filePath || keepIds.contains(r.recordId)) {
        survivors.add(r);
      }
    }
    final ledger = _ledgerFile(sessionId);
    if (survivors.isEmpty) {
      await _deleteFileIfPresent(ledger, 'trim ledger');
    } else {
      final buffer = StringBuffer();
      for (final r in survivors) {
        buffer.writeln(jsonEncode(r.toJson()));
      }
      await writeFileAtomically(ledger, buffer.toString());
    }
    _invalidateSessionCache(sessionId);
    final survivorIds = survivors.map((r) => r.recordId).toSet();
    final undone = await _loadUndoneSet(sessionId);
    undone.removeWhere((id) => !survivorIds.contains(id));
    await _saveUndoneSet(sessionId, undone);
  }

  /// 对每个文件每个会话只保留最近 [maxVersionsPerFile] 条记录的 before/after
  /// 引用；老记录从 ledger 中物理移除。返回被移除的记录条数。
  Future<int> pruneToMaxVersionsPerFile(int maxVersionsPerFile) async {
    if (maxVersionsPerFile <= 0) return 0;
    var removed = 0;
    try {
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return 0;
      await for (final entity in sessions.list()) {
        if (entity is! Directory) continue;
        final sessionId = p.basename(entity.path);
        final records = await recordsForSession(sessionId);
        // 按文件分组，按时间倒序保留前 N 条。
        final byFile = <String, List<FileMutationRecord>>{};
        for (final r in records) {
          byFile.putIfAbsent(r.filePath, () => <FileMutationRecord>[]).add(r);
        }
        final keepIds = <String>{};
        byFile.forEach((_, list) {
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          for (final r in list.take(maxVersionsPerFile)) {
            keepIds.add(r.recordId);
          }
        });
        final survivors = records
            .where((r) => keepIds.contains(r.recordId))
            .toList();
        removed += records.length - survivors.length;
        // 重写 ledger
        final ledger = _ledgerFile(sessionId);
        if (survivors.isEmpty) {
          await _deleteFileIfPresent(ledger, 'prune ledger');
        } else {
          final buffer = StringBuffer();
          for (final r in survivors) {
            buffer.writeln(jsonEncode(r.toJson()));
          }
          await writeFileAtomically(ledger, buffer.toString());
        }
        _invalidateSessionCache(sessionId);
        // 同步精简 undone 集合
        final undone = await _loadUndoneSet(sessionId);
        undone.removeWhere((id) => !keepIds.contains(id));
        await _saveUndoneSet(sessionId, undone);
      }
    } catch (error, stack) {
      silentLog(
        'ai_file_mutation_ledger',
        'pruneToMaxVersionsPerFile',
        error,
        stack,
      );
    }
    await gcUnreferencedBlobs();
    return removed;
  }

  /// 删除没有任何 ledger 引用的 blob。容错：失败仅日志，不抛出。
  /// 返回 (removed, bytesFreed) 以便 UI 展示统计。
  Future<({int removed, int bytesFreed})> gcUnreferencedBlobs() async {
    var removed = 0;
    var bytesFreed = 0;
    try {
      final referenced = <String>{};
      final sessions = _sessionsDir();
      if (await sessions.exists()) {
        await for (final entity in sessions.list()) {
          if (entity is! Directory) continue;
          final records = await recordsForSession(p.basename(entity.path));
          for (final r in records) {
            if (r.beforeSha != null) referenced.add(r.beforeSha!);
            if (r.afterSha != null) referenced.add(r.afterSha!);
          }
        }
      }
      final blobs = _blobsDir();
      if (!await blobs.exists()) return (removed: 0, bytesFreed: 0);
      await for (final shard in blobs.list()) {
        if (shard is! Directory) continue;
        await for (final blob in shard.list()) {
          if (blob is! File) continue;
          final sha = _blobShaFromFile(blob: blob, shard: shard);
          if (sha == null) {
            final bytes = await _deleteStaleAtomicBlobArtifact(blob);
            if (bytes > 0) {
              removed += 1;
              bytesFreed += bytes;
            }
            continue;
          }
          if (!referenced.contains(sha)) {
            try {
              final stat = await blob.stat();
              await blob.delete();
              removed += 1;
              bytesFreed += stat.size;
            } on FileSystemException catch (error, stack) {
              if (!_isMissingFileSystemException(error)) {
                silentLog('ai_file_mutation_ledger', 'gc blob', error, stack);
              }
            } catch (error, stack) {
              silentLog('ai_file_mutation_ledger', 'gc blob', error, stack);
            }
          }
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'gcUnreferencedBlobs', error, stack);
    }
    return (removed: removed, bytesFreed: bytesFreed);
  }

  String? _blobShaFromFile({required File blob, required Directory shard}) {
    final fileName = p.basename(blob.path);
    if (!fileName.endsWith('.txt')) {
      return null;
    }
    final sha = fileName.substring(0, fileName.length - '.txt'.length);
    if (!_sha256HexPattern.hasMatch(sha)) {
      return null;
    }
    if (p.basename(shard.path) != sha.substring(0, 2)) {
      return null;
    }
    return sha;
  }

  Future<int> _deleteStaleAtomicBlobArtifact(File file) async {
    final fileName = p.basename(file.path);
    final isAtomicArtifact =
        fileName.endsWith('.txt.tmp') || fileName.endsWith('.txt.bak');
    if (!isAtomicArtifact) {
      return 0;
    }
    try {
      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);
      if (age < _staleAtomicArtifactAge) {
        return 0;
      }
      await file.delete();
      return stat.size;
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog(
          'ai_file_mutation_ledger',
          'gc stale atomic blob artifact',
          error,
          stack,
        );
      }
      return 0;
    } catch (error, stack) {
      silentLog(
        'ai_file_mutation_ledger',
        'gc stale atomic blob artifact',
        error,
        stack,
      );
      return 0;
    }
  }

  bool _isMissingFileSystemException(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == 2 || code == 3) return true;
    final message = (error.osError?.message ?? error.message).toLowerCase();
    return message.contains('no such file') ||
        message.contains('cannot find') ||
        message.contains('path not found');
  }

  Future<void> _deleteFileIfPresent(File file, String where) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', where, error, stack);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', where, error, stack);
    }
  }

  // ───────────────────────── 内部工具 ─────────────────────────

  Future<Set<String>> _loadUndoneSet(String sessionId) async {
    final cached = _undoneCache[sessionId];
    if (cached != null) return Set<String>.from(cached);
    try {
      final state = _stateFile(sessionId);
      if (!await state.exists()) {
        _undoneCache[sessionId] = const <String>{};
        return <String>{};
      }
      final raw = await state.readAsString();
      if (raw.trim().isEmpty) {
        _undoneCache[sessionId] = const <String>{};
        return <String>{};
      }
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, Object?>) {
        final list = parsed['undone'];
        if (list is List) {
          final undone = list.whereType<String>().toSet();
          _undoneCache[sessionId] = Set<String>.unmodifiable(undone);
          return undone;
        }
      }
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', 'loadUndoneSet', error, stack);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'loadUndoneSet', error, stack);
    }
    _undoneCache[sessionId] = const <String>{};
    return <String>{};
  }

  Future<void> _saveUndoneSet(String sessionId, Set<String> undone) async {
    try {
      final state = _stateFile(sessionId);
      if (undone.isEmpty) {
        await _deleteFileIfPresent(state, 'delete empty undone state');
        _undoneCache[sessionId] = const <String>{};
        return;
      }
      final dir = _sessionDir(sessionId);
      if (!await dir.exists()) await dir.create(recursive: true);
      await writeFileAtomically(
        state,
        jsonEncode(<String, Object?>{'undone': undone.toList()..sort()}),
      );
      _undoneCache[sessionId] = Set<String>.unmodifiable(undone);
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', 'saveUndoneSet', error, stack);
      }
      _undoneCache.remove(sessionId);
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'saveUndoneSet', error, stack);
      _undoneCache.remove(sessionId);
    }
  }

  Future<void> _writeBlobIfMissing(String sha, String content) async {
    final shard = sha.substring(0, 2);
    final dir = Directory(p.join(_blobsDir().path, shard));
    final file = File(p.join(dir.path, '$sha.txt'));
    if (await file.exists()) return;
    if (!await dir.exists()) await dir.create(recursive: true);
    await writeFileAtomically(file, content);
  }

  Future<String?> _readBlob(String sha) async {
    if (!_sha256HexPattern.hasMatch(sha)) return null;
    try {
      final shard = sha.substring(0, 2);
      final file = File(p.join(_blobsDir().path, shard, '$sha.txt'));
      if (!await file.exists()) {
        return _recoverBlobFromLegacyVersions(sha);
      }
      return await file.readAsString();
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', 'readBlob', error, stack);
      }
      return null;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'readBlob', error, stack);
      return null;
    }
  }

  Future<String?> _readCurrentFileIfShaMatches({
    required String filePath,
    required String expectedSha,
    required int expectedSize,
  }) async {
    if (!_sha256HexPattern.hasMatch(expectedSha) || filePath.trim().isEmpty) {
      return null;
    }
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      if (expectedSize > 0 && stat.size != expectedSize) return null;
      if (stat.size > _blobRecoveryMaxBytes) return null;
      final content = await file.readAsString();
      if (_sha256Of(content) != expectedSha) return null;
      await _cacheRecoveredBlob(expectedSha, content, 'cache current blob');
      return content;
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog(
          'ai_file_mutation_ledger',
          'recover current file blob',
          error,
          stack,
        );
      }
      return null;
    } catch (error, stack) {
      silentLog(
        'ai_file_mutation_ledger',
        'recover current file blob',
        error,
        stack,
      );
      return null;
    }
  }

  Future<String?> _recoverBlobFromLegacyVersions(String sha) async {
    if (!_sha256HexPattern.hasMatch(sha)) return null;
    if (_legacyBlobRecoveryMisses.contains(sha)) return null;
    try {
      final index = await _legacyBlobIndex();
      final path = index[sha];
      if (path == null || path.isEmpty) {
        _legacyBlobRecoveryMisses.add(sha);
        return null;
      }
      final file = File(path);
      if (!await file.exists()) {
        _legacyBlobRecoveryMisses.add(sha);
        return null;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size > _blobRecoveryMaxBytes) {
        _legacyBlobRecoveryMisses.add(sha);
        return null;
      }
      final content = await file.readAsString();
      if (_sha256Of(content) != sha) {
        _legacyBlobRecoveryMisses.add(sha);
        return null;
      }
      await _cacheRecoveredBlob(sha, content, 'cache legacy blob');
      return content;
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog(
          'ai_file_mutation_ledger',
          'recover legacy blob',
          error,
          stack,
        );
      }
      _legacyBlobRecoveryMisses.add(sha);
      return null;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'recover legacy blob', error, stack);
      _legacyBlobRecoveryMisses.add(sha);
      return null;
    }
  }

  Future<Map<String, String>> _legacyBlobIndex() async {
    final cached = _legacyBlobPathIndex;
    if (cached != null) return cached;
    final index = <String, String>{};
    final legacyRoot = Directory(p.join(_root, 'legacy_versions'));
    try {
      if (!await legacyRoot.exists()) {
        _legacyBlobPathIndex = const <String, String>{};
        return _legacyBlobPathIndex!;
      }
      var scanned = 0;
      await for (final entity in legacyRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (scanned >= _legacyBlobRecoveryMaxFiles) break;
        if (entity is! File || !entity.path.endsWith('.content')) continue;
        scanned += 1;
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file ||
              stat.size > _blobRecoveryMaxBytes) {
            continue;
          }
          final content = await entity.readAsString();
          index.putIfAbsent(_sha256Of(content), () => entity.path);
        } on FileSystemException catch (error, stack) {
          if (!_isMissingFileSystemException(error)) {
            silentLog(
              'ai_file_mutation_ledger',
              'index legacy blob',
              error,
              stack,
            );
          }
        } catch (error, stack) {
          silentLog(
            'ai_file_mutation_ledger',
            'index legacy blob',
            error,
            stack,
          );
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'index legacy blobs', error, stack);
    }
    _legacyBlobPathIndex = Map<String, String>.unmodifiable(index);
    return _legacyBlobPathIndex!;
  }

  Future<void> _cacheRecoveredBlob(
    String sha,
    String content,
    String where,
  ) async {
    try {
      await _writeBlobIfMissing(sha, content);
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', where, error, stack);
    }
  }

  String _sha256Of(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(
      6,
      (_) => chars[_rand.nextInt(chars.length)],
    ).join();
  }

  String _safeSessionId(String raw) {
    final trimmed = raw.trim();
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
  }

  // ─────────────────────────── 跨会话查询 / 导出导入 ─────────────────────────
  /// 列出磁盘上所有可见的 sessionId。失败仅日志，返回空列表。
  Future<List<String>> listSessionIds() async {
    await _ensureInitialized();
    final out = <String>[];
    try {
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return out;
      await for (final entity in sessions.list()) {
        if (entity is Directory) {
          out.add(p.basename(entity.path));
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'listSessionIds', error, stack);
    }
    out.sort();
    return out;
  }

  /// 跨会话搜索 — 尽量在内存中过滤；UI 应控制 limit。
  Future<List<FileMutationView>> searchRecords({
    Iterable<String>? sessionIds,
    Iterable<FileMutationKind>? kinds,
    Iterable<String>? toolNames,
    String? pathContains,
    DateTime? since,
    DateTime? until,
    int limit = 200,
  }) async {
    final ids = sessionIds == null
        ? await listSessionIds()
        : sessionIds.toList();
    final kindSet = kinds?.toSet();
    final toolSet = toolNames?.map((s) => s.toLowerCase()).toSet();
    final pathNeedle = pathContains?.trim().toLowerCase();
    final out = <FileMutationView>[];
    for (final sid in ids) {
      if (out.length >= limit) break;
      final all = await recordsForSession(sid);
      if (all.isEmpty) continue;
      final undone = await _loadUndoneSet(sid);
      final undoStates = _buildUndoStates(all, undone);
      final filtered = <FileMutationRecord>[];
      for (final r in all) {
        if (out.length + filtered.length >= limit) break;
        if (kindSet != null && !kindSet.contains(r.kind)) continue;
        if (toolSet != null &&
            toolSet.isNotEmpty &&
            !toolSet.contains(r.toolName.toLowerCase())) {
          continue;
        }
        if (pathNeedle != null &&
            pathNeedle.isNotEmpty &&
            !r.filePath.toLowerCase().contains(pathNeedle)) {
          continue;
        }
        if (since != null && r.createdAt.isBefore(since)) continue;
        if (until != null && r.createdAt.isAfter(until)) continue;
        filtered.add(r);
      }
      if (filtered.isNotEmpty) {
        out.addAll(await _buildViewsWithLineDeltas(filtered, undoStates));
      }
    }
    // 最近优先。
    out.sort((a, b) => b.record.createdAt.compareTo(a.record.createdAt));
    return out;
  }

  /// 导出指定会话（默认全部）的 ledger 为 JSON bundle，包含所有引用过的
  /// blob（base64 编码）。可被 [importBundleJson] 还原。
  Future<String> exportBundleJson({Iterable<String>? sessionIds}) async {
    final ids = sessionIds == null
        ? await listSessionIds()
        : sessionIds.toList();
    final sessions = <Map<String, Object?>>[];
    final referenced = <String>{};
    for (final sid in ids) {
      final records = await recordsForSession(sid);
      final undone = await _loadUndoneSet(sid);
      sessions.add({
        'session_id': sid,
        'records': records.map((r) => r.toJson()).toList(),
        'undone': undone.toList(),
      });
      for (final r in records) {
        if (r.beforeSha != null) referenced.add(r.beforeSha!);
        if (r.afterSha != null) referenced.add(r.afterSha!);
      }
    }
    final blobMap = <String, String>{};
    for (final sha in referenced) {
      final content = await _readBlob(sha);
      if (content != null) {
        blobMap[sha] = base64Encode(utf8.encode(content));
      }
    }
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'kind': 'openhand.file_mutation_ledger.bundle',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'sessions': sessions,
      'blobs_b64': blobMap,
    });
  }

  /// 把任意 records 集合打成 bundle JSON（携带其引用的 blob）。
  /// 用于"导出过滤后的搜索结果"等场景。records 按 sessionId 分组写入。
  Future<String> exportRecordsAsBundleJson(
    Iterable<FileMutationRecord> records,
  ) async {
    final bySession = <String, List<FileMutationRecord>>{};
    final referenced = <String>{};
    for (final r in records) {
      bySession.putIfAbsent(r.sessionId, () => <FileMutationRecord>[]).add(r);
      if (r.beforeSha != null) referenced.add(r.beforeSha!);
      if (r.afterSha != null) referenced.add(r.afterSha!);
    }
    final sessions = <Map<String, Object?>>[];
    for (final entry in bySession.entries) {
      final undone = await _loadUndoneSet(entry.key);
      final ids = entry.value.map((r) => r.recordId).toSet();
      sessions.add({
        'session_id': entry.key,
        'records': entry.value.map((r) => r.toJson()).toList(),
        // 仅保留与本子集相关的 undone id（避免泄露未导出的 record）。
        'undone': undone.where(ids.contains).toList(),
      });
    }
    final blobMap = <String, String>{};
    for (final sha in referenced) {
      final content = await _readBlob(sha);
      if (content != null) {
        blobMap[sha] = base64Encode(utf8.encode(content));
      }
    }
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'kind': 'openhand.file_mutation_ledger.bundle',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'sessions': sessions,
      'blobs_b64': blobMap,
    });
  }

  /// 还原导出 bundle。返回写入的 record 数（去重统计）。失败仅日志，按
  /// session 粒度容错继续。
  Future<int> importBundleJson(String json) async {
    await _ensureInitialized();
    var imported = 0;
    Map<String, Object?> parsed;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, Object?>) return 0;
      parsed = decoded;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'importBundle parse', error, stack);
      return 0;
    }
    if ('${parsed['kind'] ?? ''}' != 'openhand.file_mutation_ledger.bundle') {
      return 0;
    }
    // 1) 先恢复 blob — 之后的 record 才有指向。
    final blobMap = parsed['blobs_b64'];
    if (blobMap is Map) {
      for (final entry in blobMap.entries) {
        final sha = '${entry.key}';
        final raw = '${entry.value}';
        if (sha.isEmpty || raw.isEmpty) continue;
        try {
          final content = utf8.decode(base64Decode(raw));
          // sha 一致性轻校验：不强制（容许导出方使用不同算法/截断）。
          await _writeBlobIfMissing(sha, content);
        } catch (error, stack) {
          silentLog(
            'ai_file_mutation_ledger',
            'importBundle blob $sha',
            error,
            stack,
          );
        }
      }
    }
    // 2) 再合并各 session 的 ledger.jsonl（追加去重 by recordId）。
    final sessions = parsed['sessions'];
    if (sessions is! List) return imported;
    for (final sessionEntry in sessions) {
      if (sessionEntry is! Map<String, Object?>) continue;
      final sid = '${sessionEntry['session_id'] ?? ''}'.trim();
      if (sid.isEmpty) continue;
      final records = sessionEntry['records'];
      if (records is! List) continue;
      try {
        final dir = _sessionDir(sid);
        if (!await dir.exists()) await dir.create(recursive: true);
        final ledger = _ledgerFile(sid);
        final existing = await recordsForSession(sid);
        final existingIds = existing.map((r) => r.recordId).toSet();
        final buffer = StringBuffer();
        try {
          if (await ledger.exists()) {
            buffer.write(await ledger.readAsString());
            if (!buffer.toString().endsWith('\n') && buffer.isNotEmpty) {
              buffer.writeln();
            }
          }
        } on FileSystemException catch (error, stack) {
          if (!_isMissingFileSystemException(error)) {
            silentLog(
              'ai_file_mutation_ledger',
              'importBundle read existing ledger',
              error,
              stack,
            );
          }
        }
        for (final raw in records) {
          if (raw is! Map<String, Object?>) continue;
          final id = '${raw['id'] ?? ''}'.trim();
          if (id.isEmpty || existingIds.contains(id)) continue;
          buffer.writeln(jsonEncode(raw));
          existingIds.add(id);
          imported += 1;
        }
        await writeFileAtomically(ledger, buffer.toString());
        _invalidateSessionCache(sid);
        // 还原 undone 集合：合并存在的 undone 列表。
        final undoneList = sessionEntry['undone'];
        if (undoneList is List) {
          final cur = await _loadUndoneSet(sid);
          for (final item in undoneList) {
            cur.add('$item');
          }
          await _saveUndoneSet(sid, cur);
        }
      } catch (error, stack) {
        silentLog(
          'ai_file_mutation_ledger',
          'importBundle session $sid',
          error,
          stack,
        );
      }
    }
    return imported;
  }
}
