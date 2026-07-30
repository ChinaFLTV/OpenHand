import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';
import '../model/harness_phase.dart';
import '../model/harness_phase_context_config.dart';
import '../model/harness_role_config.dart';
import '../model/harness_session_config.dart';
import '../service/harness_api_phase_runner.dart';
import '../service/harness_bounded_file_io.dart';
import '../service/harness_cli_catalog.dart';
import '../service/harness_prompt_builder.dart';

const String kHarnessOrchestratorDisplayVersion = '1.0.0';
const int _kMaxHarnessPhaseLogLines = 4000;
const int _kMaxHarnessLogLineCharacters = 4000;
const Duration _kHarnessProcessStartTimeout = Duration(seconds: 10);
const Duration _kHarnessArtifactIoTimeout = Duration(seconds: 3);

// ─────────────────────────────────────────────────────────────────────────────
// Phase-level status & log
// ─────────────────────────────────────────────────────────────────────────────

enum HarnessPhaseStatus {
  pending,
  paused,
  running,
  completed,
  failed,
  cancelled,
  skipped,
}

enum HarnessPhaseExecutionBlocker {
  missingConfig,
  unsupportedCli,
  missingApiModel,
  missingApiRunner,
}

HarnessPhaseStatus _harnessPhaseStatusFromStorageValue(String value) {
  for (final status in HarnessPhaseStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return HarnessPhaseStatus.pending;
}

List<String> _harnessLogLinesFromValue(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item == null ? '' : '$item')
      .toList(growable: false);
}

class HarnessPhaseLog {
  HarnessPhaseLog(this.phase);

  final HarnessPhase phase;
  HarnessPhaseStatus status = HarnessPhaseStatus.pending;
  final List<String> lines = [];
  int? exitCode;
  String? savedLogPath;

  /// For reviewing phases: true if the review verdict was FAIL.
  /// Used by the UI to show a distinct status for completed-but-failed reviews.
  bool reviewVerdictFail = false;

  /// Files changed during this phase execution.
  /// Each entry: relative path → (before content hash, after content hash).
  List<HarnessChangedFile> changedFiles = [];

  HarnessPhaseLogSnapshot toSnapshot() {
    return HarnessPhaseLogSnapshot(
      phaseValue: phase.storageValue,
      statusValue: status.name,
      lines: List<String>.from(lines),
      exitCode: exitCode,
      savedLogPath: savedLogPath,
      changedFiles: changedFiles.map((f) => f.toJson()).toList(),
      reviewVerdictFail: reviewVerdictFail,
    );
  }

  static HarnessPhaseLog fromSnapshot(HarnessPhaseLogSnapshot snapshot) {
    final log = HarnessPhaseLog(snapshot.phase)
      ..status = snapshot.status
      ..exitCode = snapshot.exitCode
      ..savedLogPath = snapshot.savedLogPath
      ..changedFiles = snapshot.parsedChangedFiles
      ..reviewVerdictFail = snapshot.reviewVerdictFail;
    log.lines.addAll(snapshot.lines);
    return log;
  }
}

class HarnessPhaseLogSnapshot {
  const HarnessPhaseLogSnapshot({
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

  HarnessPhase get phase => HarnessPhase.fromStorageValue(phaseValue)!;
  HarnessPhaseStatus get status =>
      _harnessPhaseStatusFromStorageValue(statusValue);

  List<HarnessChangedFile> get parsedChangedFiles =>
      changedFiles.map(HarnessChangedFile.fromJson).toList();

  HarnessPhaseLogSnapshot copyWith({
    String? phaseValue,
    String? statusValue,
    List<String>? lines,
    int? exitCode,
    Object? savedLogPath = _harnessPhaseLogSnapshotUnset,
    List<Map<String, Object?>>? changedFiles,
    bool? reviewVerdictFail,
  }) {
    return HarnessPhaseLogSnapshot(
      phaseValue: phaseValue ?? this.phaseValue,
      statusValue: statusValue ?? this.statusValue,
      lines: lines ?? this.lines,
      exitCode: exitCode ?? this.exitCode,
      savedLogPath: identical(savedLogPath, _harnessPhaseLogSnapshotUnset)
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

  static HarnessPhaseLogSnapshot? fromJson(Map<String, Object?> json) {
    final phaseValue = '${json['phase'] ?? ''}'.trim();
    if (HarnessPhase.fromStorageValue(phaseValue) == null) {
      return null;
    }
    final rawLines = json['lines'];
    return HarnessPhaseLogSnapshot(
      phaseValue: phaseValue,
      statusValue: '${json['status'] ?? HarnessPhaseStatus.pending.name}',
      lines: _harnessLogLinesFromValue(rawLines),
      exitCode: optionalIntegralIntFromValue(json['exit_code']),
      savedLogPath: json['saved_log_path'] == null
          ? null
          : '${json['saved_log_path']}',
      changedFiles: stringKeyedMapListFromValue(json['changed_files']),
      reviewVerdictFail: boolFromValue(json['review_verdict_fail']),
    );
  }
}

/// Represents a file changed during a phase execution.
class HarnessChangedFile {
  const HarnessChangedFile({
    required this.relativePath,
    required this.absolutePath,
    required this.changeType,
    this.beforeContent,
    this.afterContent,
  });

  final String relativePath;
  final String absolutePath;
  final HarnessFileChangeType changeType;
  final String? beforeContent;
  final String? afterContent;

  Map<String, Object?> toJson() => {
    'relative_path': relativePath,
    'absolute_path': absolutePath,
    'change_type': changeType.name,
    'before_content': beforeContent,
    'after_content': afterContent,
  };

  static HarnessChangedFile fromJson(Map<String, Object?> json) {
    return HarnessChangedFile(
      relativePath: '${json['relative_path'] ?? ''}',
      absolutePath: '${json['absolute_path'] ?? ''}',
      changeType: enumByNameOr(
        HarnessFileChangeType.values,
        json['change_type'],
        fallback: HarnessFileChangeType.modified,
      ),
      beforeContent: json['before_content']?.toString(),
      afterContent: json['after_content']?.toString(),
    );
  }
}

enum HarnessFileChangeType { added, modified, deleted }

const Object _harnessPhaseLogSnapshotUnset = Object();

// ─────────────────────────────────────────────────────────────────────────────
// Overall orchestrator status
// ─────────────────────────────────────────────────────────────────────────────

enum HarnessOrchestratorStatus { idle, running, completed, failed, cancelled }

// ─────────────────────────────────────────────────────────────────────────────
// HarnessOrchestrator
// Program-driven state machine that executes Harness Engineering phases
// directly via CLI processes — no AI orchestration layer involved.
// ─────────────────────────────────────────────────────────────────────────────

class HarnessOrchestrator extends ChangeNotifier {
  HarnessOrchestrator(this._config);

  HarnessSessionConfig _config;
  HarnessSessionConfig get config => _config;

  /// Optional API phase runner for URL mode execution. Must be set before
  /// starting a session that contains URL-mode role configs.
  HarnessApiPhaseRunner? apiPhaseRunner;

  /// Callback to resolve an AiModelConfig by its ID from settings.
  /// Must be set before starting a session that contains URL-mode role configs.
  AiModelConfig? Function(String configId)? resolveAiModelConfig;

  /// Callback to build the runtime context for API-based phase execution.
  /// Provides memory entries, MCP servers, skills, etc.
  Future<AiSessionRuntimeContext> Function(String workingDirectory)?
  buildApiRuntimeContext;

  HarnessOrchestratorStatus _status = HarnessOrchestratorStatus.idle;
  HarnessOrchestratorStatus get status => _status;

  List<HarnessPhaseLog> _phaseLogs = <HarnessPhaseLog>[];
  List<HarnessPhaseLog> get phaseLogs => _phaseLogs;
  List<HarnessPhaseLogSnapshot> get phaseLogSnapshots =>
      _phaseLogs.map((log) => log.toSnapshot()).toList(growable: false);

  HarnessPhase? _currentPhase;
  HarnessPhase? get currentPhase => _currentPhase;

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
  void Function(HarnessPhase nextPhase)? onPhaseApprovalRequired;

  /// Completer used to resume the pipeline after waiting for user approval.
  Completer<bool>? _phaseApprovalCompleter;

  /// The phase that is awaiting user approval, or null.
  HarnessPhase? _awaitingApprovalPhase;
  HarnessPhase? get awaitingApprovalPhase => _awaitingApprovalPhase;

  /// When true, the paused phase is waiting for user-authored input from the
  /// composer before continuing.
  bool _manualPhaseInputRequested = false;
  bool get manualPhaseInputRequested => _manualPhaseInputRequested;
  HarnessPhase? get awaitingManualPhaseInputPhase =>
      _manualPhaseInputRequested ? _awaitingApprovalPhase : null;
  bool get awaitingManualPhaseInput => awaitingManualPhaseInputPhase != null;

  /// User-authored content queued for the next execution of a specific phase.
  /// This survives app restarts so an interrupted approval can continue with
  /// the same human context.
  HarnessPhase? _queuedManualPhaseInputPhase;
  HarnessPhase? get queuedManualPhaseInputPhase => _queuedManualPhaseInputPhase;
  String? _queuedManualPhaseInput;
  String? get queuedManualPhaseInput => _queuedManualPhaseInput;
  bool get hasQueuedManualPhaseInput =>
      _queuedManualPhaseInput?.trim().isNotEmpty == true;
  bool hasQueuedManualPhaseInputFor(HarnessPhase phase) =>
      _queuedManualPhaseInputPhase == phase && hasQueuedManualPhaseInput;
  bool isManualPhaseInputActiveFor(HarnessPhase phase) =>
      awaitingManualPhaseInputPhase == phase;

  /// Explicit review verdict set by the user through the pass/fail buttons.
  /// true = PASS, false = FAIL, null = not set (AI-only review).
  bool? _userReviewVerdict;

  bool _resumePendingApproval = false;
  int? _resumeStartIndex;

  static const String _resumePausedPhaseNote = '⚠ 应用关闭后，该阶段已暂停；恢复执行前需要重新审批。';
  static const String _resumeSessionNote = '⚠ 应用关闭后，会话已恢复；继续执行前需要重新审批。';

  bool supportsManualPhaseInput(HarnessPhase phase) {
    return switch (phase) {
      HarnessPhase.metaCollection ||
      HarnessPhase.planning ||
      HarnessPhase.reviewing => true,
      HarnessPhase.reading || HarnessPhase.implementing => false,
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
    if (awaitingPhase == HarnessPhase.reviewing && reviewVerdict != null) {
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
      if (awaitingPhase == HarnessPhase.reviewing && reviewVerdict != null) {
        _appendLine(awaitingLog, reviewVerdict ? 'PASS' : 'FAIL');
        _appendLine(awaitingLog, '');
      }
      for (final line in normalized.split('\n')) {
        _appendLine(awaitingLog, line);
      }
      _appendLine(awaitingLog, '');
      // Show verdict-specific accepted-log for reviewing phase.
      if (awaitingPhase == HarnessPhase.reviewing && reviewVerdict != null) {
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
        _status = HarnessOrchestratorStatus.cancelled;
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
  void updateConfig(HarnessSessionConfig newConfig) {
    _config = newConfig;
    notifyListeners();
  }

  HarnessPhaseExecutionBlocker? phaseExecutionBlocker(HarnessPhase phase) {
    final roleConfig = _roleConfigForPhase(phase);
    if (!roleConfig.isConfigured) {
      return HarnessPhaseExecutionBlocker.missingConfig;
    }
    if (roleConfig.isUrlMode) {
      // URL mode: check API infrastructure and model config availability.
      if (apiPhaseRunner == null || buildApiRuntimeContext == null) {
        return HarnessPhaseExecutionBlocker.missingApiRunner;
      }
      final configId = roleConfig.aiModelConfigId;
      if (configId == null || configId.trim().isEmpty) {
        return HarnessPhaseExecutionBlocker.missingApiModel;
      }
      final modelConfig = resolveAiModelConfig?.call(configId);
      if (modelConfig == null) {
        return HarnessPhaseExecutionBlocker.missingApiModel;
      }
      return null;
    }
    // CLI mode: check headless support.
    final cliEntry = _cliEntryForRoleConfig(roleConfig);
    if (!cliEntry.supportsHeadless) {
      return HarnessPhaseExecutionBlocker.unsupportedCli;
    }
    return null;
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> startOrResume() async {
    if (_status == HarnessOrchestratorStatus.running) {
      return;
    }
    if (_resumePendingApproval) {
      notifyListeners();
      return;
    }
    final failedIndex = _failedPhaseIndex();
    if (_status == HarnessOrchestratorStatus.failed &&
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
    if (_status == HarnessOrchestratorStatus.failed &&
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
      if (_status == HarnessOrchestratorStatus.completed) {
        return;
      }
    }
    final resumableIndex = _resumablePhaseIndex();
    if (_status == HarnessOrchestratorStatus.idle &&
        _phaseLogs.isNotEmpty &&
        resumableIndex != null) {
      await _resumeFromIndex(resumableIndex);
      return;
    }
    await start();
  }

  /// Starts the full Harness Engineering phase pipeline.
  /// Safe to call only when [status] is [HarnessOrchestratorStatus.idle].
  Future<void> start() async {
    if (_status == HarnessOrchestratorStatus.running) return;
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

    final firstRun = await config.isFirstRun();
    final phases = firstRun
        ? [
            HarnessPhase.metaCollection,
            HarnessPhase.reading,
            HarnessPhase.planning,
            HarnessPhase.implementing,
            HarnessPhase.reviewing,
          ]
        : [
            HarnessPhase.reading,
            HarnessPhase.planning,
            HarnessPhase.implementing,
            HarnessPhase.reviewing,
          ];

    _phaseLogs = List<HarnessPhaseLog>.from(phases.map(HarnessPhaseLog.new));
    await _executePipeline(startIndex: 0, skipApprovalForStartIndex: !firstRun);
  }

  Future<void> _resumeFromIndex(int startIndex) async {
    if (_status == HarnessOrchestratorStatus.running) {
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
    _status = HarnessOrchestratorStatus.running;
    notifyListeners();

    HarnessPhaseLog? activeLog;
    try {
      for (var i = startIndex; i < _phaseLogs.length; i++) {
        final log = _phaseLogs[i];
        activeLog = log;
        if (_isDisposed || _stopRequested) {
          if (log.status == HarnessPhaseStatus.pending ||
              log.status == HarnessPhaseStatus.paused) {
            log.status = HarnessPhaseStatus.cancelled;
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
          log.status = HarnessPhaseStatus.paused;
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
            log.status = HarnessPhaseStatus.cancelled;
            notifyListeners();
            // Mark all remaining phases as cancelled too.
            _markRemainingPhasesCancelledFrom(i + 1);
            _status = HarnessOrchestratorStatus.cancelled;
            _currentPhase = null;
            notifyListeners();
            return;
          }
        }

        if (_isDisposed || _stopRequested) {
          log.status = HarnessPhaseStatus.cancelled;
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
        if (log.phase == HarnessPhase.reviewing &&
            _reviewIndicatesFailure(log)) {
          // The reviewing phase detected a FAIL verdict (either from the
          // user button or from the CLI output).  Override a potential
          // execution failure status to "completed" because the phase did
          // produce the expected semantics (a verdict), and mark it as
          // review-verdict-fail.
          if (log.status == HarnessPhaseStatus.failed) {
            _appendLine(log, '');
            _appendLine(log, 'ℹ 验收判定为 FAIL，执行异常已降级处理，进入反馈迭代流程。');
            log.status = HarnessPhaseStatus.completed;
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
          if (log.status == HarnessPhaseStatus.completed &&
              _queuedManualPhaseInputPhase == log.phase) {
            _queuedManualPhaseInputPhase = null;
            _queuedManualPhaseInput = null;
          }
          continue;
        }

        if (log.status == HarnessPhaseStatus.failed ||
            log.status == HarnessPhaseStatus.cancelled) {
          break;
        }

        if (log.status == HarnessPhaseStatus.completed &&
            _queuedManualPhaseInputPhase == log.phase) {
          _queuedManualPhaseInputPhase = null;
          _queuedManualPhaseInput = null;
        }
      }

      if (_isDisposed) return;

      // Mark any remaining untouched phases according to the final outcome.
      for (final log in _phaseLogs) {
        if (log.status == HarnessPhaseStatus.pending ||
            log.status == HarnessPhaseStatus.paused) {
          log.status = _stopRequested
              ? HarnessPhaseStatus.cancelled
              : HarnessPhaseStatus.skipped;
        }
      }

      if (_stopRequested) {
        _status = HarnessOrchestratorStatus.cancelled;
      } else if (_phaseLogs.any((l) => l.status == HarnessPhaseStatus.failed)) {
        _status = HarnessOrchestratorStatus.failed;
        _errorMessage ??= '有阶段执行失败，请检查日志';
      } else if (_reviewRetriesExhausted) {
        _status = HarnessOrchestratorStatus.failed;
        _errorMessage ??= '验收连续 $_maxReviewRetries 轮未通过，已停止迭代';
      } else {
        _status = HarnessOrchestratorStatus.completed;
      }
    } catch (e) {
      if (_isDisposed) return;
      _recordUnhandledPhaseError(activeLog, e);
      _status = HarnessOrchestratorStatus.failed;
      _errorMessage = _friendlyOrchestratorError(e);
    }

    _currentPhase = null;
    notifyListeners();
  }

  /// Requests cancellation of the currently running phase.
  /// Sends SIGTERM followed by SIGKILL after a short grace period.
  void cancel() {
    if (_status != HarnessOrchestratorStatus.running) return;
    _stopRequested = true;
    _manualPhaseInputRequested = false;
    _completePendingApproval(approved: false);
    _cancelActiveApiPhase();
    // Immediately mark any running phase as cancelled for instant UI feedback.
    for (final log in _phaseLogs) {
      if (log.status == HarnessPhaseStatus.running) {
        log.status = HarnessPhaseStatus.cancelled;
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
    _activeProcess = null;
    unawaited(
      terminateTrackedProcessTree(
        process,
        gracefulTimeout: const Duration(seconds: 3),
      ).catchError((Object error, StackTrace stack) {
        silentLog('harness_orchestrator', '终止活动中的 CLI 进程', error, stack);
      }),
    );
  }

  void _completePendingApproval({required bool approved}) {
    final completer = _phaseApprovalCompleter;
    if (completer == null) return;
    if (!completer.isCompleted) {
      completer.complete(approved);
    }
    _phaseApprovalCompleter = null;
    _awaitingApprovalPhase = null;
  }

  void _cancelActiveApiPhase() {
    final apiCancel = _apiCancelCompleter;
    if (apiCancel == null) return;
    if (!apiCancel.isCompleted) {
      apiCancel.complete();
    }
    _apiCancelCompleter = null;
  }

  void restoreSnapshot({
    required HarnessOrchestratorStatus status,
    required List<HarnessPhaseLogSnapshot> phaseLogs,
    String? errorMessage,
    HarnessPhase? currentPhase,
    bool manualPhaseInputRequested = false,
    String? queuedManualPhaseInput,
    HarnessPhase? queuedManualPhaseInputPhase,
  }) {
    _stopRequested = false;
    _activeProcess = null;
    _status = status;
    _phaseLogs = List<HarnessPhaseLog>.from(
      phaseLogs.map(HarnessPhaseLog.fromSnapshot),
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

    if (_status == HarnessOrchestratorStatus.running) {
      final interruptedIndex = _resumablePhaseIndex(includeRunning: true);
      if (interruptedIndex != null) {
        final interruptedLog = _phaseLogs[interruptedIndex];
        _appendResumeNotice(
          interruptedLog,
          wasRunning: interruptedLog.status == HarnessPhaseStatus.running,
        );
        interruptedLog.status = HarnessPhaseStatus.paused;
        _status = HarnessOrchestratorStatus.idle;
      }
    }

    final resumableIndex = _resumablePhaseIndex();
    if (_status == HarnessOrchestratorStatus.idle && resumableIndex != null) {
      final resumableLog = _phaseLogs[resumableIndex];
      if (resumableLog.status == HarnessPhaseStatus.pending) {
        resumableLog.status = HarnessPhaseStatus.paused;
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
      if (status == HarnessPhaseStatus.paused ||
          status == HarnessPhaseStatus.pending ||
          (includeRunning && status == HarnessPhaseStatus.running)) {
        return index;
      }
    }
    return null;
  }

  int? _failedPhaseIndex() {
    for (var index = 0; index < _phaseLogs.length; index += 1) {
      if (_phaseLogs[index].status == HarnessPhaseStatus.failed) {
        return index;
      }
    }
    return null;
  }

  void _resetPhaseLogsForRetryFrom(int startIndex) {
    if (startIndex < 0 || startIndex >= _phaseLogs.length) {
      return;
    }
    final nextLogs = List<HarnessPhaseLog>.from(_phaseLogs);
    for (var index = startIndex; index < nextLogs.length; index += 1) {
      nextLogs[index] = HarnessPhaseLog(nextLogs[index].phase);
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
    if (_status == HarnessOrchestratorStatus.running) return;

    final oldLog = _phaseLogs[phaseIndex];
    final freshLog = HarnessPhaseLog(oldLog.phase);
    _phaseLogs = List<HarnessPhaseLog>.from(_phaseLogs);
    _phaseLogs[phaseIndex] = freshLog;

    _status = HarnessOrchestratorStatus.running;
    _errorMessage = null;
    _stopRequested = false;
    _userReviewVerdict = null;
    notifyListeners();

    try {
      // ── Phase-gate: request user approval if not full-access ──────
      if (!_fullAccessPermission) {
        _currentPhase = freshLog.phase;
        freshLog.status = HarnessPhaseStatus.paused;
        _awaitingApprovalPhase = freshLog.phase;
        _phaseApprovalCompleter = Completer<bool>();
        notifyListeners();

        onPhaseApprovalRequired?.call(freshLog.phase);

        final approved = await _phaseApprovalCompleter!.future;
        _phaseApprovalCompleter = null;
        _awaitingApprovalPhase = null;
        notifyListeners();

        if (!approved || _isDisposed) {
          freshLog.status = HarnessPhaseStatus.cancelled;
          _status = HarnessOrchestratorStatus.idle;
          _currentPhase = null;
          notifyListeners();
          return;
        }
      }

      if (_isDisposed || _stopRequested) {
        freshLog.status = HarnessPhaseStatus.cancelled;
        _status = HarnessOrchestratorStatus.idle;
        _currentPhase = null;
        notifyListeners();
        return;
      }

      await _runPhase(freshLog);

      if (freshLog.status == HarnessPhaseStatus.completed &&
          _queuedManualPhaseInputPhase == freshLog.phase) {
        _queuedManualPhaseInputPhase = null;
        _queuedManualPhaseInput = null;
      }

      // Handle review verdict fail for single-phase re-execution.
      // When a FAIL verdict is detected, insert retry phases (plan→impl→
      // review) after the current position and continue as a pipeline
      // instead of ending the single-phase re-execution here.
      if (freshLog.phase == HarnessPhase.reviewing &&
          _reviewIndicatesFailure(freshLog)) {
        if (freshLog.status == HarnessPhaseStatus.failed) {
          _appendLine(freshLog, '');
          _appendLine(freshLog, 'ℹ 验收判定为 FAIL，执行异常已降级处理，进入反馈迭代流程。');
          freshLog.status = HarnessPhaseStatus.completed;
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
      _errorMessage = _friendlyOrchestratorError(e);
    }

    // Determine overall status from all phase logs.
    _status = _computeOverallStatus();
    _currentPhase = null;
    notifyListeners();
  }

  /// Deletes the phase log at the given index and refreshes state.
  void deletePhaseLog(int phaseIndex) {
    if (phaseIndex < 0 || phaseIndex >= _phaseLogs.length) return;
    if (_status == HarnessOrchestratorStatus.running) return;

    _phaseLogs = List<HarnessPhaseLog>.from(_phaseLogs)..removeAt(phaseIndex);

    // Recompute overall status.
    _status = _computeOverallStatus();
    _reviewRetryCount = _inferReviewRetryCount();
    notifyListeners();
  }

  /// 验收连续判 FAIL 且重试次数已耗尽。
  ///
  /// 达到上限后不再插入重试阶段，而 reviewing 日志早已被降级成 completed
  /// （为了让反馈迭代流程能继续走），于是收尾判断看不到任何 failed 阶段，
  /// 整体状态会落到 completed——用户看到「全部完成」，实际是连续
  /// [_maxReviewRetries] + 1 轮验收都没通过。
  bool get _reviewRetriesExhausted {
    return _reviewRetryCount > _maxReviewRetries &&
        _phaseLogs.any(
          (l) => l.phase == HarnessPhase.reviewing && l.reviewVerdictFail,
        );
  }

  HarnessOrchestratorStatus _computeOverallStatus() {
    if (_phaseLogs.isEmpty) return HarnessOrchestratorStatus.idle;
    if (_phaseLogs.any((l) => l.status == HarnessPhaseStatus.running)) {
      return HarnessOrchestratorStatus.running;
    }
    if (_phaseLogs.any((l) => l.status == HarnessPhaseStatus.failed)) {
      return HarnessOrchestratorStatus.failed;
    }
    if (_reviewRetriesExhausted) {
      return HarnessOrchestratorStatus.failed;
    }
    if (_phaseLogs.every(
      (l) =>
          l.status == HarnessPhaseStatus.completed ||
          l.status == HarnessPhaseStatus.skipped,
    )) {
      return HarnessOrchestratorStatus.completed;
    }
    if (_phaseLogs.any((l) => l.status == HarnessPhaseStatus.cancelled)) {
      return HarnessOrchestratorStatus.cancelled;
    }
    return HarnessOrchestratorStatus.idle;
  }

  int _inferReviewRetryCount() {
    final reviewPhaseCount = _phaseLogs
        .where((log) => log.phase == HarnessPhase.reviewing)
        .length;
    if (reviewPhaseCount <= 1) {
      return 0;
    }
    return reviewPhaseCount - 1;
  }

  List<HarnessPhaseLog> _buildReviewRetryPhaseLogs() {
    return <HarnessPhaseLog>[
      HarnessPhaseLog(HarnessPhase.planning),
      HarnessPhaseLog(HarnessPhase.implementing),
      HarnessPhaseLog(HarnessPhase.reviewing),
    ];
  }

  void _insertReviewRetryPhasesAfter(int phaseIndex) {
    if (phaseIndex < 0 || phaseIndex >= _phaseLogs.length) {
      return;
    }
    final nextLogs = List<HarnessPhaseLog>.from(_phaseLogs);
    nextLogs.insertAll(phaseIndex + 1, _buildReviewRetryPhaseLogs());
    _phaseLogs = nextLogs;
  }

  void _recordUnhandledPhaseError(HarnessPhaseLog? log, Object error) {
    if (log == null) {
      return;
    }
    if (log.lines.isNotEmpty && log.lines.last.isNotEmpty) {
      _appendLine(log, '');
    }
    _appendLine(log, '✗ Harness orchestrator 内部异常：$error');
    if (log.status == HarnessPhaseStatus.running ||
        log.status == HarnessPhaseStatus.pending ||
        log.status == HarnessPhaseStatus.paused) {
      log.status = HarnessPhaseStatus.failed;
    }
  }

  /// 把 orchestrator 顶层 catch 拿到的未识别异常翻译成 header 错误栏
  /// 上的简短中英双语标题 + Raw，使 ProcessException / TimeoutException
  /// / FormatException / FileSystem 错误能立刻定位类别，详细栈仍然写
  /// 进 phase log。
  String _friendlyOrchestratorError(Object error) {
    final raw = error.toString();
    if (error is ProcessException) {
      return '进程启动失败 / Failed to start process: '
          '${error.executable}\n原始错误：$raw';
    }
    if (error is TimeoutException) {
      return '执行超时 / Operation timed out\n原始错误：$raw';
    }
    if (error is FormatException) {
      return '解析输出失败 / Failed to parse output\n原始错误：$raw';
    }
    if (raw.startsWith('FileSystemException') ||
        raw.startsWith('PathNotFoundException')) {
      return '文件系统错误 / Filesystem error\n原始错误：$raw';
    }
    return raw;
  }

  bool _shouldGatePhaseEntry(int index, HarnessPhase phase) {
    if (index > 0) {
      return true;
    }
    return phase == HarnessPhase.metaCollection;
  }

  String _manualPhaseInputLogHeading(HarnessPhase phase) => switch (phase) {
    HarnessPhase.metaCollection => '用户人工研究结果',
    HarnessPhase.planning => '用户人工计划草案',
    HarnessPhase.reviewing => '用户人工验收结果',
    HarnessPhase.reading => '用户人工输入',
    HarnessPhase.implementing => '用户人工输入',
  };

  String _manualPhaseInputAcceptedLog(HarnessPhase phase) => switch (phase) {
    HarnessPhase.metaCollection =>
      'ℹ 已接收用户人工研究结果，本轮 Profile 会结合这些资料产出符合规范的 architecture / conventions 文档。',
    HarnessPhase.planning => 'ℹ 已接收用户人工计划草案，本轮 Plan 会在此基础上润色、补全并输出符合规范的计划文档。',
    HarnessPhase.reviewing => 'ℹ 已接收用户人工验收结果，本轮验收会结合该结果输出 PASS / FAIL 与反馈。',
    HarnessPhase.reading => 'ℹ 已接收用户人工输入。',
    HarnessPhase.implementing => 'ℹ 已接收用户人工输入。',
  };

  String _manualPhaseInputSectionTitle(HarnessPhase phase) => switch (phase) {
    HarnessPhase.metaCollection => '## 用户人工研究结果（高优先级输入）',
    HarnessPhase.planning => '## 用户人工计划草案（高优先级输入）',
    HarnessPhase.reviewing => '## 用户人工验收结果（高优先级输入）',
    HarnessPhase.reading => '## 用户人工输入（高优先级输入）',
    HarnessPhase.implementing => '## 用户人工输入（高优先级输入）',
  };

  String _manualPhaseMissionAddendum(HarnessPhase phase) {
    if (!hasQueuedManualPhaseInputFor(phase)) {
      return '';
    }
    return switch (phase) {
      HarnessPhase.metaCollection =>
        '''
    **本轮存在用户亲自研究的资料或结论。**
    - 你必须把“用户人工研究结果（高优先级输入）”视为高优先级素材，并优先吸收其中的事实、结构与观察结论
    - 你的职责不是忽略这些内容重新来过，而是将其校正、补全、结构化，整理成符合要求的 architecture.md 与 conventions.md
    - 若用户研究结果存在缺漏、格式不规范或信息颗粒度不一致，你需要基于真实项目状态补足并统一表达
    ''',
      HarnessPhase.planning =>
        '''
    **本轮存在用户亲自制定的计划草案。**
    - 你必须把“用户人工计划草案（高优先级输入）”视为高优先级种子方案，在其基础上进行润色、优化、补全与规范化
    - 你的职责不是抛开用户计划另起炉灶，而是将其整理成符合 plan 文档约束的结构化执行计划
    - 若用户草案缺少步骤粒度、验收标准、复杂度标签或文件指向，你需要补足这些缺失项
    ''',
      HarnessPhase.reviewing =>
        '''
    **本轮存在真实用户提交的人工验收结果。**
    - 你必须把"用户人工验收结果（高优先级输入）"视为真实外部观察，而不是可忽略的参考意见
    - 用户已通过界面按钮明确指定了验收结论（PASS 或 FAIL），你必须尊重该结论作为最终判定
    - 若用户判定为 FAIL：你必须输出 FAIL，并将用户的审查意见整理为结构化、可执行的 feedback，保存到指定路径
    - 若用户判定为 PASS：你仍需结合计划、代码与实际实现交叉核验，但应优先尊重用户的通过结论
    ''',
      HarnessPhase.reading => '',
      HarnessPhase.implementing => '',
    };
  }

  void _markRemainingPhasesCancelledFrom(int startIndex) {
    for (var index = startIndex; index < _phaseLogs.length; index += 1) {
      if (_phaseLogs[index].status == HarnessPhaseStatus.pending ||
          _phaseLogs[index].status == HarnessPhaseStatus.paused) {
        _phaseLogs[index].status = HarnessPhaseStatus.cancelled;
      }
    }
  }

  HarnessPhaseLog? _currentAwaitingApprovalLog() {
    final awaitingPhase = _awaitingApprovalPhase;
    if (awaitingPhase == null) {
      return null;
    }
    for (var index = _phaseLogs.length - 1; index >= 0; index -= 1) {
      final log = _phaseLogs[index];
      if (log.phase != awaitingPhase) {
        continue;
      }
      if (log.status == HarnessPhaseStatus.paused ||
          log.status == HarnessPhaseStatus.pending) {
        return log;
      }
    }
    return null;
  }

  void _appendResumeNotice(HarnessPhaseLog log, {required bool wasRunning}) {
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
    _stopRequested = true;
    _completePendingApproval(approved: false);
    _cancelActiveApiPhase();
    _killActiveProcess();
    super.dispose();
  }

  // ── Phase execution ─────────────────────────────────────────────────────────

  Future<void> _runPhase(HarnessPhaseLog log) async {
    _currentPhase = log.phase;
    log.status = HarnessPhaseStatus.running;
    notifyListeners();

    final roleConfig = _roleConfigForPhase(log.phase);
    final executionBlocker = phaseExecutionBlocker(log.phase);

    if (executionBlocker == HarnessPhaseExecutionBlocker.missingConfig) {
      _appendLine(log, '✗ 阶段无法执行：请先为该阶段配置 CLI/模型 或 API 模型。');
      _errorMessage = '存在未配置的阶段，执行已停止。';
      log.status = HarnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    if (executionBlocker == HarnessPhaseExecutionBlocker.unsupportedCli) {
      _appendLine(log, '✗ 阶段无法执行：当前 CLI 不支持无交互执行，请更换为支持 headless 的 CLI。');
      _errorMessage = '存在不支持无交互执行的 CLI 配置，执行已停止。';
      log.status = HarnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    if (executionBlocker == HarnessPhaseExecutionBlocker.missingApiModel) {
      _appendLine(log, '✗ 阶段无法执行：所选 API 模型配置无效或已被删除。请在设置中检查模型配置。');
      _errorMessage = 'API 模型配置无效，执行已停止。';
      log.status = HarnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    if (executionBlocker == HarnessPhaseExecutionBlocker.missingApiRunner) {
      _appendLine(log, '✗ 阶段无法执行：API 运行时未初始化。请重启应用后重试。');
      _errorMessage = 'API 运行时未就绪，执行已停止。';
      log.status = HarnessPhaseStatus.failed;
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
    HarnessPhaseLog log,
    HarnessRoleConfig roleConfig,
  ) async {
    final runner = apiPhaseRunner;
    final contextBuilder = buildApiRuntimeContext;
    final configId = roleConfig.aiModelConfigId;
    if (runner == null || contextBuilder == null || configId == null) {
      _appendLine(log, '✗ API 运行时配置不完整。');
      log.status = HarnessPhaseStatus.failed;
      notifyListeners();
      await _finalizePhaseArtifacts(log);
      return;
    }

    final resolvedConfig = resolveAiModelConfig?.call(configId);
    if (resolvedConfig == null) {
      _appendLine(log, '✗ 找不到 ID 为 "$configId" 的模型配置。请检查设置。');
      log.status = HarnessPhaseStatus.failed;
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
      HarnessDirectorySnapshot preSnapshot;
      if (_stopRequested) {
        preSnapshot = HarnessDirectorySnapshot.incomplete();
      } else {
        try {
          preSnapshot = await _snapshotWorkingDirectory();
        } catch (_) {
          preSnapshot = HarnessDirectorySnapshot.incomplete();
        }
      }
      if (_isDisposed || _stopRequested) {
        if (log.status != HarnessPhaseStatus.cancelled) {
          log.status = HarnessPhaseStatus.cancelled;
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
        if (log.status != HarnessPhaseStatus.cancelled) {
          _appendLine(log, '');
          _appendLine(log, '⚠ 已中止');
          log.status = HarnessPhaseStatus.cancelled;
        }
        notifyListeners();
        // 收尾统一交给 finally：这里再调一次会重复落盘。
        return;
      }

      final postSnapshot = await _snapshotWorkingDirectory();
      _recordChangedFiles(log, preSnapshot, postSnapshot);

      if (result.success) {
        log.exitCode = 0;
        log.status = HarnessPhaseStatus.completed;

        // ── Post-completion artifact verification ──────────────────────
        // Phases with mandatory output files (metaCollection, planning,
        // reviewing) must actually produce them. A "success" from the
        // API runner only means the model replied — it doesn't guarantee
        // the expected files were written.
        final missingArtifacts = await _checkMandatoryArtifacts(log.phase);
        if (missingArtifacts.isNotEmpty) {
          _appendLine(log, '');
          _appendLine(log, '⚠ 阶段产物验证失败：以下必需文件未被创建：');
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
          log.status = HarnessPhaseStatus.failed;
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
        log.status = HarnessPhaseStatus.failed;
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
      log.status = HarnessPhaseStatus.failed;
      _errorMessage = safeError;
    } finally {
      _apiCancelCompleter = null;
      await _finalizePhaseArtifacts(log, promptFile: promptFile);
    }
  }

  // ── CLI-based phase execution ─────────────────────────────────────────────

  Future<void> _runPhaseViaCli(
    HarnessPhaseLog log,
    HarnessRoleConfig roleConfig,
  ) async {
    // Resolve CLI entry from catalog; fall back to a minimal entry if unknown.
    final cliEntry = _cliEntryForRoleConfig(roleConfig);

    final configuredModelId = roleConfig.modelId.trim();
    final displayModelLabel = describeHarnessCliModel(
      configuredModelId,
      isZh: true,
    );
    final invocationModelId = resolveHarnessCliInvocationModelId(
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
        final CliScanEntry scanEntry = (
          cli: cliEntry,
          installed: true,
          resolvedPath: null,
          isLoggedIn: null,
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
          log.status = HarnessPhaseStatus.failed;
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
        log.status = HarnessPhaseStatus.failed;
        notifyListeners();
        return;
      }

      _appendLine(log, '');
      _appendLine(log, '> $cliCmd');
      _appendLine(log, '');
      notifyListeners();

      // 2b. Snapshot working directory files before execution.
      final preSnapshot = _stopRequested
          ? HarnessDirectorySnapshot.incomplete()
          : await _snapshotWorkingDirectory();
      if (_isDisposed || _stopRequested) {
        if (log.status != HarnessPhaseStatus.cancelled) {
          log.status = HarnessPhaseStatus.cancelled;
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
        if (log.status != HarnessPhaseStatus.cancelled) {
          _appendLine(log, '');
          _appendLine(log, '⚠ 已中止');
          log.status = HarnessPhaseStatus.cancelled;
        }
        notifyListeners();
        // 收尾统一交给 finally：这里再调一次不仅重复落盘，而且因为没带
        // promptFile，两次写入的日志内容还不一致（缺「调试 Prompt 文件」行）。
        return;
      }

      final postSnapshot = await _snapshotWorkingDirectory();
      _recordChangedFiles(log, preSnapshot, postSnapshot);

      log.exitCode = exitCode;

      if (exitCode != 0) {
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 进程退出码：$exitCode');
        log.status = HarnessPhaseStatus.failed;
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
        log.status = HarnessPhaseStatus.failed;
      } else if (_looksLikeHollowCliSession(log.lines)) {
        // Exit code 0 but the CLI produced no substantive output, indicating
        // it silently skipped execution (e.g. expired token, config error).
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 以退出码 0 结束，但未产生有效输出，本阶段执行可能未真正生效。');
        _appendLine(log, '  → 可能原因：认证已过期、配置异常或 CLI 静默跳过了任务。请检查 CLI 状态后重试。');
        log.status = HarnessPhaseStatus.failed;
        await _appendCliFailureDiagnostics(log, cliEntry.executable);
      } else {
        log.status = HarnessPhaseStatus.completed;

        // ── Post-completion artifact verification (CLI path) ──────────
        final missingArtifacts = await _checkMandatoryArtifacts(log.phase);
        if (missingArtifacts.isNotEmpty) {
          _appendLine(log, '');
          _appendLine(log, '⚠ 阶段产物验证失败：以下必需文件未被创建：');
          for (final path in missingArtifacts) {
            _appendLine(log, '  • $path');
          }
          _appendLine(log, '');
          _appendLine(log, '✗ 本阶段被判定为失败，因为 CLI 未能生成预期的输出产物。');
          log.status = HarnessPhaseStatus.failed;
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
      log.status = HarnessPhaseStatus.failed;
      await _appendCliFailureDiagnostics(log, cliEntry.executable);
    } on TimeoutException catch (e) {
      if (_isDisposed) return;
      _appendLine(log, '');
      _appendLine(log, '✗ 超时：${e.message}');
      log.status = HarnessPhaseStatus.failed;
      await _appendCliFailureDiagnostics(log, cliEntry.executable);
    } catch (e) {
      if (_isDisposed) return;
      _appendLine(log, '');
      _appendLine(log, '✗ 执行错误：$e');
      log.status = HarnessPhaseStatus.failed;
      await _appendCliFailureDiagnostics(log, cliEntry.executable);
    } finally {
      await _finalizePhaseArtifacts(log, promptFile: promptFile);
    }
  }

  // ── Review failure detection ─────────────────────────────────────────────

  /// Returns true if the reviewing phase indicates a FAIL verdict,
  /// considering both explicit user verdict and CLI output analysis.
  bool _reviewIndicatesFailure(HarnessPhaseLog log) {
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
  bool _reviewOutputIndicatesFailure(HarnessPhaseLog log) {
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

  HarnessRoleConfig _roleConfigForPhase(HarnessPhase phase) => switch (phase) {
    HarnessPhase.metaCollection => config.profilerConfig,
    HarnessPhase.reading => config.readerConfig,
    HarnessPhase.planning => config.plannerConfig,
    HarnessPhase.implementing => config.implementerConfig,
    HarnessPhase.reviewing => config.reviewerConfig,
  };

  HarnessCli _cliEntryForRoleConfig(HarnessRoleConfig roleConfig) {
    return kHarnessCliCatalog
            .where((c) => c.name == roleConfig.cliName)
            .firstOrNull ??
        HarnessCli(
          name: roleConfig.cliName,
          executable: roleConfig.cliName.split(' ').first.toLowerCase(),
          knownModels: const [],
        );
  }

  // ── Prompt construction ──────────────────────────────────────────────────

  static final HarnessFileIoLimits _promptContextIoLimits = HarnessFileIoLimits(
    maxScannedFiles: 1024,
    maxTextFiles: 40,
    maxDirectoryEntries: 1024,
    maxFileBytes: 512 * 1024,
    maxTotalBytes: 4 * 1024 * 1024,
    totalTimeout: const Duration(seconds: 5),
    operationTimeout: const Duration(seconds: 1),
  );
  static const int _maxLessonContextFiles = 32;
  static const int _maxLessonContextBytes = 1536 * 1024;

  Future<String> _buildPhasePrompt(HarnessPhase phase) async {
    final steeringDir = p.join(config.persistenceDirectory, 'steering');
    final contextConfig = getPhaseContextConfig(phase);

    final contextFileIo = HarnessBoundedFileIo(_promptContextIoLimits);
    Future<String> readContextFile(String path) async =>
        (await contextFileIo.readText(File(path)))?.text ?? '';

    // 按阶段配置条件加载上下文
    final archContent = contextConfig.includeArchitecture
        ? await readContextFile(p.join(steeringDir, 'meta', 'architecture.md'))
        : '';
    final convContent = contextConfig.includeConventions
        ? await readContextFile(p.join(steeringDir, 'meta', 'conventions.md'))
        : '';

    // Load the latest plan and feedback before the potentially larger lesson
    // collection so essential current-phase context retains budget priority.
    String planContent = '';
    if (contextConfig.includePlan) {
      try {
        planContent = await contextFileIo.readLexicographicallyLatestText(
          Directory(p.join(steeringDir, 'plan')),
        );
      } catch (error, stack) {
        silentLog('harness_orchestrator', '读取计划', error, stack);
      }
    }

    String feedbackContent = '';
    if (contextConfig.includeFeedback || _reviewRetryCount > 0) {
      try {
        feedbackContent = await contextFileIo.readLexicographicallyLatestText(
          Directory(p.join(steeringDir, 'feedback')),
        );
      } catch (error, stack) {
        silentLog('harness_orchestrator', '读取反馈', error, stack);
      }
    }

    // Latest handoff document.
    String handoffContent = '';
    if (contextConfig.includeHandoff) {
      try {
        handoffContent = await contextFileIo.readLexicographicallyLatestText(
          Directory(p.join(steeringDir, 'handoff')),
        );
      } catch (error, stack) {
        silentLog('harness_orchestrator', '读取交接记录', error, stack);
      }
    }

    // Load lessons based on config mode.
    String lessonsContent = '';
    if (contextConfig.lessonsMode != HarnessLessonInclusionMode.none) {
      try {
        final fullContent = await contextFileIo.readJoinedTextFiles(
          Directory(p.join(steeringDir, 'lesson')),
          separator: '\n\n---\n\n',
          maxJoinedBytes: _maxLessonContextBytes,
          maxFiles: _maxLessonContextFiles,
        );
        if (fullContent.isNotEmpty) {
          // Use summary mode for lessons when configured
          lessonsContent =
              contextConfig.lessonsMode == HarnessLessonInclusionMode.summary
              ? harnessPromptBuilder.renderLessonsSummary(fullContent)
              : fullContent;
        }
      } catch (error, stack) {
        silentLog('harness_orchestrator', '读取经验记录', error, stack);
      }
    }

    var manualPhaseInputContent = _queuedManualPhaseInputPhase == phase
        ? _queuedManualPhaseInput?.trim() ?? ''
        : '';
    // If the user provided an explicit review verdict, prepend it to the
    // manual input so the reviewer CLI receives an unambiguous signal.
    if (phase == HarnessPhase.reviewing &&
        manualPhaseInputContent.isNotEmpty &&
        _userReviewVerdict != null) {
      final verdictLabel = _userReviewVerdict! ? 'PASS' : 'FAIL';
      manualPhaseInputContent =
          '用户判定：$verdictLabel\n\n$manualPhaseInputContent';
    }

    // 构建阶段提示词（语言策略已在系统指令中定义，此处仅引用）
    final sb = StringBuffer()
      ..writeln('# Harness Engineering - ${phase.displayNameZh}阶段')
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
  String _phaseDirectoryPermissionConstraint(HarnessPhase phase) {
    return switch (phase) {
      HarnessPhase.reading || HarnessPhase.planning =>
        '2. **工作目录仅供只读分析。** 严禁在本阶段修改、创建或删除工作目录下的任何源码、配置、资源或其他文件。严禁执行会改变项目状态的命令（构建、安装、测试等）。允许写入的唯一位置是持久化目录中的指定输出文件。',
      HarnessPhase.metaCollection =>
        '2. 工作目录仅供只读扫描；允许写入的唯一位置是持久化目录下的 meta/ 子目录。',
      HarnessPhase.reviewing =>
        '2. 工作目录仅供只读验证。允许写入的唯一位置是持久化目录下的 feedback/ 子目录。严禁在验收阶段修改项目代码或资源。',
      HarnessPhase.implementing =>
        '2. 允许读写的核心目录为工作目录与持久化目录；涉及产物、计划、反馈等文件时，请直接写入任务中指定的路径。',
    };
  }

  String _missionTemplate(HarnessPhase phase) {
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
      HarnessPhase.metaCollection =>
        '''你是该项目的探档者（Profiler）。

    ${_manualPhaseMissionAddendum(HarnessPhase.metaCollection)}

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

      HarnessPhase.reading =>
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

      HarnessPhase.planning =>
        '''你是本任务的规划者（Planner）。

    ${_manualPhaseMissionAddendum(HarnessPhase.planning)}

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

      HarnessPhase.implementing =>
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

      HarnessPhase.reviewing =>
        '''你是本任务的验收者（Reviewer）。

    **关键要求：你处于一个全新且独立的会话中，与实施者完全隔离。**
    你不知道实施者的推理过程，也不能假设任何步骤已经被正确完成。
    你必须仅基于原始需求、上方执行计划以及项目当前真实代码状态进行验收。

    **评审独立性**：你与实施者完全隔离，必须从零核验每个步骤。
    ${_reviewRetryCount > 0 ? '\n**注意**：第 $_reviewRetryCount 次重试，重点检查之前的问题是否修复。\n' : ''}
    ${_manualPhaseMissionAddendum(HarnessPhase.reviewing)}

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

  /// Returns a shell command string suitable for the Harness POSIX shell
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
      // Harness approval already happens at the phase boundary. In Gemini
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

  // ── I/O 辅助方法 ─────────────────────────────────────────────────────────

  Future<File> _writePromptFile(HarnessPhase phase, String content) async {
    final name =
        'he_${phase.storageValue}_${DateTime.now().millisecondsSinceEpoch}.md';
    final promptDir = Directory(
      p.join(config.persistenceDirectory, 'steering', 'log', 'prompts'),
    );
    final file = File(p.join(promptDir.path, name));
    await writeFileAtomically(file, content);
    return file;
  }

  Future<int> _spawnAndCollect(
    String cmdStr, {
    required String workingDirectory,
    required void Function(String line) onLine,
    // 安全兜底：进程在该时限内未退出时强制终止。两小时足以覆盖正常 AI 编码任务。
    Duration timeout = const Duration(hours: 2),
  }) async {
    final quotedWd = _shellSingleQuote(workingDirectory);
    final fullCmd = 'cd $quotedWd && $cmdStr';
    Process? startedProcess;
    try {
      final result = await runTrackedProcessWithLineLogging(
        resolveHarnessCliShellExecutable(),
        buildHarnessCliShellArgs(fullCmd),
        timeout: timeout,
        processStartTimeout: _kHarnessProcessStartTimeout,
        tag: 'harness_orchestrator',
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
        onStdoutLine: onLine,
        onStderrLine: onLine,
        onProcessStarted: (process) {
          startedProcess = process;
          if (_isDisposed || _stopRequested) {
            unawaited(
              terminateTrackedProcessTree(
                process,
                gracefulTimeout: const Duration(seconds: 3),
              ).catchError((Object error, StackTrace stack) {
                silentLog(
                  'harness_orchestrator',
                  '终止已取消任务的延迟 CLI 进程',
                  error,
                  stack,
                );
              }),
            );
            return;
          }
          _activeProcess = process;
        },
      );
      if (result.timedOut) {
        throw TimeoutException('CLI 进程超过启动或执行时限。', timeout);
      }
      return result.exitCode;
    } finally {
      if (identical(_activeProcess, startedProcess)) _activeProcess = null;
    }
  }

  Future<void> _savePhasePersistence(HarnessPhaseLog log) async {
    try {
      final logDir = Directory(
        p.join(config.persistenceDirectory, 'steering', 'log'),
      );
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final file = File(
        p.join(logDir.path, '${log.phase.storageValue}-$ts.log'),
      );
      await writeFileAtomically(file, log.lines.join('\n'));
      log.savedLogPath = file.path;
    } catch (error, stack) {
      silentLog('harness_orchestrator', '持久化阶段日志', error, stack);
    }
  }

  Future<void> _appendCliFailureDiagnostics(
    HarnessPhaseLog log,
    String executable,
  ) async {
    if (log.lines.any((line) => line == 'ℹ 运行环境诊断：')) {
      return;
    }

    final diagnostics = await collectHarnessCliFailureDiagnostics(executable);
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
  bool _looksLikeHollowCliSession(List<String> lines) {
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
    HarnessPhaseLog log,
    HarnessCli cliEntry,
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

    final suggestedModels = suggestedHarnessCliModels(cliEntry, max: 4)
        .map((candidate) => describeHarnessCliModel(candidate, isZh: true))
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
      '  当前请求模型：${describeHarnessCliModel(modelId, isZh: true)}',
    );
    if (suggestedModels.isNotEmpty) {
      _appendLine(log, '  可优先尝试：$suggestedModels');
    }
    _appendLine(log, '  建议在当前阶段卡片中手动更换 CLI / 模型后，再点击“重试失败阶段”。');
    _appendLine(log, '  模型列表文档：$kHarnessGeminiModelsDocUrl');
  }

  void _appendGeminiHeadlessRuntimeHints(HarnessPhaseLog log) {
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
    HarnessPhaseLog log, {
    File? promptFile,
  }) async {
    if (_isDisposed) {
      return;
    }

    final shouldRetainPrompt =
        promptFile != null && log.status != HarnessPhaseStatus.completed;
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
        if (promptFile != null &&
            await promptFile.exists().timeout(_kHarnessArtifactIoTimeout)) {
          await promptFile.delete().timeout(_kHarnessArtifactIoTimeout);
        }
      } catch (error, stack) {
        silentLog('harness_orchestrator', '清理 Prompt 文件', error, stack);
      }
    }

    notifyListeners();
  }

  void _appendLine(HarnessPhaseLog log, String line) {
    if (log.lines.length >= _kMaxHarnessPhaseLogLines) {
      log.lines.removeRange(0, _kMaxHarnessPhaseLogLines ~/ 4);
      log.lines.insert(0, '… earlier phase output truncated …');
    }
    log.lines.add(clipTextWithEllipsis(line, _kMaxHarnessLogLineCharacters));
  }

  /// Checks whether the mandatory output artifacts for a phase exist.
  ///
  /// Returns a list of missing file paths (empty list = all present).
  /// Phases with no mandatory artifacts (reading, implementing) always
  /// return an empty list.
  Future<List<String>> _checkMandatoryArtifacts(HarnessPhase phase) async {
    final steeringDir = p.join(config.persistenceDirectory, 'steering');
    final missing = <String>[];

    switch (phase) {
      case HarnessPhase.metaCollection:
        final archPath = p.join(steeringDir, 'meta', 'architecture.md');
        final convPath = p.join(steeringDir, 'meta', 'conventions.md');
        if (!await File(archPath).exists()) missing.add(archPath);
        if (!await File(convPath).exists()) missing.add(convPath);
      case HarnessPhase.planning:
        final planDir = Directory(p.join(steeringDir, 'plan'));
        final hasPlanFile = await _containsMarkdownArtifact(planDir);
        if (!hasPlanFile) {
          missing.add('${planDir.path}/*.md (no plan file found)');
        }
      case HarnessPhase.reviewing:
        final feedbackDir = Directory(p.join(steeringDir, 'feedback'));
        final hasFeedbackFile = await _containsMarkdownArtifact(feedbackDir);
        if (!hasFeedbackFile) {
          missing.add('${feedbackDir.path}/*.md (no feedback file found)');
        }
      case HarnessPhase.reading:
      case HarnessPhase.implementing:
        break; // No mandatory artifacts
    }
    return missing;
  }

  Future<bool> _containsMarkdownArtifact(Directory directory) async {
    if (!await directory.exists()) {
      return false;
    }
    try {
      final listing = await listDirectoryBounded(
        directory,
        maxEntries: 512,
        totalTimeout: const Duration(seconds: 3),
      );
      return listing.entries.whereType<File>().any(
        (file) => p.extension(file.path).toLowerCase() == '.md',
      );
    } on FileSystemException catch (error, stack) {
      silentLog(
        'harness_orchestrator',
        '检查必需产物 ${directory.path}',
        error,
        stack,
      );
      return false;
    }
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

  static final HarnessFileIoLimits _snapshotIoLimits = HarnessFileIoLimits(
    maxScannedFiles: 5000,
    maxTextFiles: 5000,
    maxDirectoryEntries: 10000,
    maxFileBytes: _maxDiffFileSize,
    maxTotalBytes: 16 * 1024 * 1024,
    totalTimeout: const Duration(seconds: 12),
    operationTimeout: const Duration(seconds: 2),
  );

  /// Takes a bounded snapshot of working-directory metadata and diff content.
  Future<HarnessDirectorySnapshot> _snapshotWorkingDirectory() {
    return HarnessBoundedFileIo(_snapshotIoLimits).snapshotDirectory(
      Directory(_config.workingDirectory),
      ignoredNames: _snapshotIgnoredDirs,
    );
  }

  void _recordChangedFiles(
    HarnessPhaseLog log,
    HarnessDirectorySnapshot before,
    HarnessDirectorySnapshot after,
  ) {
    if (!before.complete || !after.complete) {
      log.changedFiles = const <HarnessChangedFile>[];
      _appendLine(log, '⚠ 工作目录快照达到安全上限或读取异常，已跳过文件变更明细。');
      return;
    }
    log.changedFiles = _computeChangedFiles(before.files, after.files);
  }

  List<HarnessChangedFile> _computeChangedFiles(
    Map<String, HarnessFileSnapshot> before,
    Map<String, HarnessFileSnapshot> after,
  ) {
    final changes = <HarnessChangedFile>[];

    // Added or modified files
    for (final entry in after.entries) {
      final rel = entry.key;
      final post = entry.value;
      final pre = before[rel];

      if (pre == null) {
        changes.add(
          HarnessChangedFile(
            relativePath: rel,
            absolutePath: p.join(_config.workingDirectory, rel),
            changeType: HarnessFileChangeType.added,
            afterContent: post.content,
          ),
        );
      } else if (pre.modified != post.modified || pre.size != post.size) {
        changes.add(
          HarnessChangedFile(
            relativePath: rel,
            absolutePath: p.join(_config.workingDirectory, rel),
            changeType: HarnessFileChangeType.modified,
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
          HarnessChangedFile(
            relativePath: rel,
            absolutePath: p.join(_config.workingDirectory, rel),
            changeType: HarnessFileChangeType.deleted,
            beforeContent: before[rel]!.content,
          ),
        );
      }
    }

    changes.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return changes;
  }
}
