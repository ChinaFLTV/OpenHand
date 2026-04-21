import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../ai/model/ai_model_config.dart';
import '../ai/model/ai_session_runtime_context.dart';
import 'hardness_api_phase_runner.dart';
import 'hardness_cli_catalog.dart';
import 'hardness_prompt_builder.dart';
import 'model/hardness_phase.dart';
import 'model/hardness_phase_context_config.dart';
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

enum HardnessPhaseExecutionBlocker {
  missingConfig,
  unsupportedCli,
  missingApiModel,
  missingApiRunner,
}

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

  /// For reviewing phases: true if the review verdict was FAIL.
  /// Used by the UI to show a distinct status for completed-but-failed reviews.
  bool reviewVerdictFail = false;

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
      reviewVerdictFail: reviewVerdictFail,
    );
  }

  static HardnessPhaseLog fromSnapshot(HardnessPhaseLogSnapshot snapshot) {
    final log = HardnessPhaseLog(snapshot.phase)
      ..status = snapshot.status
      ..exitCode = snapshot.exitCode
      ..savedLogPath = snapshot.savedLogPath
      ..changedFiles = snapshot.parsedChangedFiles
      ..reviewVerdictFail = snapshot.reviewVerdictFail;
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
    this.reviewVerdictFail = false,
  });

  final String phaseValue;
  final String statusValue;
  final List<String> lines;
  final int? exitCode;
  final String? savedLogPath;
  final List<Map<String, Object?>> changedFiles;
  final bool reviewVerdictFail;

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
    bool? reviewVerdictFail,
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
      reviewVerdictFail: reviewVerdictFail ?? this.reviewVerdictFail,
    );
  }

  Map<String, Object?> toJson() => {
    'phase': phaseValue,
    'status': statusValue,
    'lines': lines,
    'exit_code': exitCode,
    'saved_log_path': savedLogPath,
    'changed_files': changedFiles,
    'review_verdict_fail': reviewVerdictFail,
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
      reviewVerdictFail: json['review_verdict_fail'] == true,
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

  /// Optional API phase runner for URL mode execution. Must be set before
  /// starting a session that contains URL-mode role configs.
  HardnessApiPhaseRunner? apiPhaseRunner;

  /// Callback to resolve an AiModelConfig by its ID from settings.
  /// Must be set before starting a session that contains URL-mode role configs.
  AiModelConfig? Function(String configId)? resolveAiModelConfig;

  /// Callback to build the runtime context for API-based phase execution.
  /// Provides memory entries, MCP servers, skills, etc.
  Future<AiSessionRuntimeContext> Function(String workingDirectory)?
  buildApiRuntimeContext;

  HardnessOrchestratorStatus _status = HardnessOrchestratorStatus.idle;
  HardnessOrchestratorStatus get status => _status;

  List<HardnessPhaseLog> _phaseLogs = <HardnessPhaseLog>[];
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
  Completer<void>? _apiCancelCompleter;

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
    if (value &&
        _phaseApprovalCompleter != null &&
        !_phaseApprovalCompleter!.isCompleted) {
      _manualPhaseInputRequested = false;
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

  /// When true, the paused phase is waiting for user-authored input from the
  /// composer before continuing.
  bool _manualPhaseInputRequested = false;
  bool get manualPhaseInputRequested => _manualPhaseInputRequested;
  HardnessPhase? get awaitingManualPhaseInputPhase =>
      _manualPhaseInputRequested ? _awaitingApprovalPhase : null;
  bool get awaitingManualPhaseInput => awaitingManualPhaseInputPhase != null;

  /// User-authored content queued for the next execution of a specific phase.
  /// This survives app restarts so an interrupted approval can continue with
  /// the same human context.
  HardnessPhase? _queuedManualPhaseInputPhase;
  HardnessPhase? get queuedManualPhaseInputPhase =>
      _queuedManualPhaseInputPhase;
  String? _queuedManualPhaseInput;
  String? get queuedManualPhaseInput => _queuedManualPhaseInput;
  bool get hasQueuedManualPhaseInput =>
      _queuedManualPhaseInput?.trim().isNotEmpty == true;
  bool hasQueuedManualPhaseInputFor(HardnessPhase phase) =>
      _queuedManualPhaseInputPhase == phase && hasQueuedManualPhaseInput;
  bool isManualPhaseInputActiveFor(HardnessPhase phase) =>
      awaitingManualPhaseInputPhase == phase;

  /// Explicit review verdict set by the user through the pass/fail buttons.
  /// true = PASS, false = FAIL, null = not set (AI-only review).
  bool? _userReviewVerdict;

  bool _resumePendingApproval = false;
  int? _resumeStartIndex;

  static const String _resumePausedPhaseNote = '⚠ 应用关闭后，该阶段已暂停；恢复执行前需要重新审批。';
  static const String _resumeSessionNote = '⚠ 应用关闭后，会话已恢复；继续执行前需要重新审批。';

  bool supportsManualPhaseInput(HardnessPhase phase) {
    return switch (phase) {
      HardnessPhase.metaCollection ||
      HardnessPhase.planning ||
      HardnessPhase.reviewing => true,
      HardnessPhase.reading || HardnessPhase.implementing => false,
    };
  }

  void setManualPhaseInputRequested(bool value) {
    final awaitingPhase = _awaitingApprovalPhase;
    if (_fullAccessPermission ||
        awaitingPhase == null ||
        !supportsManualPhaseInput(awaitingPhase)) {
      return;
    }
    if (_manualPhaseInputRequested == value) {
      return;
    }
    _manualPhaseInputRequested = value;
    notifyListeners();
  }

  bool submitManualPhaseInput(String input, {bool? reviewVerdict}) {
    final awaitingPhase = _awaitingApprovalPhase;
    if (awaitingPhase == null || !supportsManualPhaseInput(awaitingPhase)) {
      return false;
    }
    final normalized = input.trim();
    if (normalized.isEmpty) {
      return false;
    }
    _queuedManualPhaseInputPhase = awaitingPhase;
    _queuedManualPhaseInput = normalized;
    _manualPhaseInputRequested = false;

    // Store explicit user review verdict when provided.
    if (awaitingPhase == HardnessPhase.reviewing && reviewVerdict != null) {
      _userReviewVerdict = reviewVerdict;
    }

    final awaitingLog = _currentAwaitingApprovalLog();
    if (awaitingLog != null) {
      if (awaitingLog.lines.isNotEmpty && awaitingLog.lines.last.isNotEmpty) {
        _appendLine(awaitingLog, '');
      }
      _appendLine(
        awaitingLog,
        '【${_manualPhaseInputLogHeading(awaitingPhase)}】',
      );
      // Prepend explicit verdict marker for reviewing phase.
      if (awaitingPhase == HardnessPhase.reviewing && reviewVerdict != null) {
        _appendLine(awaitingLog, reviewVerdict ? 'PASS' : 'FAIL');
        _appendLine(awaitingLog, '');
      }
      for (final line in normalized.split('\n')) {
        _appendLine(awaitingLog, line);
      }
      _appendLine(awaitingLog, '');
      // Show verdict-specific accepted-log for reviewing phase.
      if (awaitingPhase == HardnessPhase.reviewing && reviewVerdict != null) {
        _appendLine(
          awaitingLog,
          reviewVerdict
              ? 'ℹ 已接收用户人工验收结果，用户判定为 PASS。本轮验收会结合该结果进行交叉核验并生成 feedback。'
              : 'ℹ 已接收用户人工验收结果，用户判定为 FAIL。AI 会将审查意见做润色处理，持久化到 feedback 目录，随后推进到新一轮规划阶段。',
        );
      } else {
        _appendLine(awaitingLog, _manualPhaseInputAcceptedLog(awaitingPhase));
      }
    }

    _completePhaseApproval(true);
    return true;
  }

  /// Called by the UI to approve/reject advancing to the pending phase.
  void resolvePhaseApproval(bool approved) {
    _manualPhaseInputRequested = false;
    _completePhaseApproval(approved);
  }

  void _completePhaseApproval(bool approved) {
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
    if (roleConfig.isUrlMode) {
      // URL mode: check API infrastructure and model config availability.
      if (apiPhaseRunner == null || buildApiRuntimeContext == null) {
        return HardnessPhaseExecutionBlocker.missingApiRunner;
      }
      final configId = roleConfig.aiModelConfigId;
      if (configId == null || configId.trim().isEmpty) {
        return HardnessPhaseExecutionBlocker.missingApiModel;
      }
      final modelConfig = resolveAiModelConfig?.call(configId);
      if (modelConfig == null) {
        return HardnessPhaseExecutionBlocker.missingApiModel;
      }
      return null;
    }
    // CLI mode: check headless support.
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
    final failedIndex = _failedPhaseIndex();
    if (_status == HardnessOrchestratorStatus.failed &&
        _phaseLogs.isNotEmpty &&
        failedIndex != null) {
      _resetPhaseLogsForRetryFrom(failedIndex);
      await _resumeFromIndex(failedIndex);
      return;
    }
    // Handle the case where the overall status is "failed" due to an
    // unhandled exception (e.g. the old fixed-length list bug) but no
    // individual phase is actually "failed".  Recompute the true status
    // and try to resume from the last non-completed phase instead of
    // restarting the entire pipeline.
    if (_status == HardnessOrchestratorStatus.failed &&
        _phaseLogs.isNotEmpty &&
        failedIndex == null) {
      _status = _computeOverallStatus();
      _errorMessage = null;
      notifyListeners();
      final resumable = _resumablePhaseIndex();
      if (resumable != null) {
        await _resumeFromIndex(resumable);
        return;
      }
      // All phases completed — nothing more to do.
      if (_status == HardnessOrchestratorStatus.completed) {
        return;
      }
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
    _manualPhaseInputRequested = false;
    _queuedManualPhaseInputPhase = null;
    _queuedManualPhaseInput = null;
    _userReviewVerdict = null;

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

    _phaseLogs = List<HardnessPhaseLog>.from(phases.map(HardnessPhaseLog.new));
    await _executePipeline(startIndex: 0, skipApprovalForStartIndex: !firstRun);
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
    _manualPhaseInputRequested = false;
    _userReviewVerdict = null;
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

    HardnessPhaseLog? activeLog;
    try {
      for (var i = startIndex; i < _phaseLogs.length; i++) {
        final log = _phaseLogs[i];
        activeLog = log;
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
        if (!_fullAccessPermission &&
            !shouldSkipApprovalForThisPhase &&
            _shouldGatePhaseEntry(i, log.phase)) {
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

        // ── Review verdict handling ────────────────────────────────────
        // Check for review verdict BEFORE the generic failed/cancelled
        // break so that a reviewing phase whose CLI/API execution happened
        // to fail can still enter the feedback loop when the user already
        // submitted a FAIL verdict.  "Review not passed" is a *result*,
        // not an execution failure — the orchestrator should continue to
        // the plan→implement→review retry cycle.
        if (log.phase == HardnessPhase.reviewing &&
            _reviewIndicatesFailure(log)) {
          // The reviewing phase detected a FAIL verdict (either from the
          // user button or from the CLI output).  Override a potential
          // execution failure status to "completed" because the phase did
          // produce the expected semantics (a verdict), and mark it as
          // review-verdict-fail.
          if (log.status == HardnessPhaseStatus.failed) {
            _appendLine(log, '');
            _appendLine(log, 'ℹ 验收判定为 FAIL，执行异常已降级处理，进入反馈迭代流程。');
            log.status = HardnessPhaseStatus.completed;
            _errorMessage = null;
          }
          log.reviewVerdictFail = true;
          _reviewRetryCount++;
          if (_reviewRetryCount <= _maxReviewRetries) {
            _insertReviewRetryPhasesAfter(i);
            notifyListeners();
          }
          // Do NOT break — continue to the next iteration which processes
          // the freshly-inserted planning phase.
          if (log.status == HardnessPhaseStatus.completed &&
              _queuedManualPhaseInputPhase == log.phase) {
            _queuedManualPhaseInputPhase = null;
            _queuedManualPhaseInput = null;
          }
          continue;
        }

        if (log.status == HardnessPhaseStatus.failed ||
            log.status == HardnessPhaseStatus.cancelled) {
          break;
        }

        if (log.status == HardnessPhaseStatus.completed &&
            _queuedManualPhaseInputPhase == log.phase) {
          _queuedManualPhaseInputPhase = null;
          _queuedManualPhaseInput = null;
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
      } else if (_phaseLogs.any(
        (l) => l.status == HardnessPhaseStatus.failed,
      )) {
        _status = HardnessOrchestratorStatus.failed;
        _errorMessage ??= '有阶段执行失败，请检查日志';
      } else {
        _status = HardnessOrchestratorStatus.completed;
      }
    } catch (e) {
      if (_isDisposed) return;
      _recordUnhandledPhaseError(activeLog, e);
      _status = HardnessOrchestratorStatus.failed;
      _errorMessage = e.toString();
    }

    _currentPhase = null;
    notifyListeners();
  }

  /// Requests cancellation of the currently running phase.
  /// Sends SIGTERM followed by SIGKILL after a short grace period.
  void cancel() {
    if (_status != HardnessOrchestratorStatus.running) return;
    _stopRequested = true;
    _manualPhaseInputRequested = false;
    // Resolve any pending approval completer so the pipeline loop can exit.
    final completer = _phaseApprovalCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
      _phaseApprovalCompleter = null;
      _awaitingApprovalPhase = null;
    }
    // Signal cancellation to any running API phase.
    final apiCancel = _apiCancelCompleter;
    if (apiCancel != null && !apiCancel.isCompleted) {
      apiCancel.complete();
      _apiCancelCompleter = null;
    }
    // Immediately mark any running phase as cancelled for instant UI feedback.
    for (final log in _phaseLogs) {
      if (log.status == HardnessPhaseStatus.running) {
        log.status = HardnessPhaseStatus.cancelled;
      }
    }
    _killActiveProcess();
    notifyListeners();
  }

  /// Gracefully kills the active CLI process: SIGTERM first, then SIGKILL
  /// after 3 seconds if still alive.
  void _killActiveProcess() {
    final process = _activeProcess;
    if (process == null) return;
    try {
      process.kill(); // SIGTERM
    } catch (_) {}
    // Escalate to SIGKILL after 3 seconds if the process hasn't exited.
    Future.delayed(const Duration(seconds: 3), () {
      if (_activeProcess == process) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    });
  }

  void restoreSnapshot({
    required HardnessOrchestratorStatus status,
    required List<HardnessPhaseLogSnapshot> phaseLogs,
    String? errorMessage,
    HardnessPhase? currentPhase,
    bool manualPhaseInputRequested = false,
    String? queuedManualPhaseInput,
    HardnessPhase? queuedManualPhaseInputPhase,
  }) {
    _stopRequested = false;
    _activeProcess = null;
    _status = status;
    _phaseLogs = List<HardnessPhaseLog>.from(
      phaseLogs.map(HardnessPhaseLog.fromSnapshot),
    );
    _currentPhase = currentPhase;
    _errorMessage = errorMessage;
    _phaseApprovalCompleter = null;
    _awaitingApprovalPhase = null;
    _resumePendingApproval = false;
    _resumeStartIndex = null;
    _manualPhaseInputRequested = false;
    final normalizedManualPhaseInput = queuedManualPhaseInput?.trim();
    if (normalizedManualPhaseInput == null ||
        normalizedManualPhaseInput.isEmpty) {
      _queuedManualPhaseInputPhase = null;
      _queuedManualPhaseInput = null;
    } else {
      _queuedManualPhaseInputPhase = queuedManualPhaseInputPhase;
      _queuedManualPhaseInput = normalizedManualPhaseInput;
    }
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
      _manualPhaseInputRequested =
          manualPhaseInputRequested &&
          supportsManualPhaseInput(resumableLog.phase);
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

  int? _failedPhaseIndex() {
    for (var index = 0; index < _phaseLogs.length; index += 1) {
      if (_phaseLogs[index].status == HardnessPhaseStatus.failed) {
        return index;
      }
    }
    return null;
  }

  void _resetPhaseLogsForRetryFrom(int startIndex) {
    if (startIndex < 0 || startIndex >= _phaseLogs.length) {
      return;
    }
    final nextLogs = List<HardnessPhaseLog>.from(_phaseLogs);
    for (var index = startIndex; index < nextLogs.length; index += 1) {
      nextLogs[index] = HardnessPhaseLog(nextLogs[index].phase);
    }
    _phaseLogs = nextLogs;
    _currentPhase = null;
    _errorMessage = null;
  }

  /// Re-executes a single phase at the given index.
  /// Resets the phase log, runs it, and does NOT auto-advance.
  /// If [fullAccessPermission] is false, the phase will first pause for
  /// approval before executing.
  Future<void> reExecutePhase(int phaseIndex) async {
    if (phaseIndex < 0 || phaseIndex >= _phaseLogs.length) return;
    if (_status == HardnessOrchestratorStatus.running) return;

    final oldLog = _phaseLogs[phaseIndex];
    final freshLog = HardnessPhaseLog(oldLog.phase);
    _phaseLogs = List<HardnessPhaseLog>.from(_phaseLogs);
    _phaseLogs[phaseIndex] = freshLog;

    _status = HardnessOrchestratorStatus.running;
    _errorMessage = null;
    _stopRequested = false;
    _userReviewVerdict = null;
    notifyListeners();

    try {
      // ── Phase-gate: request user approval if not full-access ──────
      if (!_fullAccessPermission) {
        _currentPhase = freshLog.phase;
        freshLog.status = HardnessPhaseStatus.paused;
        _awaitingApprovalPhase = freshLog.phase;
        _phaseApprovalCompleter = Completer<bool>();
        notifyListeners();

        onPhaseApprovalRequired?.call(freshLog.phase);

        final approved = await _phaseApprovalCompleter!.future;
        _phaseApprovalCompleter = null;
        _awaitingApprovalPhase = null;
        notifyListeners();

        if (!approved || _isDisposed) {
          freshLog.status = HardnessPhaseStatus.cancelled;
          _status = HardnessOrchestratorStatus.idle;
          _currentPhase = null;
          notifyListeners();
          return;
        }
      }

      if (_isDisposed || _stopRequested) {
        freshLog.status = HardnessPhaseStatus.cancelled;
        _status = HardnessOrchestratorStatus.idle;
        _currentPhase = null;
        notifyListeners();
        return;
      }

      await _runPhase(freshLog);

      if (freshLog.status == HardnessPhaseStatus.completed &&
          _queuedManualPhaseInputPhase == freshLog.phase) {
        _queuedManualPhaseInputPhase = null;
        _queuedManualPhaseInput = null;
      }

      // Handle review verdict fail for single-phase re-execution.
      // When a FAIL verdict is detected, insert retry phases (plan→impl→
      // review) after the current position and continue as a pipeline
      // instead of ending the single-phase re-execution here.
      if (freshLog.phase == HardnessPhase.reviewing &&
          _reviewIndicatesFailure(freshLog)) {
        if (freshLog.status == HardnessPhaseStatus.failed) {
          _appendLine(freshLog, '');
          _appendLine(freshLog, 'ℹ 验收判定为 FAIL，执行异常已降级处理，进入反馈迭代流程。');
          freshLog.status = HardnessPhaseStatus.completed;
          _errorMessage = null;
        }
        freshLog.reviewVerdictFail = true;
        _reviewRetryCount++;
        if (_reviewRetryCount <= _maxReviewRetries) {
          _insertReviewRetryPhasesAfter(phaseIndex);
          notifyListeners();
          // Continue as a pipeline from the newly inserted planning phase.
          await _executePipeline(
            startIndex: phaseIndex + 1,
            skipApprovalForStartIndex: false,
          );
          return;
        }
      }
    } catch (e) {
      if (_isDisposed) return;
      _recordUnhandledPhaseError(freshLog, e);
      _errorMessage = e.toString();
    }

    // Determine overall status from all phase logs.
    _status = _computeOverallStatus();
    _currentPhase = null;
    notifyListeners();
  }

  /// Deletes the phase log at the given index and refreshes state.
  void deletePhaseLog(int phaseIndex) {
    if (phaseIndex < 0 || phaseIndex >= _phaseLogs.length) return;
    if (_status == HardnessOrchestratorStatus.running) return;

    _phaseLogs = List<HardnessPhaseLog>.from(_phaseLogs)..removeAt(phaseIndex);

    // Recompute overall status.
    _status = _computeOverallStatus();
    _reviewRetryCount = _inferReviewRetryCount();
    notifyListeners();
  }

  HardnessOrchestratorStatus _computeOverallStatus() {
    if (_phaseLogs.isEmpty) return HardnessOrchestratorStatus.idle;
    if (_phaseLogs.any((l) => l.status == HardnessPhaseStatus.running)) {
      return HardnessOrchestratorStatus.running;
    }
    if (_phaseLogs.any((l) => l.status == HardnessPhaseStatus.failed)) {
      return HardnessOrchestratorStatus.failed;
    }
    if (_phaseLogs.every(
      (l) =>
          l.status == HardnessPhaseStatus.completed ||
          l.status == HardnessPhaseStatus.skipped,
    )) {
      return HardnessOrchestratorStatus.completed;
    }
    if (_phaseLogs.any((l) => l.status == HardnessPhaseStatus.cancelled)) {
      return HardnessOrchestratorStatus.cancelled;
    }
    return HardnessOrchestratorStatus.idle;
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

  List<HardnessPhaseLog> _buildReviewRetryPhaseLogs() {
    return <HardnessPhaseLog>[
      HardnessPhaseLog(HardnessPhase.planning),
      HardnessPhaseLog(HardnessPhase.implementing),
      HardnessPhaseLog(HardnessPhase.reviewing),
    ];
  }

  void _insertReviewRetryPhasesAfter(int phaseIndex) {
    if (phaseIndex < 0 || phaseIndex >= _phaseLogs.length) {
      return;
    }
    final nextLogs = List<HardnessPhaseLog>.from(_phaseLogs);
    nextLogs.insertAll(phaseIndex + 1, _buildReviewRetryPhaseLogs());
    _phaseLogs = nextLogs;
  }

  void _recordUnhandledPhaseError(HardnessPhaseLog? log, Object error) {
    if (log == null) {
      return;
    }
    if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
      _appendLine(log, '');
    }
    _appendLine(log, '✗ HardnessOrchestrator 内部异常：$error');
    if (log.status == HardnessPhaseStatus.running ||
        log.status == HardnessPhaseStatus.pending ||
        log.status == HardnessPhaseStatus.paused) {
      log.status = HardnessPhaseStatus.failed;
    }
  }

  bool _shouldGatePhaseEntry(int index, HardnessPhase phase) {
    if (index > 0) {
      return true;
    }
    return phase == HardnessPhase.metaCollection;
  }

  String _manualPhaseInputLogHeading(HardnessPhase phase) => switch (phase) {
    HardnessPhase.metaCollection => '用户人工研究结果',
    HardnessPhase.planning => '用户人工计划草案',
    HardnessPhase.reviewing => '用户人工验收结果',
    HardnessPhase.reading => '用户人工输入',
    HardnessPhase.implementing => '用户人工输入',
  };

  String _manualPhaseInputAcceptedLog(HardnessPhase phase) => switch (phase) {
    HardnessPhase.metaCollection =>
      'ℹ 已接收用户人工研究结果，本轮 Profile 会结合这些资料产出符合规范的 architecture / conventions 文档。',
    HardnessPhase.planning => 'ℹ 已接收用户人工计划草案，本轮 Plan 会在此基础上润色、补全并输出符合规范的计划文档。',
    HardnessPhase.reviewing => 'ℹ 已接收用户人工验收结果，本轮验收会结合该结果输出 PASS / FAIL 与反馈。',
    HardnessPhase.reading => 'ℹ 已接收用户人工输入。',
    HardnessPhase.implementing => 'ℹ 已接收用户人工输入。',
  };

  String _manualPhaseInputSectionTitle(HardnessPhase phase) => switch (phase) {
    HardnessPhase.metaCollection => '## 用户人工研究结果（高优先级输入）',
    HardnessPhase.planning => '## 用户人工计划草案（高优先级输入）',
    HardnessPhase.reviewing => '## 用户人工验收结果（高优先级输入）',
    HardnessPhase.reading => '## 用户人工输入（高优先级输入）',
    HardnessPhase.implementing => '## 用户人工输入（高优先级输入）',
  };

  String _manualPhaseMissionAddendum(HardnessPhase phase) {
    if (!hasQueuedManualPhaseInputFor(phase)) {
      return '';
    }
    return switch (phase) {
      HardnessPhase.metaCollection =>
        '''
    **本轮存在用户亲自研究的资料或结论。**
    - 你必须把“用户人工研究结果（高优先级输入）”视为高优先级素材，并优先吸收其中的事实、结构与观察结论
    - 你的职责不是忽略这些内容重新来过，而是将其校正、补全、结构化，整理成符合要求的 architecture.md 与 conventions.md
    - 若用户研究结果存在缺漏、格式不规范或信息颗粒度不一致，你需要基于真实项目状态补足并统一表达
    ''',
      HardnessPhase.planning =>
        '''
    **本轮存在用户亲自制定的计划草案。**
    - 你必须把“用户人工计划草案（高优先级输入）”视为高优先级种子方案，在其基础上进行润色、优化、补全与规范化
    - 你的职责不是抛开用户计划另起炉灶，而是将其整理成符合 plan 文档约束的结构化执行计划
    - 若用户草案缺少步骤粒度、验收标准、复杂度标签或文件指向，你需要补足这些缺失项
    ''',
      HardnessPhase.reviewing =>
        '''
    **本轮存在真实用户提交的人工验收结果。**
    - 你必须把"用户人工验收结果（高优先级输入）"视为真实外部观察，而不是可忽略的参考意见
    - 用户已通过界面按钮明确指定了验收结论（PASS 或 FAIL），你必须尊重该结论作为最终判定
    - 若用户判定为 FAIL：你必须输出 FAIL，并将用户的审查意见整理为结构化、可执行的 feedback，保存到指定路径
    - 若用户判定为 PASS：你仍需结合计划、代码与实际实现交叉核验，但应优先尊重用户的通过结论
    ''',
      HardnessPhase.reading => '',
      HardnessPhase.implementing => '',
    };
  }

  void _markRemainingPhasesCancelledFrom(int startIndex) {
    for (var index = startIndex; index < _phaseLogs.length; index += 1) {
      if (_phaseLogs[index].status == HardnessPhaseStatus.pending ||
          _phaseLogs[index].status == HardnessPhaseStatus.paused) {
        _phaseLogs[index].status = HardnessPhaseStatus.cancelled;
      }
    }
  }

  HardnessPhaseLog? _currentAwaitingApprovalLog() {
    final awaitingPhase = _awaitingApprovalPhase;
    if (awaitingPhase == null) {
      return null;
    }
    for (var index = _phaseLogs.length - 1; index >= 0; index -= 1) {
      final log = _phaseLogs[index];
      if (log.phase != awaitingPhase) {
        continue;
      }
      if (log.status == HardnessPhaseStatus.paused ||
          log.status == HardnessPhaseStatus.pending) {
        return log;
      }
    }
    return null;
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
    // Signal cancellation to any running API phase.
    final apiCancel = _apiCancelCompleter;
    if (apiCancel != null && !apiCancel.isCompleted) {
      apiCancel.complete();
      _apiCancelCompleter = null;
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
      _appendLine(log, '✗ 阶段无法执行：请先为该阶段配置 CLI/模型 或 API 模型。');
      _errorMessage = '存在未配置的阶段，执行已停止。';
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    if (executionBlocker == HardnessPhaseExecutionBlocker.unsupportedCli) {
      _appendLine(log, '✗ 阶段无法执行：当前 CLI 不支持无交互执行，请更换为支持 headless 的 CLI。');
      _errorMessage = '存在不支持无交互执行的 CLI 配置，执行已停止。';
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    if (executionBlocker == HardnessPhaseExecutionBlocker.missingApiModel) {
      _appendLine(log, '✗ 阶段无法执行：所选 API 模型配置无效或已被删除。请在设置中检查模型配置。');
      _errorMessage = 'API 模型配置无效，执行已停止。';
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    if (executionBlocker == HardnessPhaseExecutionBlocker.missingApiRunner) {
      _appendLine(log, '✗ 阶段无法执行：API 运行时未初始化。请重启应用后重试。');
      _errorMessage = 'API 运行时未就绪，执行已停止。';
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    // Dispatch to the appropriate execution path.
    if (roleConfig.isUrlMode) {
      await _runPhaseViaApi(log, roleConfig);
    } else {
      await _runPhaseViaCli(log, roleConfig);
    }
  }

  // ── URL/API-based phase execution ─────────────────────────────────────────

  Future<void> _runPhaseViaApi(
    HardnessPhaseLog log,
    HardnessRoleConfig roleConfig,
  ) async {
    final runner = apiPhaseRunner;
    final contextBuilder = buildApiRuntimeContext;
    final configId = roleConfig.aiModelConfigId;
    if (runner == null || contextBuilder == null || configId == null) {
      _appendLine(log, '✗ API 运行时配置不完整。');
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    final resolvedConfig = resolveAiModelConfig?.call(configId);
    if (resolvedConfig == null) {
      _appendLine(log, '✗ 找不到 ID 为 "$configId" 的模型配置。请检查设置。');
      log.status = HardnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    // Override the model ID if the role config specifies a specific model
    // within the provider.
    final overrideModelId = roleConfig.urlModeModelId?.trim();
    final modelConfig = (overrideModelId != null && overrideModelId.isNotEmpty)
        ? resolvedConfig.copyWith(modelId: overrideModelId)
        : resolvedConfig;

    _appendLine(
      log,
      '▶ 阶段：${log.phase.displayNameZh}  |  模式: URL/API'
      '  |  模型: ${modelConfig.displayName}'
      '  |  协议: ${modelConfig.protocolType.storageValue}',
    );
    notifyListeners();

    File? promptFile;
    try {
      // 1. Build the phase prompt (same as CLI path).
      final prompt = await _buildPhasePrompt(log.phase);
      if (_isDisposed) return;

      promptFile = await _writePromptFile(log.phase, prompt);
      if (_isDisposed) return;

      // 2. Build runtime context (memory, MCP, skills, etc.).
      final runtimeContext = await contextBuilder(config.workingDirectory);
      if (_isDisposed) return;

      _appendLine(log, '');
      _appendLine(
        log,
        'ℹ API 模式启动 | 工具: ${runtimeContext.availableSkills.length} 技能, '
        '${runtimeContext.availableMcpServers.where((s) => s.enabled).length} MCP 服务, '
        '${runtimeContext.memoryEntries.length} 记忆条目',
      );
      _appendLine(log, '');
      notifyListeners();

      // 2b. Snapshot working directory before execution.
      Map<String, _FileSnapshot> preSnapshot;
      if (_stopRequested) {
        preSnapshot = <String, _FileSnapshot>{};
      } else {
        try {
          preSnapshot = await _snapshotWorkingDirectory();
        } catch (_) {
          preSnapshot = <String, _FileSnapshot>{};
        }
      }
      if (_isDisposed || _stopRequested) {
        if (log.status != HardnessPhaseStatus.cancelled) {
          log.status = HardnessPhaseStatus.cancelled;
        }
        notifyListeners();
        return;
      }

      // 3. Run the phase via API with tool loop.
      final cancelCompleter = Completer<void>();
      _apiCancelCompleter = cancelCompleter;

      final result = await runner.runPhase(
        model: modelConfig,
        phase: log.phase,
        phasePrompt: prompt,
        runtimeContext: runtimeContext,
        persistenceDirectory: config.persistenceDirectory,
        onLine: (line) {
          _appendLine(log, line);
          notifyListeners();
        },
        requireWriteCommandConfirmation: !_fullAccessPermission,
        cancelSignal: cancelCompleter.future,
      );

      _apiCancelCompleter = null;

      if (_isDisposed) return;

      // 3b. Skip post-snapshot if cancelled.
      if (_stopRequested) {
        log.exitCode = result.success ? 0 : 1;
        if (log.status != HardnessPhaseStatus.cancelled) {
          _appendLine(log, '');
          _appendLine(log, '⚠ 已中止');
          log.status = HardnessPhaseStatus.cancelled;
        }
        notifyListeners();
        await _finalizePhaseArtifacts(log, promptFile: promptFile);
        return;
      }

      final postSnapshot = await _snapshotWorkingDirectory();
      log.changedFiles = _computeChangedFiles(preSnapshot, postSnapshot);

      if (result.success) {
        log.exitCode = 0;
        log.status = HardnessPhaseStatus.completed;

        // ── Post-completion artifact verification ──────────────────────
        // Phases with mandatory output files (metaCollection, planning,
        // reviewing) must actually produce them. A "success" from the
        // API runner only means the model replied — it doesn't guarantee
        // the expected files were written.
        final missingArtifacts = _checkMandatoryArtifacts(log.phase);
        if (missingArtifacts.isNotEmpty) {
          _appendLine(log, '');
          _appendLine(
            log,
            '⚠ 阶段产物验证失败：以下必需文件未被创建：',
          );
          for (final path in missingArtifacts) {
            _appendLine(log, '  • $path');
          }
          _appendLine(log, '');
          _appendLine(
            log,
            '✗ 本阶段被判定为失败，因为模型未能生成预期的输出产物。'
            '常见原因：Write 工具未被正确调用、工具调用被跳过、'
            '或模型在上下文中迷失了输出路径。',
          );
          log.status = HardnessPhaseStatus.failed;
          log.exitCode = 1;
          _errorMessage = '阶段产物验证失败：必需文件未生成。';
        }
      } else {
        log.exitCode = 1;
        _appendLine(log, '');
        _appendLine(
          log,
          '✗ API 阶段执行失败${result.errorMessage != null ? "：${result.errorMessage}" : ""}',
        );
        log.status = HardnessPhaseStatus.failed;
        _errorMessage = result.errorMessage ?? 'API 阶段执行失败';
      }
    } catch (e) {
      if (_isDisposed) return;
      // Sanitize error to avoid leaking auth tokens from model config.
      var safeError = '$e';
      final token = modelConfig.token;
      if (token.length >= 8) {
        safeError = safeError.replaceAll(token, '****');
      }
      _appendLine(log, '');
      _appendLine(log, '✗ API 执行错误：$safeError');
      log.status = HardnessPhaseStatus.failed;
      _errorMessage = safeError;
    } finally {
      _apiCancelCompleter = null;
      await _finalizePhaseArtifacts(log, promptFile: promptFile);
    }
  }

  // ── CLI-based phase execution ─────────────────────────────────────────────

  Future<void> _runPhaseViaCli(
    HardnessPhaseLog log,
    HardnessRoleConfig roleConfig,
  ) async {
    // Resolve CLI entry from catalog; fall back to a minimal entry if unknown.
    final cliEntry = _cliEntryForRoleConfig(roleConfig);

    final configuredModelId = roleConfig.modelId.trim();
    final displayModelLabel = describeHardnessCliModel(
      cliEntry,
      configuredModelId,
      isZh: true,
    );
    final invocationModelId = resolveHardnessCliInvocationModelId(
      cliEntry,
      configuredModelId,
    );

    _appendLine(
      log,
      '▶ 阶段：${log.phase.displayNameZh}  |  CLI: ${cliEntry.executable}'
      '  |  模型: $displayModelLabel',
    );
    notifyListeners();

    File? promptFile;
    try {
      // 1. Build the prompt from persistence context + mission template.
      final prompt = await _buildPhasePrompt(log.phase);
      if (_isDisposed) return;

      promptFile = await _writePromptFile(log.phase, prompt);
      if (_isDisposed) return;

      // 1b. Pre-execution auth re-validation for CLIs that support it.
      //     Auth tokens may expire between session setup and phase execution.
      if (cliEntry.hasLoginCheck) {
        final scanEntry = (
          cli: cliEntry,
          installed: true,
          resolvedPath: null as String?,
          isLoggedIn: null as bool?,
        );
        final authOk = await probeCliAuth(scanEntry);
        if (authOk == false) {
          _appendLine(log, '');
          _appendLine(log, '✗ ${cliEntry.name} 认证已失效，无法执行当前阶段。');
          _appendLine(
            log,
            '  → 请先在"设置 → CLI 登录"中重新完成 ${cliEntry.name} 的登录认证，再重试。',
          );
          _errorMessage = '${cliEntry.name} 认证已失效，执行已停止。';
          log.status = HardnessPhaseStatus.failed;
          notifyListeners();
          return;
        }
      }

      // 2. Construct the shell command string.
      final cliCmd = _buildCliCommandStr(
        cliEntry.executable,
        invocationModelId,
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
      final preSnapshot = _stopRequested
          ? <String, _FileSnapshot>{}
          : await _snapshotWorkingDirectory();
      if (_isDisposed || _stopRequested) {
        if (log.status != HardnessPhaseStatus.cancelled) {
          log.status = HardnessPhaseStatus.cancelled;
        }
        notifyListeners();
        return;
      }

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

      // 3b. Skip post-snapshot if cancelled for immediate feedback.
      if (_stopRequested) {
        log.exitCode = exitCode;
        if (log.status != HardnessPhaseStatus.cancelled) {
          _appendLine(log, '');
          _appendLine(log, '⚠ 已中止');
          log.status = HardnessPhaseStatus.cancelled;
        }
        notifyListeners();
        await _finalizePhaseArtifacts(log);
        return;
      }

      final postSnapshot = await _snapshotWorkingDirectory();
      log.changedFiles = _computeChangedFiles(preSnapshot, postSnapshot);

      log.exitCode = exitCode;

      if (exitCode != 0) {
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 进程退出码：$exitCode');
        log.status = HardnessPhaseStatus.failed;
        _appendCliModelFailureHints(log, cliEntry, configuredModelId);
        _appendGeminiHeadlessRuntimeHints(log);
        await _appendCliFailureDiagnostics(log, cliEntry.executable);
      } else if (_looksLikeCliAuthInterrupt(log.lines)) {
        // Exit code 0 but the CLI emitted an interactive auth prompt and
        // exited without performing any work (stdin was closed → EOF).
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 在未完成认证的情况下退出（退出码 0），本阶段未产生有效产出。');
        _appendLine(
          log,
          '  → 请先在"设置 → CLI 登录"中完成 ${cliEntry.name} 的登录认证，再重试当前阶段。',
        );
        log.status = HardnessPhaseStatus.failed;
      } else if (_looksLikeHollowCliSession(log.lines, cliEntry.executable)) {
        // Exit code 0 but the CLI produced no substantive output, indicating
        // it silently skipped execution (e.g. expired token, config error).
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 以退出码 0 结束，但未产生有效输出，本阶段执行可能未真正生效。');
        _appendLine(log, '  → 可能原因：认证已过期、配置异常或 CLI 静默跳过了任务。请检查 CLI 状态后重试。');
        log.status = HardnessPhaseStatus.failed;
        await _appendCliFailureDiagnostics(log, cliEntry.executable);
      } else {
        log.status = HardnessPhaseStatus.completed;

        // ── Post-completion artifact verification (CLI path) ──────────
        final missingArtifacts = _checkMandatoryArtifacts(log.phase);
        if (missingArtifacts.isNotEmpty) {
          _appendLine(log, '');
          _appendLine(
            log,
            '⚠ 阶段产物验证失败：以下必需文件未被创建：',
          );
          for (final path in missingArtifacts) {
            _appendLine(log, '  • $path');
          }
          _appendLine(log, '');
          _appendLine(
            log,
            '✗ 本阶段被判定为失败，因为 CLI 未能生成预期的输出产物。',
          );
          log.status = HardnessPhaseStatus.failed;
          _errorMessage = '阶段产物验证失败：必需文件未生成。';
        }
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
      await _appendCliFailureDiagnostics(log, cliEntry.executable);
    } on TimeoutException catch (e) {
      if (_isDisposed) return;
      _appendLine(log, '');
      _appendLine(log, '✗ 超时：${e.message}');
      log.status = HardnessPhaseStatus.failed;
      await _appendCliFailureDiagnostics(log, cliEntry.executable);
    } catch (e) {
      if (_isDisposed) return;
      _appendLine(log, '');
      _appendLine(log, '✗ 执行错误：$e');
      log.status = HardnessPhaseStatus.failed;
      await _appendCliFailureDiagnostics(log, cliEntry.executable);
    } finally {
      await _finalizePhaseArtifacts(log, promptFile: promptFile);
    }
  }

  // ── Review failure detection ─────────────────────────────────────────────

  /// Returns true if the reviewing phase indicates a FAIL verdict,
  /// considering both explicit user verdict and CLI output analysis.
  bool _reviewIndicatesFailure(HardnessPhaseLog log) {
    // Priority 1: explicit user verdict from pass/fail buttons.
    final userVerdict = _userReviewVerdict;
    if (userVerdict != null) {
      _userReviewVerdict = null; // consume once
      return !userVerdict;
    }
    // Priority 2: scan CLI output for verdict keywords.
    return _reviewOutputIndicatesFailure(log);
  }

  /// Scans the reviewer's output for a "FAIL" verdict.
  /// The reviewer mission template instructs the agent to begin with PASS or
  /// FAIL on the first non-empty line. We scan meaningful lines (skipping
  /// blanks, command echoes, UI decoration, and manual input headers) for a
  /// FAIL indicator.
  bool _reviewOutputIndicatesFailure(HardnessPhaseLog log) {
    var meaningfulLineCount = 0;
    var insideManualInput = false;
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
        // A command-echo line ("> ...") marks the end of any manual input
        // section and the start of CLI output. Reset the skip flag.
        if (trimmed.startsWith('> ')) {
          insideManualInput = false;
        }
        continue;
      }
      // Skip manual input header and its content (they are user text,
      // not the reviewer CLI's verdict).
      if (trimmed.startsWith('【') && trimmed.endsWith('】')) {
        insideManualInput = true;
        continue;
      }
      if (trimmed.startsWith('ℹ ')) {
        // Acknowledgment lines like "ℹ 已接收用户人工验收结果..."
        insideManualInput = false;
        continue;
      }
      if (insideManualInput) {
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
      // Only inspect the first several meaningful lines of CLI output.
      meaningfulLineCount++;
      if (meaningfulLineCount >= 20) {
        return false;
      }
    }
    return false;
  }

  // ── Role ↔ config mapping ────────────────────────────────────────────────

  HardnessRoleConfig _roleConfigForPhase(HardnessPhase phase) =>
      switch (phase) {
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
    final contextConfig = getPhaseContextConfig(phase);

    String readIfExists(String path) {
      try {
        final f = File(path);
        return f.existsSync() ? f.readAsStringSync() : '';
      } catch (_) {
        return '';
      }
    }

    // 按阶段配置条件加载上下文
    final archContent = contextConfig.includeArchitecture
        ? readIfExists(p.join(steeringDir, 'meta', 'architecture.md'))
        : '';
    final convContent = contextConfig.includeConventions
        ? readIfExists(p.join(steeringDir, 'meta', 'conventions.md'))
        : '';

    // Latest handoff document.
    String handoffContent = '';
    if (contextConfig.includeHandoff) {
      try {
        final handoffDir = Directory(p.join(steeringDir, 'handoff'));
        if (handoffDir.existsSync()) {
          final files = handoffDir.listSync().whereType<File>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
          if (files.isNotEmpty) handoffContent = files.last.readAsStringSync();
        }
      } catch (_) {}
    }

    // Load lessons based on config mode.
    String lessonsContent = '';
    if (contextConfig.lessonsMode != HardnessLessonInclusionMode.none) {
      try {
        final lessonDir = Directory(p.join(steeringDir, 'lesson'));
        if (lessonDir.existsSync()) {
          final files = lessonDir.listSync().whereType<File>().toList();
          if (files.isNotEmpty) {
            final fullContent = files
                .map((f) => f.readAsStringSync())
                .join('\n\n---\n\n');
            // Use summary mode for lessons when configured
            lessonsContent =
                contextConfig.lessonsMode == HardnessLessonInclusionMode.summary
                    ? hardnessPromptBuilder.renderLessonsSummary(fullContent)
                    : fullContent;
          }
        }
      } catch (_) {}
    }

    // Latest plan (based on config).
    String planContent = '';
    if (contextConfig.includePlan) {
      try {
        final planDir = Directory(p.join(steeringDir, 'plan'));
        if (planDir.existsSync()) {
          final files = planDir.listSync().whereType<File>().toList()
            ..sort((a, b) => b.path.compareTo(a.path)); // newest first
          if (files.isNotEmpty) planContent = files.first.readAsStringSync();
        }
      } catch (_) {}
    }

    // Latest reviewer feedback (based on config + retry state).
    String feedbackContent = '';
    if (contextConfig.includeFeedback || _reviewRetryCount > 0) {
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

    var manualPhaseInputContent = _queuedManualPhaseInputPhase == phase
        ? _queuedManualPhaseInput?.trim() ?? ''
        : '';
    // If the user provided an explicit review verdict, prepend it to the
    // manual input so the reviewer CLI receives an unambiguous signal.
    if (phase == HardnessPhase.reviewing &&
        manualPhaseInputContent.isNotEmpty &&
        _userReviewVerdict != null) {
      final verdictLabel = _userReviewVerdict! ? 'PASS' : 'FAIL';
      manualPhaseInputContent =
          '用户判定：$verdictLabel\n\n$manualPhaseInputContent';
    }

    // 构建阶段提示词（语言策略已在系统指令中定义，此处仅引用）
    final sb = StringBuffer()
      ..writeln('# Hardness Engineering - ${phase.displayNameZh}阶段')
      ..writeln()
      ..writeln()
      ..writeln('> 遵循系统语言策略：所有输出使用简体中文，技术标识保留原文。')
      ..writeln()
      ..writeln('## 任务')
      ..writeln(config.task)
      ..writeln()
      ..writeln('## 工作目录')
      ..writeln(config.workingDirectory)
      ..writeln()
      ..writeln('## 运行时约束')
      ..writeln('1. 无交互 CLI 自动化会话，阶段内无需等待人工批准。')
      ..writeln(_phaseDirectoryPermissionConstraint(phase))
      ..writeln('3. 直接使用会话内可用工具；不要转交子代理或尝试未注册工具。')
      ..writeln('4. 若路径或工具不可用，立即报告阻塞原因与替代方案。')
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

    if (manualPhaseInputContent.isNotEmpty) {
      sb
        ..writeln(_manualPhaseInputSectionTitle(phase))
        ..writeln(manualPhaseInputContent)
        ..writeln();
    }

    sb
      ..writeln('## 当前角色任务')
      ..writeln(_missionTemplate(phase));

    return sb.toString();
  }

  /// Returns a phase-specific directory permission constraint. Reading and
  /// planning phases are restricted to read-only access on the working
  /// directory to prevent the AI from implementing changes prematurely.
  String _phaseDirectoryPermissionConstraint(HardnessPhase phase) {
    return switch (phase) {
      HardnessPhase.reading || HardnessPhase.planning =>
        '2. **工作目录仅供只读分析。** 严禁在本阶段修改、创建或删除工作目录下的任何源码、配置、资源或其他文件。严禁执行会改变项目状态的命令（构建、安装、测试等）。允许写入的唯一位置是持久化目录中的指定输出文件。',
      HardnessPhase.metaCollection =>
        '2. 工作目录仅供只读扫描；允许写入的唯一位置是持久化目录下的 meta/ 子目录。',
      HardnessPhase.reviewing =>
        '2. 工作目录仅供只读验证。允许写入的唯一位置是持久化目录下的 feedback/ 子目录。严禁在验收阶段修改项目代码或资源。',
      HardnessPhase.implementing =>
        '2. 允许读写的核心目录为工作目录与持久化目录；涉及产物、计划、反馈等文件时，请直接写入任务中指定的路径。',
    };
  }

  String _missionTemplate(HardnessPhase phase) {
    final meta = p.join(config.persistenceDirectory, 'steering', 'meta');
    final planDir = p.join(config.persistenceDirectory, 'steering', 'plan');
    final feedbackDir = p.join(
      config.persistenceDirectory,
      'steering',
      'feedback',
    );
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);

    return switch (phase) {
      HardnessPhase.metaCollection =>
        '''你是该项目的探档者（Profiler）。

    ${_manualPhaseMissionAddendum(HardnessPhase.metaCollection)}

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

    分析完成后，你**必须**调用 Write 工具将文件写入以下路径（使用绝对路径）：
    - $meta/architecture.md
    - $meta/conventions.md

    **重要**：不要仅仅描述分析结果——你必须实际调用 Write 工具将两个文件分别写入磁盘。未成功写入将导致阶段失败。
    要求准确、克制、基于事实。项目中不存在的信息不得臆测。''',

      HardnessPhase.reading =>
        '''你是本任务的调查者/分析者（Reader/Analyst）。

    请深入分析 ${config.workingDirectory} 下的项目，并产出一份结构化分析报告。除代码、命令、路径、文件名等技术标识外，报告全文必须使用简体中文。

    分析内容必须覆盖：
    1. 对任务要求的精确拆解
    2. 需要创建或修改的具体文件与模块
    3. 每个相关文件的当前状态（准确概括关键实现）
    4. 潜在风险、副作用与外部依赖
    5. 推荐的实现路径及理由

    请使用清晰、结构化的 Markdown 报告格式输出。
    这份报告会被规划者直接使用，因此必须充分、准确、可执行。''',

      HardnessPhase.planning =>
        '''你是本任务的规划者（Planner）。

    ${_manualPhaseMissionAddendum(HardnessPhase.planning)}

    请基于上方的任务与分析上下文，产出一份详细、按编号排列的执行计划。除代码、命令、路径、文件名等技术标识外，所有步骤说明和验收标准都必须使用简体中文。

    每个步骤都必须满足：
    - **原子化**：表示一个可独立验证的单一改动
    - **具体**：明确指出需要创建或修改的确切文件
    - **可验证**：包含清晰的验收标准
    - **带复杂度标签**：使用 [simple | medium | complex]

    **严禁事项（违反即为严重错误）：**
    - 绝对不要修改、创建或删除工作目录下的任何项目源码、配置文件或资源文件
    - 绝对不要执行构建、测试、安装或其他改变项目状态的命令
    - 不要编写或生成任何代码到项目中——所有实施工作必须留给实施者（Implementer）在下一阶段完成
    - 你的唯一输出产物是保存到持久化目录中的计划文件

    计划完成后，你**必须**调用 Write 工具将完整计划写入以下路径（注意使用绝对路径）：
    $planDir/plan-$ts.md

    计划文件必须以任务描述开头，并包含全部执行步骤。
    **重要**：不要仅仅描述计划内容——你必须实际调用 Write 工具将文件写入磁盘。未调用 Write 将导致阶段失败。''',

      HardnessPhase.implementing =>
        '''你是本任务的实施者（Implementer）。

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

      HardnessPhase.reviewing =>
        '''你是本任务的验收者（Reviewer）。

    **关键要求：你处于一个全新且独立的会话中，与实施者完全隔离。**
    你不知道实施者的推理过程，也不能假设任何步骤已经被正确完成。
    你必须仅基于原始需求、上方执行计划以及项目当前真实代码状态进行验收。

    **评审独立性**：你与实施者完全隔离，必须从零核验每个步骤。
    ${_reviewRetryCount > 0 ? '\n**注意**：第 $_reviewRetryCount 次重试，重点检查之前的问题是否修复。\n' : ''}
    ${_manualPhaseMissionAddendum(HardnessPhase.reviewing)}

    验证内容：
    1. 所有计划步骤已完成且满足验收标准
    2. 无回归问题（如可行，运行相关测试）
    3. 代码质量符合项目约定
    4. 边界与错误处理得当
    5. 无明显安全风险

    输出格式：首行 **PASS** 或 **FAIL**，后续为具体发现与问题。
    你**必须**调用 Write 工具将验收报告写入（使用绝对路径）：$feedbackDir/feedback-$ts.md
    **重要**：不要仅仅描述验收结论——你必须实际调用 Write 工具将报告写入磁盘。未成功写入将导致阶段失败。''',
    };
  }

  // ── CLI command construction ─────────────────────────────────────────────

  /// Returns a shell command string suitable for the Hardness POSIX shell
  /// wrapper, which uses the same interactive login environment as CLI scan.
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
    final modelFlag = modelId.isNotEmpty
        ? ' --model ${_shellSingleQuote(modelId)}'
        : '';
    final modelFlagShort = modelId.isNotEmpty
        ? ' -m ${_shellSingleQuote(modelId)}'
        : '';
    // Quoted working directory — used by CLIs that accept an explicit -C flag.
    final quotedWd = _shellSingleQuote(config.workingDirectory);
    final geminiIncludeDirectoriesFlags = _buildGeminiIncludeDirectoriesFlags();

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
      // Hardness approval already happens at the phase boundary. In Gemini
      // headless mode, mutating tools are unavailable unless approval is
      // auto-granted for the session, and paths outside the cwd must be added
      // as extra workspace roots.
      'gemini' =>
        'gemini$modelFlagShort --approval-mode yolo$geminiIncludeDirectoriesFlags -p $promptSubst',
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

  String _buildGeminiIncludeDirectoriesFlags() {
    final persistenceDirRaw = config.persistenceDirectory.trim();
    if (persistenceDirRaw.isEmpty) {
      return '';
    }

    final normalizedWorkingDirectory = p.normalize(
      p.absolute(config.workingDirectory.trim()),
    );
    final normalizedPersistenceDirectory = p.normalize(
      p.absolute(persistenceDirRaw),
    );

    if (normalizedPersistenceDirectory == normalizedWorkingDirectory ||
        p.isWithin(
          normalizedWorkingDirectory,
          normalizedPersistenceDirectory,
        )) {
      return '';
    }

    return ' --include-directories ${_shellSingleQuote(normalizedPersistenceDirectory)}';
  }

  // ── I/O helpers ──────────────────────────────────────────────────────────

  Future<File> _writePromptFile(HardnessPhase phase, String content) async {
    final name =
        'he_${phase.storageValue}_${DateTime.now().millisecondsSinceEpoch}.md';
    final promptDir = Directory(
      p.join(config.persistenceDirectory, 'steering', 'log', 'prompts'),
    );
    await promptDir.create(recursive: true);
    final file = File(p.join(promptDir.path, name));
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
    final quotedWd = _shellSingleQuote(workingDirectory);
    final fullCmd = 'cd $quotedWd && $cmdStr';

    final process = await Process.start(
      resolveHardnessCliShellExecutable(),
      buildHardnessCliShellArgs(fullCmd),
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
          exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
          exitCode = await process.exitCode
              .timeout(const Duration(seconds: 2))
              .catchError((_) => -1);
        }
        // Drain remaining buffered output before propagating the timeout.
        // catchError ensures we don't fail if the streams errored (e.g.
        // after SIGKILL).
        await Future.wait([
          stdoutFuture.catchError((_) {}),
          stderrFuture.catchError((_) {}),
        ]).timeout(const Duration(seconds: 5), onTimeout: () => []);
        rethrow; // Propagated as TimeoutException → _runPhase catch block.
      }

      // Drain remaining buffered output.  Time-box this so that a child
      // process that inherited our pipe FDs can never prevent us from
      // returning (e.g. a daemon launched by the CLI that doesn't exit).
      await Future.wait([
        stdoutFuture,
        stderrFuture,
      ]).timeout(const Duration(seconds: 5), onTimeout: () => []);
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
      // Silently fail if unable to save log
    }
  }

  Future<void> _appendCliFailureDiagnostics(
    HardnessPhaseLog log,
    String executable,
  ) async {
    if (log.lines.any((line) => line == 'ℹ 运行环境诊断：')) {
      return;
    }

    final diagnostics = await collectHardnessCliFailureDiagnostics(executable);
    if (diagnostics.isEmpty) {
      return;
    }

    if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
      _appendLine(log, '');
    }
    _appendLine(log, 'ℹ 运行环境诊断：');
    for (final line in diagnostics) {
      _appendLine(log, '  $line');
    }
  }

  bool _looksLikeGeminiModelNotFound(List<String> lines) {
    final joinedOutput = lines.join('\n').toLowerCase();
    return joinedOutput.contains('modelnotfounderror') ||
        joinedOutput.contains('requested entity was not found');
  }

  bool _looksLikeGeminiHeadlessToolingFailure(List<String> lines) {
    final joinedOutput = lines.join('\n').toLowerCase();
    return joinedOutput.contains('tool "write_file" not found') ||
        joinedOutput.contains('tool "run_shell_command" not found') ||
        joinedOutput.contains('unauthorized tool call') ||
        joinedOutput.contains('outside the allowed workspace directories') ||
        joinedOutput.contains('path not in workspace');
  }

  bool _looksLikeGeminiUnsupportedHeadlessFlags(List<String> lines) {
    final joinedOutput = lines.join('\n').toLowerCase();
    return joinedOutput.contains('unknown option') &&
        (joinedOutput.contains('approval-mode') ||
            joinedOutput.contains('include-directories'));
  }

  // ── Auth-interrupt & hollow-session detection ───────────────────────────

  /// Detects whether the CLI emitted an interactive authentication prompt
  /// and exited without performing any work.  This happens when the CLI's
  /// auth token has expired (or was never granted) and stdin was closed
  /// (EOF), causing it to exit cleanly (code 0) without doing anything.
  bool _looksLikeCliAuthInterrupt(List<String> lines) {
    final joined = lines.join('\n').toLowerCase();
    // Gemini CLI auth prompts
    if (joined.contains('opening authentication page') ||
        joined.contains('authenticate with google') ||
        joined.contains('please authenticate') ||
        joined.contains('authorization required')) {
      return true;
    }
    // Claude Code auth prompts
    if (joined.contains('please sign in') ||
        joined.contains('you need to authenticate') ||
        joined.contains('login required')) {
      return true;
    }
    // Codex / OpenAI auth prompts
    if (joined.contains('not logged in') ||
        joined.contains('authentication is required') ||
        (joined.contains('log in') && joined.contains('continue'))) {
      return true;
    }
    // Generic patterns across CLIs
    if (joined.contains('do you want to continue? [y/n]') &&
        joined.contains('authentication')) {
      return true;
    }
    return false;
  }

  /// Detects a "hollow" CLI session: the process exited with code 0 but
  /// produced no substantive output, strongly suggesting it silently skipped
  /// execution (expired credentials, silent config error, etc.).
  ///
  /// Ignores: blank lines, our own `▶ > ✓ ✗ ⚠ ℹ` decoration, and the
  /// leading command-echo line.
  bool _looksLikeHollowCliSession(List<String> lines, String executable) {
    var substantiveLineCount = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Skip our own UI decoration lines.
      if (trimmed.startsWith('▶ ') ||
          trimmed.startsWith('> ') ||
          trimmed.startsWith('✓ ') ||
          trimmed.startsWith('✗ ') ||
          trimmed.startsWith('⚠ ') ||
          trimmed.startsWith('ℹ ')) {
        continue;
      }
      substantiveLineCount++;
    }
    // A healthy phase always produces meaningful output from the AI agent.
    // Fewer than 3 substantive lines (after stripping decorations and
    // command echoes) is highly suspicious.
    return substantiveLineCount < 3;
  }

  void _appendCliModelFailureHints(
    HardnessPhaseLog log,
    HardnessCli cliEntry,
    String modelId,
  ) {
    if (cliEntry.executable != 'gemini') {
      return;
    }
    if (!_looksLikeGeminiModelNotFound(log.lines)) {
      return;
    }
    if (log.lines.any((line) => line.contains('Gemini CLI 返回 ModelNotFound'))) {
      return;
    }

    final suggestedModels = suggestedHardnessCliModels(cliEntry, max: 4)
        .map(
          (candidate) =>
              describeHardnessCliModel(cliEntry, candidate, isZh: true),
        )
        .join('、');
    if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
      _appendLine(log, '');
    }
    _appendLine(
      log,
      'ℹ Gemini CLI 返回 ModelNotFound，通常表示模型 ID 已失效、已下线，或当前账号无权限访问。',
    );
    _appendLine(
      log,
      '  当前请求模型：${describeHardnessCliModel(cliEntry, modelId, isZh: true)}',
    );
    if (suggestedModels.isNotEmpty) {
      _appendLine(log, '  可优先尝试：$suggestedModels');
    }
    _appendLine(log, '  建议在当前阶段卡片中手动更换 CLI / 模型后，再点击“重试失败阶段”。');
    _appendLine(log, '  模型列表文档：$kHardnessGeminiModelsDocUrl');
  }

  void _appendGeminiHeadlessRuntimeHints(HardnessPhaseLog log) {
    if (_looksLikeGeminiUnsupportedHeadlessFlags(log.lines)) {
      if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
        _appendLine(log, '');
      }
      _appendLine(
        log,
        'ℹ 当前 Gemini CLI 版本过旧，无法识别 OpenHand 所需的 headless 参数（如 --approval-mode / --include-directories）。',
      );
      _appendLine(log, '  请先升级 Gemini CLI 到较新的稳定版本，再重试当前失败阶段。');
      _appendLine(log, '  推荐命令：npm install -g @google/gemini-cli@latest');
      return;
    }

    if (!_looksLikeGeminiHeadlessToolingFailure(log.lines)) {
      return;
    }

    if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
      _appendLine(log, '');
    }
    _appendLine(
      log,
      'ℹ 这类错误通常不是模型本身不可用，而是 Gemini CLI 的 headless 会话没有拿到可写工具或目标目录未被纳入工作区。',
    );
    _appendLine(
      log,
      '  OpenHand 会以阶段级审批替代 Gemini 的逐工具审批，并将持久化目录加入 Gemini 工作区，以便当前阶段直接写文件/执行命令。',
    );
    _appendLine(
      log,
      '  若仍重复出现，请检查本机 Gemini 配置中是否强制禁用了 YOLO / 编辑工具，或存在企业安全策略拦截。',
    );
  }

  Future<void> _finalizePhaseArtifacts(
    HardnessPhaseLog log, {
    File? promptFile,
  }) async {
    if (_isDisposed) {
      return;
    }

    final shouldRetainPrompt =
        promptFile != null && log.status != HardnessPhaseStatus.completed;
    if (shouldRetainPrompt) {
      final promptRetentionLine = 'ℹ 调试 Prompt 文件：${promptFile.path}';
      if (!log.lines.contains(promptRetentionLine)) {
        if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
          _appendLine(log, '');
        }
        _appendLine(log, promptRetentionLine);
      }
    }

    await _savePhasePersistence(log);

    if (!shouldRetainPrompt) {
      try {
        promptFile?.deleteSync();
      } catch (_) {}
    }

    notifyListeners();
  }

  void _appendLine(HardnessPhaseLog log, String line) {
    log.lines.add(line);
  }

  /// Checks whether the mandatory output artifacts for a phase exist.
  ///
  /// Returns a list of missing file paths (empty list = all present).
  /// Phases with no mandatory artifacts (reading, implementing) always
  /// return an empty list.
  List<String> _checkMandatoryArtifacts(HardnessPhase phase) {
    final steeringDir = p.join(config.persistenceDirectory, 'steering');
    final missing = <String>[];

    switch (phase) {
      case HardnessPhase.metaCollection:
        final archPath = p.join(steeringDir, 'meta', 'architecture.md');
        final convPath = p.join(steeringDir, 'meta', 'conventions.md');
        if (!File(archPath).existsSync()) missing.add(archPath);
        if (!File(convPath).existsSync()) missing.add(convPath);
      case HardnessPhase.planning:
        final planDir = Directory(p.join(steeringDir, 'plan'));
        final hasPlanFile = planDir.existsSync() &&
            planDir.listSync().whereType<File>().any(
                  (f) => f.path.endsWith('.md'),
                );
        if (!hasPlanFile) {
          missing.add('${planDir.path}/*.md (no plan file found)');
        }
      case HardnessPhase.reviewing:
        final feedbackDir = Directory(p.join(steeringDir, 'feedback'));
        final hasFeedbackFile = feedbackDir.existsSync() &&
            feedbackDir.listSync().whereType<File>().any(
                  (f) => f.path.endsWith('.md'),
                );
        if (!hasFeedbackFile) {
          missing.add('${feedbackDir.path}/*.md (no feedback file found)');
        }
      case HardnessPhase.reading:
      case HardnessPhase.implementing:
        break; // No mandatory artifacts
    }
    return missing;
  }

  /// POSIX single-quote a string, safely escaping embedded single quotes.
  static String _shellSingleQuote(String s) =>
      "'${s.replaceAll("'", "'\\''")}'";

  // ── File change tracking ────────────────────────────────────────────────

  /// Ignored directory names for snapshot (common build artifacts / VCS).
  static const Set<String> _snapshotIgnoredDirs = {
    '.git',
    '.svn',
    '.hg',
    'node_modules',
    '.dart_tool',
    'build',
    '.build',
    '__pycache__',
    '.idea',
    '.vscode',
    '.gradle',
    '.DS_Store',
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
      await for (final entity in workDir.list(
        recursive: true,
        followLinks: false,
      )) {
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
      // Silently fail on snapshot errors
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
        changes.add(
          HardnessChangedFile(
            relativePath: rel,
            absolutePath: p.join(_config.workingDirectory, rel),
            changeType: HardnessFileChangeType.added,
            afterContent: post.content,
          ),
        );
      } else if (pre.modified != post.modified || pre.size != post.size) {
        changes.add(
          HardnessChangedFile(
            relativePath: rel,
            absolutePath: p.join(_config.workingDirectory, rel),
            changeType: HardnessFileChangeType.modified,
            beforeContent: pre.content,
            afterContent: post.content,
          ),
        );
      }
    }

    // Deleted files
    for (final rel in before.keys) {
      if (!after.containsKey(rel)) {
        changes.add(
          HardnessChangedFile(
            relativePath: rel,
            absolutePath: p.join(_config.workingDirectory, rel),
            changeType: HardnessFileChangeType.deleted,
            beforeContent: before[rel]!.content,
          ),
        );
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
