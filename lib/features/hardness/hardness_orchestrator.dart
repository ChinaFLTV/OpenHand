import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'hardness_cli_catalog.dart';
import 'model/hardness_phase.dart';
import 'model/hardness_role_config.dart';
import 'model/hardness_session_config.dart';

/// Framework version for the Hardness Engineering orchestrator protocol.
/// Increment when the prompt schema or orchestration logic changes
/// in a breaking / significant way.
const int kHardnessOrchestratorVersion = 1;
const String kHardnessOrchestratorDisplayVersion = '1.0.0';

// ─────────────────────────────────────────────────────────────────────────────
// Phase-level status & log
// ─────────────────────────────────────────────────────────────────────────────

enum HardnessPhaseStatus {
  pending,
  paused,
  running,
  completed,
  failed,
  cancelled,
  skipped,
}

enum HardnessPhaseExecutionBlocker { missingConfig, unsupportedCli }

HardnessPhaseStatus _hardnessPhaseStatusFromStorageValue(String value) {
  for (final status in HardnessPhaseStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return HardnessPhaseStatus.pending;
}

class HardnessPhaseLog {
  HardnessPhaseLog(this.phase);

  final HardnessPhase phase;
  HardnessPhaseStatus status = HardnessPhaseStatus.pending;
  final List<String> lines = [];
  int? exitCode;
  String? savedLogPath;

  /// Files changed during this phase execution.
  /// Each entry: relative path → (before content hash, after content hash).
  List<HardnessChangedFile> changedFiles = [];

  HardnessPhaseLogSnapshot toSnapshot() {
    return HardnessPhaseLogSnapshot(
      phaseValue: phase.storageValue,
      statusValue: status.name,
      lines: List<String>.from(lines),
      exitCode: exitCode,
      savedLogPath: savedLogPath,
      changedFiles: changedFiles.map((f) => f.toJson()).toList(),
    );
  }

  static HardnessPhaseLog fromSnapshot(HardnessPhaseLogSnapshot snapshot) {
    final log = HardnessPhaseLog(snapshot.phase)
      ..status = snapshot.status
      ..exitCode = snapshot.exitCode
      ..savedLogPath = snapshot.savedLogPath
      ..changedFiles = snapshot.parsedChangedFiles;
    log.lines.addAll(snapshot.lines);
    return log;
  }
}

class HardnessPhaseLogSnapshot {
  const HardnessPhaseLogSnapshot({
    required this.phaseValue,
    required this.statusValue,
    required this.lines,
    this.exitCode,
    this.savedLogPath,
    this.changedFiles = const [],
  });

  final String phaseValue;
  final String statusValue;
  final List<String> lines;
  final int? exitCode;
  final String? savedLogPath;
  final List<Map<String, Object?>> changedFiles;

  HardnessPhase get phase => HardnessPhase.fromStorageValue(phaseValue)!;
  HardnessPhaseStatus get status =>
      _hardnessPhaseStatusFromStorageValue(statusValue);

  List<HardnessChangedFile> get parsedChangedFiles =>
      changedFiles.map(HardnessChangedFile.fromJson).toList();

  HardnessPhaseLogSnapshot copyWith({
    String? phaseValue,
    String? statusValue,
    List<String>? lines,
    int? exitCode,
    Object? savedLogPath = _hardnessPhaseLogSnapshotUnset,
    List<Map<String, Object?>>? changedFiles,
  }) {
    return HardnessPhaseLogSnapshot(
      phaseValue: phaseValue ?? this.phaseValue,
      statusValue: statusValue ?? this.statusValue,
      lines: lines ?? this.lines,
      exitCode: exitCode ?? this.exitCode,
      savedLogPath: identical(savedLogPath, _hardnessPhaseLogSnapshotUnset)
          ? this.savedLogPath
          : savedLogPath as String?,
      changedFiles: changedFiles ?? this.changedFiles,
    );
  }

  Map<String, Object?> toJson() => {
    'phase': phaseValue,
    'status': statusValue,
    'lines': lines,
    'exit_code': exitCode,
    'saved_log_path': savedLogPath,
    'changed_files': changedFiles,
  };

  static HardnessPhaseLogSnapshot? fromJson(Map<String, Object?> json) {
    final phaseValue = '${json['phase'] ?? ''}'.trim();
    if (HardnessPhase.fromStorageValue(phaseValue) == null) {
      return null;
    }
    final rawLines = json['lines'];
    final rawChangedFiles = json['changed_files'];
    return HardnessPhaseLogSnapshot(
      phaseValue: phaseValue,
      statusValue: '${json['status'] ?? HardnessPhaseStatus.pending.name}',
      lines: rawLines is List
          ? rawLines.map((item) => '$item').toList(growable: false)
          : const <String>[],
      exitCode: json['exit_code'] is int ? json['exit_code'] as int : null,
      savedLogPath: json['saved_log_path'] == null
          ? null
          : '${json['saved_log_path']}',
      changedFiles: rawChangedFiles is List
          ? rawChangedFiles
              .whereType<Map>()
              .map((m) => Map<String, Object?>.from(m))
              .toList()
          : const [],
    );
  }
}

/// Represents a file changed during a phase execution.
class HardnessChangedFile {
  const HardnessChangedFile({
    required this.relativePath,
    required this.absolutePath,
    required this.changeType,
    this.beforeContent,
    this.afterContent,
  });

  final String relativePath;
  final String absolutePath;
  final HardnessFileChangeType changeType;
  final String? beforeContent;
  final String? afterContent;

  Map<String, Object?> toJson() => {
    'relative_path': relativePath,
    'absolute_path': absolutePath,
    'change_type': changeType.name,
    'before_content': beforeContent,
    'after_content': afterContent,
  };

  static HardnessChangedFile fromJson(Map<String, Object?> json) {
    return HardnessChangedFile(
      relativePath: '${json['relative_path'] ?? ''}',
      absolutePath: '${json['absolute_path'] ?? ''}',
      changeType: HardnessFileChangeType.values.firstWhere(
        (t) => t.name == '${json['change_type']}',
        orElse: () => HardnessFileChangeType.modified,
      ),
      beforeContent: json['before_content'] as String?,
      afterContent: json['after_content'] as String?,
    );
  }
}

enum HardnessFileChangeType { added, modified, deleted }

const Object _hardnessPhaseLogSnapshotUnset = Object();

// ─────────────────────────────────────────────────────────────────────────────
// Overall orchestrator status
// ─────────────────────────────────────────────────────────────────────────────

enum HardnessOrchestratorStatus { idle, running, completed, failed, cancelled }

// ─────────────────────────────────────────────────────────────────────────────
// HardnessOrchestrator
//
// Program-driven state machine that executes Hardness Engineering phases
// directly via CLI processes — no AI orchestration layer involved.
// ─────────────────────────────────────────────────────────────────────────────

class HardnessOrchestrator extends ChangeNotifier {
  HardnessOrchestrator(this._config);

  HardnessSessionConfig _config;
  HardnessSessionConfig get config => _config;

  HardnessOrchestratorStatus _status = HardnessOrchestratorStatus.idle;
  HardnessOrchestratorStatus get status => _status;

  List<HardnessPhaseLog> _phaseLogs = const [];
  List<HardnessPhaseLog> get phaseLogs => _phaseLogs;
  List<HardnessPhaseLogSnapshot> get phaseLogSnapshots =>
      _phaseLogs.map((log) => log.toSnapshot()).toList(growable: false);

  HardnessPhase? _currentPhase;
  HardnessPhase? get currentPhase => _currentPhase;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _stopRequested = false;
  bool _isDisposed = false;
  Process? _activeProcess;

  /// Tracks how many review→re-plan→re-implement cycles have been executed
  /// to prevent infinite loops.
  int _reviewRetryCount = 0;
  int get reviewRetryCount => _reviewRetryCount;
  static const int _maxReviewRetries = 3;

  /// When true, phases auto-advance without user approval (YOLO mode).
  bool _fullAccessPermission = false;
  bool get fullAccessPermission => _fullAccessPermission;
  set fullAccessPermission(bool value) {
    if (_fullAccessPermission == value) return;
    _fullAccessPermission = value;
    // If full-access was just enabled while waiting for approval, auto-approve.
    if (value && _phaseApprovalCompleter != null && !_phaseApprovalCompleter!.isCompleted) {
      resolvePhaseApproval(true);
    }
    notifyListeners();
  }

  /// Callback invoked between phases when [fullAccessPermission] is false.
  /// Serves as a notification so the UI can rebuild and show the approval
  /// banner. The actual approval/rejection flows through [resolvePhaseApproval].
  void Function(HardnessPhase nextPhase)? onPhaseApprovalRequired;

  /// Completer used to resume the pipeline after waiting for user approval.
  Completer<bool>? _phaseApprovalCompleter;

  /// The phase that is awaiting user approval, or null.
  HardnessPhase? _awaitingApprovalPhase;
  HardnessPhase? get awaitingApprovalPhase => _awaitingApprovalPhase;

  bool _resumePendingApproval = false;
  int? _resumeStartIndex;

  static const String _resumePausedPhaseNote =
      '⚠ 应用关闭后，该阶段已暂停；恢复执行前需要重新审批。';
  static const String _resumeSessionNote =
      '⚠ 应用关闭后，会话已恢复；继续执行前需要重新审批。';

  /// Called by the UI to approve/reject advancing to the pending phase.
  void resolvePhaseApproval(bool approved) {
    final completer = _phaseApprovalCompleter;
    if (completer == null || completer.isCompleted) {
      if (!_resumePendingApproval || _resumeStartIndex == null) {
        return;
      }
      final resumeIndex = _resumeStartIndex!;
      _resumePendingApproval = false;
      _resumeStartIndex = null;
      _awaitingApprovalPhase = null;
      if (!approved) {
        _markRemainingPhasesCancelledFrom(resumeIndex);
        _status = HardnessOrchestratorStatus.cancelled;
        _currentPhase = null;
        notifyListeners();
        return;
      }
      notifyListeners();
      unawaited(_resumeFromIndex(resumeIndex));
      return;
    }
    completer.complete(approved);
    _phaseApprovalCompleter = null;
    _awaitingApprovalPhase = null;
    notifyListeners();
  }

  /// Updates the config (e.g. role CLI/model changes for pending phases).
  void updateConfig(HardnessSessionConfig newConfig) {
    _config = newConfig;
    notifyListeners();
  }

  bool canExecutePhase(HardnessPhase phase) =>
      phaseExecutionBlocker(phase) == null;

  HardnessPhaseExecutionBlocker? phaseExecutionBlocker(HardnessPhase phase) {
    final roleConfig = _roleConfigForPhase(phase);
    if (!roleConfig.isConfigured) {
      return HardnessPhaseExecutionBlocker.missingConfig;
    }
    final cliEntry = _cliEntryForRoleConfig(roleConfig);
    if (!cliEntry.supportsHeadless) {
      return HardnessPhaseExecutionBlocker.unsupportedCli;
    }
    return null;
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> startOrResume() async {
    if (_status == HardnessOrchestratorStatus.running) {
      return;
    }
    if (_resumePendingApproval) {
      notifyListeners();
      return;
    }
    final resumableIndex = _resumablePhaseIndex();
    if (_status == HardnessOrchestratorStatus.idle &&
        _phaseLogs.isNotEmpty &&
        resumableIndex != null) {
      await _resumeFromIndex(resumableIndex);
      return;
    }
    await start();
  }

  /// Starts the full Hardness Engineering phase pipeline.
  /// Safe to call only when [status] is [HardnessOrchestratorStatus.idle].
  Future<void> start() async {
    if (_status == HardnessOrchestratorStatus.running) return;
    _stopRequested = false;
    _reviewRetryCount = 0;
    _errorMessage = null;
    _resumePendingApproval = false;
    _resumeStartIndex = null;
    _awaitingApprovalPhase = null;
    _phaseApprovalCompleter = null;

    final firstRun = config.isFirstRun();
    final phases = firstRun
        ? [
            HardnessPhase.metaCollection,
            HardnessPhase.reading,
            HardnessPhase.planning,
            HardnessPhase.implementing,
            HardnessPhase.reviewing,
          ]
        : [
            HardnessPhase.reading,
            HardnessPhase.planning,
            HardnessPhase.implementing,
            HardnessPhase.reviewing,
          ];

    _phaseLogs = phases.map(HardnessPhaseLog.new).toList();
    await _executePipeline(startIndex: 0, skipApprovalForStartIndex: true);
  }

  Future<void> _resumeFromIndex(int startIndex) async {
    if (_status == HardnessOrchestratorStatus.running) {
      return;
    }
    if (startIndex < 0 || startIndex >= _phaseLogs.length) {
      await start();
      return;
    }
    _stopRequested = false;
    _errorMessage = null;
    _resumePendingApproval = false;
    _resumeStartIndex = null;
    _phaseApprovalCompleter = null;
    _awaitingApprovalPhase = null;
    _reviewRetryCount = _inferReviewRetryCount();
    await _executePipeline(
      startIndex: startIndex,
      skipApprovalForStartIndex: true,
    );
  }

  Future<void> _executePipeline({
    required int startIndex,
    required bool skipApprovalForStartIndex,
  }) async {
    _status = HardnessOrchestratorStatus.running;
    notifyListeners();

    try {
      for (var i = startIndex; i < _phaseLogs.length; i++) {
        final log = _phaseLogs[i];
        if (_isDisposed || _stopRequested) {
          if (log.status == HardnessPhaseStatus.pending ||
              log.status == HardnessPhaseStatus.paused) {
            log.status = HardnessPhaseStatus.cancelled;
          }
          continue;
        }

        // ── Phase-gate: request user approval unless full-access ────────
        final shouldSkipApprovalForThisPhase =
            skipApprovalForStartIndex && i == startIndex;
        if (i > 0 && !_fullAccessPermission && !shouldSkipApprovalForThisPhase) {
          _currentPhase = log.phase;
          log.status = HardnessPhaseStatus.paused;
          _awaitingApprovalPhase = log.phase;
          _phaseApprovalCompleter = Completer<bool>();
          notifyListeners();

          // Notify external listener (fire-and-forget) so the UI can rebuild
          // and show the approval banner.
          onPhaseApprovalRequired?.call(log.phase);

          // Block until resolvePhaseApproval() is called from the UI.
          final approved = await _phaseApprovalCompleter!.future;
          _phaseApprovalCompleter = null;
          _awaitingApprovalPhase = null;
          notifyListeners();

          if (!approved || _isDisposed) {
            log.status = HardnessPhaseStatus.cancelled;
            notifyListeners();
            // Mark all remaining phases as cancelled too.
            _markRemainingPhasesCancelledFrom(i + 1);
            _status = HardnessOrchestratorStatus.cancelled;
            _currentPhase = null;
            notifyListeners();
            return;
          }
        }

        if (_isDisposed || _stopRequested) {
          log.status = HardnessPhaseStatus.cancelled;
          notifyListeners();
          break;
        }

        await _runPhase(log);
        if (log.status == HardnessPhaseStatus.failed ||
            log.status == HardnessPhaseStatus.cancelled) {
          break;
        }

        // ── Review failure → re-plan/re-implement loop ──────────────────
        // When the reviewer outputs "FAIL" and the phase completed normally,
        // insert additional planning + implementing + reviewing phases so
        // the issues can be addressed in a new iteration.
        if (log.phase == HardnessPhase.reviewing &&
            log.status == HardnessPhaseStatus.completed &&
            _reviewOutputIndicatesFailure(log)) {
          _reviewRetryCount++;
          if (_reviewRetryCount <= _maxReviewRetries) {
            final extraPhases = [
              HardnessPhaseLog(HardnessPhase.planning),
              HardnessPhaseLog(HardnessPhase.implementing),
              HardnessPhaseLog(HardnessPhase.reviewing),
            ];
            // Insert after current position.
            _phaseLogs.insertAll(i + 1, extraPhases);
            notifyListeners();
          }
        }
      }

      if (_isDisposed) return;

      // Mark any remaining untouched phases according to the final outcome.
      for (final log in _phaseLogs) {
        if (log.status == HardnessPhaseStatus.pending ||
            log.status == HardnessPhaseStatus.paused) {
          log.status = _stopRequested
              ? HardnessPhaseStatus.cancelled
              : HardnessPhaseStatus.skipped;
        }
      }

      if (_stopRequested) {
        _status = HardnessOrchestratorStatus.cancelled;
      } else if (_phaseLogs.any((l) => l.status == HardnessPhaseStatus.failed)) {
        _status = HardnessOrchestratorStatus.failed;
        _errorMessage ??= '有阶段执行失败，请检查日志';
      } else {
        _status = HardnessOrchestratorStatus.completed;
      }
    } catch (e, st) {
      if (_isDisposed) return;
      _status = HardnessOrchestratorStatus.failed;
      _errorMessage = e.toString();
      debugPrint('HardnessOrchestrator unhandled error: $e\n$st');
    }

    _currentPhase = null;
    notifyListeners();
  }

  /// Requests cancellation of the currently running phase.
  /// Sends SIGTERM to the active CLI process if any.
  void cancel() {
    if (_status != HardnessOrchestratorStatus.running) return;
    _stopRequested = true;
    // Resolve any pending approval completer so the pipeline loop can exit.
    final completer = _phaseApprovalCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
      _phaseApprovalCompleter = null;
      _awaitingApprovalPhase = null;
    }
    try {
      _activeProcess?.kill();
    } catch (_) {}
    notifyListeners();
  }

  void restoreSnapshot({
    required HardnessOrchestratorStatus status,
    required List<HardnessPhaseLogSnapshot> phaseLogs,
    String? errorMessage,
    HardnessPhase? currentPhase,
  }) {
    _stopRequested = false;
    _activeProcess = null;
    _status = status;
    _phaseLogs = phaseLogs
        .map(HardnessPhaseLog.fromSnapshot)
        .toList(growable: false);
    _currentPhase = currentPhase;
    _errorMessage = errorMessage;
    _phaseApprovalCompleter = null;
    _awaitingApprovalPhase = null;
    _resumePendingApproval = false;
    _resumeStartIndex = null;
    _reviewRetryCount = _inferReviewRetryCount();

    if (_status == HardnessOrchestratorStatus.running) {
      final interruptedIndex = _resumablePhaseIndex(includeRunning: true);
      if (interruptedIndex != null) {
        final interruptedLog = _phaseLogs[interruptedIndex];
        _appendResumeNotice(
          interruptedLog,
          wasRunning: interruptedLog.status == HardnessPhaseStatus.running,
        );
        interruptedLog.status = HardnessPhaseStatus.paused;
        _status = HardnessOrchestratorStatus.idle;
      }
    }

    final resumableIndex = _resumablePhaseIndex();
    if (_status == HardnessOrchestratorStatus.idle && resumableIndex != null) {
      final resumableLog = _phaseLogs[resumableIndex];
      if (resumableLog.status == HardnessPhaseStatus.pending) {
        resumableLog.status = HardnessPhaseStatus.paused;
        _appendResumeNotice(resumableLog, wasRunning: false);
      }
      _currentPhase = resumableLog.phase;
      _awaitingApprovalPhase = resumableLog.phase;
      _resumePendingApproval = true;
      _resumeStartIndex = resumableIndex;
      _errorMessage = null;
    }
    notifyListeners();
  }

  int? _resumablePhaseIndex({bool includeRunning = false}) {
    for (var index = 0; index < _phaseLogs.length; index += 1) {
      final status = _phaseLogs[index].status;
      if (status == HardnessPhaseStatus.paused ||
          status == HardnessPhaseStatus.pending ||
          (includeRunning && status == HardnessPhaseStatus.running)) {
        return index;
      }
    }
    return null;
  }

  int _inferReviewRetryCount() {
    final reviewPhaseCount = _phaseLogs
        .where((log) => log.phase == HardnessPhase.reviewing)
        .length;
    if (reviewPhaseCount <= 1) {
      return 0;
    }
    return reviewPhaseCount - 1;
  }

  void _markRemainingPhasesCancelledFrom(int startIndex) {
    for (var index = startIndex; index < _phaseLogs.length; index += 1) {
      if (_phaseLogs[index].status == HardnessPhaseStatus.pending ||
          _phaseLogs[index].status == HardnessPhaseStatus.paused) {
        _phaseLogs[index].status = HardnessPhaseStatus.cancelled;
      }
    }
  }

  void _appendResumeNotice(HardnessPhaseLog log, {required bool wasRunning}) {
    final note = wasRunning ? _resumePausedPhaseNote : _resumeSessionNote;
    if (log.lines.contains(note)) {
      return;
    }
    if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
      log.lines.add('');
    }
    log.lines.add(note);
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Resolve any pending approval so the pipeline loop exits cleanly.
    final completer = _phaseApprovalCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
      _phaseApprovalCompleter = null;
    }
    // Kill any running process so it doesn't become an orphan.
    try {
      _activeProcess?.kill();
    } catch (_) {}
    super.dispose();
  }

  // ── Phase execution ─────────────────────────────────────────────────────────

  Future<void> _runPhase(HardnessPhaseLog log) async {
    _currentPhase = log.phase;
    log.status = HardnessPhaseStatus.running;
    notifyListeners();

    final roleConfig = _roleConfigForPhase(log.phase);
    final executionBlocker = phaseExecutionBlocker(log.phase);

    if (executionBlocker == HardnessPhaseExecutionBlocker.missingConfig) {
      _appendLine(log, '✗ 阶段无法执行：请先为该阶段配置 CLI 和模型。');
      _errorMessage = '存在未配置 CLI/模型的阶段，执行已停止。';
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      return;
    }

    if (executionBlocker == HardnessPhaseExecutionBlocker.unsupportedCli) {
      _appendLine(log, '✗ 阶段无法执行：当前 CLI 不支持无交互执行，请更换为支持 headless 的 CLI。');
      _errorMessage = '存在不支持无交互执行的 CLI 配置，执行已停止。';
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      return;
    }

    // Resolve CLI entry from catalog; fall back to a minimal entry if unknown.
    final cliEntry = _cliEntryForRoleConfig(roleConfig);

    _appendLine(
      log,
      '▶ 阶段：${log.phase.displayNameZh}  |  CLI: ${cliEntry.executable}'
      '  |  模型: ${roleConfig.modelId.isNotEmpty ? roleConfig.modelId : '(默认)'}',
    );
    notifyListeners();

    File? promptFile;
    try {
      // 1. Build the prompt from persistence context + mission template.
      final prompt = await _buildPhasePrompt(log.phase);
      if (_isDisposed) return;

      promptFile = await _writePromptFile(log.phase, prompt);
      if (_isDisposed) return;

      // 2. Construct the shell command string.
      final cliCmd = _buildCliCommandStr(
        cliEntry.executable,
        roleConfig.modelId,
        promptFile.path,
      );

      if (cliCmd == null) {
        _appendLine(
          log,
          '✗ 不支持 ${cliEntry.executable} 的无交互 CLI 调用方式。\n'
          '  请改选支持非交互模式的 CLI（如 claude、codex、aider、gemini）。',
        );
        _errorMessage = '存在不支持无交互执行的 CLI 配置，执行已停止。';
        log.status = HardnessPhaseStatus.failed;
        notifyListeners();
        return;
      }

      _appendLine(log, '');
      _appendLine(log, '> $cliCmd');
      _appendLine(log, '');
      notifyListeners();

      // 2b. Snapshot working directory files before execution.
      final preSnapshot = await _snapshotWorkingDirectory();

      // 3. Run the CLI and stream output.
      final exitCode = await _spawnAndCollect(
        cliCmd,
        workingDirectory: _config.workingDirectory,
        onLine: (line) {
          _appendLine(log, line);
          notifyListeners();
        },
      );

      if (_isDisposed) return;

      log.exitCode = exitCode;

      // 3b. Snapshot after execution and compute diff.
      final postSnapshot = await _snapshotWorkingDirectory();
      log.changedFiles = _computeChangedFiles(preSnapshot, postSnapshot);

      if (_stopRequested) {
        _appendLine(log, '');
        _appendLine(log, '⚠ 已中止');
        log.status = HardnessPhaseStatus.cancelled;
      } else if (exitCode != 0) {
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 进程退出码：$exitCode');
        log.status = HardnessPhaseStatus.failed;
      } else {
        log.status = HardnessPhaseStatus.completed;
        await _savePhasePersistence(log);
      }
    } on ProcessException catch (e) {
      if (_isDisposed) return;
      _appendLine(log, '');
      _appendLine(log, '✗ 进程启动失败：${e.message}（命令：${e.executable}）');
      if (e.message.contains('No such file') || e.errorCode == 2) {
        _appendLine(
          log,
          '  → 检测不到可执行文件"${cliEntry.executable}"，请确认 CLI 已安装并在 PATH 中。',
        );
      }
      log.status = HardnessPhaseStatus.failed;
    } on TimeoutException catch (e) {
      if (_isDisposed) return;
      _appendLine(log, '');
      _appendLine(log, '✗ 超时：${e.message}');
      log.status = HardnessPhaseStatus.failed;
    } catch (e, st) {
      if (_isDisposed) return;
      _appendLine(log, '');
      _appendLine(log, '✗ 执行错误：$e');
      debugPrint('Phase ${log.phase} error: $e\n$st');
      log.status = HardnessPhaseStatus.failed;
    } finally {
      try {
        promptFile?.deleteSync();
      } catch (_) {}
    }

    notifyListeners();
  }

  // ── Review failure detection ─────────────────────────────────────────────

  /// Scans the reviewer's output for a "FAIL" verdict.
  /// The reviewer mission template instructs the agent to begin with PASS or
  /// FAIL on the first non-empty line. We scan the first meaningful lines
  /// (skipping blanks, command echoes, and UI decoration) for a FAIL indicator.
  bool _reviewOutputIndicatesFailure(HardnessPhaseLog log) {
    for (final line in log.lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      // Skip UI decoration lines.
      if (trimmed.startsWith('▶ ') ||
          trimmed.startsWith('✓ ') ||
          trimmed.startsWith('✗ ') ||
          trimmed.startsWith('⚠ ') ||
          trimmed.startsWith('> ')) {
        continue;
      }
      // Check for FAIL verdict (case-insensitive, may be prefixed by ** markdown).
      final normalized = trimmed
          .replaceAll('*', '')
          .replaceAll('#', '')
          .trim()
          .toUpperCase();
      if (normalized.startsWith('FAIL')) {
        return true;
      }
      if (normalized.startsWith('PASS')) {
        return false;
      }
      // Only inspect the first few meaningful lines.
      if (normalized.length > 5) {
        return false;
      }
    }
    return false;
  }

  // ── Role ↔ config mapping ────────────────────────────────────────────────

  HardnessRoleConfig _roleConfigForPhase(HardnessPhase phase) => switch (phase) {
        HardnessPhase.metaCollection => config.profilerConfig,
        HardnessPhase.reading => config.readerConfig,
        HardnessPhase.planning => config.plannerConfig,
        HardnessPhase.implementing => config.implementerConfig,
        HardnessPhase.reviewing => config.reviewerConfig,
      };

  HardnessCli _cliEntryForRoleConfig(HardnessRoleConfig roleConfig) {
    return kHardnessCliCatalog
            .where((c) => c.name == roleConfig.cliName)
            .firstOrNull ??
        HardnessCli(
          name: roleConfig.cliName,
          executable: roleConfig.cliName.split(' ').first.toLowerCase(),
          knownModels: const [],
        );
  }

  // ── Prompt construction ──────────────────────────────────────────────────

  Future<String> _buildPhasePrompt(HardnessPhase phase) async {
    final steeringDir = p.join(config.persistenceDirectory, 'steering');

    String readIfExists(String path) {
      try {
        final f = File(path);
        return f.existsSync() ? f.readAsStringSync() : '';
      } catch (_) {
        return '';
      }
    }

    final archContent =
        readIfExists(p.join(steeringDir, 'meta', 'architecture.md'));
    final convContent =
        readIfExists(p.join(steeringDir, 'meta', 'conventions.md'));

    // Latest handoff document.
    String handoffContent = '';
    try {
      final handoffDir = Directory(p.join(steeringDir, 'handoff'));
      if (handoffDir.existsSync()) {
        final files = handoffDir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        if (files.isNotEmpty) handoffContent = files.last.readAsStringSync();
      }
    } catch (_) {}

    // All lesson files combined.
    String lessonsContent = '';
    try {
      final lessonDir = Directory(p.join(steeringDir, 'lesson'));
      if (lessonDir.existsSync()) {
        final files = lessonDir.listSync().whereType<File>().toList();
        if (files.isNotEmpty) {
          lessonsContent =
              files.map((f) => f.readAsStringSync()).join('\n\n---\n\n');
        }
      }
    } catch (_) {}

    // Latest plan (needed for implementing and reviewing phases).
    String planContent = '';
    if (phase == HardnessPhase.implementing ||
        phase == HardnessPhase.reviewing) {
      try {
        final planDir = Directory(p.join(steeringDir, 'plan'));
        if (planDir.existsSync()) {
          final files = planDir.listSync().whereType<File>().toList()
            ..sort((a, b) => b.path.compareTo(a.path)); // newest first
          if (files.isNotEmpty) planContent = files.first.readAsStringSync();
        }
      } catch (_) {}
    }

    // Latest reviewer feedback (included in planning/implementing during retry).
    String feedbackContent = '';
    if (_reviewRetryCount > 0 &&
        (phase == HardnessPhase.planning ||
            phase == HardnessPhase.implementing ||
            phase == HardnessPhase.reviewing)) {
      try {
        final feedbackDir = Directory(p.join(steeringDir, 'feedback'));
        if (feedbackDir.existsSync()) {
          final files = feedbackDir.listSync().whereType<File>().toList()
            ..sort((a, b) => b.path.compareTo(a.path)); // newest first
          if (files.isNotEmpty) {
            feedbackContent = files.first.readAsStringSync();
          }
        }
      } catch (_) {}
    }

    final sb = StringBuffer()
      ..writeln('# Hardness Engineering - ${phase.displayNameZh}阶段')
      ..writeln()
      ..writeln('## 语言要求（强制）')
      ..writeln('1. 你在本阶段的所有自然语言输出、分析结论、执行计划、评审报告，以及写入 steering 目录的全部 Markdown 文档，都必须使用简体中文。')
      ..writeln('2. 禁止使用英文标题、英文小节、英文说明或英文总结，除非内容本身是代码、命令、路径、文件名、接口名、配置键名、日志原文或其他必须保留的技术标识。')
      ..writeln('3. PASS / FAIL、CLI 名称、模型名、代码片段、命令、路径、文件名等技术标识允许保留原文。')
      ..writeln('4. 若需要引用英文原文，请仅保留最小必要范围，并在上下文中使用简体中文解释。')
      ..writeln()
      ..writeln('## 任务')
      ..writeln(config.task)
      ..writeln()
      ..writeln('## 工作目录')
      ..writeln(config.workingDirectory)
      ..writeln();

    if (archContent.isNotEmpty) {
      sb
        ..writeln('## 项目结构与架构')
        ..writeln(archContent)
        ..writeln();
    }

    if (convContent.isNotEmpty) {
      sb
        ..writeln('## 约定与约束')
        ..writeln(convContent)
        ..writeln();
    }

    if (handoffContent.isNotEmpty) {
      sb
        ..writeln('## 交接上下文（上一轮会话）')
        ..writeln(handoffContent)
        ..writeln();
    }

    if (lessonsContent.isNotEmpty) {
      sb
        ..writeln('## 经验教训')
        ..writeln(lessonsContent)
        ..writeln();
    }

    if (planContent.isNotEmpty) {
      sb
        ..writeln('## 执行计划')
        ..writeln(planContent)
        ..writeln();
    }

    if (feedbackContent.isNotEmpty) {
      sb
        ..writeln('## 上一轮验收反馈（必须处理）')
        ..writeln(feedbackContent)
        ..writeln();
    }

    sb
      ..writeln('## 当前角色任务')
      ..writeln(_missionTemplate(phase));

    return sb.toString();
  }

  String _missionTemplate(HardnessPhase phase) {
    final meta = p.join(config.persistenceDirectory, 'steering', 'meta');
    final planDir = p.join(config.persistenceDirectory, 'steering', 'plan');
    final feedbackDir =
        p.join(config.persistenceDirectory, 'steering', 'feedback');
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);

    return switch (phase) {
      HardnessPhase.metaCollection => '''你是该项目的探档者（Profiler）。

    请仔细扫描 ${config.workingDirectory} 下的项目，并产出两个完整的 Markdown 文档。除代码、命令、路径、文件名等技术标识外，所有标题、说明、总结都必须使用简体中文。

    1. **architecture.md**：必须包含
       - 顶层目录树（展开 2-3 层）
       - 关键入口点（主文件、配置文件、构建文件）
       - 识别到的语言、框架以及构建/测试工具
       - 主要模块及其职责
       - 外部依赖（库、API、服务）

    2. **conventions.md**：必须包含
       - 现有代码中观察到的编码风格与命名约定
       - 目录约定（不同类型文件通常放在哪里）
       - README 或配置文件中可确认的构建、测试、Lint 命令
       - 明确存在的限制、规则或易错点

    将文件保存到：
    - $meta/architecture.md
    - $meta/conventions.md

    要求准确、克制、基于事实。项目中不存在的信息不得臆测。''',

      HardnessPhase.reading => '''你是本任务的调读者/分析者（Reader/Analyst）。

    请深入分析 ${config.workingDirectory} 下的项目，并产出一份结构化分析报告。除代码、命令、路径、文件名等技术标识外，报告全文必须使用简体中文。

    分析内容必须覆盖：
    1. 对任务要求的精确拆解
    2. 需要创建或修改的具体文件与模块
    3. 每个相关文件的当前状态（准确概括关键实现）
    4. 潜在风险、副作用与外部依赖
    5. 推荐的实现路径及理由

    请使用清晰、结构化的 Markdown 报告格式输出。
    这份报告会被规划者直接使用，因此必须充分、准确、可执行。''',

      HardnessPhase.planning => '''你是本任务的规划者（Planner）。

    请基于上方的任务与分析上下文，产出一份详细、按编号排列的执行计划。除代码、命令、路径、文件名等技术标识外，所有步骤说明和验收标准都必须使用简体中文。

    每个步骤都必须满足：
    - **原子化**：表示一个可独立验证的单一改动
    - **具体**：明确指出需要创建或修改的确切文件
    - **可验证**：包含清晰的验收标准
    - **带复杂度标签**：使用 [simple | medium | complex]

    计划完成后，请将完整 Markdown 文件保存到：
    $planDir/plan-$ts.md

    计划文件必须以任务描述开头，并包含全部执行步骤。''',

      HardnessPhase.implementing => '''你是本任务的实施者（Implementer）。

    请按照上方“执行计划”中的步骤逐项实施。
    工作目录：${config.workingDirectory}

    关键要求：
    - 严格遵守“约定与约束”中的要求
    - 若存在“经验教训”，必须主动规避已知问题
    - 每次改动都必须保持原子性，并与当前计划步骤严格对应
    - 不得修改与当前任务无关的文件
    - 面向用户或后续角色输出的总结说明必须使用简体中文

    全部步骤完成后，请用简体中文简要总结：
    - 改了什么，以及为什么这样改
    - 如果偏离了计划，说明偏离点及原因
    - 实施过程中发现的潜在问题''',

      HardnessPhase.reviewing => '''你是本任务的验收者（Reviewer）。

    **关键要求：你处于一个全新且独立的会话中。**
    你不知道实施者的推理过程，也不能假设任何步骤已经被正确完成。
    你必须仅基于原始需求、上方执行计划以及项目当前真实代码状态进行验收。
    不要默认实现正确，必须从零开始逐项核验。
    ${_reviewRetryCount > 0 ? '\n**注意：这是第 $_reviewRetryCount 次重试验收。上一轮或更早的验收已经发现问题，请重点检查这些问题是否已被真正修复。**\n' : ''}
    请将当前实现与原始需求及上方执行计划逐项对照。

    必须验证以下内容：
    1. 所有计划步骤均已完成，并满足对应验收标准
    2. 没有引入回归问题（如可行，应运行相关测试）
    3. 代码质量与项目约定保持一致
    4. 边界情况与错误路径得到了恰当处理
    5. 没有引入明显的安全风险

    请输出一份结构化验收报告：
    - 第一行必须写 **PASS** 或 **FAIL**
    - 除第一行 verdict 外，其余正文、标题、问题描述、修复建议必须全部使用简体中文
    - 列出带有具体文件引用的发现
    - 若为 FAIL：列出验收通过前必须修复的具体问题
    - 若为 FAIL：每个问题都必须具体、可执行，并指向精确文件路径

    将完整报告保存到：
    $feedbackDir/feedback-$ts.md''',
    };
  }

  // ── CLI command construction ─────────────────────────────────────────────

  /// Returns a shell command string suitable for `bash -l -c "..."`.
  /// Returns [null] for CLI executables with no known non-interactive mode.
  String? _buildCliCommandStr(
    String executable,
    String modelId,
    String promptFilePath,
  ) {
    final quotedPath = _shellSingleQuote(promptFilePath);
    // Double-quoted command substitution prevents word-splitting when the
    // shell expands the file contents as a CLI argument.
    // \$ escapes Dart interpolation; the resulting shell string is "$(cat '...')".
    final promptSubst = '"\$(cat $quotedPath)"';
    final modelFlag =
        modelId.isNotEmpty ? ' --model ${_shellSingleQuote(modelId)}' : '';
    final modelFlagShort =
        modelId.isNotEmpty ? ' -m ${_shellSingleQuote(modelId)}' : '';
    // Quoted working directory — used by CLIs that accept an explicit -C flag.
    final quotedWd = _shellSingleQuote(config.workingDirectory);

    return switch (executable) {
      'claude' => 'claude$modelFlag -p $promptSubst',
      // codex exec flags:
      //   -m / --model  : exec-level model flag
      //   --skip-git-repo-check : required when the workdir is not a git repo
      //   --full-auto   : non-interactive mode (-a on-request + sandbox workspace-write)
      //   -C <dir>      : tell codex the project root (distinct from shell cd)
      //   --            : end of flags, next token is positional PROMPT
      'codex' =>
        'codex exec$modelFlag --skip-git-repo-check --full-auto -C $quotedWd -- $promptSubst',
      'aider' =>
        'aider$modelFlag --message $promptSubst --yes --no-auto-commits',
      'gemini' => 'gemini$modelFlagShort -p $promptSubst',
      'goose' => 'goose run$modelFlag --text $promptSubst',
      'q' => 'q chat --no-interactive $promptSubst',
      'amp' => 'amp$modelFlag $promptSubst',
      'plandex' => 'plandex tell -f $quotedPath',
      // GUI IDEs — do not support headless non-interactive CLI invocation.
      'cursor' || 'windsurf' || 'kiro' => null,
      // Generic fallback — try -p flag; may not work for all CLIs.
      _ => '$executable$modelFlag -p $promptSubst',
    };
  }

  // ── I/O helpers ──────────────────────────────────────────────────────────

  Future<File> _writePromptFile(HardnessPhase phase, String content) async {
    final name =
        'he_${phase.storageValue}_${DateTime.now().millisecondsSinceEpoch}.md';
    final file = File(p.join(Directory.systemTemp.path, name));
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<int> _spawnAndCollect(
    String cmdStr, {
    required String workingDirectory,
    required void Function(String line) onLine,
    // Safety net: kill the process if it hasn't exited within this duration.
    // Two hours is generous; real AI coding tasks complete well within that.
    Duration timeout = const Duration(hours: 2),
  }) async {
    final shell = Platform.environment['SHELL'] ?? '/bin/bash';
    final quotedWd = _shellSingleQuote(workingDirectory);
    final fullCmd = 'cd $quotedWd && $cmdStr';

    final process = await Process.start(
      shell,
      ['-l', '-c', fullCmd],
    );
    _activeProcess = process;

    // ── Critical fix: close stdin immediately ──────────────────────────────
    // When spawned by the app the child's stdin is a live pipe (not a TTY).
    // Several CLI tools (and the Rust `rmcp` MCP transport library used by
    // codex) poll stdin for protocol framing or readline input.  Since the
    // app never writes to the pipe the child blocks indefinitely waiting for
    // data.  Sending EOF removes that block without affecting execution.
    unawaited(process.stdin.close());

    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(onLine)
        .asFuture<void>();

    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(onLine)
        .asFuture<void>();

    try {
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        // Graceful escalation: SIGTERM first, then SIGKILL after 5 s.
        process.kill(); // SIGTERM (default)
        try {
          exitCode = await process.exitCode
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
          exitCode = await process.exitCode
              .timeout(const Duration(seconds: 2))
              .catchError((_) => -1);
        }
        rethrow; // Propagated as TimeoutException → _runPhase catch block.
      }

      // Drain remaining buffered output.  Time-box this so that a child
      // process that inherited our pipe FDs can never prevent us from
      // returning (e.g. a daemon launched by the CLI that doesn't exit).
      await Future.wait([stdoutFuture, stderrFuture]).timeout(
        const Duration(seconds: 5),
        onTimeout: () => [],
      );
      return exitCode;
    } finally {
      _activeProcess = null;
    }
  }

  Future<void> _savePhasePersistence(HardnessPhaseLog log) async {
    try {
      final logDir = Directory(
        p.join(config.persistenceDirectory, 'steering', 'log'),
      );
      await logDir.create(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final file = File(
        p.join(logDir.path, '${log.phase.storageValue}-$ts.log'),
      );
      await file.writeAsString(log.lines.join('\n'));
      log.savedLogPath = file.path;
    } catch (e) {
      debugPrint('Failed to save phase log: $e');
    }
  }

  void _appendLine(HardnessPhaseLog log, String line) {
    log.lines.add(line);
  }

  /// POSIX single-quote a string, safely escaping embedded single quotes.
  static String _shellSingleQuote(String s) =>
      "'${s.replaceAll("'", "'\\''")}'";

  // ── File change tracking ────────────────────────────────────────────────

  /// Ignored directory names for snapshot (common build artifacts / VCS).
  static const Set<String> _snapshotIgnoredDirs = {
    '.git', '.svn', '.hg', 'node_modules', '.dart_tool', 'build', '.build',
    '__pycache__', '.idea', '.vscode', '.gradle', '.DS_Store',
  };

  /// Max file size to capture content for diff (1 MB).
  static const int _maxDiffFileSize = 1024 * 1024;

  /// Takes a lightweight snapshot of the working directory:
  /// returns a map of relativePath → (lastModified, size, content).
  Future<Map<String, _FileSnapshot>> _snapshotWorkingDirectory() async {
    final result = <String, _FileSnapshot>{};
    final workDir = Directory(_config.workingDirectory);
    if (!workDir.existsSync()) return result;

    try {
      await for (final entity in workDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: _config.workingDirectory);
        // Skip ignored directories
        final parts = p.split(rel);
        if (parts.any((part) => _snapshotIgnoredDirs.contains(part))) continue;

        try {
          final stat = entity.statSync();
          String? content;
          if (stat.size <= _maxDiffFileSize) {
            try {
              content = entity.readAsStringSync();
            } catch (_) {
              // binary file — skip content
            }
          }
          result[rel] = _FileSnapshot(
            modified: stat.modified,
            size: stat.size,
            content: content,
          );
        } catch (_) {
          // Permission denied or gone — skip
        }
      }
    } catch (e) {
      debugPrint('Snapshot error: $e');
    }
    return result;
  }

  List<HardnessChangedFile> _computeChangedFiles(
    Map<String, _FileSnapshot> before,
    Map<String, _FileSnapshot> after,
  ) {
    final changes = <HardnessChangedFile>[];

    // Added or modified files
    for (final entry in after.entries) {
      final rel = entry.key;
      final post = entry.value;
      final pre = before[rel];

      if (pre == null) {
        changes.add(HardnessChangedFile(
          relativePath: rel,
          absolutePath: p.join(_config.workingDirectory, rel),
          changeType: HardnessFileChangeType.added,
          afterContent: post.content,
        ));
      } else if (pre.modified != post.modified || pre.size != post.size) {
        changes.add(HardnessChangedFile(
          relativePath: rel,
          absolutePath: p.join(_config.workingDirectory, rel),
          changeType: HardnessFileChangeType.modified,
          beforeContent: pre.content,
          afterContent: post.content,
        ));
      }
    }

    // Deleted files
    for (final rel in before.keys) {
      if (!after.containsKey(rel)) {
        changes.add(HardnessChangedFile(
          relativePath: rel,
          absolutePath: p.join(_config.workingDirectory, rel),
          changeType: HardnessFileChangeType.deleted,
          beforeContent: before[rel]!.content,
        ));
      }
    }

    changes.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return changes;
  }
}

class _FileSnapshot {
  const _FileSnapshot({
    required this.modified,
    required this.size,
    this.content,
  });
  final DateTime modified;
  final int size;
  final String? content;
}
