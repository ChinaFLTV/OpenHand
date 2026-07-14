// 文件变动 ledger（内容寻址 + 撤销/重做 + 级联追踪）。
// 存储布局（位于 ~/.openhand/file_history/ 之下）：
//   blobs/<sha[0..2]>/<sha>.txt       内容寻址的 UTF-8 文本 blob（去重）
//   sessions/<sessionId>/ledger.jsonl  追加式变动日志，每行一条 MutationRecord
//   sessions/<sessionId>/state.json    {"undone":["<recordId>", ...]}
// 核心语义：每次文件级写操作（Write/Edit/MultiEdit/NotebookEdit/DeleteFile/
// Bash 写入/MCP 文件写入等）在工具执行钩子里调用 [recordMutation] 同时落
// before/after 两份内容；撤销 X 时把磁盘文件恢复为 X.before 并把"X 之后所
// 有发生在同一文件上的记录"标记为 undone（级联）；重做 X 时把磁盘文件恢
// 复为 X.after 并仅清除 X 自己的 undone 标志。
// 可恢复的记录级失败返回降级结果；初始化与配置写入失败向调用方传播。

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
import '../../../../shared/util/bounded_base64.dart';
import '../../../../shared/util/bounded_delete.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/exponential_backoff.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../../../shared/util/unified_diff.dart' as unified_diff;

const int _fileMutationRecordIdMaxCharacters = 512;

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
    final id = optionalStringFromValue(json['id']);
    if (id == null || id.length > _fileMutationRecordIdMaxCharacters) {
      return null;
    }
    final kind = enumByNameOr(
      FileMutationKind.values,
      json['kind'],
      fallback: FileMutationKind.modify,
    );
    return FileMutationRecord(
      recordId: id,
      sessionId: sessionId,
      toolCallId: stringFromValue(json['tool_call_id']),
      toolName: stringFromValue(json['tool_name']),
      filePath: stringFromValue(json['path']),
      kind: kind,
      createdAt: utcDateTimeFromValue(json['ts']) ?? DateTime.now().toUtc(),
      beforeSha: optionalStringFromValue(json['before_sha']),
      afterSha: optionalStringFromValue(json['after_sha']),
      beforeSize: nonNegativeIntFromValue(json['before_size'], fallback: 0),
      afterSize: nonNegativeIntFromValue(json['after_size'], fallback: 0),
    );
  }
}

final class _LedgerSessionMutationLane {
  final SerialTaskQueue queue = SerialTaskQueue();
  int pending = 0;
  Future<void> tail = Future<void>.value();
}

Iterable<String> _ledgerLines(String content) sync* {
  var start = 0;
  for (var index = 0; index < content.length; index++) {
    if (content.codeUnitAt(index) != 0x0a) continue;
    yield content.substring(start, index);
    start = index + 1;
  }
  if (start < content.length) {
    yield content.substring(start);
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
  static const IntValueRange _maxVersionsPerFileRange = IntValueRange(
    fallback: defaultMaxVersionsPerFile,
    min: minMaxVersionsPerFile,
    max: maxMaxVersionsPerFile,
  );
  static const IntValueRange _autoCleanupDaysRange = IntValueRange(
    fallback: defaultAutoCleanupDays,
    min: minAutoCleanupDays,
    max: maxAutoCleanupDays,
  );
  static const IntValueRange _miniDiffMaxBytesRange = IntValueRange(
    fallback: defaultMiniDiffMaxBytes,
    min: minMiniDiffMaxBytes,
    max: maxMiniDiffMaxBytes,
  );

  static int maxVersionsPerFileFromValue(Object? value) {
    return _maxVersionsPerFileRange.fromValue(value);
  }

  static int normalizeMaxVersionsPerFile(int value) {
    return _maxVersionsPerFileRange.normalize(value);
  }

  static int autoCleanupDaysFromValue(Object? value) {
    return _autoCleanupDaysRange.fromValue(value);
  }

  static int normalizeAutoCleanupDays(int value) {
    return _autoCleanupDaysRange.normalize(value);
  }

  static int miniDiffMaxBytesFromValue(Object? value) {
    return _miniDiffMaxBytesRange.fromValue(value);
  }

  static int normalizeMiniDiffMaxBytes(int value) {
    return _miniDiffMaxBytesRange.normalize(value);
  }

  LedgerConfig copyWith({
    int? maxVersionsPerFile,
    int? autoCleanupDays,
    int? miniDiffMaxBytes,
  }) => LedgerConfig(
    maxVersionsPerFile: normalizeMaxVersionsPerFile(
      maxVersionsPerFile ?? this.maxVersionsPerFile,
    ),
    autoCleanupDays: normalizeAutoCleanupDays(
      autoCleanupDays ?? this.autoCleanupDays,
    ),
    miniDiffMaxBytes: normalizeMiniDiffMaxBytes(
      miniDiffMaxBytes ?? this.miniDiffMaxBytes,
    ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'max_versions_per_file': normalizeMaxVersionsPerFile(maxVersionsPerFile),
    'auto_cleanup_days': normalizeAutoCleanupDays(autoCleanupDays),
    'mini_diff_max_bytes': normalizeMiniDiffMaxBytes(miniDiffMaxBytes),
  };

  static LedgerConfig fromJson(Map<String, Object?> json) {
    return LedgerConfig(
      maxVersionsPerFile: maxVersionsPerFileFromValue(
        json['max_versions_per_file'],
      ),
      autoCleanupDays: autoCleanupDaysFromValue(json['auto_cleanup_days']),
      miniDiffMaxBytes: miniDiffMaxBytesFromValue(json['mini_diff_max_bytes']),
    );
  }
}

/// 极简 unified diff 行级摘要。共同行标 ` `，删除行 `-`，
/// 新增行 `+`。不做 LCS 最优——目标是粘到 PR/聊天里能一眼看出改了
/// 哪几行。
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
  factory AiFileMutationLedger({String? rootDirectory}) {
    if (rootDirectory != null && nullIfBlank(rootDirectory) == null) {
      throw ArgumentError.value(
        rootDirectory,
        'rootDirectory',
        'Must not be blank.',
      );
    }
    final root = p.normalize(
      p.absolute(
        rootDirectory?.trim() ??
            p.join(OpenHandPaths.defaultRootDirectoryPath(), 'file_history'),
      ),
    );
    return _instances.putIfAbsent(root, () => AiFileMutationLedger._(root));
  }

  AiFileMutationLedger._(this._rootDirectory);

  static final Map<String, AiFileMutationLedger> _instances =
      <String, AiFileMutationLedger>{};

  static final RegExp _sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _unsafeSessionIdCharPattern = RegExp(r'[^a-zA-Z0-9_\-.]');
  static const Duration _staleAtomicArtifactAge = Duration(days: 1);
  static const int _initializationRetryBaseMs = 1000;
  static const int _initializationRetryCapMs = 60000;
  static const int _legacyBlobRecoveryMaxFiles = 2000;
  static const int _blobRecoveryMaxBytes = 16 * kBytesPerMiB;
  static const int _maxConfigBytes = 64 * kBytesPerKiB;
  static const int _maxStateBytes = 2 * kBytesPerMiB;
  static const int _maxLedgerBytes = 64 * kBytesPerMiB;
  static const int _maxBlobBase64Characters =
      (_blobRecoveryMaxBytes * 4 ~/ 3) + 8;
  static const int _maxSessionIdCharacters = 120;
  static const int _sanitizedSessionIdPrefixCharacters = 80;
  static const int _lineDeltaConcurrency = 4;
  static const int _maxCachedRecordSessions = 32;
  static const int _maxCachedRecords = 12000;
  static const int _maxCachedUndoneSessions = 64;
  static const int _maxCachedUndoneIds = 12000;
  static const int _maxCachedLineDeltas = 2048;
  static const int _maxRecordsPerLedger = 100000;
  static const int _maxMalformedLedgerLines = 256;
  static const int _maxSearchResults = 2000;
  static const int _maxExportSessions = 1000;
  static const int _maxExportRecords = 10000;
  static const int _maxExportBlobBytes = 64 * kBytesPerMiB;
  static const int _maxBundleJsonCharacters = 128 * kBytesPerMiB;
  static const int _maxSessionScanEntries = 10000;
  static const int _maxBlobScanEntries = 100000;
  static const int _maxLegacyMigrationEntries = 10000;
  static const Duration _ledgerTreeScanTimeout = Duration(seconds: 30);
  static const BoundedDeletePolicy _ledgerTreeDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: _maxSessionScanEntries + _maxBlobScanEntries,
        maxDepth: 32,
      );
  static const BoundedDeletePolicy _legacyTreeDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: _maxLegacyMigrationEntries + 1,
        maxDepth: 32,
        totalTimeout: _ledgerTreeScanTimeout,
      );

  /// Upper bound for the negative-cache of blob shas that failed legacy
  /// recovery. Keeps the set from growing without limit across long sessions
  /// while still skipping repeated lookups for recently-missed shas.
  static const int _maxLegacyBlobRecoveryMisses = 4096;

  final Random _rand = Random.secure();
  final String _rootDirectory;
  Future<void>? _initializationFuture;
  bool _initialized = false;
  Object? _initializationError;
  StackTrace? _initializationErrorStack;
  DateTime? _nextInitializationRetryAt;
  int _initializationFailureCount = 0;
  Map<String, String>? _legacyBlobPathIndex;
  final Set<String> _legacyBlobRecoveryMisses = <String>{};
  final Map<String, _LedgerSessionMutationLane> _sessionMutationLanes =
      <String, _LedgerSessionMutationLane>{};
  Completer<void>? _maintenanceGate;

  // Per-session in-memory caches for records and undone set. The session
  // ledger / state files are mutated only through this class, so we can
  // invalidate the cache reliably whenever this instance writes. Cross-
  // process mutations (extremely rare for app state) would not be reflected,
  // but no such writers exist today; the trade-off saves up to N redundant
  // disk reads when N round summary cards open simultaneously on session
  // resume — each card was previously triggering a full ledger.jsonl scan
  // plus a state.json read.
  final LifecycleLruCache<List<FileMutationRecord>> _recordsCache =
      LifecycleLruCache<List<FileMutationRecord>>(
        maxEntries: _maxCachedRecordSessions,
        maxCost: _maxCachedRecords,
        costOf: (records) => records.length,
      );
  final LifecycleLruCache<Set<String>> _undoneCache =
      LifecycleLruCache<Set<String>>(
        maxEntries: _maxCachedUndoneSessions,
        maxCost: _maxCachedUndoneIds,
        costOf: (ids) => ids.length,
      );
  final LifecycleLruCache<Future<FileMutationLineDelta>> _lineDeltaCache =
      LifecycleLruCache<Future<FileMutationLineDelta>>(
        maxEntries: _maxCachedLineDeltas,
      );

  void _invalidateSessionCache(String sessionId) {
    final cacheKey = _safeSessionId(sessionId);
    _recordsCache.remove(cacheKey);
    _undoneCache.remove(cacheKey);
    final prefix = '$cacheKey::';
    _lineDeltaCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  void _invalidateAllCaches() {
    _recordsCache.clear();
    _undoneCache.clear();
    _lineDeltaCache.clear();
  }

  Future<T> _enqueueSessionMutation<T>(
    String sessionId,
    Future<T> Function() mutation, {
    bool waitForMaintenance = true,
    bool ensureInitialized = false,
  }) async {
    if (waitForMaintenance) {
      while (_maintenanceGate != null) {
        await _maintenanceGate!.future;
      }
    }
    if (ensureInitialized) await _ensureInitialized();
    final key = _safeSessionId(sessionId);
    final lane = _sessionMutationLanes.putIfAbsent(
      key,
      _LedgerSessionMutationLane.new,
    );
    lane.pending += 1;
    final future = lane.queue.enqueue(mutation);
    lane.tail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future.whenComplete(() {
      lane.pending -= 1;
      if (lane.pending == 0 && identical(_sessionMutationLanes[key], lane)) {
        _sessionMutationLanes.remove(key);
      }
    });
  }

  Future<T> _runExclusiveMaintenance<T>(Future<T> Function() operation) async {
    while (_maintenanceGate != null) {
      await _maintenanceGate!.future;
    }
    final maintenance = Completer<void>();
    _maintenanceGate = maintenance;
    final pendingMutations = _sessionMutationLanes.values
        .map((lane) => lane.tail)
        .toList(growable: false);
    try {
      await Future.wait<void>(pendingMutations);
      return await operation();
    } finally {
      if (!maintenance.isCompleted) maintenance.complete();
      if (identical(_maintenanceGate, maintenance)) {
        _maintenanceGate = null;
      }
    }
  }

  String get _root => _rootDirectory;

  Directory _blobsDir() => Directory(p.join(_root, 'blobs'));
  Directory _sessionsDir() => Directory(p.join(_root, 'sessions'));
  Directory _sessionDir(String sessionId) =>
      Directory(p.join(_sessionsDir().path, _safeSessionId(sessionId)));

  Future<BoundedDirectoryListing> _listSessionEntries() {
    return listDirectoryBounded(
      _sessionsDir(),
      maxEntries: _maxSessionScanEntries,
    );
  }

  Future<BoundedDirectoryListing> _listBlobEntries() {
    return listDirectoryBounded(
      _blobsDir(),
      maxEntries: _maxBlobScanEntries,
      recursive: true,
      totalTimeout: _ledgerTreeScanTimeout,
    );
  }

  File _ledgerFile(String sessionId) =>
      File(p.join(_sessionDir(sessionId).path, 'ledger.jsonl'));
  File _stateFile(String sessionId) =>
      File(p.join(_sessionDir(sessionId).path, 'state.json'));

  /// 暴露给 UI 用：点击卡片 header 时把 ledger.jsonl 在系统
  /// 文件管理器里高亮。返回的文件可能尚未存在（会话尚未发生过 mutation）。
  File ledgerFileFor(String sessionId) => _ledgerFile(sessionId);
  File _configFile() => File(p.join(_root, 'config.json'));

  LedgerConfig? _cachedConfig;

  Future<LedgerConfig> loadConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;
    try {
      final f = _configFile();
      if (await f.exists()) {
        final raw = await readBoundedFileString(f, maxBytes: _maxConfigBytes);
        final text = nullIfBlank(raw);
        if (text != null) {
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            _cachedConfig = LedgerConfig.fromJson(
              stringKeyedMapFromValue(decoded),
            );
            return _cachedConfig!;
          }
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
    try {
      await _ensureInitialized();
      await writeFileAtomically(_configFile(), jsonEncode(config.toJson()));
      _cachedConfig = config;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'saveConfig', error, stack);
      rethrow;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final pending = _initializationFuture;
    if (pending != null) return pending;
    final retryAt = _nextInitializationRetryAt;
    final previousError = _initializationError;
    if (retryAt != null &&
        previousError != null &&
        DateTime.now().toUtc().isBefore(retryAt)) {
      Error.throwWithStackTrace(
        previousError,
        _initializationErrorStack ?? StackTrace.current,
      );
    }
    final future = _initializeOnce();
    _initializationFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    }
  }

  Future<void> _initializeOnce() async {
    try {
      final blobs = _blobsDir();
      if (!await blobs.exists()) await blobs.create(recursive: true);
      final sessions = _sessionsDir();
      if (!await sessions.exists()) await sessions.create(recursive: true);
      await _migrateLegacyTempStorage();
      await _runAutoCleanupOnce();
      _initialized = true;
      _resetInitializationFailure();
    } catch (error, stack) {
      _initializationFailureCount++;
      _initializationError = error;
      _initializationErrorStack = stack;
      _nextInitializationRetryAt = DateTime.now().toUtc().add(
        Duration(
          milliseconds: exponentialBackoffMs(
            attempt: _initializationFailureCount,
            baseMs: _initializationRetryBaseMs,
            capMs: _initializationRetryCapMs,
          ),
        ),
      );
      silentLog('ai_file_mutation_ledger', 'init', error, stack);
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _resetInitializationFailure() {
    _initializationError = null;
    _initializationErrorStack = null;
    _nextInitializationRetryAt = null;
    _initializationFailureCount = 0;
  }

  /// 初始化时按 [LedgerConfig.autoCleanupDays] 清理过期记录，再按
  /// [LedgerConfig.maxVersionsPerFile] 修剪每个文件的历史。
  Future<void> _runAutoCleanupOnce() async {
    try {
      final config = await loadConfig();
      var shouldCollectBlobs = false;
      if (config.autoCleanupDays > 0) {
        await _pruneOlderThan(Duration(days: config.autoCleanupDays));
        shouldCollectBlobs = true;
      }
      if (config.maxVersionsPerFile > 0) {
        await _pruneToMaxVersionsPerFile(
          config.maxVersionsPerFile,
          initializeRecordReads: false,
        );
        shouldCollectBlobs = true;
      }
      if (shouldCollectBlobs) {
        await _gcUnreferencedBlobs(initializeRecordReads: false);
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'auto cleanup', error, stack);
    }
  }

  /// 一次性把 [Directory.systemTemp]/.openhand-file-history 的旧扁平结构
  /// 拷贝为 ledger 友好的 blob，丢失的元数据用合成 record 兜底。失败不
  /// 影响主流程；仅在完整扫描后删除旧目录。
  Future<void> _migrateLegacyTempStorage() async {
    try {
      final legacyDir = Directory(
        p.join(Directory.systemTemp.path, '.openhand-file-history'),
      );
      if (!await legacyDir.exists()) return;
      // 旧布局：<hash>/<versionId>.{content,meta.json}
      final listing = await listDirectoryBounded(
        legacyDir,
        maxEntries: _maxLegacyMigrationEntries,
        recursive: true,
        totalTimeout: _ledgerTreeScanTimeout,
      );
      for (final file in listing.entries.whereType<File>()) {
        if (!file.path.endsWith('.content')) continue;
        try {
          final content = await readBoundedFileString(
            file,
            maxBytes: _blobRecoveryMaxBytes,
          );
          await _writeBlobIfMissing(_sha256Of(content), content);
        } on FileSystemException catch (error, stack) {
          if (!_isMissingFileSystemException(error)) {
            silentLog('ai_file_mutation_ledger', 'migrate blob', error, stack);
          }
        } catch (error, stack) {
          silentLog('ai_file_mutation_ledger', 'migrate blob', error, stack);
        }
      }
      if (!listing.truncated) {
        try {
          await deletePathBounded(
            p.absolute(legacyDir.path),
            policy: _legacyTreeDeletePolicy,
            allowedRoot: p.absolute(Directory.systemTemp.path),
          );
        } catch (error, stack) {
          silentLog(
            'ai_file_mutation_ledger',
            'delete legacy dir',
            error,
            stack,
          );
        }
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
  }) {
    return _enqueueSessionMutation(
      sessionId,
      () => _recordMutationLocked(
        sessionId: sessionId,
        toolCallId: toolCallId,
        toolName: toolName,
        filePath: filePath,
        kind: kind,
        beforeContent: beforeContent,
        afterContent: afterContent,
      ),
      ensureInitialized: true,
    );
  }

  Future<FileMutationRecord?> _recordMutationLocked({
    required String sessionId,
    required String toolCallId,
    required String toolName,
    required String filePath,
    required FileMutationKind kind,
    required String? beforeContent,
    required String? afterContent,
  }) async {
    final normalizedSessionId = nullIfBlank(sessionId);
    final normalizedFilePath = nullIfBlank(filePath);
    if (normalizedSessionId == null || normalizedFilePath == null) {
      return null;
    }
    final normalizedToolCallId = nullIfBlank(toolCallId) ?? '';
    final normalizedToolName = nullIfBlank(toolName) ?? '';
    try {
      final sessionDir = _sessionDir(normalizedSessionId);
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
        sessionId: normalizedSessionId,
        toolCallId: normalizedToolCallId,
        toolName: normalizedToolName,
        filePath: p.normalize(normalizedFilePath),
        kind: kind,
        createdAt: DateTime.now().toUtc(),
        beforeSha: beforeSha,
        afterSha: afterSha,
        beforeSize: beforeSize,
        afterSize: afterSize,
      );
      final ledger = _ledgerFile(normalizedSessionId);
      final line = '${jsonEncode(record.toJson())}\n';
      await ledger.writeAsString(line, mode: FileMode.append, flush: true);
      _invalidateSessionCache(normalizedSessionId);
      // 写入后按当前配置即时收紧每文件历史数。autoCleanupDays 在启动时已处理。
      try {
        final cfg = await loadConfig();
        if (cfg.maxVersionsPerFile > 0) {
          await _trimSessionFileVersions(
            normalizedSessionId,
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
    return (await _recordsForSessionResult(sessionId)).records;
  }

  Future<({List<FileMutationRecord> records, bool succeeded})>
  _recordsForSessionResult(String sessionId, {bool initialize = true}) async {
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null) {
      return (records: const <FileMutationRecord>[], succeeded: false);
    }
    final cacheKey = _safeSessionId(normalizedSessionId);
    final cached = _recordsCache.get(cacheKey);
    if (cached != null) return (records: cached, succeeded: true);
    if (initialize) await _ensureInitialized();
    final ledger = _ledgerFile(normalizedSessionId);
    final records = <FileMutationRecord>[];
    try {
      if (!await ledger.exists()) {
        _recordsCache.put(cacheKey, const <FileMutationRecord>[]);
        return (records: const <FileMutationRecord>[], succeeded: true);
      }
      final content = await readBoundedFileString(
        ledger,
        maxBytes: _maxLedgerBytes,
      );
      var hitRecordLimit = false;
      var malformedLines = 0;
      Object? firstMalformedError;
      StackTrace? firstMalformedStack;
      for (final raw in _ledgerLines(content)) {
        final trimmed = nullIfBlank(raw);
        if (trimmed == null) continue;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
          final record = FileMutationRecord.tryFromJson(
            stringKeyedMapFromValue(decoded),
            sessionId: normalizedSessionId,
          );
          if (record != null) {
            if (records.length >= _maxRecordsPerLedger) {
              hitRecordLimit = true;
              break;
            }
            records.add(record);
          }
        } catch (error, stack) {
          malformedLines += 1;
          firstMalformedError ??= error;
          firstMalformedStack ??= stack;
          if (malformedLines >= _maxMalformedLedgerLines) {
            throw const FormatException(
              'Ledger malformed record limit exceeded.',
            );
          }
        }
      }
      if (hitRecordLimit) {
        throw const FormatException('Ledger record limit exceeded.');
      }
      if (malformedLines > 0) {
        silentLog(
          'ai_file_mutation_ledger',
          'ignored $malformedLines malformed ledger records',
          firstMalformedError!,
          firstMalformedStack,
        );
      }
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', 'read ledger', error, stack);
      }
      return (records: const <FileMutationRecord>[], succeeded: false);
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'read ledger', error, stack);
      return (records: const <FileMutationRecord>[], succeeded: false);
    }
    records.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final immutable = List<FileMutationRecord>.unmodifiable(records);
    _recordsCache.put(cacheKey, immutable);
    return (records: immutable, succeeded: true);
  }

  Future<List<FileMutationView>> viewsForToolCall({
    required String sessionId,
    required String toolCallId,
  }) async {
    final normalizedToolCallId = nullIfBlank(toolCallId);
    if (normalizedToolCallId == null) return const <FileMutationView>[];
    final viewsByToolCall = await viewsForToolCalls(
      sessionId: sessionId,
      toolCallIds: <String>[normalizedToolCallId],
    );
    return viewsByToolCall[normalizedToolCallId] ?? const <FileMutationView>[];
  }

  /// Counts mutation records for the requested tool calls with one ledger
  /// scan. IDs that have no records are omitted from the result.
  Future<Map<String, int>> recordCountsForToolCalls({
    required String sessionId,
    required Iterable<String> toolCallIds,
  }) async {
    final all = await recordsForSession(sessionId);
    if (all.isEmpty) return const <String, int>{};
    final countsByToolCall = <String, int>{};
    for (final record in all) {
      final toolCallId = nullIfBlank(record.toolCallId);
      if (toolCallId == null) continue;
      countsByToolCall.update(
        toolCallId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (countsByToolCall.isEmpty) return const <String, int>{};

    final requestedCounts = <String, int>{};
    for (final rawToolCallId in toolCallIds) {
      final toolCallId = nullIfBlank(rawToolCallId);
      if (toolCallId == null || requestedCounts.containsKey(toolCallId)) {
        continue;
      }
      final count = countsByToolCall[toolCallId];
      if (count != null) requestedCounts[toolCallId] = count;
    }
    return Map<String, int>.unmodifiable(requestedCounts);
  }

  /// Builds mutation views for multiple tool calls with one ledger/state read.
  /// Requested IDs and their views retain ledger order; IDs without records
  /// are omitted. Line-delta work remains bounded by [_lineDeltaConcurrency].
  Future<Map<String, List<FileMutationView>>> viewsForToolCalls({
    required String sessionId,
    required Iterable<String> toolCallIds,
  }) async {
    final all = await recordsForSession(sessionId);
    if (all.isEmpty) return const <String, List<FileMutationView>>{};
    final availableToolCallIds = <String>{
      for (final record in all)
        if (nullIfBlank(record.toolCallId) case final toolCallId?) toolCallId,
    };
    if (availableToolCallIds.isEmpty) {
      return const <String, List<FileMutationView>>{};
    }

    final requestedToolCallIds = <String>[];
    final requestedToolCallIdSet = <String>{};
    for (final rawToolCallId in toolCallIds) {
      final toolCallId = nullIfBlank(rawToolCallId);
      if (toolCallId != null &&
          availableToolCallIds.contains(toolCallId) &&
          requestedToolCallIdSet.add(toolCallId)) {
        requestedToolCallIds.add(toolCallId);
      }
    }
    if (requestedToolCallIds.isEmpty) {
      return const <String, List<FileMutationView>>{};
    }

    final matching = all
        .where(
          (record) =>
              requestedToolCallIdSet.contains(nullIfBlank(record.toolCallId)),
        )
        .toList(growable: false);
    final undone = await _loadUndoneSet(sessionId);
    final undoStates = _buildUndoStates(all, undone);
    final views = await _buildViewsWithLineDeltas(matching, undoStates);
    final mutableViewsByToolCall = <String, List<FileMutationView>>{
      for (final toolCallId in requestedToolCallIds)
        toolCallId: <FileMutationView>[],
    };
    for (final view in views) {
      final toolCallId = nullIfBlank(view.record.toolCallId);
      if (toolCallId != null) {
        mutableViewsByToolCall[toolCallId]?.add(view);
      }
    }
    return Map<String, List<FileMutationView>>.unmodifiable(
      <String, List<FileMutationView>>{
        for (final entry in mutableViewsByToolCall.entries)
          entry.key: List<FileMutationView>.unmodifiable(entry.value),
      },
    );
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
      _safeSessionId(record.sessionId),
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
  }) {
    return _enqueueSessionMutation(
      sessionId,
      () => _undoRecordLocked(sessionId: sessionId, recordId: recordId),
      ensureInitialized: true,
    );
  }

  Future<FileMutationOutcome> _undoRecordLocked({
    required String sessionId,
    required String recordId,
  }) async {
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
  }) {
    return _enqueueSessionMutation(
      sessionId,
      () => _redoRecordLocked(sessionId: sessionId, recordId: recordId),
      ensureInitialized: true,
    );
  }

  Future<FileMutationOutcome> _redoRecordLocked({
    required String sessionId,
    required String recordId,
  }) async {
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
        final listing = await _listSessionEntries();
        for (final entity in listing.entries) {
          if (entity is! Directory) continue;
          sessionCount += 1;
          try {
            final ledgerFile = File(p.join(entity.path, 'ledger.jsonl'));
            if (!await ledgerFile.exists()) continue;
            final content = await readBoundedFileString(
              ledgerFile,
              maxBytes: _maxLedgerBytes,
            );
            for (final line in _ledgerLines(content)) {
              if (nullIfBlank(line) != null) recordCount += 1;
            }
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
        final listing = await _listBlobEntries();
        for (final entity in listing.entries) {
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
      final usage = await measureDirectoryBounded(
        root,
        maxEntries: _maxSessionScanEntries + _maxBlobScanEntries,
        totalTimeout: _ledgerTreeScanTimeout,
      );
      total = usage.totalBytes;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'totalSizeBytes', error, stack);
    }
    return total;
  }

  Future<void> clearAll() async {
    await _ensureInitialized();
    return _runExclusiveMaintenance(_clearAllExclusive);
  }

  Future<void> _clearAllExclusive() async {
    try {
      await _initializationFuture;
      final root = Directory(_root);
      await deletePathBounded(
        p.absolute(root.path),
        policy: _ledgerTreeDeletePolicy,
        allowedRoot: p.absolute(_root),
      );
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'clearAll', error, stack);
      rethrow;
    } finally {
      _invalidateAllCaches();
      _cachedConfig = null;
      _legacyBlobPathIndex = null;
      _legacyBlobRecoveryMisses.clear();
      _initialized = false;
      _initializationFuture = null;
      _resetInitializationFailure();
    }
  }

  Future<void> clearSession(String sessionId) async {
    await _enqueueSessionMutation(
      sessionId,
      () => _clearSessionLocked(sessionId),
      ensureInitialized: true,
    );
    await gcUnreferencedBlobs();
  }

  Future<void> _clearSessionLocked(String sessionId) async {
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null) return;
    try {
      final dir = _sessionDir(normalizedSessionId);
      await deletePathBounded(
        p.absolute(dir.path),
        policy: _ledgerTreeDeletePolicy,
        allowedRoot: p.absolute(_sessionsDir().path),
      );
      // 不主动 GC blobs，避免影响其他会话引用；总清理时统一处理。
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'clearSession', error, stack);
      rethrow;
    }
    _invalidateSessionCache(normalizedSessionId);
  }

  /// 清理所有非 [keepSessionIds] 列出的会话目录。
  Future<int> clearSessionsExcept(Set<String> keepSessionIds) async {
    await _ensureInitialized();
    var removed = 0;
    try {
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return 0;
      final keep = keepSessionIds.map(_safeSessionId).toSet();
      final listing = await _listSessionEntries();
      for (final entity in listing.entries) {
        if (entity is! Directory) continue;
        final sessionId = p.basename(entity.path);
        if (keep.contains(sessionId)) continue;
        try {
          await _enqueueSessionMutation(
            sessionId,
            () => deletePathBounded(
              p.absolute(entity.path),
              policy: _ledgerTreeDeletePolicy,
              allowedRoot: p.absolute(sessions.path),
            ),
            ensureInitialized: true,
          );
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
    await _ensureInitialized();
    final removed = await _pruneOlderThan(retention);
    await gcUnreferencedBlobs();
    return removed;
  }

  Future<int> _pruneOlderThan(Duration retention) async {
    var removed = 0;
    final pruned = <String>{};
    try {
      final cutoff = DateTime.now().subtract(retention);
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return 0;
      final listing = await _listSessionEntries();
      for (final entity in listing.entries) {
        if (entity is! Directory) continue;
        final sessionId = p.basename(entity.path);
        try {
          final didPrune = await _enqueueSessionMutation(sessionId, () async {
            final stat = await entity.stat();
            if (!stat.modified.isBefore(cutoff)) return false;
            await deletePathBounded(
              p.absolute(entity.path),
              policy: _ledgerTreeDeletePolicy,
              allowedRoot: p.absolute(sessions.path),
            );
            return true;
          });
          if (didPrune) {
            pruned.add(sessionId);
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
    final loaded = await _recordsForSessionResult(sessionId);
    if (!loaded.succeeded) return;
    final records = loaded.records;
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
    await _ensureInitialized();
    final removed = await _pruneToMaxVersionsPerFile(
      maxVersionsPerFile,
      initializeRecordReads: true,
    );
    await gcUnreferencedBlobs();
    return removed;
  }

  Future<int> _pruneToMaxVersionsPerFile(
    int maxVersionsPerFile, {
    required bool initializeRecordReads,
  }) async {
    if (maxVersionsPerFile <= 0) return 0;
    var removed = 0;
    try {
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return 0;
      final listing = await _listSessionEntries();
      for (final entity in listing.entries) {
        if (entity is! Directory) continue;
        final sessionId = p.basename(entity.path);
        removed += await _enqueueSessionMutation(
          sessionId,
          () => _pruneSessionToMaxVersionsLocked(
            sessionId,
            maxVersionsPerFile,
            initializeRecordReads: initializeRecordReads,
          ),
        );
      }
    } catch (error, stack) {
      silentLog(
        'ai_file_mutation_ledger',
        'pruneToMaxVersionsPerFile',
        error,
        stack,
      );
    }
    return removed;
  }

  Future<int> _pruneSessionToMaxVersionsLocked(
    String sessionId,
    int maxVersionsPerFile, {
    required bool initializeRecordReads,
  }) async {
    final loaded = await _recordsForSessionResult(
      sessionId,
      initialize: initializeRecordReads,
    );
    if (!loaded.succeeded) return 0;
    final records = loaded.records;
    final byFile = <String, List<FileMutationRecord>>{};
    for (final record in records) {
      byFile
          .putIfAbsent(record.filePath, () => <FileMutationRecord>[])
          .add(record);
    }
    final keepIds = <String>{};
    byFile.forEach((_, records) {
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      keepIds.addAll(
        records.take(maxVersionsPerFile).map((record) => record.recordId),
      );
    });
    final survivors = records
        .where((record) => keepIds.contains(record.recordId))
        .toList(growable: false);
    final ledger = _ledgerFile(sessionId);
    if (survivors.isEmpty) {
      await _deleteFileIfPresent(ledger, 'prune ledger');
    } else {
      final buffer = StringBuffer();
      for (final record in survivors) {
        buffer.writeln(jsonEncode(record.toJson()));
      }
      await writeFileAtomically(ledger, buffer.toString());
    }
    _invalidateSessionCache(sessionId);
    final undone = await _loadUndoneSet(sessionId);
    undone.removeWhere((id) => !keepIds.contains(id));
    await _saveUndoneSet(sessionId, undone);
    return records.length - survivors.length;
  }

  /// 删除没有任何 ledger 引用的 blob。容错：失败仅日志，不抛出。
  /// 返回 (removed, bytesFreed) 以便 UI 展示统计。
  Future<({int removed, int bytesFreed})> gcUnreferencedBlobs() async {
    await _ensureInitialized();
    return _runExclusiveMaintenance(
      () => _gcUnreferencedBlobs(initializeRecordReads: true),
    );
  }

  Future<({int removed, int bytesFreed})> _gcUnreferencedBlobs({
    required bool initializeRecordReads,
  }) async {
    var removed = 0;
    var bytesFreed = 0;
    try {
      final referenced = <String>{};
      final sessions = _sessionsDir();
      if (await sessions.exists()) {
        final sessionListing = await _listSessionEntries();
        if (sessionListing.truncated) {
          return (removed: 0, bytesFreed: 0);
        }
        for (final entity in sessionListing.entries) {
          if (entity is! Directory) continue;
          final loaded = await _recordsForSessionResult(
            p.basename(entity.path),
            initialize: initializeRecordReads,
          );
          if (!loaded.succeeded) {
            return (removed: 0, bytesFreed: 0);
          }
          final records = loaded.records;
          for (final r in records) {
            if (r.beforeSha != null) referenced.add(r.beforeSha!);
            if (r.afterSha != null) referenced.add(r.afterSha!);
          }
        }
      }
      final blobs = _blobsDir();
      if (!await blobs.exists()) return (removed: 0, bytesFreed: 0);
      final blobListing = await _listBlobEntries();
      for (final blob in blobListing.entries.whereType<File>()) {
        final sha = _blobShaFromFile(blob: blob, shard: blob.parent);
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
    final cacheKey = _safeSessionId(sessionId);
    final cached = _undoneCache.get(cacheKey);
    if (cached != null) return Set<String>.from(cached);
    try {
      final state = _stateFile(sessionId);
      if (!await state.exists()) {
        _undoneCache.put(cacheKey, const <String>{});
        return <String>{};
      }
      final raw = await readBoundedFileString(state, maxBytes: _maxStateBytes);
      final text = nullIfBlank(raw);
      if (text == null) {
        _undoneCache.put(cacheKey, const <String>{});
        return <String>{};
      }
      final parsed = jsonDecode(text);
      if (parsed is Map<String, Object?>) {
        final list = parsed['undone'];
        if (list is List) {
          final undone = list.whereType<String>().toSet();
          _undoneCache.put(cacheKey, Set<String>.unmodifiable(undone));
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
    _undoneCache.put(cacheKey, const <String>{});
    return <String>{};
  }

  Future<void> _saveUndoneSet(String sessionId, Set<String> undone) async {
    final cacheKey = _safeSessionId(sessionId);
    try {
      final state = _stateFile(sessionId);
      if (undone.isEmpty) {
        await _deleteFileIfPresent(state, 'delete empty undone state');
        _undoneCache.put(cacheKey, const <String>{});
        return;
      }
      final dir = _sessionDir(sessionId);
      if (!await dir.exists()) await dir.create(recursive: true);
      await writeFileAtomically(
        state,
        jsonEncode(<String, Object?>{'undone': undone.toList()..sort()}),
      );
      _undoneCache.put(cacheKey, Set<String>.unmodifiable(undone));
    } on FileSystemException catch (error, stack) {
      if (!_isMissingFileSystemException(error)) {
        silentLog('ai_file_mutation_ledger', 'saveUndoneSet', error, stack);
      }
      _undoneCache.remove(cacheKey);
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'saveUndoneSet', error, stack);
      _undoneCache.remove(cacheKey);
    }
  }

  Future<void> _writeBlobIfMissing(String sha, String content) async {
    if (!_sha256HexPattern.hasMatch(sha) || _sha256Of(content) != sha) {
      throw const FormatException(
        'Blob content does not match its SHA-256 key.',
      );
    }
    if (utf8.encode(content).length > _blobRecoveryMaxBytes) {
      throw const FileSystemException(
        'Blob exceeds the $_blobRecoveryMaxBytes byte limit.',
      );
    }
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
      return await readBoundedFileString(file, maxBytes: _blobRecoveryMaxBytes);
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
    if (!_sha256HexPattern.hasMatch(expectedSha) ||
        nullIfBlank(filePath) == null) {
      return null;
    }
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      if (expectedSize > 0 && stat.size != expectedSize) return null;
      if (stat.size > _blobRecoveryMaxBytes) return null;
      final content = await readBoundedFileString(
        file,
        maxBytes: _blobRecoveryMaxBytes,
      );
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
      final path = nullIfBlank(index[sha]);
      if (path == null) {
        _recordLegacyBlobRecoveryMiss(sha);
        return null;
      }
      final file = File(path);
      if (!await file.exists()) {
        _recordLegacyBlobRecoveryMiss(sha);
        return null;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size > _blobRecoveryMaxBytes) {
        _recordLegacyBlobRecoveryMiss(sha);
        return null;
      }
      final content = await readBoundedFileString(
        file,
        maxBytes: _blobRecoveryMaxBytes,
      );
      if (_sha256Of(content) != sha) {
        _recordLegacyBlobRecoveryMiss(sha);
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
      _recordLegacyBlobRecoveryMiss(sha);
      return null;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'recover legacy blob', error, stack);
      _recordLegacyBlobRecoveryMiss(sha);
      return null;
    }
  }

  /// Records [sha] in the negative-recovery cache, evicting the oldest entry
  /// once the cap is reached so the set never grows without bound.
  void _recordLegacyBlobRecoveryMiss(String sha) {
    if (_legacyBlobRecoveryMisses.length >= _maxLegacyBlobRecoveryMisses) {
      _legacyBlobRecoveryMisses.remove(_legacyBlobRecoveryMisses.first);
    }
    _legacyBlobRecoveryMisses.add(sha);
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
      final listing = await listDirectoryBounded(
        legacyRoot,
        maxEntries: _maxLegacyMigrationEntries,
        recursive: true,
        totalTimeout: _ledgerTreeScanTimeout,
      );
      for (final entity in listing.entries) {
        if (scanned >= _legacyBlobRecoveryMaxFiles) break;
        if (entity is! File || !entity.path.endsWith('.content')) continue;
        scanned += 1;
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file ||
              stat.size > _blobRecoveryMaxBytes) {
            continue;
          }
          final content = await readBoundedFileString(
            entity,
            maxBytes: _blobRecoveryMaxBytes,
          );
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
    final trimmed = nullIfBlank(raw) ?? '';
    if (trimmed.isNotEmpty &&
        trimmed.length <= _maxSessionIdCharacters &&
        !_unsafeSessionIdCharPattern.hasMatch(trimmed)) {
      return trimmed;
    }
    final digest = sha256
        .convert(utf8.encode(trimmed))
        .toString()
        .substring(0, 12);
    final sanitized = trimmed.replaceAll(_unsafeSessionIdCharPattern, '_');
    final prefix = sanitized.isEmpty
        ? 'session'
        : sanitized.substring(
            0,
            min(sanitized.length, _sanitizedSessionIdPrefixCharacters),
          );
    return '${prefix}_$digest';
  }

  // ─────────────────────────── 跨会话查询 / 导出导入 ─────────────────────────
  /// 列出磁盘上所有可见的 sessionId。失败仅日志，返回空列表。
  Future<List<String>> listSessionIds() async {
    await _ensureInitialized();
    final out = <String>[];
    try {
      final sessions = _sessionsDir();
      if (!await sessions.exists()) return out;
      final listing = await _listSessionEntries();
      for (final entity in listing.entries) {
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
    if (limit <= 0) return const <FileMutationView>[];
    final safeLimit = min(limit, _maxSearchResults);
    final ids = sessionIds == null
        ? await listSessionIds()
        : sessionIds.take(_maxSessionScanEntries).toList(growable: false);
    final kindSet = kinds?.toSet();
    final toolSet = toolNames
        ?.map(optionalLowercaseStringFromValue)
        .whereType<String>()
        .toSet();
    final pathNeedle = optionalLowercaseStringFromValue(pathContains);
    final out = <FileMutationView>[];
    for (final sid in ids) {
      if (out.length >= safeLimit) break;
      final all = await recordsForSession(sid);
      if (all.isEmpty) continue;
      final undone = await _loadUndoneSet(sid);
      final undoStates = _buildUndoStates(all, undone);
      final filtered = <FileMutationRecord>[];
      for (final r in all) {
        if (out.length + filtered.length >= safeLimit) break;
        if (kindSet != null && !kindSet.contains(r.kind)) continue;
        if (toolSet != null &&
            toolSet.isNotEmpty &&
            !toolSet.contains(lowercaseStringFromValue(r.toolName))) {
          continue;
        }
        if (pathNeedle != null &&
            !lowercaseStringFromValue(r.filePath).contains(pathNeedle)) {
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
    final ids = await _boundedExportSessionIds(sessionIds);
    final sessions = <Map<String, Object?>>[];
    final referenced = <String>{};
    var recordCount = 0;
    for (final sid in ids) {
      final records = await recordsForSession(sid);
      recordCount += records.length;
      if (recordCount > _maxExportRecords) {
        throw StateError(
          'Ledger export exceeds the $_maxExportRecords record limit.',
        );
      }
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
    final blobMap = await _exportReferencedBlobs(referenced);
    return prettyPrintJson(<String, Object?>{
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
    var recordCount = 0;
    for (final r in records) {
      recordCount += 1;
      if (recordCount > _maxExportRecords) {
        throw StateError(
          'Ledger export exceeds the $_maxExportRecords record limit.',
        );
      }
      bySession.putIfAbsent(r.sessionId, () => <FileMutationRecord>[]).add(r);
      if (r.beforeSha != null) referenced.add(r.beforeSha!);
      if (r.afterSha != null) referenced.add(r.afterSha!);
    }
    if (bySession.length > _maxExportSessions) {
      throw StateError(
        'Ledger export exceeds the $_maxExportSessions session limit.',
      );
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
    final blobMap = await _exportReferencedBlobs(referenced);
    return prettyPrintJson(<String, Object?>{
      'kind': 'openhand.file_mutation_ledger.bundle',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'sessions': sessions,
      'blobs_b64': blobMap,
    });
  }

  Future<List<String>> _boundedExportSessionIds(
    Iterable<String>? sessionIds,
  ) async {
    final candidates = sessionIds ?? await listSessionIds();
    final ids = candidates.take(_maxExportSessions + 1).toList(growable: false);
    if (ids.length > _maxExportSessions) {
      throw StateError(
        'Ledger export exceeds the $_maxExportSessions session limit.',
      );
    }
    return ids;
  }

  Future<Map<String, String>> _exportReferencedBlobs(
    Set<String> referenced,
  ) async {
    final blobMap = <String, String>{};
    var totalBytes = 0;
    for (final sha in referenced) {
      final content = await _readBlob(sha);
      if (content == null) continue;
      final bytes = utf8.encode(content);
      totalBytes += bytes.length;
      if (totalBytes > _maxExportBlobBytes) {
        throw StateError(
          'Ledger export exceeds the ${formatByteSize(_maxExportBlobBytes)} blob limit.',
        );
      }
      blobMap[sha] = base64Encode(bytes);
    }
    return blobMap;
  }

  /// 还原导出 bundle。返回写入的 record 数（去重统计）。失败仅日志，按
  /// session 粒度容错继续。
  Future<int> importBundleJson(String json) async {
    await _ensureInitialized();
    return _runExclusiveMaintenance(() => _importBundleJsonExclusive(json));
  }

  Future<int> _importBundleJsonExclusive(String json) async {
    var imported = 0;
    if (json.length > _maxBundleJsonCharacters) return 0;
    Map<String, Object?> parsed;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, Object?>) return 0;
      parsed = decoded;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', 'importBundle parse', error, stack);
      return 0;
    }
    if (optionalStringFromValue(parsed['kind']) !=
        'openhand.file_mutation_ledger.bundle') {
      return 0;
    }
    final sessions = parsed['sessions'];
    if (sessions is! List || sessions.length > _maxExportSessions) return 0;
    var bundledRecordCount = 0;
    for (final sessionEntry in sessions) {
      if (sessionEntry is! Map<String, Object?>) continue;
      final records = sessionEntry['records'];
      if (records is! List) continue;
      bundledRecordCount += records.length;
      if (bundledRecordCount > _maxExportRecords) return 0;
    }
    // 1) 先恢复 blob — 之后的 record 才有指向。
    final blobMap = parsed['blobs_b64'];
    if (blobMap is Map) {
      if (blobMap.length > _maxExportRecords * 2) return 0;
      for (final entry in blobMap.entries) {
        final sha = optionalStringFromValue(entry.key);
        final raw = optionalStringFromValue(entry.value);
        if (sha == null ||
            raw == null ||
            !_sha256HexPattern.hasMatch(sha) ||
            raw.length > _maxBlobBase64Characters) {
          continue;
        }
        try {
          final bytes = decodeBase64Bounded(
            raw,
            maxDecodedBytes: _blobRecoveryMaxBytes,
          );
          if (sha256.convert(bytes).toString() != sha) continue;
          final content = utf8.decode(bytes);
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
    for (final sessionEntry in sessions) {
      if (sessionEntry is! Map<String, Object?>) continue;
      final sid = optionalStringFromValue(sessionEntry['session_id']);
      if (sid == null) continue;
      final records = sessionEntry['records'];
      if (records is! List) continue;
      try {
        final sessionImported = await _enqueueSessionMutation(sid, () async {
          final dir = _sessionDir(sid);
          if (!await dir.exists()) await dir.create(recursive: true);
          final ledger = _ledgerFile(sid);
          final loaded = await _recordsForSessionResult(sid);
          if (!loaded.succeeded) return 0;
          final existingIds = loaded.records.map((r) => r.recordId).toSet();
          final buffer = StringBuffer();
          try {
            if (await ledger.exists()) {
              final existing = await readBoundedFileString(
                ledger,
                maxBytes: _maxLedgerBytes,
              );
              buffer.write(existing);
              if (!existing.endsWith('\n') && existing.isNotEmpty) {
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
            return 0;
          } catch (error, stack) {
            silentLog(
              'ai_file_mutation_ledger',
              'importBundle read existing ledger',
              error,
              stack,
            );
            return 0;
          }
          var added = 0;
          for (final raw in records) {
            if (raw is! Map) continue;
            final record = FileMutationRecord.tryFromJson(
              stringKeyedMapFromValue(raw),
              sessionId: sid,
            );
            if (record == null || existingIds.contains(record.recordId)) {
              continue;
            }
            buffer.writeln(jsonEncode(record.toJson()));
            existingIds.add(record.recordId);
            added += 1;
          }
          final updatedLedger = buffer.toString();
          if (utf8.encode(updatedLedger).length > _maxLedgerBytes) return 0;
          await writeFileAtomically(ledger, updatedLedger);
          _invalidateSessionCache(sid);
          // 还原 undone 集合：合并存在的 undone 列表。
          final undoneList = sessionEntry['undone'];
          if (undoneList is List) {
            final cur = await _loadUndoneSet(sid);
            for (final item in undoneList) {
              if (item is String && existingIds.contains(item)) {
                cur.add(item);
              }
            }
            await _saveUndoneSet(sid, cur);
          }
          return added;
        }, waitForMaintenance: false);
        imported += sessionImported;
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
