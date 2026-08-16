import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/platform_shell.dart';
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
const int kHarnessManualPhaseInputMaxCharacters = 64 * 1024;
const int _kMaxHarnessPhaseLogLines = 1000;
const int _kMaxHarnessLogLineCharacters = 2000;
const int _kMaxHarnessChangedFiles = 500;
const int _kMaxHarnessDiffSideCharacters = 128 * 1024;
const int _kMaxHarnessDiffTotalCharacters = 2 * kBytesPerMiB;
const int _kMaxHarnessStoredPathCharacters = 4096;
const int _kMaxHarnessStorageValueCharacters = 64;
const String _kHarnessLogTruncationMarker = '… 较早的阶段输出已截断 …';
const Duration _kHarnessProcessStartTimeout = Duration(seconds: 10);
const Duration _kHarnessProcessStopTimeout = Duration(seconds: 3);
const Duration _kHarnessArtifactIoTimeout = Duration(seconds: 3);
const BoundedDeletePolicy _kHarnessPromptDeletePolicy = BoundedDeletePolicy(
  maxEntries: 1,
  maxDepth: 0,
  operationTimeout: _kHarnessArtifactIoTimeout,
  totalTimeout: Duration(seconds: 5),
);

// ─────────────────────────────────────────────────────────────────────────────
// 阶段状态与日志
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
  final omitted = value.length > _kMaxHarnessPhaseLogLines;
  final start = omitted ? value.length - _kMaxHarnessPhaseLogLines + 1 : 0;
  return <String>[
    if (omitted) _kHarnessLogTruncationMarker,
    for (var index = start; index < value.length; index++)
      clipTextByCodeUnitsWithEllipsis(
        value[index] == null ? '' : '${value[index]}',
        _kMaxHarnessLogLineCharacters,
      ),
  ];
}

List<Map<String, Object?>> _harnessChangedFileMapsFromValue(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  final count = value.length < _kMaxHarnessChangedFiles
      ? value.length
      : _kMaxHarnessChangedFiles;
  var remainingCharacters = _kMaxHarnessDiffTotalCharacters;
  final retained = <Map<String, Object?>>[];
  for (var index = 0; index < count; index++) {
    final change = HarnessChangedFile.fromJson(
      stringKeyedMapFromValue(value[index]),
    );
    var contentTruncated = change.contentTruncated;

    String? retainContent(String? content) {
      if (content == null || content.isEmpty) return content;
      if (remainingCharacters <= 0) {
        contentTruncated = true;
        return null;
      }
      final limit = remainingCharacters < _kMaxHarnessDiffSideCharacters
          ? remainingCharacters
          : _kMaxHarnessDiffSideCharacters;
      final clipped = clipTextByCodeUnits(content, limit, suffix: '');
      remainingCharacters -= clipped.length;
      contentTruncated |= clipped.length < content.length;
      return clipped;
    }

    retained.add(
      HarnessChangedFile(
        relativePath: change.relativePath,
        absolutePath: change.absolutePath,
        changeType: change.changeType,
        beforeContent: retainContent(change.beforeContent),
        afterContent: retainContent(change.afterContent),
        contentTruncated: contentTruncated,
      ).toJson(),
    );
  }
  return retained;
}

class HarnessPhaseLog {
  HarnessPhaseLog(this.phase);

  final HarnessPhase phase;
  HarnessPhaseStatus status = HarnessPhaseStatus.pending;
  final List<String> lines = [];
  int? exitCode;
  String? savedLogPath;

  /// 验收阶段是否判定失败。
  bool reviewVerdictFail = false;

  /// 本阶段产生的文件变更。
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
      statusValue: clipTextByCodeUnits(
        '${json['status'] ?? HarnessPhaseStatus.pending.name}',
        _kMaxHarnessStorageValueCharacters,
        suffix: '',
      ),
      lines: _harnessLogLinesFromValue(rawLines),
      exitCode: optionalIntegralIntFromValue(json['exit_code']),
      savedLogPath: json['saved_log_path'] == null
          ? null
          : clipTextByCodeUnits(
              '${json['saved_log_path']}',
              _kMaxHarnessStoredPathCharacters,
              suffix: '',
            ),
      changedFiles: _harnessChangedFileMapsFromValue(json['changed_files']),
      reviewVerdictFail: boolFromValue(json['review_verdict_fail']),
    );
  }
}

/// 阶段执行产生的文件变更。
class HarnessChangedFile {
  const HarnessChangedFile({
    required this.relativePath,
    required this.absolutePath,
    required this.changeType,
    this.beforeContent,
    this.afterContent,
    this.contentTruncated = false,
  });

  final String relativePath;
  final String absolutePath;
  final HarnessFileChangeType changeType;
  final String? beforeContent;
  final String? afterContent;
  final bool contentTruncated;

  Map<String, Object?> toJson() => {
    'relative_path': relativePath,
    'absolute_path': absolutePath,
    'change_type': changeType.name,
    'before_content': beforeContent,
    'after_content': afterContent,
    'content_truncated': contentTruncated,
  };

  static HarnessChangedFile fromJson(Map<String, Object?> json) {
    final rawBefore = json['before_content']?.toString();
    final rawAfter = json['after_content']?.toString();
    return HarnessChangedFile(
      relativePath: clipTextByCodeUnits(
        '${json['relative_path'] ?? ''}',
        _kMaxHarnessStoredPathCharacters,
        suffix: '',
      ),
      absolutePath: clipTextByCodeUnits(
        '${json['absolute_path'] ?? ''}',
        _kMaxHarnessStoredPathCharacters,
        suffix: '',
      ),
      changeType: enumByNameOr(
        HarnessFileChangeType.values,
        json['change_type'],
        fallback: HarnessFileChangeType.modified,
      ),
      beforeContent: rawBefore == null
          ? null
          : clipTextByCodeUnits(
              rawBefore,
              _kMaxHarnessDiffSideCharacters,
              suffix: '',
            ),
      afterContent: rawAfter == null
          ? null
          : clipTextByCodeUnits(
              rawAfter,
              _kMaxHarnessDiffSideCharacters,
              suffix: '',
            ),
      contentTruncated:
          boolFromValue(json['content_truncated']) ||
          (rawBefore?.length ?? 0) > _kMaxHarnessDiffSideCharacters ||
          (rawAfter?.length ?? 0) > _kMaxHarnessDiffSideCharacters,
    );
  }
}

enum HarnessFileChangeType { added, modified, deleted }

const Object _harnessPhaseLogSnapshotUnset = Object();

// ─────────────────────────────────────────────────────────────────────────────
// 编排器整体状态
// ─────────────────────────────────────────────────────────────────────────────

enum HarnessOrchestratorStatus { idle, running, completed, failed, cancelled }

// ─────────────────────────────────────────────────────────────────────────────
// Harness 工程阶段编排器
// ─────────────────────────────────────────────────────────────────────────────

class HarnessOrchestrator extends ChangeNotifier {
  HarnessOrchestrator(this._config);

  HarnessSessionConfig _config;
  HarnessSessionConfig get config => _config;

  /// URL 模式使用的 API 阶段执行器。
  HarnessApiPhaseRunner? apiPhaseRunner;

  /// 按配置 ID 解析 AI 模型。
  AiModelConfig? Function(String configId)? resolveAiModelConfig;

  /// 构建 API 阶段执行所需的运行上下文。
  Future<AiSessionRuntimeContext> Function(String workingDirectory)?
  buildApiRuntimeContext;

  HarnessOrchestratorStatus _status = HarnessOrchestratorStatus.idle;
  HarnessOrchestratorStatus get status => _status;
  final OpenHandSingleFlight<void> _startFlight = OpenHandSingleFlight<void>();

  List<HarnessPhaseLog> _phaseLogs = const <HarnessPhaseLog>[];
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

  /// 验收失败后的重试轮数，用于阻止无限循环。
  int _reviewRetryCount = 0;
  int get reviewRetryCount => _reviewRetryCount;
  static const int _maxReviewRetries = 3;

  /// 是否无需逐阶段审批。
  bool _fullAccessPermission = false;
  bool get fullAccessPermission => _fullAccessPermission;
  set fullAccessPermission(bool value) {
    if (_fullAccessPermission == value) return;
    _fullAccessPermission = value;
    // 等待审批时启用完全访问权限，立即通过当前审批。
    if (value &&
        _phaseApprovalCompleter != null &&
        !_phaseApprovalCompleter!.isCompleted) {
      _manualPhaseInputRequested = false;
      resolvePhaseApproval(true);
    }
    notifyListeners();
  }

  /// 等待阶段审批时通知界面刷新；审批结果由 [resolvePhaseApproval] 提交。
  void Function(HarnessPhase nextPhase)? onPhaseApprovalRequired;

  /// 当前阶段审批结果。
  Completer<bool>? _phaseApprovalCompleter;

  /// 当前等待审批的阶段。
  HarnessPhase? _awaitingApprovalPhase;
  HarnessPhase? get awaitingApprovalPhase => _awaitingApprovalPhase;

  /// 暂停阶段是否正在等待用户补充内容。
  bool _manualPhaseInputRequested = false;
  bool get manualPhaseInputRequested => _manualPhaseInputRequested;
  HarnessPhase? get awaitingManualPhaseInputPhase =>
      _manualPhaseInputRequested ? _awaitingApprovalPhase : null;
  bool get awaitingManualPhaseInput => awaitingManualPhaseInputPhase != null;

  /// 指定阶段下次执行时使用的用户补充内容，可跨应用重启恢复。
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

  /// 用户验收结论；空值表示仅采用 AI 验收结果。
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
    if (normalized.isEmpty ||
        normalized.length > kHarnessManualPhaseInputMaxCharacters) {
      return false;
    }
    _queuedManualPhaseInputPhase = awaitingPhase;
    _queuedManualPhaseInput = normalized;
    _manualPhaseInputRequested = false;

    // 记录用户明确提交的验收结论。
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
      // 将明确结论置于验收补充内容之前。
      if (awaitingPhase == HarnessPhase.reviewing && reviewVerdict != null) {
        _appendLine(awaitingLog, reviewVerdict ? 'PASS' : 'FAIL');
        _appendLine(awaitingLog, '');
      }
      for (final line in normalized.split('\n')) {
        _appendLine(awaitingLog, line);
      }
      _appendLine(awaitingLog, '');
      // 记录验收结论已被接收。
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

  /// 提交当前待执行阶段的审批结果。
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

  /// 更新后续阶段使用的配置。
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
      // URL 模式需具备 API 执行器和模型配置。
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
    // CLI 模式必须支持无界面执行。
    final cliEntry = _cliEntryForRoleConfig(roleConfig);
    if (!cliEntry.supportsHeadless) {
      return HarnessPhaseExecutionBlocker.unsupportedCli;
    }
    return null;
  }

  // ── 公共接口 ──────────────────────────────────────────────────────────────

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
    // 顶层异常可能只标记整体失败；此时从首个未完成阶段恢复。
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

  /// 启动完整的 Harness 工程阶段流水线。
  Future<void> start() {
    if (_isDisposed) return Future<void>.value();
    return _startFlight.run(_startPipeline);
  }

  Future<void> _startPipeline() async {
    if (_isDisposed || _status == HarnessOrchestratorStatus.running) return;
    _status = HarnessOrchestratorStatus.running;
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
    notifyListeners();

    try {
      final firstRun = await config.isFirstRun();
      if (_isDisposed) return;
      if (_stopRequested) {
        _status = HarnessOrchestratorStatus.cancelled;
        notifyListeners();
        return;
      }
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

      _phaseLogs = List<HarnessPhaseLog>.unmodifiable(
        phases.map(HarnessPhaseLog.new),
      );
      await _executePipeline(
        startIndex: 0,
        skipApprovalForStartIndex: !firstRun,
      );
    } catch (error, stack) {
      if (_isDisposed) return;
      _status = HarnessOrchestratorStatus.failed;
      _currentPhase = null;
      _errorMessage = _friendlyOrchestratorError(error);
      silentLog('harness_orchestrator', '启动 Harness 流水线', error, stack);
      notifyListeners();
    }
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

        // 非完全访问模式下，进入阶段前需用户审批。
        final shouldSkipApprovalForThisPhase =
            skipApprovalForStartIndex && i == startIndex;
        if (!_fullAccessPermission &&
            !shouldSkipApprovalForThisPhase &&
            _shouldGatePhaseEntry(i, log.phase)) {
          _currentPhase = log.phase;
          log.status = HarnessPhaseStatus.paused;
          final approved = await _awaitPhaseApproval(log.phase);

          if (!approved || _isDisposed) {
            log.status = HarnessPhaseStatus.cancelled;
            notifyListeners();
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

        // 验收不通过属于业务结论，应优先进入反馈迭代而非按执行异常终止。
        if (log.phase == HarnessPhase.reviewing &&
            _reviewIndicatesFailure(log)) {
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

      // 根据最终结果收敛尚未执行的阶段。
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

  /// 取消当前阶段及其活动进程。
  void cancel() {
    if (_status != HarnessOrchestratorStatus.running) return;
    _stopRequested = true;
    _manualPhaseInputRequested = false;
    _completePendingApproval(approved: false);
    _cancelActiveApiPhase();
    // 立即更新状态，避免界面等待进程清理完成。
    for (final log in _phaseLogs) {
      if (log.status == HarnessPhaseStatus.running) {
        log.status = HarnessPhaseStatus.cancelled;
      }
    }
    _killActiveProcess();
    notifyListeners();
  }

  /// 先请求正常退出，超时后强制终止活动 CLI 进程。
  void _killActiveProcess() {
    final process = _activeProcess;
    if (process == null) return;
    _activeProcess = null;
    unawaited(
      terminateTrackedProcessTree(
        process,
        gracefulTimeout: _kHarnessProcessStopTimeout,
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

  Future<bool> _awaitPhaseApproval(HarnessPhase phase) async {
    final approval = Completer<bool>();
    _awaitingApprovalPhase = phase;
    _phaseApprovalCompleter = approval;
    notifyListeners();
    try {
      if (!approval.isCompleted && !_isDisposed) {
        onPhaseApprovalRequired?.call(phase);
      }
      return await approval.future;
    } finally {
      if (identical(_phaseApprovalCompleter, approval)) {
        _phaseApprovalCompleter = null;
        if (_awaitingApprovalPhase == phase) _awaitingApprovalPhase = null;
        notifyListeners();
      }
    }
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
    _phaseLogs = List<HarnessPhaseLog>.unmodifiable(
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
      _queuedManualPhaseInput = clipTextByCodeUnits(
        normalizedManualPhaseInput,
        kHarnessManualPhaseInputMaxCharacters,
        suffix: '',
      );
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
    _phaseLogs = List<HarnessPhaseLog>.unmodifiable(nextLogs);
    _currentPhase = null;
    _errorMessage = null;
  }

  /// 重置并重新执行指定阶段；非完全访问模式下仍需审批。
  Future<void> reExecutePhase(int phaseIndex) async {
    if (phaseIndex < 0 || phaseIndex >= _phaseLogs.length) return;
    if (_status == HarnessOrchestratorStatus.running) return;

    final oldLog = _phaseLogs[phaseIndex];
    final freshLog = HarnessPhaseLog(oldLog.phase);
    final nextLogs = List<HarnessPhaseLog>.from(_phaseLogs);
    nextLogs[phaseIndex] = freshLog;
    _phaseLogs = List<HarnessPhaseLog>.unmodifiable(nextLogs);

    _status = HarnessOrchestratorStatus.running;
    _errorMessage = null;
    _stopRequested = false;
    _userReviewVerdict = null;
    notifyListeners();

    try {
      if (!_fullAccessPermission) {
        _currentPhase = freshLog.phase;
        freshLog.status = HarnessPhaseStatus.paused;
        final approved = await _awaitPhaseApproval(freshLog.phase);

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

      // 单阶段验收失败时继续插入规划、实现和验收阶段。
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

    _status = _computeOverallStatus();
    _currentPhase = null;
    notifyListeners();
  }

  /// 删除指定阶段日志并重新计算整体状态。
  void deletePhaseLog(int phaseIndex) {
    if (phaseIndex < 0 || phaseIndex >= _phaseLogs.length) return;
    if (_status == HarnessOrchestratorStatus.running) return;

    final nextLogs = List<HarnessPhaseLog>.from(_phaseLogs)
      ..removeAt(phaseIndex);
    _phaseLogs = List<HarnessPhaseLog>.unmodifiable(nextLogs);

    _status = _computeOverallStatus();
    _reviewRetryCount = _inferReviewRetryCount();
    notifyListeners();
  }

  /// 验收连续判 FAIL 且重试次数已耗尽。
  ///
  /// 达到上限后不再插入重试阶段，避免已降级的验收日志误导整体状态。
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
    _phaseLogs = List<HarnessPhaseLog>.unmodifiable(nextLogs);
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

  /// 将未识别异常转换为简短的双语错误标题，详细信息仍写入阶段日志。
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
      _appendLine(log, '');
    }
    _appendLine(log, note);
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _stopRequested = true;
    _completePendingApproval(approved: false);
    _cancelActiveApiPhase();
    _killActiveProcess();
    super.dispose();
  }

  // ── 阶段执行 ──────────────────────────────────────────────────────────────

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

    if (roleConfig.isUrlMode) {
      await _runPhaseViaApi(log, roleConfig);
    } else {
      await _runPhaseViaCli(log, roleConfig);
    }
  }

  // ── URL/API 阶段执行 ──────────────────────────────────────────────────────

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

    // 阶段配置可覆盖服务商的默认模型 ID。
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
      final prompt = await _buildPhasePrompt(log.phase);
      if (_isDisposed) return;

      promptFile = await _writePromptFile(log.phase, prompt);
      if (_isDisposed) return;

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

      // 执行前记录工作目录快照。
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

        // API 返回成功后仍需验证阶段必需产物。
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
      // 避免模型令牌进入错误信息。
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

  // ── CLI 阶段执行 ─────────────────────────────────────────────────────────

  Future<void> _runPhaseViaCli(
    HarnessPhaseLog log,
    HarnessRoleConfig roleConfig,
  ) async {
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
      final prompt = await _buildPhasePrompt(log.phase);
      if (_isDisposed) return;

      promptFile = await _writePromptFile(log.phase, prompt);
      if (_isDisposed) return;

      // 支持认证探测的 CLI 在执行前重新确认登录状态。
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

      // 执行前记录工作目录快照。
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

      final exitCode = await _spawnAndCollect(
        cliCmd,
        workingDirectory: _config.workingDirectory,
        onLine: (line) {
          _appendLine(log, line);
          notifyListeners();
        },
      );

      if (_isDisposed) return;

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
        // 退出码为 0，但交互式认证提示表明任务并未执行。
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 在未完成认证的情况下退出（退出码 0），本阶段未产生有效产出。');
        _appendLine(
          log,
          '  → 请先在"设置 → CLI 登录"中完成 ${cliEntry.name} 的登录认证，再重试当前阶段。',
        );
        log.status = HarnessPhaseStatus.failed;
      } else if (_looksLikeHollowCliSession(log.lines)) {
        // 退出码为 0，但缺少有效输出，视为静默跳过。
        _appendLine(log, '');
        _appendLine(log, '✗ CLI 以退出码 0 结束，但未产生有效输出，本阶段执行可能未真正生效。');
        _appendLine(log, '  → 可能原因：认证已过期、配置异常或 CLI 静默跳过了任务。请检查 CLI 状态后重试。');
        log.status = HarnessPhaseStatus.failed;
        await _appendCliFailureDiagnostics(log, cliEntry.executable);
      } else {
        log.status = HarnessPhaseStatus.completed;

        // CLI 返回成功后仍需验证阶段必需产物。
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

  // ── 验收失败识别 ─────────────────────────────────────────────────────────

  /// 综合用户结论和 CLI 输出判断验收是否失败。
  bool _reviewIndicatesFailure(HarnessPhaseLog log) {
    final userVerdict = _userReviewVerdict;
    if (userVerdict != null) {
      _userReviewVerdict = null;
      return !userVerdict;
    }
    return _reviewOutputIndicatesFailure(log);
  }

  /// 跳过界面标记和人工输入，在有效输出前部识别 PASS/FAIL。
  bool _reviewOutputIndicatesFailure(HarnessPhaseLog log) {
    var meaningfulLineCount = 0;
    var insideManualInput = false;
    for (final line in log.lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.startsWith('▶ ') ||
          trimmed.startsWith('✓ ') ||
          trimmed.startsWith('✗ ') ||
          trimmed.startsWith('⚠ ') ||
          trimmed.startsWith('> ')) {
        if (trimmed.startsWith('> ')) {
          insideManualInput = false;
        }
        continue;
      }
      if (trimmed.startsWith('【') && trimmed.endsWith('】')) {
        insideManualInput = true;
        continue;
      }
      if (trimmed.startsWith('ℹ ')) {
        insideManualInput = false;
        continue;
      }
      if (insideManualInput) {
        continue;
      }
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
      meaningfulLineCount++;
      if (meaningfulLineCount >= 20) {
        return false;
      }
    }
    return false;
  }

  // ── 阶段配置映射 ─────────────────────────────────────────────────────────

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

  // ── 提示词构建 ───────────────────────────────────────────────────────────

  static final HarnessFileIoLimits _promptContextIoLimits = HarnessFileIoLimits(
    maxScannedFiles: 1024,
    maxTextFiles: 40,
    maxDirectoryEntries: 1024,
    maxFileBytes: 512 * kBytesPerKiB,
    maxTotalBytes: 4 * kBytesPerMiB,
    totalTimeout: const Duration(seconds: 5),
    operationTimeout: const Duration(seconds: 1),
  );
  static const int _maxLessonContextFiles = 32;
  static const int _maxLessonContextBytes = 1536 * kBytesPerKiB;

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

    // 优先加载计划和反馈，确保关键上下文先占用容量预算。
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
    // 将用户结论置于补充内容之前，避免验收含义不明确。
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
      ..writeln('> 遵循系统语言策略：所有输出使用简体中文，技术标识保留原文。')
      ..writeln()
      ..writeln('## 任务')
      ..writeln(config.task)
      ..writeln()
      ..writeln('## 工作目录')
      ..writeln(config.workingDirectory)
      ..writeln()
      ..writeln('## 运行时约束')
      ..writeln('1. 直接执行允许的操作；需要审批时使用运行时审批流程。')
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

  /// 返回当前阶段的目录权限约束。
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

    扫描 ${config.workingDirectory}，基于事实生成简体中文文档：
    - `$meta/architecture.md`：2–3 层目录树、入口与构建文件、语言/框架/测试工具、模块职责、外部依赖。
    - `$meta/conventions.md`：编码与命名风格、目录约定、可确认的构建/测试/Lint 命令、限制与易错点。

    必须调用 Write 分别写入以上绝对路径；不得臆测缺失信息。''',

      HarnessPhase.reading =>
        '''你是本任务的调查者/分析者（Reader/Analyst）。

    分析 ${config.workingDirectory} 并输出简体中文 Markdown 报告，覆盖：
    1. 对任务要求的精确拆解
    2. 需要创建或修改的具体文件与模块
    3. 每个相关文件的当前状态（准确概括关键实现）
    4. 潜在风险、副作用与外部依赖
    5. 推荐的实现路径及理由

    结论必须具体、可验证，供规划阶段直接使用。''',

      HarnessPhase.planning =>
        '''你是本任务的规划者（Planner）。

    ${_manualPhaseMissionAddendum(HarnessPhase.planning)}

    基于任务和分析上下文生成编号计划。每步必须：
    - 只包含一个可独立验证的改动；
    - 指明确切文件和验收标准；
    - 标注 `[simple | medium | complex]`。

    本阶段不得修改项目、生成代码或运行会改变项目状态的命令。唯一产物是 `$planDir/plan-$ts.md`；文件以任务描述开头并包含全部步骤。必须调用 Write 写入该绝对路径。''',

      HarnessPhase.implementing =>
        '''你是本任务的实施者（Implementer）。

    在 ${config.workingDirectory} 按执行计划逐项实施。遵守项目约定和经验教训；改动保持原子、限定于任务范围并逐项验证。

    完成后用简体中文简述改动及原因、计划偏离和新发现的风险。''',

      HarnessPhase.reviewing =>
        '''你是本任务的验收者（Reviewer）。

    仅依据原始需求、执行计划和当前工作区验收；不要依赖实施者的解释或结论。
    ${_reviewRetryCount > 0 ? '\n**注意**：第 $_reviewRetryCount 次重试，重点检查之前的问题是否修复。\n' : ''}
    ${_manualPhaseMissionAddendum(HarnessPhase.reviewing)}

    逐项验证：
    1. 所有计划步骤已完成且满足验收标准
    2. 无回归问题（如可行，运行相关测试）
    3. 代码质量符合项目约定
    4. 边界与错误处理得当
    5. 无明显安全风险

    首行输出 **PASS** 或 **FAIL**，随后列出证据和问题。必须调用 Write 将完整报告写入 `$feedbackDir/feedback-$ts.md`。''',
    };
  }

  // ── CLI 命令构建 ─────────────────────────────────────────────────────────

  /// 构建 POSIX Shell 命令；不支持无交互模式时返回空值。
  String? _buildCliCommandStr(
    String executable,
    String modelId,
    String promptFilePath,
  ) {
    final quotedPath = posixShellQuote(promptFilePath);
    // 双引号阻止 Shell 展开提示词内容时发生分词。
    final promptSubst = '"\$(cat $quotedPath)"';
    final modelFlag = modelId.isNotEmpty
        ? ' --model ${posixShellQuote(modelId)}'
        : '';
    final modelFlagShort = modelId.isNotEmpty
        ? ' -m ${posixShellQuote(modelId)}'
        : '';
    final quotedWd = posixShellQuote(config.workingDirectory);
    final geminiIncludeDirectoriesFlags = _buildGeminiIncludeDirectoriesFlags();

    return switch (executable) {
      'claude' => 'claude$modelFlag -p $promptSubst',
      // Codex 使用完全自动模式，并显式传入项目目录和提示词。
      'codex' =>
        'codex exec$modelFlag --skip-git-repo-check --full-auto -C $quotedWd -- $promptSubst',
      'aider' =>
        'aider$modelFlag --message $promptSubst --yes --no-auto-commits',
      // Harness 已在阶段边界完成审批，Gemini 会话可直接授权并补充外部目录。
      'gemini' =>
        'gemini$modelFlagShort --approval-mode yolo$geminiIncludeDirectoriesFlags -p $promptSubst',
      'goose' => 'goose run$modelFlag --text $promptSubst',
      'q' => 'q chat --no-interactive $promptSubst',
      'amp' => 'amp$modelFlag $promptSubst',
      'plandex' => 'plandex tell -f $quotedPath',
      // 图形化 IDE 不支持无界面调用。
      'cursor' || 'windsurf' || 'kiro' => null,
      // 未知 CLI 尝试通用的 -p 参数。
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

    return ' --include-directories ${posixShellQuote(normalizedPersistenceDirectory)}';
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
    final quotedWd = posixShellQuote(workingDirectory);
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
                gracefulTimeout: _kHarnessProcessStopTimeout,
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

  // ── 认证中断与空执行识别 ─────────────────────────────────────────────────

  /// 识别 CLI 因认证失效进入交互提示后未执行任务便正常退出的情况。
  bool _looksLikeCliAuthInterrupt(List<String> lines) {
    final joined = lines.join('\n').toLowerCase();
    // Gemini CLI 认证提示。
    if (joined.contains('opening authentication page') ||
        joined.contains('authenticate with google') ||
        joined.contains('please authenticate') ||
        joined.contains('authorization required')) {
      return true;
    }
    // Claude Code 认证提示。
    if (joined.contains('please sign in') ||
        joined.contains('you need to authenticate') ||
        joined.contains('login required')) {
      return true;
    }
    // Codex/OpenAI 认证提示。
    if (joined.contains('not logged in') ||
        joined.contains('authentication is required') ||
        (joined.contains('log in') && joined.contains('continue'))) {
      return true;
    }
    // 各类 CLI 的通用认证提示。
    if (joined.contains('do you want to continue? [y/n]') &&
        joined.contains('authentication')) {
      return true;
    }
    return false;
  }

  /// 识别退出码为 0 但没有有效输出的空执行。
  bool _looksLikeHollowCliSession(List<String> lines) {
    var substantiveLineCount = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
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
    // 正常阶段应至少产生三行有效输出。
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
        if (promptFile != null) {
          await deletePathBounded(
            p.absolute(promptFile.path),
            policy: _kHarnessPromptDeletePolicy,
            allowedRoot: p.absolute(promptFile.parent.path),
          );
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
      log.lines.insert(0, _kHarnessLogTruncationMarker);
    }
    log.lines.add(
      clipTextByCodeUnitsWithEllipsis(line, _kMaxHarnessLogLineCharacters),
    );
  }

  /// 检查阶段必需产物，返回缺失文件路径。
  ///
  /// 无必需产物的阅读和实施阶段始终返回空列表。
  Future<List<String>> _checkMandatoryArtifacts(HarnessPhase phase) async {
    final steeringDir = p.join(config.persistenceDirectory, 'steering');
    final missing = <String>[];

    switch (phase) {
      case HarnessPhase.metaCollection:
        final archPath = p.join(steeringDir, 'meta', 'architecture.md');
        final convPath = p.join(steeringDir, 'meta', 'conventions.md');
        if (!await isRegularFilePath(archPath)) {
          missing.add(archPath);
        }
        if (!await isRegularFilePath(convPath)) {
          missing.add(convPath);
        }
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
        break;
    }
    return missing;
  }

  Future<bool> _containsMarkdownArtifact(Directory directory) async {
    if (!await isDirectoryPath(directory.path)) {
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

  // ── 文件变更跟踪 ─────────────────────────────────────────────────────────

  /// 工作目录快照忽略的构建产物和版本控制目录。
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

  /// 单个差异文件最多保留 1 MiB。
  static const int _maxDiffFileSize = kBytesPerMiB;

  static final HarnessFileIoLimits _snapshotIoLimits = HarnessFileIoLimits(
    maxScannedFiles: 5000,
    maxTextFiles: 5000,
    maxDirectoryEntries: 10000,
    maxFileBytes: _maxDiffFileSize,
    maxTotalBytes: 16 * kBytesPerMiB,
    totalTimeout: const Duration(seconds: 12),
    operationTimeout: const Duration(seconds: 2),
  );

  /// 在容量和时限内获取工作目录快照。
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
    final result = _computeChangedFiles(before.files, after.files);
    log.changedFiles = result.files;
    if (result.omittedFiles > 0) {
      _appendLine(log, '⚠ 文件变动过多，已省略 ${result.omittedFiles} 个文件的差异明细。');
    }
    if (result.contentTruncated) {
      _appendLine(log, '⚠ 文件差异内容达到安全上限，界面仅展示保留部分。');
    }
  }

  ({List<HarnessChangedFile> files, int omittedFiles, bool contentTruncated})
  _computeChangedFiles(
    Map<String, HarnessFileSnapshot> before,
    Map<String, HarnessFileSnapshot> after,
  ) {
    final changes = <HarnessChangedFile>[];

    // 新增或修改的文件。
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
            contentTruncated: post.content == null && post.size > 0,
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
            contentTruncated:
                pre.content == null && pre.size > 0 ||
                post.content == null && post.size > 0,
          ),
        );
      }
    }

    // 删除的文件。
    for (final rel in before.keys) {
      if (!after.containsKey(rel)) {
        changes.add(
          HarnessChangedFile(
            relativePath: rel,
            absolutePath: p.join(_config.workingDirectory, rel),
            changeType: HarnessFileChangeType.deleted,
            beforeContent: before[rel]!.content,
            contentTruncated:
                before[rel]!.content == null && before[rel]!.size > 0,
          ),
        );
      }
    }

    changes.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final retainedCount = changes.length < _kMaxHarnessChangedFiles
        ? changes.length
        : _kMaxHarnessChangedFiles;
    var remainingCharacters = _kMaxHarnessDiffTotalCharacters;
    var anyContentTruncated = false;
    final retained = <HarnessChangedFile>[];
    for (var index = 0; index < retainedCount; index++) {
      final change = changes[index];
      var fileContentTruncated = change.contentTruncated;
      String? retainContent(String? value) {
        if (value == null || value.isEmpty) return value;
        final limit = remainingCharacters < _kMaxHarnessDiffSideCharacters
            ? remainingCharacters
            : _kMaxHarnessDiffSideCharacters;
        if (limit <= 0) {
          fileContentTruncated = true;
          return null;
        }
        final retainedValue = clipTextByCodeUnits(value, limit, suffix: '');
        remainingCharacters -= retainedValue.length;
        if (retainedValue.length < value.length) {
          fileContentTruncated = true;
        }
        return retainedValue;
      }

      final beforeContent = retainContent(change.beforeContent);
      final afterContent = retainContent(change.afterContent);
      anyContentTruncated |= fileContentTruncated;
      retained.add(
        HarnessChangedFile(
          relativePath: change.relativePath,
          absolutePath: change.absolutePath,
          changeType: change.changeType,
          beforeContent: beforeContent,
          afterContent: afterContent,
          contentTruncated: fileContentTruncated,
        ),
      );
    }
    return (
      files: retained,
      omittedFiles: changes.length - retainedCount,
      contentTruncated: anyContentTruncated,
    );
  }
}
