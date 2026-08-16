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
import '../../../../shared/util/hex_encoding.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../../../shared/util/unified_diff.dart' as unified_diff;
import '../../model/ai_session_message.dart';

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
    aiSessionMessageToolCallIdMetadataKey: toolCallId,
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
      toolCallId: stringFromValue(json[aiSessionMessageToolCallIdMetadataKey]),
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

final class _LedgerMutationQueueFull implements Exception {
  const _LedgerMutationQueueFull();

  @override
  String toString() => '文件变更任务队列已满。';
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

  /// 每个会话内同一文件保留的最近 N 条变动。
  final int maxVersionsPerFile;

  /// 自动清理 N 天前的全部变动（启动时触发一次）。<=0 表示禁用。
  final int autoCleanupDays;

  /// mini-diff 切换阈值（KiB）。任一侧 > 此值（且 ≤ maxBytes）
  /// 时 unifiedDiffLineSummary 仅保留 +/- 行；超过 maxBytes 仍走 sha 占
  /// 位摘要。<=0 时退化为永远全量 diff（直到 maxBytes）。
  final int miniDiffMaxBytes;

  static const int defaultMaxVersionsPerFile = 10;
  static const int minMaxVersionsPerFile = 1;
  static const int maxMaxVersionsPerFile = 200;
  static const int defaultAutoCleanupDays = 30;
  static const int minAutoCleanupDays = 0;
  static const int maxAutoCleanupDays = 365;
  static const int defaultMiniDiffMaxBytes =
      unifiedDiffLineSummaryDefaultMiniDiffBytes;
  static const int minMiniDiffMaxBytes = 0;
  static const int maxMiniDiffMaxBytes = 256 * kBytesPerKiB;
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
        optionalPositiveIntFromValue(json['max_versions_per_file']),
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
      throw ArgumentError.value(rootDirectory, 'rootDirectory', '不能为空。');
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

  static final RegExp _unsafeSessionIdCharPattern = RegExp(r'[^a-zA-Z0-9_\-.]');
  static const Duration _staleAtomicArtifactAge = Duration(days: 1);
  static const int _initializationRetryBaseMs = 1000;
  static const int _initializationRetryCapMs = 60000;
  static const Duration _configLoadRetryDelay = Duration(seconds: 5);
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
  static const int _maxPendingSessionMutations = 1024;
  static const int _maxConcurrentLedgerAppends = 16;
  static const Duration _ledgerTreeScanTimeout = Duration(seconds: 30);
  static const Duration _ledgerFileIoTimeout = Duration(seconds: 3);
  static const Duration _ledgerAppendQueueTimeout = Duration(seconds: 30);
  static const BoundedDeletePolicy _ledgerTreeDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: _maxSessionScanEntries + _maxBlobScanEntries,
        maxDepth: 32,
      );

  /// 旧版 Blob 恢复失败记录的缓存上限，避免长会话持续增长。
  static const int _maxLegacyBlobRecoveryMisses = 4096;

  final Random _rand = Random.secure();
  final String _rootDirectory;
  final Stopwatch _retryStopwatch = Stopwatch()..start();
  Future<void>? _initializationFuture;
  bool _initialized = false;
  Object? _initializationError;
  StackTrace? _initializationErrorStack;
  Duration? _nextInitializationRetryAt;
  int _initializationFailureCount = 0;
  Map<String, String>? _legacyBlobPathIndex;
  final Set<String> _legacyBlobRecoveryMisses = <String>{};
  final Map<String, _LedgerSessionMutationLane> _sessionMutationLanes =
      <String, _LedgerSessionMutationLane>{};
  final Map<String, Future<void>> _lateLedgerAppends = <String, Future<void>>{};
  final OpenHandAsyncSemaphore _ledgerAppendSlots = OpenHandAsyncSemaphore(
    _maxConcurrentLedgerAppends,
    maxWaiters: _maxPendingSessionMutations,
  );
  int _pendingSessionMutations = 0;
  Completer<void>? _maintenanceGate;
  final SerialTaskQueue _configQueue = SerialTaskQueue();
  ({Object error, StackTrace stack})? _configLoadFailure;
  Duration? _nextConfigLoadRetryAt;

  // 按会话缓存记录和撤销集合；本类写入后统一失效，避免恢复会话时重复扫描磁盘。
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
    if (_pendingSessionMutations >= _maxPendingSessionMutations) {
      throw const _LedgerMutationQueueFull();
    }
    _pendingSessionMutations += 1;
    try {
      if (waitForMaintenance) {
        while (_maintenanceGate != null) {
          await _maintenanceGate!.future;
        }
      }
      if (ensureInitialized) await _ensureInitialized();
      final key = _safeSessionId(sessionId);
      if (waitForMaintenance) {
        // 初始化期间可能启动维护，入队前必须再次原子检查门闩。
        while (_maintenanceGate != null) {
          await _maintenanceGate!.future;
        }
      }
      final lane = _sessionMutationLanes.putIfAbsent(
        key,
        _LedgerSessionMutationLane.new,
      );
      lane.pending += 1;
      try {
        final future = lane.queue.enqueue(() async {
          await _waitForLateLedgerAppend(key);
          return mutation();
        });
        lane.tail = future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        return await future;
      } finally {
        lane.pending -= 1;
        if (lane.pending == 0 && identical(_sessionMutationLanes[key], lane)) {
          _sessionMutationLanes.remove(key);
        }
      }
    } finally {
      _pendingSessionMutations -= 1;
    }
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
      if (pendingMutations.isNotEmpty) {
        await Future.wait<void>(pendingMutations).timeout(
          _ledgerTreeScanTimeout,
          onTimeout: () =>
              throw TimeoutException('等待文件变更写入队列完成超时。', _ledgerTreeScanTimeout),
        );
      }
      final lateAppends = _lateLedgerAppends.values.toList(growable: false);
      if (lateAppends.isNotEmpty) {
        await Future.wait<void>(lateAppends).timeout(_ledgerFileIoTimeout);
      }
      return await operation();
    } finally {
      if (!maintenance.isCompleted) maintenance.complete();
      if (identical(_maintenanceGate, maintenance)) {
        _maintenanceGate = null;
      }
    }
  }

  Future<void> _waitForLateLedgerAppend(String sessionKey) async {
    final pending = _lateLedgerAppends[sessionKey];
    if (pending == null) return;
    await pending.timeout(
      _ledgerFileIoTimeout,
      onTimeout: () =>
          throw TimeoutException('等待延迟账本写入完成超时。', _ledgerFileIoTimeout),
    );
  }

  String get _root => _rootDirectory;

  Directory _blobsDir() => Directory(p.join(_root, 'blobs'));
  Directory _sessionsDir() => Directory(p.join(_root, 'sessions'));
  Directory _sessionDir(String sessionId) =>
      Directory(p.join(_sessionsDir().path, _safeSessionId(sessionId)));

  Future<BoundedDirectoryListing> _listSessionEntries({
    MonotonicDeadline? deadline,
  }) {
    return listDirectoryBounded(
      _sessionsDir(),
      maxEntries: _maxSessionScanEntries,
      totalTimeout:
          deadline?.remaining() ?? defaultBoundedDirectoryTotalTimeout,
    );
  }

  Future<BoundedDirectoryListing> _listBlobEntries({
    MonotonicDeadline? deadline,
  }) {
    return listDirectoryBounded(
      _blobsDir(),
      maxEntries: _maxBlobScanEntries,
      recursive: true,
      totalTimeout: deadline?.remaining() ?? _ledgerTreeScanTimeout,
    );
  }

  File _ledgerFile(String sessionId) =>
      File(p.join(_sessionDir(sessionId).path, 'ledger.jsonl'));
  File _stateFile(String sessionId) =>
      File(p.join(_sessionDir(sessionId).path, 'state.json'));

  Future<bool> _entityExists(
    FileSystemEntity entity, {
    MonotonicDeadline? deadline,
  }) {
    return entity.exists().timeout(_fileIoTimeout(deadline));
  }

  Future<FileStat> _entityStat(
    FileSystemEntity entity, {
    MonotonicDeadline? deadline,
  }) {
    return entity.stat().timeout(_fileIoTimeout(deadline));
  }

  Future<void> _ensureDirectory(
    Directory directory, {
    MonotonicDeadline? deadline,
  }) async {
    if (await _entityExists(directory, deadline: deadline)) return;
    await directory.create(recursive: true).timeout(_fileIoTimeout(deadline));
  }

  Duration _fileIoTimeout(MonotonicDeadline? deadline) {
    return deadline?.limit(_ledgerFileIoTimeout) ?? _ledgerFileIoTimeout;
  }

  Future<String> _readTextFile(
    File file, {
    required int maxBytes,
    MonotonicDeadline? deadline,
  }) {
    if (deadline == null) {
      return readBoundedFileString(file, maxBytes: maxBytes);
    }
    final totalTimeout = deadline.remaining();
    return readBoundedFileString(
      file,
      maxBytes: maxBytes,
      idleTimeout: _fileIoTimeout(deadline),
      totalTimeout: totalTimeout,
    );
  }

  /// 暴露给 UI 用：点击卡片 header 时把 ledger.jsonl 在系统
  /// 文件管理器里高亮。返回的文件可能尚未存在（会话尚未发生过 mutation）。
  File ledgerFileFor(String sessionId) => _ledgerFile(sessionId);
  File _configFile() => File(p.join(_root, 'config.json'));

  LedgerConfig? _cachedConfig;

  Future<LedgerConfig> loadConfig() async {
    try {
      return await _loadTrustedConfig();
    } catch (_) {
      return const LedgerConfig();
    }
  }

  Future<LedgerConfig> _loadTrustedConfig() {
    final cached = _cachedConfig;
    if (cached != null) return Future<LedgerConfig>.value(cached);
    return _configQueue.enqueue(_loadConfigLocked);
  }

  Future<LedgerConfig> _loadConfigLocked() async {
    final cached = _cachedConfig;
    if (cached != null) return cached;
    final failure = _configLoadFailure;
    final retryAt = _nextConfigLoadRetryAt;
    if (failure != null &&
        retryAt != null &&
        _retryStopwatch.elapsed < retryAt) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
    try {
      final f = _configFile();
      if (!await _entityExists(f)) {
        return _acceptLoadedConfig(const LedgerConfig());
      }
      final raw = await readBoundedFileString(f, maxBytes: _maxConfigBytes);
      final text = nullIfBlank(raw);
      if (text == null) throw const FormatException('账本配置内容为空。');
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('账本配置必须是对象。');
      return _acceptLoadedConfig(
        LedgerConfig.fromJson(stringKeyedMapFromValue(decoded)),
      );
    } catch (error, stack) {
      _configLoadFailure = (error: error, stack: stack);
      _nextConfigLoadRetryAt = _retryStopwatch.elapsed + _configLoadRetryDelay;
      _logFileErrorUnlessMissing('加载账本配置', error, stack);
      Error.throwWithStackTrace(error, stack);
    }
  }

  LedgerConfig _acceptLoadedConfig(LedgerConfig config) {
    _cachedConfig = config;
    _configLoadFailure = null;
    _nextConfigLoadRetryAt = null;
    return config;
  }

  Future<void> saveConfig(LedgerConfig config) async {
    await _ensureInitialized();
    final normalized = config.copyWith();
    await _configQueue.enqueue(() async {
      await writeFileAtomically(_configFile(), jsonEncode(normalized.toJson()));
      _acceptLoadedConfig(normalized);
    });
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final pending = _initializationFuture;
    if (pending != null) return pending;
    final retryAt = _nextInitializationRetryAt;
    final previousError = _initializationError;
    if (retryAt != null &&
        previousError != null &&
        _retryStopwatch.elapsed < retryAt) {
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
      await _ensureDirectory(_blobsDir());
      await _ensureDirectory(_sessionsDir());
      await _migrateLegacyTempStorage();
      await _runAutoCleanupOnce();
      _initialized = true;
      _resetInitializationFailure();
    } catch (error, stack) {
      _initializationFailureCount++;
      _initializationError = error;
      _initializationErrorStack = stack;
      _nextInitializationRetryAt =
          _retryStopwatch.elapsed +
          Duration(
            milliseconds: exponentialBackoffMs(
              attempt: _initializationFailureCount,
              baseMs: _initializationRetryBaseMs,
              capMs: _initializationRetryCapMs,
            ),
          );
      silentLog('ai_file_mutation_ledger', '初始化账本', error, stack);
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
    late final LedgerConfig config;
    try {
      config = await _loadTrustedConfig();
    } catch (_) {
      return;
    }
    try {
      if (config.autoCleanupDays > 0) {
        await _pruneOlderThan(Duration(days: config.autoCleanupDays));
      }
      await _pruneToMaxVersionsPerFile(
        config.maxVersionsPerFile,
        initializeRecordReads: false,
      );
      await _gcUnreferencedBlobs(initializeRecordReads: false);
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '自动清理', error, stack);
    }
  }

  /// 一次性把 [Directory.systemTemp]/.openhand-file-history 的旧扁平结构
  /// 拷贝为 ledger 友好的 blob，丢失的元数据用合成 record 兜底。失败不
  /// 影响主流程；仅在完整扫描且全部内容迁移成功后删除旧目录。
  Future<void> _migrateLegacyTempStorage() async {
    final deadline = MonotonicDeadline(
      _ledgerTreeScanTimeout,
      timeoutMessage: '迁移旧版文件历史超过总时限。',
    );
    try {
      final legacyDir = Directory(
        p.join(Directory.systemTemp.path, '.openhand-file-history'),
      );
      if (!await _entityExists(legacyDir, deadline: deadline)) return;
      // 旧布局：<hash>/<versionId>.{content,meta.json}
      final listing = await listDirectoryBounded(
        legacyDir,
        maxEntries: _maxLegacyMigrationEntries,
        recursive: true,
        totalTimeout: deadline.remaining(),
      );
      var migrationComplete = !listing.truncated;
      for (final file in listing.entries.whereType<File>()) {
        if (!file.path.endsWith('.content')) continue;
        if (deadline.isExpired) {
          migrationComplete = false;
          break;
        }
        try {
          final content = await _readTextFile(
            file,
            maxBytes: _blobRecoveryMaxBytes,
            deadline: deadline,
          );
          await _writeBlobIfMissing(_sha256Of(content), content);
        } on TimeoutException {
          migrationComplete = false;
          break;
        } catch (error, stack) {
          migrationComplete = false;
          _logFileErrorUnlessMissing('迁移 blob', error, stack);
        }
      }
      if (migrationComplete && !deadline.isExpired) {
        try {
          await deletePathBounded(
            p.absolute(legacyDir.path),
            policy: BoundedDeletePolicy(
              maxEntries: _maxLegacyMigrationEntries + 1,
              maxDepth: 32,
              totalTimeout: deadline.remaining(),
            ),
            allowedRoot: p.absolute(Directory.systemTemp.path),
          );
        } catch (error, stack) {
          silentLog('ai_file_mutation_ledger', '删除旧版目录', error, stack);
        }
      }
    } on TimeoutException {
      // 保留旧目录，后续初始化时继续迁移。
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '迁移旧版数据', error, stack);
    } finally {
      deadline.stop();
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
    try {
      return await _enqueueSessionMutation(
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
    } on _LedgerMutationQueueFull {
      return null;
    }
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
      await _ensureDirectory(sessionDir);

      String? beforeSha;
      int beforeSize = 0;
      if (beforeContent != null) {
        beforeSha = _sha256Of(beforeContent);
        beforeSize = utf8.encode(beforeContent).length;
      }
      String? afterSha;
      int afterSize = 0;
      if (afterContent != null) {
        afterSha = _sha256Of(afterContent);
        afterSize = utf8.encode(afterContent).length;
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
      final config = await loadConfig();
      final lineBytes = utf8.encode(line).length;
      if (!await _ensureLedgerCapacity(
        normalizedSessionId,
        ledger,
        lineBytes,
        config.maxVersionsPerFile,
      )) {
        silentLog(
          'ai_file_mutation_ledger',
          '账本达到容量上限，已拒绝新增记录',
          normalizedSessionId,
        );
        return null;
      }
      if (beforeContent != null) {
        await _writeBlobIfMissing(beforeSha!, beforeContent);
      }
      if (afterContent != null) {
        await _writeBlobIfMissing(afterSha!, afterContent);
      }
      await _appendLedgerLine(normalizedSessionId, ledger, line);
      _invalidateSessionCache(normalizedSessionId);
      // 写入后按当前配置即时收紧每文件历史数。autoCleanupDays 在启动时已处理。
      try {
        await _trimSessionFileVersions(
          normalizedSessionId,
          record.filePath,
          config.maxVersionsPerFile,
        );
      } catch (error, stack) {
        silentLog('ai_file_mutation_ledger', '记录后裁剪', error, stack);
      }
      return record;
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '记录文件变更', error, stack);
      return null;
    }
  }

  Future<bool> _ensureLedgerCapacity(
    String sessionId,
    File ledger,
    int appendBytes,
    int maxVersionsPerFile,
  ) async {
    if (appendBytes > _maxLedgerBytes) return false;
    if (!await _entityExists(ledger)) return true;
    var size = (await _entityStat(ledger)).size;
    if (size <= _maxLedgerBytes - appendBytes) return true;
    await _pruneSessionToMaxVersionsLocked(
      sessionId,
      maxVersionsPerFile,
      initializeRecordReads: true,
    );
    if (!await _entityExists(ledger)) return true;
    size = (await _entityStat(ledger)).size;
    return size <= _maxLedgerBytes - appendBytes;
  }

  Future<void> _appendLedgerLine(
    String sessionId,
    File ledger,
    String line,
  ) async {
    final acquired = await _ledgerAppendSlots.acquireWithin(
      _ledgerAppendQueueTimeout,
    );
    if (!acquired) {
      throw TimeoutException('文件变更账本追加排队超时。', _ledgerAppendQueueTimeout);
    }
    Future<File>? append;
    var releasePermit = true;
    try {
      append = ledger.writeAsString(line, mode: FileMode.append, flush: true);
      await append.timeout(_ledgerFileIoTimeout);
    } on TimeoutException {
      if (append == null) rethrow;
      releasePermit = false;
      _trackLateLedgerAppend(sessionId, append);
      rethrow;
    } finally {
      if (releasePermit) _ledgerAppendSlots.release();
    }
  }

  void _trackLateLedgerAppend(String sessionId, Future<File> append) {
    final key = _safeSessionId(sessionId);
    late final Future<void> barrier;
    barrier = append
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) =>
              silentLog('ai_file_mutation_ledger', '延迟账本写入失败', error, stack),
        )
        .whenComplete(() {
          try {
            _invalidateSessionCache(sessionId);
            if (identical(_lateLedgerAppends[key], barrier)) {
              _lateLedgerAppends.remove(key);
            }
          } finally {
            _ledgerAppendSlots.release();
          }
        });
    _lateLedgerAppends[key] = barrier;
  }

  Future<List<FileMutationRecord>> recordsForSession(String sessionId) async {
    return (await _recordsForSessionResult(sessionId)).records;
  }

  Future<({List<FileMutationRecord> records, bool succeeded})>
  _recordsForSessionResult(
    String sessionId, {
    bool initialize = true,
    MonotonicDeadline? deadline,
  }) async {
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
      if (!await _entityExists(ledger, deadline: deadline)) {
        _recordsCache.put(cacheKey, const <FileMutationRecord>[]);
        return (records: const <FileMutationRecord>[], succeeded: true);
      }
      final content = await _readTextFile(
        ledger,
        maxBytes: _maxLedgerBytes,
        deadline: deadline,
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
            throw const FormatException('变更账本损坏记录数已达到上限。');
          }
        }
      }
      if (hitRecordLimit) {
        throw const FormatException('变更账本记录数已达到上限。');
      }
      if (malformedLines > 0) {
        silentLog(
          'ai_file_mutation_ledger',
          '忽略 $malformedLines 条损坏账本记录',
          firstMalformedError!,
          firstMalformedStack,
        );
      }
    } on TimeoutException {
      return (records: const <FileMutationRecord>[], succeeded: false);
    } catch (error, stack) {
      _logFileErrorUnlessMissing('读取账本', error, stack);
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

  /// 单次扫描统计指定工具调用的变更记录，无记录的 ID 不返回。
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

  /// 单次读取账本和状态，按账本顺序构建多个工具调用的变更视图。
  /// 无记录的 ID 不返回，行差异计算受 [_lineDeltaConcurrency] 限制。
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

  /// 会话级 history inspector 用：一次性返回当前会话所有记录
  /// 的 view，一次完成磁盘扫描和 ledger 读取。
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
      silentLog('ai_file_mutation_ledger', '计算记录行差异', error, stack);
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
  }) {
    return _restoreRecordLocked(
      sessionId: sessionId,
      recordId: recordId,
      // before 为 null 表示这是 create，撤销 = 删除磁盘文件。
      targetSha: (record) => record.beforeSha,
      missingBlobReason: 'before-blob-missing',
      logAction: '撤销',
      applyUndoneMutation: (all, target, undone) {
        // 级联标记：同一文件上不早于本记录的变更全部视为已撤销。
        for (final record in all) {
          if (record.filePath != target.filePath) continue;
          if (!record.createdAt.isBefore(target.createdAt)) {
            undone.add(record.recordId);
          }
        }
      },
    );
  }

  /// 撤销与重做的共用骨架：定位记录 → 按目标侧 blob 恢复磁盘（blob 为 null
  /// 即删除文件）→ 更新 undone 集合。两者只在「取哪一侧 blob」「缺失 blob 的
  /// 原因串」「日志措辞」和「如何变更 undone 集合」四点上不同。
  Future<FileMutationOutcome> _restoreRecordLocked({
    required String sessionId,
    required String recordId,
    required String? Function(FileMutationRecord record) targetSha,
    required String missingBlobReason,
    required String logAction,
    required void Function(
      List<FileMutationRecord> all,
      FileMutationRecord target,
      Set<String> undone,
    )
    applyUndoneMutation,
  }) async {
    try {
      final all = await recordsForSession(sessionId);
      final target = all.where((r) => r.recordId == recordId).firstOrNull;
      if (target == null) {
        return const FileMutationOutcome.fail('record-not-found');
      }

      final outFile = File(target.filePath);
      final sha = targetSha(target);
      if (sha == null) {
        if (await _entityExists(outFile)) {
          try {
            await deleteFileAtomically(outFile);
          } catch (error, stack) {
            if (!_isMissingFileError(error)) {
              silentLog(
                'ai_file_mutation_ledger',
                '$logAction删除',
                error,
                stack,
              );
              return FileMutationOutcome.fail('delete-failed:$error');
            }
          }
        }
      } else {
        final content = await _readBlob(sha);
        if (content == null) {
          return FileMutationOutcome.fail(missingBlobReason);
        }
        try {
          await _ensureDirectory(outFile.parent);
          await writeFileAtomically(outFile, content);
        } catch (error, stack) {
          silentLog('ai_file_mutation_ledger', '$logAction写入', error, stack);
          return FileMutationOutcome.fail('restore-failed:$error');
        }
      }

      final undone = await _loadUndoneSet(sessionId);
      applyUndoneMutation(all, target, undone);
      await _saveUndoneSet(sessionId, undone);
      return const FileMutationOutcome.ok();
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '$logAction变更记录', error, stack);
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
  }) {
    return _restoreRecordLocked(
      sessionId: sessionId,
      recordId: recordId,
      // after 为 null 表示这是 delete，重做 = 删除文件。
      targetSha: (record) => record.afterSha,
      missingBlobReason: 'after-blob-missing',
      logAction: '重做',
      // 重做只清除自己的 undone 标志，不做级联。
      applyUndoneMutation: (_, _, undone) => undone.remove(recordId),
    );
  }

  /// 读取账本两侧快照：优先内容寻址 blob，其次旧版历史快照，最后仅在
  /// 当前文件哈希匹配时回退磁盘内容，避免生成看似可信的错误差异。
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
    final deadline = MonotonicDeadline(
      _ledgerTreeScanTimeout,
      timeoutMessage: '统计文件变更账本超过总时限。',
    );
    try {
      final sessionsRoot = Directory(p.join(_root, 'sessions'));
      if (await _entityExists(sessionsRoot, deadline: deadline)) {
        final listing = await _listSessionEntries(deadline: deadline);
        for (final entity in listing.entries) {
          if (deadline.isExpired) break;
          if (entity is! Directory) continue;
          sessionCount += 1;
          try {
            final ledgerFile = File(p.join(entity.path, 'ledger.jsonl'));
            if (!await _entityExists(ledgerFile, deadline: deadline)) continue;
            final content = await _readTextFile(
              ledgerFile,
              maxBytes: _maxLedgerBytes,
              deadline: deadline,
            );
            for (final line in _ledgerLines(content)) {
              if (nullIfBlank(line) != null) recordCount += 1;
            }
          } on TimeoutException {
            break;
          } catch (error, stack) {
            _logFileErrorUnlessMissing('统计会话快照', error, stack);
          }
        }
      }
      final blobsRoot = Directory(p.join(_root, 'blobs'));
      if (!deadline.isExpired &&
          await _entityExists(blobsRoot, deadline: deadline)) {
        final listing = await _listBlobEntries(deadline: deadline);
        for (final entity in listing.entries) {
          if (deadline.isExpired) break;
          if (entity is File &&
              _blobShaFromFile(blob: entity, shard: entity.parent) != null) {
            blobCount += 1;
          }
        }
      }
    } on TimeoutException {
      // 返回时限内完成的部分统计。
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '统计账本快照', error, stack);
    } finally {
      deadline.stop();
    }
    return LedgerStatsSnapshot(
      sessionCount: sessionCount,
      recordCount: recordCount,
      blobCount: blobCount,
    );
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
    } finally {
      _invalidateAllCaches();
      _cachedConfig = null;
      _configLoadFailure = null;
      _nextConfigLoadRetryAt = null;
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
    final dir = _sessionDir(normalizedSessionId);
    await deletePathBounded(
      p.absolute(dir.path),
      policy: _ledgerTreeDeletePolicy,
      allowedRoot: p.absolute(_sessionsDir().path),
    );
    // 不主动 GC blobs，避免影响其他会话引用；总清理时统一处理。
    _invalidateSessionCache(normalizedSessionId);
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
    final deadline = MonotonicDeadline(
      _ledgerTreeScanTimeout,
      timeoutMessage: '清理过期文件变更记录超过总时限。',
    );
    try {
      final cutoff = DateTime.now().subtract(retention);
      final sessions = _sessionsDir();
      if (!await _entityExists(sessions, deadline: deadline)) return 0;
      final listing = await _listSessionEntries(deadline: deadline);
      for (final entity in listing.entries) {
        if (deadline.isExpired) break;
        if (entity is! Directory) continue;
        final sessionId = p.basename(entity.path);
        try {
          final didPrune = await _enqueueSessionMutation(sessionId, () async {
            final stat = await _entityStat(entity, deadline: deadline);
            if (!stat.modified.isBefore(cutoff)) return false;
            await deletePathBounded(
              p.absolute(entity.path),
              policy: BoundedDeletePolicy(
                maxEntries: _maxSessionScanEntries + _maxBlobScanEntries,
                maxDepth: 32,
                totalTimeout: deadline.remaining(),
              ),
              allowedRoot: p.absolute(sessions.path),
            );
            return true;
          });
          if (didPrune) {
            pruned.add(sessionId);
            removed++;
          }
        } on TimeoutException {
          break;
        } catch (error, stack) {
          silentLog('ai_file_mutation_ledger', '清理旧版本记录', error, stack);
        }
      }
    } on TimeoutException {
      // 已完成的清理保留，剩余内容下次继续处理。
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '清理旧版本记录', error, stack);
    } finally {
      deadline.stop();
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
      await _deleteFileIfPresent(ledger, '裁剪账本');
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
    final deadline = MonotonicDeadline(
      _ledgerTreeScanTimeout,
      timeoutMessage: '按版本上限清理文件变更记录超过总时限。',
    );
    try {
      final sessions = _sessionsDir();
      if (!await _entityExists(sessions, deadline: deadline)) return 0;
      final listing = await _listSessionEntries(deadline: deadline);
      for (final entity in listing.entries) {
        if (deadline.isExpired) break;
        if (entity is! Directory) continue;
        final sessionId = p.basename(entity.path);
        removed += await _enqueueSessionMutation(
          sessionId,
          () => _pruneSessionToMaxVersionsLocked(
            sessionId,
            maxVersionsPerFile,
            initializeRecordReads: initializeRecordReads,
            deadline: deadline,
          ),
        );
      }
    } on TimeoutException {
      // 已完成的清理保留，剩余会话下次继续处理。
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '按文件版本上限清理', error, stack);
    } finally {
      deadline.stop();
    }
    return removed;
  }

  Future<int> _pruneSessionToMaxVersionsLocked(
    String sessionId,
    int maxVersionsPerFile, {
    required bool initializeRecordReads,
    MonotonicDeadline? deadline,
  }) async {
    final loaded = await _recordsForSessionResult(
      sessionId,
      initialize: initializeRecordReads,
      deadline: deadline,
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
    if (deadline?.isExpired ?? false) return 0;
    if (survivors.isEmpty) {
      await _deleteFileIfPresent(ledger, '清理账本');
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
    final deadline = MonotonicDeadline(
      _ledgerTreeScanTimeout,
      timeoutMessage: '回收文件变更 Blob 超过总时限。',
    );
    try {
      final referenced = <String>{};
      final sessions = _sessionsDir();
      if (await _entityExists(sessions, deadline: deadline)) {
        final sessionListing = await _listSessionEntries(deadline: deadline);
        if (sessionListing.truncated) {
          return (removed: 0, bytesFreed: 0);
        }
        for (final entity in sessionListing.entries) {
          if (deadline.isExpired) {
            return (removed: 0, bytesFreed: 0);
          }
          if (entity is! Directory) continue;
          final loaded = await _recordsForSessionResult(
            p.basename(entity.path),
            initialize: initializeRecordReads,
            deadline: deadline,
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
      if (!await _entityExists(blobs, deadline: deadline)) {
        return (removed: 0, bytesFreed: 0);
      }
      final blobListing = await _listBlobEntries(deadline: deadline);
      for (final blob in blobListing.entries.whereType<File>()) {
        if (deadline.isExpired) break;
        final sha = _blobShaFromFile(blob: blob, shard: blob.parent);
        if (sha == null) {
          final bytes = await _deleteStaleAtomicBlobArtifact(blob, deadline);
          if (bytes > 0) {
            removed += 1;
            bytesFreed += bytes;
          }
          continue;
        }
        if (!referenced.contains(sha)) {
          try {
            final stat = await _entityStat(blob, deadline: deadline);
            await deleteFileAtomically(blob).timeout(deadline.remaining());
            removed += 1;
            bytesFreed += stat.size;
          } catch (error, stack) {
            _logFileErrorUnlessMissing('回收 blob', error, stack);
          }
        }
      }
    } on TimeoutException {
      // 返回已完成的回收结果，剩余 Blob 下次继续处理。
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '回收未引用 blob', error, stack);
    } finally {
      deadline.stop();
    }
    return (removed: removed, bytesFreed: bytesFreed);
  }

  String? _blobShaFromFile({required File blob, required Directory shard}) {
    final fileName = p.basename(blob.path);
    if (!fileName.endsWith('.txt')) {
      return null;
    }
    final sha = fileName.substring(0, fileName.length - '.txt'.length);
    if (!isLowercaseSha256Hex(sha)) {
      return null;
    }
    if (p.basename(shard.path) != sha.substring(0, 2)) {
      return null;
    }
    return sha;
  }

  Future<int> _deleteStaleAtomicBlobArtifact(
    File file,
    MonotonicDeadline deadline,
  ) async {
    final fileName = p.basename(file.path);
    final isAtomicArtifact =
        fileName.endsWith('.txt.tmp') || fileName.endsWith('.txt.bak');
    if (!isAtomicArtifact) {
      return 0;
    }
    try {
      final stat = await _entityStat(file, deadline: deadline);
      final age = DateTime.now().difference(stat.modified);
      if (age < _staleAtomicArtifactAge) {
        return 0;
      }
      await file.delete().timeout(_fileIoTimeout(deadline));
      return stat.size;
    } catch (error, stack) {
      _logFileErrorUnlessMissing('回收过期原子 blob 产物', error, stack);
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

  bool _isMissingFileError(Object error) {
    return error is FileSystemException && _isMissingFileSystemException(error);
  }

  void _logFileErrorUnlessMissing(
    String action,
    Object error,
    StackTrace stack,
  ) {
    if (_isMissingFileError(error)) {
      return;
    }
    silentLog('ai_file_mutation_ledger', action, error, stack);
  }

  Future<void> _deleteFileIfPresent(File file, String where) async {
    try {
      await deleteFileAtomically(file);
    } catch (error, stack) {
      _logFileErrorUnlessMissing(where, error, stack);
    }
  }

  // ───────────────────────── 内部工具 ─────────────────────────

  Future<Set<String>> _loadUndoneSet(String sessionId) async {
    final cacheKey = _safeSessionId(sessionId);
    final cached = _undoneCache.get(cacheKey);
    if (cached != null) return Set<String>.from(cached);
    try {
      final state = _stateFile(sessionId);
      if (!await _entityExists(state)) {
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
    } catch (error, stack) {
      _logFileErrorUnlessMissing('加载撤销集合', error, stack);
    }
    _undoneCache.put(cacheKey, const <String>{});
    return <String>{};
  }

  Future<void> _saveUndoneSet(String sessionId, Set<String> undone) async {
    final cacheKey = _safeSessionId(sessionId);
    try {
      final state = _stateFile(sessionId);
      if (undone.isEmpty) {
        await _deleteFileIfPresent(state, '删除空的撤销状态');
        _undoneCache.put(cacheKey, const <String>{});
        return;
      }
      await _ensureDirectory(_sessionDir(sessionId));
      await writeFileAtomically(
        state,
        jsonEncode(<String, Object?>{'undone': undone.toList()..sort()}),
      );
      _undoneCache.put(cacheKey, Set<String>.unmodifiable(undone));
    } catch (error, stack) {
      _logFileErrorUnlessMissing('保存撤销集合', error, stack);
      _undoneCache.remove(cacheKey);
    }
  }

  Future<void> _writeBlobIfMissing(String sha, String content) async {
    if (!isLowercaseSha256Hex(sha) || _sha256Of(content) != sha) {
      throw const FormatException('Blob 内容与其 SHA-256 键不匹配。');
    }
    if (utf8.encode(content).length > _blobRecoveryMaxBytes) {
      throw const FileSystemException('Blob 大小超过 $_blobRecoveryMaxBytes 字节上限。');
    }
    final shard = sha.substring(0, 2);
    final dir = Directory(p.join(_blobsDir().path, shard));
    final file = File(p.join(dir.path, '$sha.txt'));
    if (await _entityExists(file)) return;
    await _ensureDirectory(dir);
    await writeFileAtomically(file, content);
  }

  Future<String?> _readBlob(String sha) async {
    if (!isLowercaseSha256Hex(sha)) return null;
    try {
      final shard = sha.substring(0, 2);
      final file = File(p.join(_blobsDir().path, shard, '$sha.txt'));
      if (!await _entityExists(file)) {
        return _recoverBlobFromLegacyVersions(sha);
      }
      return await readBoundedFileString(file, maxBytes: _blobRecoveryMaxBytes);
    } catch (error, stack) {
      _logFileErrorUnlessMissing('读取 blob', error, stack);
      return null;
    }
  }

  Future<String?> _readCurrentFileIfShaMatches({
    required String filePath,
    required String expectedSha,
    required int expectedSize,
  }) async {
    if (!isLowercaseSha256Hex(expectedSha) || nullIfBlank(filePath) == null) {
      return null;
    }
    try {
      final file = File(filePath);
      if (!await _entityExists(file)) return null;
      final stat = await _entityStat(file);
      if (stat.type != FileSystemEntityType.file) return null;
      if (expectedSize > 0 && stat.size != expectedSize) return null;
      if (stat.size > _blobRecoveryMaxBytes) return null;
      final content = await readBoundedFileString(
        file,
        maxBytes: _blobRecoveryMaxBytes,
      );
      if (_sha256Of(content) != expectedSha) return null;
      await _cacheRecoveredBlob(expectedSha, content, '缓存当前 blob');
      return content;
    } catch (error, stack) {
      _logFileErrorUnlessMissing('恢复当前文件 blob', error, stack);
      return null;
    }
  }

  Future<String?> _recoverBlobFromLegacyVersions(String sha) async {
    if (!isLowercaseSha256Hex(sha)) return null;
    if (_legacyBlobRecoveryMisses.contains(sha)) return null;
    try {
      final indexResult = await _legacyBlobIndex();
      final path = nullIfBlank(indexResult.paths[sha]);
      if (path == null) {
        if (indexResult.complete) _recordLegacyBlobRecoveryMiss(sha);
        return null;
      }
      final file = File(path);
      if (!await _entityExists(file)) {
        _recordLegacyBlobRecoveryMiss(sha);
        return null;
      }
      final stat = await _entityStat(file);
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
      await _cacheRecoveredBlob(sha, content, '缓存旧版 blob');
      return content;
    } catch (error, stack) {
      _logFileErrorUnlessMissing('恢复旧版 blob', error, stack);
      _recordLegacyBlobRecoveryMiss(sha);
      return null;
    }
  }

  /// 记录恢复失败的 [sha]，达到上限时淘汰最早条目。
  void _recordLegacyBlobRecoveryMiss(String sha) {
    if (_legacyBlobRecoveryMisses.length >= _maxLegacyBlobRecoveryMisses) {
      _legacyBlobRecoveryMisses.remove(_legacyBlobRecoveryMisses.first);
    }
    _legacyBlobRecoveryMisses.add(sha);
  }

  Future<({Map<String, String> paths, bool complete})>
  _legacyBlobIndex() async {
    final cached = _legacyBlobPathIndex;
    if (cached != null) return (paths: cached, complete: true);
    final index = <String, String>{};
    final legacyRoot = Directory(p.join(_root, 'legacy_versions'));
    final deadline = MonotonicDeadline(
      _ledgerTreeScanTimeout,
      timeoutMessage: '索引旧版文件历史超过总时限。',
    );
    var complete = false;
    try {
      if (!await _entityExists(legacyRoot, deadline: deadline)) {
        _legacyBlobPathIndex = const <String, String>{};
        return (paths: _legacyBlobPathIndex!, complete: true);
      }
      var scanned = 0;
      final listing = await listDirectoryBounded(
        legacyRoot,
        maxEntries: _maxLegacyMigrationEntries,
        recursive: true,
        totalTimeout: deadline.remaining(),
      );
      complete = !listing.truncated;
      for (final entity in listing.entries) {
        if (scanned >= _legacyBlobRecoveryMaxFiles || deadline.isExpired) {
          complete = false;
          break;
        }
        if (entity is! File || !entity.path.endsWith('.content')) continue;
        scanned += 1;
        try {
          final stat = await _entityStat(entity, deadline: deadline);
          if (stat.type != FileSystemEntityType.file ||
              stat.size > _blobRecoveryMaxBytes) {
            continue;
          }
          final content = await _readTextFile(
            entity,
            maxBytes: _blobRecoveryMaxBytes,
            deadline: deadline,
          );
          index.putIfAbsent(_sha256Of(content), () => entity.path);
        } on TimeoutException {
          complete = false;
          break;
        } catch (error, stack) {
          complete = false;
          _logFileErrorUnlessMissing('索引旧版 blob', error, stack);
        }
      }
    } on TimeoutException {
      complete = false;
    } catch (error, stack) {
      complete = false;
      silentLog('ai_file_mutation_ledger', '索引旧版 blob', error, stack);
    } finally {
      deadline.stop();
    }
    final immutable = Map<String, String>.unmodifiable(index);
    if (complete) _legacyBlobPathIndex = immutable;
    return (paths: immutable, complete: complete);
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
      if (!await _entityExists(sessions)) return out;
      final listing = await _listSessionEntries();
      for (final entity in listing.entries) {
        if (entity is Directory) {
          out.add(p.basename(entity.path));
        }
      }
    } catch (error, stack) {
      silentLog('ai_file_mutation_ledger', '列出会话 ID', error, stack);
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
        throw StateError('账本导出记录数超过上限 $_maxExportRecords。');
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
        throw StateError('账本导出记录数超过上限 $_maxExportRecords。');
      }
      bySession.putIfAbsent(r.sessionId, () => <FileMutationRecord>[]).add(r);
      if (r.beforeSha != null) referenced.add(r.beforeSha!);
      if (r.afterSha != null) referenced.add(r.afterSha!);
    }
    if (bySession.length > _maxExportSessions) {
      throw StateError('账本导出会话数超过上限 $_maxExportSessions。');
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
      throw StateError('账本导出会话数超过上限 $_maxExportSessions。');
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
          '账本导出 Blob 大小超过上限 ${formatByteSize(_maxExportBlobBytes)}。',
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
      silentLog('ai_file_mutation_ledger', '解析导入包', error, stack);
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
            !isLowercaseSha256Hex(sha) ||
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
          silentLog('ai_file_mutation_ledger', '导入包 blob $sha', error, stack);
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
          await _ensureDirectory(_sessionDir(sid));
          final ledger = _ledgerFile(sid);
          final loaded = await _recordsForSessionResult(sid);
          if (!loaded.succeeded) return 0;
          final existingIds = loaded.records.map((r) => r.recordId).toSet();
          final buffer = StringBuffer();
          try {
            if (await _entityExists(ledger)) {
              final existing = await readBoundedFileString(
                ledger,
                maxBytes: _maxLedgerBytes,
              );
              buffer.write(existing);
              if (!existing.endsWith('\n') && existing.isNotEmpty) {
                buffer.writeln();
              }
            }
          } catch (error, stack) {
            _logFileErrorUnlessMissing('读取现有账本以导入', error, stack);
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
        silentLog('ai_file_mutation_ledger', '导入包会话 $sid', error, stack);
      }
    }
    return imported;
  }
}
