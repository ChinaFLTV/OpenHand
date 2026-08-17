import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import '../../app/support/openhand_paths.dart';
import '../../app/support/silent_log.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/bounded_text_buffer.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/storage_identifier.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';

const String kMachineExpertTemplateId = 'machine_expert';
const String kMachineTerminalMetadataKey = 'machine_terminal';
const int kMachineTerminalMetadataSchemaVersion = 2;
const Duration kMachineTerminalDefaultCommandTimeout = Duration(seconds: 120);
const int kMachineTerminalMinCommandTimeoutMs = 1000;
const int kMachineTerminalMaxCommandTimeoutMs = 600000;

int clampMachineTerminalCommandTimeoutMs(int value) {
  if (value < kMachineTerminalMinCommandTimeoutMs) {
    return kMachineTerminalMinCommandTimeoutMs;
  }
  if (value > kMachineTerminalMaxCommandTimeoutMs) {
    return kMachineTerminalMaxCommandTimeoutMs;
  }
  return value;
}

const int _defaultRows = 30;
const int _defaultColumns = 100;
const int _maxRows = 240;
const int _maxColumns = 400;
const int _scrollbackLines = 5000;
const int _maxRetainedOutputCharacters = 240000;
const int _maxRetainedHistoryCharacters = 480000;
const int _maxToolOutputCharacters = 120000;
const int _maxReplayOutputCharacters = _maxRetainedHistoryCharacters;
const int _maxCommandHistoryEntries = 80;
const int _maxCommandHistoryCommandCharacters = 16000;
const int _maxCommandHistoryOutputCharacters = 40000;
const int _maxCommandHistoryErrorCharacters = 4000;
const int _maxCommandHistoryRetainedCharacters = 480000;
const int _maxRestoredCommandSequence = 0x7fffffff;
const int _maxPersistedTerminalSnapshots = 48;
const int _maxTerminalSessionsPerWorkspace = _maxPersistedTerminalSnapshots;
const Duration _commandPollInterval = Duration(milliseconds: 80);
const Duration _commandInterruptSettleDelay = Duration(milliseconds: 80);
const Duration _commandRecoveryTimeout = Duration(seconds: 1);
const Duration _metadataPersistDebounce = Duration(milliseconds: 700);
const Duration _historyPersistDebounce = Duration(milliseconds: 650);
const Duration _terminalStopGraceDuration = Duration(milliseconds: 900);
const Duration _terminalForceStopWaitDuration = Duration(milliseconds: 500);
const Duration _terminalFilesystemProbeTimeout = Duration(seconds: 3);
const Duration _workspaceLoadQueueTimeout = Duration(seconds: 15);
const int _maxConcurrentWorkspaceLoads = 4;
const int _maxPendingWorkspaceLoads = 32;
const int _maxTerminalWorkspaces = 32;
const int _shutdownConcurrency = 4;
const Duration _shutdownStepTimeout = Duration(milliseconds: 1500);
const String _machineTerminalSurface = 'openhand_machine_terminal';
const String _machineTerminalWorkflow = 'builtin_terminal_panel';
const String _machineTerminalWorkspacePrefix = 'machine-terminal';
const String _machineTerminalHistoryFileName = 'machine-terminal-history.json';
const String _terminalOutputFailureMessage = '终端输出通道异常，请重新启动终端。';
const String _terminalExitFailureMessage = '无法读取终端退出状态，请重新启动终端。';
const String _terminalStartFailureMessage = '终端启动失败，请检查 Shell 路径和工作目录。';
const String _terminalRestoredFailureMessage = '上次终端运行异常，请重新启动终端。';
const int _machineTerminalHistoryStorageSchemaVersion = 2;
const int _machineTerminalHistoryMaxBytes = 32 * kBytesPerMiB;
const int _machineTerminalHistoryPayloadReserveBytes = 64 * kBytesPerKiB;
const String _terminalBusyError = '已有其他终端命令正在运行。';
const String _terminalNotRunningError = '终端未运行。';
const int _terminalUploadChunkBytes = 48 * kBytesPerKiB;
const int _terminalPtyWriteChunkBytes = 64;
const Duration _terminalPtyWritePace = Duration(milliseconds: 1);
const Duration _terminalUploadReadyTimeout = Duration(seconds: 10);
const Duration _terminalUploadFinalizeTimeout = Duration(minutes: 2);
const Duration _terminalEchoReadyTimeout = Duration(seconds: 3);

typedef MachineTerminalUploadProgress = void Function(int transferredBytes);
typedef MachineTerminalUploadPauseWaiter = Future<void> Function();
typedef MachineTerminalUploadCancelCheck = bool Function();

final class MachineTerminalUploadCancelled implements Exception {
  const MachineTerminalUploadCancelled();

  @override
  String toString() => '文件传输已取消。';
}

typedef MachineTerminalMetadataPersister =
    Future<void> Function(String sessionId, Map<String, Object?> metadata);

enum MachineTerminalStatus { idle, starting, running, stopped, failed }

extension MachineTerminalStatusJson on MachineTerminalStatus {
  String get storageValue => switch (this) {
    MachineTerminalStatus.idle => 'idle',
    MachineTerminalStatus.starting => 'starting',
    MachineTerminalStatus.running => 'running',
    MachineTerminalStatus.stopped => 'stopped',
    MachineTerminalStatus.failed => 'failed',
  };
}

class MachineTerminalCommandResult {
  const MachineTerminalCommandResult({
    required this.terminalId,
    required this.command,
    required this.output,
    required this.status,
    required this.durationMs,
    this.exitCode,
    this.timedOut = false,
    this.error,
  });

  final String terminalId;
  final String command;
  final String output;
  final int? exitCode;
  final MachineTerminalStatus status;
  final int durationMs;
  final bool timedOut;
  final String? error;

  bool get succeeded => !timedOut && error == null && exitCode == 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'terminal_id': terminalId,
      'command': command,
      'output': output,
      'exit_code': exitCode,
      'status': status.storageValue,
      'duration_ms': durationMs,
      'timed_out': timedOut,
      if (error != null) 'error': error,
    };
  }

  String toToolOutput() {
    final buffer = StringBuffer()
      ..writeln('terminal_id: $terminalId')
      ..writeln('status: ${status.storageValue}')
      ..writeln('timed_out: $timedOut')
      ..writeln('exit_code: ${exitCode ?? ''}')
      ..writeln('duration_ms: $durationMs');
    if (error != null && error!.trim().isNotEmpty) {
      buffer.writeln('error: ${error!.trim()}');
    }
    buffer
      ..writeln('output:')
      ..write(output.trimRight());
    return buffer.toString().trimRight();
  }
}

class MachineTerminalCommandRecord {
  const MachineTerminalCommandRecord({
    required this.id,
    required this.terminalId,
    required this.command,
    required this.output,
    required this.startedAt,
    required this.completedAt,
    required this.durationMs,
    this.exitCode,
    this.timedOut = false,
    this.error,
  });

  final String id;
  final String terminalId;
  final String command;
  final String output;
  final DateTime startedAt;
  final DateTime completedAt;
  final int durationMs;
  final int? exitCode;
  final bool timedOut;
  final String? error;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'terminal_id': terminalId,
      'command': _clipString(command, _maxCommandHistoryCommandCharacters),
      'output': _clipString(output, _maxCommandHistoryOutputCharacters),
      'exit_code': exitCode,
      'timed_out': timedOut,
      'duration_ms': durationMs,
      'started_at': startedAt.toUtc().toIso8601String(),
      'completed_at': completedAt.toUtc().toIso8601String(),
      if (error != null)
        'error': _clipString(error!, _maxCommandHistoryErrorCharacters),
    };
  }

  static MachineTerminalCommandRecord? fromJson(
    Object? value, {
    required String fallbackTerminalId,
    String fallbackRecordId = 'cmd-restored',
  }) {
    final raw = stringKeyedMapFromValue(value);
    final command = '${raw['command'] ?? ''}';
    if (raw.isEmpty || command.trim().isEmpty) return null;
    final rawRecordId = nullIfBlank('${raw['id'] ?? ''}');
    final now = DateTime.now();
    final startedAt = utcDateTimeFromValue(raw['started_at'])?.toLocal() ?? now;
    final restoredCompletedAt =
        utcDateTimeFromValue(raw['completed_at'])?.toLocal() ?? startedAt;
    final completedAt = restoredCompletedAt.isBefore(startedAt)
        ? startedAt
        : restoredCompletedAt;
    return MachineTerminalCommandRecord(
      id: rawRecordId != null && isSafeStorageIdentifier(rawRecordId)
          ? rawRecordId
          : fallbackRecordId,
      terminalId: fallbackTerminalId,
      command: _clipString(command, _maxCommandHistoryCommandCharacters),
      output: _clipString(
        '${raw['output'] ?? ''}',
        _maxCommandHistoryOutputCharacters,
      ),
      startedAt: startedAt,
      completedAt: completedAt,
      durationMs: math.max(0, optionalIntFromValue(raw['duration_ms']) ?? 0),
      exitCode: optionalIntFromValue(raw['exit_code']),
      timedOut: boolFromValue(raw['timed_out']),
      error: _clipNullableString(
        nullIfBlank('${raw['error'] ?? ''}'),
        _maxCommandHistoryErrorCharacters,
      ),
    );
  }
}

class MachineTerminalSnapshot {
  const MachineTerminalSnapshot({
    required this.sessionId,
    required this.terminalId,
    required this.identity,
    required this.status,
    required this.shell,
    required this.workingDirectory,
    required this.rows,
    required this.columns,
    required this.output,
    required this.ansiOutput,
    required this.outputCharacters,
    required this.historyOutput,
    required this.historyAnsiOutput,
    required this.historyOutputCharacters,
    required this.commandCount,
    required this.commandHistory,
    required this.startedAt,
    required this.updatedAt,
    required this.attached,
    required this.hasUserActivity,
    this.pid,
    this.exitCode,
    this.errorMessage,
  });

  final String sessionId;
  final String terminalId;
  final String identity;
  final MachineTerminalStatus status;
  final String shell;
  final String workingDirectory;
  final int rows;
  final int columns;
  final String output;
  final String ansiOutput;
  final int outputCharacters;
  final String historyOutput;
  final String historyAnsiOutput;
  final int historyOutputCharacters;
  final int commandCount;
  final List<MachineTerminalCommandRecord> commandHistory;
  final DateTime startedAt;
  final DateTime updatedAt;
  final bool attached;
  final bool hasUserActivity;
  final int? pid;
  final int? exitCode;
  final String? errorMessage;

  Map<String, Object?> toJson({bool includeHistory = true}) {
    return <String, Object?>{
      'session_id': sessionId,
      'terminal_id': terminalId,
      'identity': identity,
      'status': status.storageValue,
      'shell': shell,
      'working_directory': workingDirectory,
      'rows': rows,
      'columns': columns,
      'output': output,
      'ansi_output': ansiOutput,
      'output_characters': outputCharacters,
      'history_output_characters': historyOutputCharacters,
      'command_count': commandCount,
      'attached': attached,
      'has_user_activity': hasUserActivity,
      if (includeHistory) ...<String, Object?>{
        'history_output': historyOutput,
        'history_ansi_output': historyAnsiOutput,
        'command_history': commandHistory.map((item) => item.toJson()).toList(),
      },
      'started_at': startedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      if (pid != null) 'pid': pid,
      if (exitCode != null) 'exit_code': exitCode,
      if (errorMessage != null) 'error_message': errorMessage,
    };
  }

  Map<String, Object?> _toPersistenceJson() {
    final persistentAnsiOutput = _clipString(
      historyAnsiOutput,
      _maxToolOutputCharacters,
    );
    return toJson()
      ..['ansi_output'] = persistentAnsiOutput
      ..['output_characters'] = persistentAnsiOutput.length
      ..remove('output')
      ..remove('history_output');
  }

  Map<String, Object?> toMetadataJson() {
    return <String, Object?>{
      'terminal_id': terminalId,
      'identity': identity,
      'status': status.storageValue,
      'shell': shell,
      'working_directory': workingDirectory,
      'rows': rows,
      'columns': columns,
      'output_characters': outputCharacters,
      'history_output_characters': historyOutputCharacters,
      'command_count': commandCount,
      'attached': attached,
      'has_user_activity': hasUserActivity,
      'started_at': startedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      if (pid != null) 'pid': pid,
      if (exitCode != null) 'exit_code': exitCode,
      if (errorMessage != null) 'error_message': errorMessage,
    };
  }
}

class MachineTerminalWorkspaceSnapshot {
  const MachineTerminalWorkspaceSnapshot({
    required this.sessionId,
    required this.activeTerminalId,
    required this.terminals,
  });

  final String sessionId;
  final String activeTerminalId;
  final List<MachineTerminalSnapshot> terminals;

  MachineTerminalSnapshot? get activeTerminal {
    for (final terminal in terminals) {
      if (terminal.attached && terminal.terminalId == activeTerminalId) {
        return terminal;
      }
    }
    for (final terminal in terminals) {
      if (terminal.attached) return terminal;
    }
    return null;
  }

  List<MachineTerminalSnapshot> get attachedTerminals =>
      terminals.where((terminal) => terminal.attached).toList(growable: false);

  Map<String, Object?> toJson({bool includeHistory = true}) {
    return <String, Object?>{
      'session_id': sessionId,
      'active_terminal_id': activeTerminalId,
      'terminals': terminals
          .map((item) => item.toJson(includeHistory: includeHistory))
          .toList(),
      'active_terminal': activeTerminal?.toJson(includeHistory: includeHistory),
    };
  }
}

abstract final class MachineTerminalSessionMetadata {
  static const List<String> toolNames = <String>[
    'MachineTerminalRead',
    'MachineTerminalWrite',
    'MachineTerminalExec',
    'MachineTerminalControl',
  ];

  static Map<String, Object?> normalize({
    required String sessionId,
    String? workingDirectory,
    MachineTerminalWorkspaceSnapshot? snapshot,
    Object? existingMetadata,
  }) {
    final raw = stringKeyedMapFromValue(existingMetadata);
    final timestamp = DateTime.now().toUtc();
    final createdAt = createdAtFrom(raw) ?? timestamp.toIso8601String();
    final resolvedWorkingDirectory = _normalizedWorkingDirectory(
      nullIfBlank(workingDirectory) ??
          defaultWorkingDirectoryFrom(raw) ??
          snapshot?.activeTerminal?.workingDirectory ??
          OpenHandPaths.applicationDirectoryPath(),
    );
    final activeTerminal = snapshot?.activeTerminal;
    final activeTerminalId =
        nullIfBlank(snapshot?.activeTerminalId) ??
        activeTerminalIdFrom(raw) ??
        activeTerminal?.terminalId ??
        '';
    final shell = activeTerminal?.shell ?? _resolveShellExecutable();
    final runtime = <String, Object?>{
      'status':
          activeTerminal?.status.storageValue ??
          MachineTerminalStatus.idle.storageValue,
      'terminal_count': snapshot?.terminals.length ?? 0,
      'active_terminal_id': activeTerminalId,
      'active_terminal': activeTerminal?.toMetadataJson(),
      'terminals':
          snapshot?.terminals
              .map((terminal) => terminal.toMetadataJson())
              .toList(growable: false) ??
          const <Object?>[],
    };
    return <String, Object?>{
      'schema_version': kMachineTerminalMetadataSchemaVersion,
      'template_id': kMachineExpertTemplateId,
      'surface': _machineTerminalSurface,
      'workflow': _machineTerminalWorkflow,
      'session_id': sessionId.trim(),
      'terminal_workspace_id':
          '$_machineTerminalWorkspacePrefix:${sessionId.trim()}',
      'active_terminal_id': activeTerminalId,
      'default_working_directory': resolvedWorkingDirectory,
      'created_at': createdAt,
      'updated_at': timestamp.toIso8601String(),
      'terminal_defaults': <String, Object?>{
        'shell': shell,
        'rows': _defaultRows,
        'columns': _defaultColumns,
        'max_rows': _maxRows,
        'max_columns': _maxColumns,
        'scrollback_lines': _scrollbackLines,
        'command_timeout_ms':
            kMachineTerminalDefaultCommandTimeout.inMilliseconds,
        'command_poll_interval_ms': _commandPollInterval.inMilliseconds,
        'max_retained_output_characters': _maxRetainedOutputCharacters,
        'max_tool_output_characters': _maxToolOutputCharacters,
      },
      'capabilities': const <String, Object?>{
        'read': true,
        'write': true,
        'execute': true,
        'control': true,
        'resize': true,
        'multiple_terminals': true,
        'duplicate_terminal': true,
        'interactive_input': true,
        'ansi_output': true,
        'shell_completion': true,
        'formatted_command_output': true,
        'marker_isolated_exec': true,
        'close_preserves_history': true,
        'terminal_history': true,
        'terminal_replay': true,
        'restore_terminal_history': true,
        'delete_terminal_history': true,
        'status_inspection': true,
        'environment_metadata': true,
        'native_keybindings': true,
        'smooth_auto_scroll': true,
      },
      'ui': const <String, Object?>{
        'panel': 'left_workspace_terminal',
        'auto_scroll_to_bottom': true,
        'terminal_tabs': true,
        'terminal_history_dialog': true,
        'terminal_replay_dialog': true,
        'status_bar': true,
        'metadata_bar': true,
      },
      'tool_names': toolNames,
      'runtime': runtime,
    };
  }

  static String? createdAtFrom(Object? metadata) {
    final raw = stringKeyedMapFromValue(metadata);
    return _isoTimeFromValue(raw['created_at']);
  }

  static String? activeTerminalIdFrom(Object? metadata) {
    final raw = stringKeyedMapFromValue(metadata);
    final runtime = stringKeyedMapFromValue(raw['runtime']);
    final active = stringKeyedMapFromValue(runtime['active_terminal']);
    return nullIfBlank('${raw['active_terminal_id'] ?? ''}') ??
        nullIfBlank('${runtime['active_terminal_id'] ?? ''}') ??
        nullIfBlank('${active['terminal_id'] ?? ''}');
  }

  static String? defaultWorkingDirectoryFrom(Object? metadata) {
    final raw = stringKeyedMapFromValue(metadata);
    final defaults = stringKeyedMapFromValue(raw['terminal_defaults']);
    return nullIfBlank('${raw['default_working_directory'] ?? ''}') ??
        nullIfBlank('${raw['working_directory'] ?? ''}') ??
        nullIfBlank('${defaults['working_directory'] ?? ''}');
  }
}

class MachineTerminalService extends ChangeNotifier {
  MachineTerminalService({String? sessionsDirectoryPath})
    : _sessionsDirectoryPath =
          sessionsDirectoryPath ?? OpenHandPaths.defaultSessionsDirectoryPath();

  static const Duration runtimeCleanupTimeout = Duration(seconds: 10);

  final String _sessionsDirectoryPath;
  final Map<String, _MachineTerminalWorkspace> _workspaces =
      <String, _MachineTerminalWorkspace>{};
  final Map<String, Future<_MachineTerminalWorkspace>> _workspaceLoads =
      <String, Future<_MachineTerminalWorkspace>>{};
  final Map<String, Future<void>> _workspaceDisposals =
      <String, Future<void>>{};
  final Map<String, int> _workspaceLoadGenerations = <String, int>{};
  final Map<String, String> _metadataCreatedAtBySession = <String, String>{};
  final Map<String, String> _metadataWorkingDirectoryBySession =
      <String, String>{};
  final Map<String, String> _lastPersistedMetadataDigestBySession =
      <String, String>{};
  final Map<String, Timer> _metadataPersistTimers = <String, Timer>{};
  final Map<String, Future<void>> _metadataPersistChains =
      <String, Future<void>>{};
  final Map<String, Timer> _historyPersistTimers = <String, Timer>{};
  final Map<String, Future<void>> _historyPersistChains =
      <String, Future<void>>{};
  final Map<String, String> _lastPersistedHistoryDigestBySession =
      <String, String>{};
  final OpenHandAsyncSemaphore _workspaceLoadSemaphore = OpenHandAsyncSemaphore(
    _maxConcurrentWorkspaceLoads,
    maxWaiters: _maxPendingWorkspaceLoads,
  );
  Future<void>? _shutdownFuture;

  int _terminalCounter = 0;
  int _commandCounter = 0;
  bool _isDisposed = false;
  bool _notifierDisposed = false;
  bool _notificationScheduled = false;
  MachineTerminalMetadataPersister? _metadataPersister;

  String get sessionsDirectoryPath => _sessionsDirectoryPath;

  void configureMetadataPersister(MachineTerminalMetadataPersister? persister) {
    _metadataPersister = persister;
  }

  void rememberSessionMetadata({required String sessionId, Object? metadata}) {
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null) return;
    final createdAt = MachineTerminalSessionMetadata.createdAtFrom(metadata);
    if (createdAt != null) {
      _metadataCreatedAtBySession[normalizedSessionId] = createdAt;
    }
    final workingDirectory =
        MachineTerminalSessionMetadata.defaultWorkingDirectoryFrom(metadata);
    if (workingDirectory != null) {
      _metadataWorkingDirectoryBySession[normalizedSessionId] =
          _normalizedWorkingDirectory(workingDirectory);
    }
  }

  Future<MachineTerminalWorkspaceSnapshot> ensureWorkspace({
    required String sessionId,
    String? workingDirectory,
    bool start = true,
  }) async {
    final normalizedSessionId = _normalizeSessionId(sessionId);
    final isNewWorkspace = !_workspaces.containsKey(normalizedSessionId);
    final workspace = await _workspaceFor(
      sessionId: normalizedSessionId,
      workingDirectory: workingDirectory,
    );
    if (_isDisposed) {
      throw StateError('终端服务已关闭。');
    }
    if (start) {
      final active = workspace.activeTerminal;
      if (active != null && !active.isRunningOrStarting) {
        unawaited(
          active
              .start()
              .whenComplete(() => _scheduleMetadataPersist(workspace.sessionId))
              .catchError((Object error, StackTrace stack) {
                silentLog('machine_terminal', '自动启动终端', error, stack);
              }),
        );
      }
    }
    if (start && isNewWorkspace) {
      _scheduleMetadataPersist(workspace.sessionId);
      _scheduleHistoryPersist(workspace.sessionId);
    }
    return workspace.snapshot();
  }

  MachineTerminalWorkspaceSnapshot? snapshot(String sessionId) {
    return _workspaces[sessionId.trim()]?.snapshot();
  }

  MachineTerminalSession? activeTerminal(String sessionId) {
    return _workspaces[sessionId.trim()]?.activeTerminal;
  }

  Future<void> disposeWorkspace(String sessionId) {
    if (nullIfBlank(sessionId) == null) return Future<void>.value();
    final normalizedSessionId = _normalizeSessionId(sessionId);
    final active = _workspaceDisposals[normalizedSessionId];
    if (active != null) return active;
    if (_isDisposed) return _shutdownFuture ?? Future<void>.value();

    late final Future<void> tracked;
    tracked = _disposeWorkspace(normalizedSessionId).whenComplete(() {
      if (identical(_workspaceDisposals[normalizedSessionId], tracked)) {
        _workspaceDisposals.remove(normalizedSessionId);
      }
      if (!_workspaceLoads.containsKey(normalizedSessionId)) {
        _workspaceLoadGenerations.remove(normalizedSessionId);
      }
    });
    _workspaceDisposals[normalizedSessionId] = tracked;
    return tracked;
  }

  Future<void> _disposeWorkspace(String normalizedSessionId) async {
    _workspaceLoadGenerations[normalizedSessionId] =
        (_workspaceLoadGenerations[normalizedSessionId] ?? 0) + 1;
    _metadataPersistTimers.remove(normalizedSessionId)?.cancel();
    final pendingMetadataPersist = _metadataPersistChains.remove(
      normalizedSessionId,
    );
    _historyPersistTimers.remove(normalizedSessionId)?.cancel();
    final pendingHistoryPersist = _historyPersistChains.remove(
      normalizedSessionId,
    );
    for (final pending in <Future<void>>[
      if (pendingMetadataPersist != null) pendingMetadataPersist,
      if (pendingHistoryPersist != null) pendingHistoryPersist,
    ]) {
      await runAsyncCleanupBounded(
        () => pending,
        timeout: _shutdownStepTimeout,
        onError: (error, stack) =>
            silentLog('machine_terminal', '释放工作区持久化任务', error, stack),
      );
    }
    _lastPersistedMetadataDigestBySession.remove(normalizedSessionId);
    _lastPersistedHistoryDigestBySession.remove(normalizedSessionId);
    _metadataCreatedAtBySession.remove(normalizedSessionId);
    _metadataWorkingDirectoryBySession.remove(normalizedSessionId);
    final workspace = _workspaces.remove(normalizedSessionId);
    if (workspace != null) {
      await runAsyncCleanupBounded(
        workspace.shutdown,
        timeout: _shutdownStepTimeout,
        onError: (error, stack) =>
            silentLog('machine_terminal', '释放工作区终端', error, stack),
      );
      workspace.dispose();
    }
    await _deleteWorkspaceHistoryFile(normalizedSessionId);
    _notifyListenersSafely();
  }

  Future<MachineTerminalSession> newTerminal({
    required String sessionId,
    String? workingDirectory,
    bool start = true,
  }) async {
    final workspace = await _workspaceFor(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
    );
    final terminal = _createTerminal(
      sessionId: workspace.sessionId,
      workingDirectory:
          nullIfBlank(workingDirectory) ?? workspace.defaultWorkingDirectory,
    );
    try {
      workspace.add(terminal);
    } catch (_) {
      terminal.dispose();
      rethrow;
    }
    _notifyListenersSafely();
    if (start) {
      _startTerminalSoon(terminal);
    }
    _scheduleMetadataPersist(workspace.sessionId);
    _scheduleHistoryPersist(workspace.sessionId);
    return terminal;
  }

  Future<MachineTerminalSession> duplicateTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final workspace = await _requireWorkspace(sessionId);
    final source =
        workspace.terminalById(terminalId) ?? workspace.activeTerminal;
    return newTerminal(
      sessionId: workspace.sessionId,
      workingDirectory:
          source?.workingDirectory ?? workspace.defaultWorkingDirectory,
    );
  }

  Future<void> selectTerminal({
    required String sessionId,
    required String terminalId,
  }) async {
    final workspace = await _requireWorkspace(sessionId);
    workspace.select(terminalId);
    _scheduleMetadataPersist(workspace.sessionId);
    _scheduleHistoryPersist(workspace.sessionId);
    _notifyListenersSafely();
  }

  Future<void> closeTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final workspace = await _requireWorkspace(sessionId);
    final terminal =
        workspace.terminalById(terminalId) ?? workspace.activeTerminal;
    if (terminal == null) return;
    await terminal.stop(force: true);
    if (terminal.shouldRetainOnClose) {
      workspace.detach(terminal.id);
    } else {
      workspace.remove(terminal.id);
    }
    if (workspace.attachedTerminals.isEmpty) {
      workspace.add(
        _createTerminal(
          sessionId: workspace.sessionId,
          workingDirectory: workspace.defaultWorkingDirectory,
        ),
      );
    }
    _scheduleMetadataPersist(workspace.sessionId);
    _scheduleHistoryPersist(workspace.sessionId);
    _notifyListenersSafely();
  }

  Future<void> restoreTerminal({
    required String sessionId,
    required String terminalId,
    bool start = true,
  }) async {
    final workspace = await _requireWorkspace(sessionId);
    final terminal = workspace.terminalById(terminalId, includeDetached: true);
    if (terminal == null) {
      throw StateError('未找到终端：$terminalId。');
    }
    workspace.restore(terminal.id);
    if (start && !terminal.isRunningOrStarting) {
      await terminal.start();
    }
    _scheduleMetadataPersist(workspace.sessionId);
    _scheduleHistoryPersist(workspace.sessionId);
    _notifyListenersSafely();
  }

  Future<void> deleteTerminal({
    required String sessionId,
    required String terminalId,
  }) async {
    final workspace = await _requireWorkspace(sessionId);
    final terminal = workspace.terminalById(terminalId, includeDetached: true);
    if (terminal == null) return;
    await terminal.stop(force: true);
    workspace.remove(terminal.id);
    if (workspace.attachedTerminals.isEmpty) {
      workspace.add(
        _createTerminal(
          sessionId: workspace.sessionId,
          workingDirectory: workspace.defaultWorkingDirectory,
        ),
      );
    }
    _scheduleMetadataPersist(workspace.sessionId);
    _scheduleHistoryPersist(workspace.sessionId);
    _notifyListenersSafely();
  }

  Future<void> startTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    await terminal.start();
    _scheduleMetadataPersist(terminal.sessionId);
    _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<void> stopTerminal({
    required String sessionId,
    String? terminalId,
    bool force = false,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    await terminal.stop(force: force);
    _scheduleMetadataPersist(terminal.sessionId);
    _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<void> restartTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    await terminal.restart();
    _scheduleMetadataPersist(terminal.sessionId);
    _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<void> clearTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    terminal.clear();
    _scheduleMetadataPersist(terminal.sessionId);
    _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<void> resizeTerminal({
    required String sessionId,
    String? terminalId,
    required int columns,
    required int rows,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    terminal.resize(columns: columns, rows: rows);
    _scheduleMetadataPersist(terminal.sessionId);
    _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<void> writeInput({
    required String sessionId,
    required String data,
    String? terminalId,
    bool appendNewline = false,
    bool startIfNeeded = true,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    final wasRunning = terminal.status == MachineTerminalStatus.running;
    if (startIfNeeded && !await terminal.ensureRunning()) {
      throw StateError('终端启动失败。');
    }
    if (terminal.status != MachineTerminalStatus.running) {
      throw StateError(_terminalNotRunningError);
    }
    terminal.writeInput(appendNewline ? '$data\n' : data);
    if (!wasRunning) {
      _scheduleMetadataPersist(terminal.sessionId);
    }
    _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<void> uploadFile({
    required String sessionId,
    required String sourcePath,
    required String targetDirectory,
    required String targetName,
    String? terminalId,
    required MachineTerminalUploadProgress onProgress,
    required MachineTerminalUploadPauseWaiter waitWhilePaused,
    required MachineTerminalUploadCancelCheck isCancelled,
    bool recordHistory = true,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    if (!await terminal.ensureRunning()) {
      throw StateError('终端启动失败。');
    }
    await terminal.uploadFile(
      sourcePath: sourcePath,
      targetDirectory: targetDirectory,
      targetName: targetName,
      onProgress: onProgress,
      waitWhilePaused: waitWhilePaused,
      isCancelled: isCancelled,
      recordHistory: recordHistory,
    );
    _scheduleMetadataPersist(terminal.sessionId);
    if (recordHistory) _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<MachineTerminalCommandResult> executeCommand({
    required String sessionId,
    required String command,
    String? terminalId,
    Duration timeout = kMachineTerminalDefaultCommandTimeout,
    bool startIfNeeded = true,
    bool recordHistory = true,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    final trimmed = command.trimRight();
    if (trimmed.isEmpty) {
      return MachineTerminalCommandResult(
        terminalId: terminal.id,
        command: command,
        output: '',
        status: terminal.status,
        durationMs: 0,
        error: '命令不能为空。',
      );
    }
    if (startIfNeeded && !await terminal.ensureRunning()) {
      return MachineTerminalCommandResult(
        terminalId: terminal.id,
        command: command,
        output: '',
        status: terminal.status,
        durationMs: 0,
        error: '终端启动失败。',
      );
    }
    final counter = ++_commandCounter;
    final token = 'OPENHAND_${DateTime.now().microsecondsSinceEpoch}_$counter';
    final effectiveTimeout = Duration(
      milliseconds: clampMachineTerminalCommandTimeoutMs(
        timeout.inMilliseconds,
      ),
    );
    final result = await terminal.executeCommand(
      command: trimmed,
      beginMarker: '${token}_BEGIN',
      endMarker: '${token}_END',
      timeout: effectiveTimeout,
      recordHistory: recordHistory,
    );
    _scheduleMetadataPersist(terminal.sessionId);
    if (recordHistory) _scheduleHistoryPersist(terminal.sessionId);
    return result;
  }

  Future<MachineTerminalWorkspaceSnapshot> control({
    required String sessionId,
    required String action,
    String? terminalId,
    String? workingDirectory,
    int? columns,
    int? rows,
  }) async {
    final normalized = action.trim().toLowerCase();
    switch (normalized) {
      case 'start':
        await startTerminal(sessionId: sessionId, terminalId: terminalId);
      case 'stop':
        await stopTerminal(sessionId: sessionId, terminalId: terminalId);
      case 'restart':
        await restartTerminal(sessionId: sessionId, terminalId: terminalId);
      case 'clear':
        await clearTerminal(sessionId: sessionId, terminalId: terminalId);
      case 'resize':
        final safeColumns = columns;
        final safeRows = rows;
        if (safeColumns == null || safeRows == null) {
          throw ArgumentError('调整尺寸需要列数和行数。');
        }
        await resizeTerminal(
          sessionId: sessionId,
          terminalId: terminalId,
          columns: safeColumns,
          rows: safeRows,
        );
      case 'new':
      case 'new_terminal':
        await newTerminal(
          sessionId: sessionId,
          workingDirectory: workingDirectory,
        );
      case 'duplicate':
        await duplicateTerminal(sessionId: sessionId, terminalId: terminalId);
      case 'close':
        await closeTerminal(sessionId: sessionId, terminalId: terminalId);
      case 'restore':
      case 'restore_terminal':
        final id = nullIfBlank(terminalId);
        if (id == null) {
          throw ArgumentError('恢复终端需要 terminal_id。');
        }
        await restoreTerminal(sessionId: sessionId, terminalId: id);
      case 'delete':
      case 'delete_terminal':
      case 'delete_history':
      case 'purge':
      case 'remove':
        final id = nullIfBlank(terminalId);
        if (id == null) {
          throw ArgumentError('删除终端需要 terminal_id。');
        }
        await deleteTerminal(sessionId: sessionId, terminalId: id);
      case 'select':
        final id = nullIfBlank(terminalId);
        if (id == null) {
          throw ArgumentError('选择终端需要 terminal_id。');
        }
        await selectTerminal(sessionId: sessionId, terminalId: id);
      default:
        throw ArgumentError(
          '不支持终端操作“$action”。可用操作：start、stop、restart、clear、resize、new、duplicate、close、restore、delete、remove、select。',
        );
    }
    return ensureWorkspace(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
      start: false,
    );
  }

  Future<Map<String, Object?>> initialMetadata({
    required String sessionId,
    String? workingDirectory,
    Object? existingMetadata,
  }) async {
    rememberSessionMetadata(sessionId: sessionId, metadata: existingMetadata);
    final snapshot = await ensureWorkspace(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
      start: false,
    );
    return sessionMetadata(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
      existingMetadata: existingMetadata,
      snapshot: snapshot,
    );
  }

  Map<String, Object?> sessionMetadata({
    required String sessionId,
    String? workingDirectory,
    Object? existingMetadata,
    MachineTerminalWorkspaceSnapshot? snapshot,
  }) {
    rememberSessionMetadata(sessionId: sessionId, metadata: existingMetadata);
    final normalizedSessionId = _normalizeSessionId(sessionId);
    final metadata = MachineTerminalSessionMetadata.normalize(
      sessionId: normalizedSessionId,
      workingDirectory:
          nullIfBlank(workingDirectory) ??
          _metadataWorkingDirectoryBySession[normalizedSessionId],
      existingMetadata: _metadataSeedFor(normalizedSessionId, existingMetadata),
      snapshot: snapshot ?? this.snapshot(normalizedSessionId),
    );
    rememberSessionMetadata(sessionId: normalizedSessionId, metadata: metadata);
    return metadata;
  }

  /// 刷新元数据与历史，并等待所有自有 PTY 停止。重复调用共享同一任务，
  /// 避免应用关闭与通知器释放互相竞争。
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _isDisposed = true;
    final shutdown = () async {
      try {
        await _shutdownResources();
      } catch (error, stack) {
        silentLog('machine_terminal', '关闭终端服务', error, stack);
      }
    }();
    _shutdownFuture = shutdown;
    return shutdown;
  }

  Future<void> _shutdownResources() async {
    _workspaceLoadSemaphore.cancelWaiters();
    for (final timer in _metadataPersistTimers.values) {
      timer.cancel();
    }
    for (final timer in _historyPersistTimers.values) {
      timer.cancel();
    }
    _metadataPersistTimers.clear();
    _historyPersistTimers.clear();

    final pendingWorkspaceOperations = <Future<void>>[
      ..._workspaceLoads.values.map((load) => load.then<void>((_) {})),
      ..._workspaceDisposals.values,
    ];
    await forEachIndexWithConcurrencyLimit(
      itemCount: pendingWorkspaceOperations.length,
      maxConcurrency: _shutdownConcurrency,
      task: (index) async {
        await runAsyncCleanupBounded(
          () => pendingWorkspaceOperations[index],
          timeout: _shutdownStepTimeout,
          onError: (error, stack) =>
              silentLog('machine_terminal', '等待工作区加载', error, stack),
        );
      },
    );

    final pendingPersists = <Future<void>>[
      ..._metadataPersistChains.values,
      ..._historyPersistChains.values,
    ];
    try {
      await forEachIndexWithConcurrencyLimit(
        itemCount: pendingPersists.length,
        maxConcurrency: _shutdownConcurrency,
        task: (index) async {
          await runAsyncCleanupBounded(
            () => pendingPersists[index],
            timeout: _shutdownStepTimeout,
            onError: (error, stack) =>
                silentLog('machine_terminal', '等待待处理持久化任务', error, stack),
          );
        },
      );
      final sessionIds = _workspaces.keys.toList(growable: false);
      await forEachIndexWithConcurrencyLimit(
        itemCount: sessionIds.length,
        maxConcurrency: _shutdownConcurrency,
        task: (index) async {
          final sessionId = sessionIds[index];
          await runAsyncCleanupBounded(
            () async {
              await _persistWorkspaceHistoryNow(sessionId);
              await _persistSessionMetadataNow(sessionId);
            },
            timeout: _shutdownStepTimeout,
            onError: (error, stack) =>
                silentLog('machine_terminal', '刷新工作区数据', error, stack),
          );
        },
      );
      final workspaces = _workspaces.values.toList(growable: false);
      await forEachIndexWithConcurrencyLimit(
        itemCount: workspaces.length,
        maxConcurrency: _shutdownConcurrency,
        task: (index) async {
          await runAsyncCleanupBounded(
            workspaces[index].shutdown,
            timeout: _shutdownStepTimeout,
            onError: (error, stack) =>
                silentLog('machine_terminal', '停止工作区', error, stack),
          );
        },
      );
    } finally {
      for (final workspace in _workspaces.values) {
        workspace.dispose();
      }
      _metadataPersistChains.clear();
      _historyPersistChains.clear();
      _lastPersistedMetadataDigestBySession.clear();
      _lastPersistedHistoryDigestBySession.clear();
      _metadataCreatedAtBySession.clear();
      _metadataWorkingDirectoryBySession.clear();
      _workspaceLoads.clear();
      _workspaceDisposals.clear();
      _workspaceLoadGenerations.clear();
      _workspaces.clear();
    }
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    unawaited(shutdown());
    super.dispose();
  }

  void _notifyListenersSafely() {
    if (_isDisposed) return;
    final scheduler = SchedulerBinding.instance;
    switch (scheduler.schedulerPhase) {
      case SchedulerPhase.idle:
      case SchedulerPhase.postFrameCallbacks:
        notifyListeners();
      case SchedulerPhase.transientCallbacks:
      case SchedulerPhase.midFrameMicrotasks:
      case SchedulerPhase.persistentCallbacks:
        if (_notificationScheduled) return;
        _notificationScheduled = true;
        scheduler.addPostFrameCallback((_) {
          _notificationScheduled = false;
          if (!_isDisposed) {
            notifyListeners();
          }
        }, debugLabel: 'MachineTerminalService.notifyListeners');
    }
  }

  Future<_MachineTerminalWorkspace> _workspaceFor({
    required String sessionId,
    String? workingDirectory,
  }) {
    if (_isDisposed) {
      throw StateError('终端服务已关闭。');
    }
    final normalizedSessionId = _normalizeSessionId(sessionId);
    if (_workspaceDisposals.containsKey(normalizedSessionId)) {
      throw StateError('终端工作区正在释放。');
    }
    final loaded = _workspaces[normalizedSessionId];
    if (loaded != null) return Future<_MachineTerminalWorkspace>.value(loaded);
    final activeLoad = _workspaceLoads[normalizedSessionId];
    if (activeLoad != null) return activeLoad;
    if (_workspaces.length + _workspaceLoads.length >= _maxTerminalWorkspaces) {
      throw StateError('终端工作区已达到上限 $_maxTerminalWorkspaces，请删除不再使用的会话后重试。');
    }

    final generation = _workspaceLoadGenerations[normalizedSessionId] ?? 0;
    late final Future<_MachineTerminalWorkspace> tracked;
    tracked =
        _loadWorkspaceWithPermit(
          sessionId: normalizedSessionId,
          workingDirectory: workingDirectory,
          generation: generation,
        ).whenComplete(() {
          if (identical(_workspaceLoads[normalizedSessionId], tracked)) {
            _workspaceLoads.remove(normalizedSessionId);
          }
          if (!_workspaces.containsKey(normalizedSessionId) &&
              !_workspaceDisposals.containsKey(normalizedSessionId)) {
            _workspaceLoadGenerations.remove(normalizedSessionId);
          }
        });
    _workspaceLoads[normalizedSessionId] = tracked;
    return tracked;
  }

  Future<_MachineTerminalWorkspace> _loadWorkspaceWithPermit({
    required String sessionId,
    required int generation,
    String? workingDirectory,
  }) async {
    final acquired = await _workspaceLoadSemaphore.acquireWithin(
      _workspaceLoadQueueTimeout,
    );
    if (!acquired) {
      if (_isDisposed) throw StateError('终端服务已关闭。');
      throw TimeoutException('终端工作区加载排队超时。', _workspaceLoadQueueTimeout);
    }
    try {
      if (_isDisposed ||
          _workspaceDisposals.containsKey(sessionId) ||
          (_workspaceLoadGenerations[sessionId] ?? 0) != generation) {
        throw StateError('终端工作区加载已取消。');
      }
      return await _loadWorkspace(
        sessionId: sessionId,
        generation: generation,
        workingDirectory: workingDirectory,
      );
    } finally {
      _workspaceLoadSemaphore.release();
    }
  }

  Future<_MachineTerminalWorkspace> _loadWorkspace({
    required String sessionId,
    required int generation,
    String? workingDirectory,
  }) async {
    final defaultWorkingDirectory =
        nullIfBlank(workingDirectory) ??
        _metadataWorkingDirectoryBySession[sessionId] ??
        OpenHandPaths.applicationDirectoryPath();
    final restored = await _restoreWorkspaceFromDisk(
      sessionId: sessionId,
      defaultWorkingDirectory: defaultWorkingDirectory,
    );
    final workspace =
        restored ??
        (_MachineTerminalWorkspace(
          sessionId: sessionId,
          defaultWorkingDirectory: defaultWorkingDirectory,
        )..add(
          _createTerminal(
            sessionId: sessionId,
            workingDirectory: defaultWorkingDirectory,
          ),
        ));
    if (_isDisposed ||
        _workspaceDisposals.containsKey(sessionId) ||
        (_workspaceLoadGenerations[sessionId] ?? 0) != generation) {
      workspace.dispose();
      throw StateError('终端工作区加载已取消。');
    }
    _workspaces[sessionId] = workspace;
    _workspaceLoadGenerations.remove(sessionId);
    _notifyListenersSafely();
    return workspace;
  }

  Future<_MachineTerminalWorkspace> _requireWorkspace(String sessionId) {
    return _workspaceFor(sessionId: sessionId);
  }

  Future<MachineTerminalSession> _requireTerminal(
    String sessionId,
    String? terminalId,
  ) async {
    final workspace = await _requireWorkspace(sessionId);
    final terminal =
        workspace.terminalById(terminalId) ?? workspace.activeTerminal;
    if (terminal == null) {
      throw StateError('会话 $sessionId 没有可用终端。');
    }
    return terminal;
  }

  MachineTerminalSession _createTerminal({
    required String sessionId,
    required String workingDirectory,
    String? id,
  }) {
    final terminalId = nullIfBlank(id) ?? 'term-${++_terminalCounter}';
    _rememberTerminalIdForCounter(terminalId);
    final shell = _resolveShellExecutable();
    final terminal = MachineTerminalSession(
      id: terminalId,
      sessionId: sessionId,
      identity: 'machine-$terminalId',
      shell: shell,
      workingDirectory: workingDirectory,
      onChanged: () => _handleTerminalChanged(sessionId),
    );
    return terminal;
  }

  void _rememberTerminalIdForCounter(String terminalId) {
    final match = RegExp(r'^term-(\d+)$').firstMatch(terminalId);
    final value = optionalIntFromValue(match?.group(1));
    if (value != null && value > _terminalCounter) {
      _terminalCounter = value;
    }
  }

  void _handleTerminalChanged(String sessionId) {
    _notifyListenersSafely();
    _scheduleHistoryPersist(sessionId);
  }

  void _startTerminalSoon(MachineTerminalSession terminal) {
    startSafeTimer(
      Duration.zero,
      () async {
        if (_isDisposed || terminal.isRunningOrStarting) return;
        await terminal.start().whenComplete(
          () => _scheduleMetadataPersist(terminal.sessionId),
        );
      },
      onError: (error, stack) =>
          silentLog('machine_terminal', '延迟启动终端', error, stack),
    );
  }

  Object? _metadataSeedFor(String sessionId, Object? existingMetadata) {
    final raw = stringKeyedMapFromValue(existingMetadata);
    if (raw.isNotEmpty) return raw;
    final seed = <String, Object?>{
      if (_metadataCreatedAtBySession[sessionId] != null)
        'created_at': _metadataCreatedAtBySession[sessionId],
      if (_metadataWorkingDirectoryBySession[sessionId] != null)
        'default_working_directory':
            _metadataWorkingDirectoryBySession[sessionId],
    };
    return seed.isEmpty ? null : seed;
  }

  Future<_MachineTerminalWorkspace?> _restoreWorkspaceFromDisk({
    required String sessionId,
    required String defaultWorkingDirectory,
  }) async {
    final file = _workspaceHistoryFile(sessionId);
    await recoverAtomicWriteBackupIfNeeded(file);
    final type = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    ).timeout(defaultBoundedFileReadIdleTimeout);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('终端历史记录不是普通文件。', file.path);
    }
    try {
      final decoded = jsonDecode(
        await readBoundedFileString(
          file,
          maxBytes: _machineTerminalHistoryMaxBytes,
        ),
      );
      final raw = stringKeyedMapFromValue(decoded);
      final terminalsJson = raw['terminals'];
      if (terminalsJson is! List || terminalsJson.isEmpty) return null;
      final workspace = _MachineTerminalWorkspace(
        sessionId: sessionId,
        defaultWorkingDirectory: defaultWorkingDirectory,
      );
      final seenTerminalIds = <String>{};
      final retained = terminalsJson.take(_maxPersistedTerminalSnapshots);
      for (final item in retained) {
        final terminalJson = stringKeyedMapFromValue(item);
        final terminalId = nullIfBlank('${terminalJson['terminal_id'] ?? ''}');
        if (terminalId == null ||
            !isSafeStorageIdentifier(terminalId) ||
            !seenTerminalIds.add(terminalId)) {
          continue;
        }
        final terminal = _createTerminal(
          sessionId: sessionId,
          workingDirectory:
              nullIfBlank('${terminalJson['working_directory'] ?? ''}') ??
              defaultWorkingDirectory,
          id: terminalId,
        )..restoreFromJson(terminalJson);
        workspace.add(terminal, activate: false);
      }
      if (workspace.terminals.isEmpty) return null;
      final activeTerminalId = nullIfBlank(
        '${raw['active_terminal_id'] ?? ''}',
      );
      if (activeTerminalId != null) {
        workspace.select(activeTerminalId);
      }
      if (workspace.activeTerminalId.isEmpty) {
        final attached = workspace.attachedTerminals;
        if (attached.isNotEmpty) {
          workspace.activeTerminalId = attached.last.id;
        } else {
          workspace.add(
            _createTerminal(
              sessionId: sessionId,
              workingDirectory: defaultWorkingDirectory,
            ),
          );
        }
      }
      final snapshot = workspace.snapshot();
      final persistedTerminals = _persistedTerminalMaps(snapshot);
      _lastPersistedHistoryDigestBySession[sessionId] = _workspaceHistoryDigest(
        sessionId: sessionId,
        activeTerminalId: snapshot.activeTerminalId,
        terminals: persistedTerminals,
      );
      return workspace;
    } on TimeoutException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } catch (error, stack) {
      silentLog('machine_terminal', '恢复终端历史', error, stack);
      return null;
    }
  }

  void _scheduleHistoryPersist(String sessionId) {
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null ||
        _isDisposed ||
        _workspaceDisposals.containsKey(normalizedSessionId)) {
      return;
    }
    _historyPersistTimers[normalizedSessionId]?.cancel();
    _historyPersistTimers[normalizedSessionId] = startSafeTimer(
      _historyPersistDebounce,
      () {
        _historyPersistTimers.remove(normalizedSessionId);
        if (_isDisposed ||
            _workspaceDisposals.containsKey(normalizedSessionId)) {
          return;
        }
        final previous =
            _historyPersistChains[normalizedSessionId] ?? Future<void>.value();
        late final Future<void> tracked;
        tracked = previous
            .catchError((Object error, StackTrace stack) {
              silentLog('machine_terminal', '终端历史持久化队列', error, stack);
            })
            .then((_) => _persistWorkspaceHistoryNow(normalizedSessionId))
            .whenComplete(() {
              if (identical(
                _historyPersistChains[normalizedSessionId],
                tracked,
              )) {
                _historyPersistChains.remove(normalizedSessionId);
              }
            });
        _historyPersistChains[normalizedSessionId] = tracked;
      },
      onError: (error, stack) =>
          silentLog('machine_terminal', '调度终端历史持久化', error, stack),
    );
  }

  Future<void> _persistWorkspaceHistoryNow(String sessionId) async {
    final workspace = _workspaces[sessionId];
    if (workspace == null) return;
    try {
      final snapshot = workspace.snapshot();
      final terminalsJson = _persistedTerminalMaps(snapshot);
      final digest = _workspaceHistoryDigest(
        sessionId: snapshot.sessionId,
        activeTerminalId: snapshot.activeTerminalId,
        terminals: terminalsJson,
      );
      if (_lastPersistedHistoryDigestBySession[sessionId] == digest) return;
      final payload = <String, Object?>{
        'schema_version': _machineTerminalHistoryStorageSchemaVersion,
        'session_id': snapshot.sessionId,
        'active_terminal_id': snapshot.activeTerminalId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'terminals': terminalsJson,
      };
      final content = '${jsonEncode(payload)}\n';
      if (utf8ByteLength(content) > _machineTerminalHistoryMaxBytes) {
        throw StateError('终端历史记录超过大小限制。');
      }
      await writeFileAtomically(_workspaceHistoryFile(sessionId), content);
      _lastPersistedHistoryDigestBySession[sessionId] = digest;
    } catch (error, stack) {
      silentLog('machine_terminal', '持久化终端历史', error, stack);
    }
  }

  List<Map<String, Object?>> _persistedTerminalMaps(
    MachineTerminalWorkspaceSnapshot snapshot,
  ) {
    final prioritized = List<MachineTerminalSnapshot>.from(snapshot.terminals)
      ..sort((a, b) {
        final aActive = a.terminalId == snapshot.activeTerminalId;
        final bActive = b.terminalId == snapshot.activeTerminalId;
        if (aActive != bActive) return aActive ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final selected = <String, Map<String, Object?>>{};
    var retainedBytes = 0;
    const byteBudget =
        _machineTerminalHistoryMaxBytes -
        _machineTerminalHistoryPayloadReserveBytes;
    for (final terminal in prioritized) {
      if (selected.length >= _maxPersistedTerminalSnapshots) break;
      final json = terminal._toPersistenceJson();
      final bytes = utf8ByteLength(jsonEncode(json)) + 1;
      if (bytes > byteBudget || retainedBytes + bytes > byteBudget) continue;
      selected[terminal.terminalId] = json;
      retainedBytes += bytes;
    }
    if (snapshot.activeTerminalId.isNotEmpty &&
        !selected.containsKey(snapshot.activeTerminalId)) {
      throw StateError('活动终端历史记录超过大小限制。');
    }
    if (snapshot.terminals.isNotEmpty && selected.isEmpty) {
      throw StateError('单个终端历史记录超过大小限制。');
    }
    return snapshot.terminals
        .where((terminal) => selected.containsKey(terminal.terminalId))
        .map((terminal) => selected[terminal.terminalId]!)
        .toList(growable: false);
  }

  String _workspaceHistoryDigest({
    required String sessionId,
    required String activeTerminalId,
    required List<Map<String, Object?>> terminals,
  }) {
    final stablePayload = <String, Object?>{
      'schema_version': _machineTerminalHistoryStorageSchemaVersion,
      'session_id': sessionId,
      'active_terminal_id': activeTerminalId,
      'terminals': terminals,
    };
    return sha256.convert(utf8.encode(jsonEncode(stablePayload))).toString();
  }

  Future<void> _deleteWorkspaceHistoryFile(String sessionId) async {
    final file = _workspaceHistoryFile(sessionId);
    try {
      await deleteFileAtomically(file);
    } catch (error, stack) {
      silentLog('machine_terminal', '删除终端历史文件', error, stack);
    }
  }

  File _workspaceHistoryFile(String sessionId) {
    return File(
      p.join(
        _sessionsDirectoryPath,
        _normalizeSessionId(sessionId),
        _machineTerminalHistoryFileName,
      ),
    );
  }

  void _scheduleMetadataPersist(String sessionId) {
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null ||
        _metadataPersister == null ||
        _isDisposed ||
        _workspaceDisposals.containsKey(normalizedSessionId)) {
      return;
    }
    _metadataPersistTimers[normalizedSessionId]?.cancel();
    _metadataPersistTimers[normalizedSessionId] = startSafeTimer(
      _metadataPersistDebounce,
      () {
        _metadataPersistTimers.remove(normalizedSessionId);
        if (_isDisposed ||
            _workspaceDisposals.containsKey(normalizedSessionId)) {
          return;
        }
        final previous =
            _metadataPersistChains[normalizedSessionId] ?? Future<void>.value();
        late final Future<void> tracked;
        tracked = previous
            .catchError((Object error, StackTrace stack) {
              silentLog('machine_terminal', '终端元数据持久化队列', error, stack);
            })
            .then((_) => _persistSessionMetadataNow(normalizedSessionId))
            .whenComplete(() {
              if (identical(
                _metadataPersistChains[normalizedSessionId],
                tracked,
              )) {
                _metadataPersistChains.remove(normalizedSessionId);
              }
            });
        _metadataPersistChains[normalizedSessionId] = tracked;
      },
      onError: (error, stack) =>
          silentLog('machine_terminal', '调度终端元数据持久化', error, stack),
    );
  }

  Future<void> _persistSessionMetadataNow(String sessionId) async {
    final persister = _metadataPersister;
    if (persister == null) return;
    final metadata = sessionMetadata(sessionId: sessionId);
    final digest = jsonEncode(metadata);
    if (_lastPersistedMetadataDigestBySession[sessionId] == digest) return;
    try {
      await persister(sessionId, metadata);
      _lastPersistedMetadataDigestBySession[sessionId] = digest;
    } catch (error, stack) {
      silentLog('machine_terminal', '持久化终端元数据', error, stack);
    }
  }
}

class MachineTerminalSession {
  MachineTerminalSession({
    required this.id,
    required this.sessionId,
    required this.identity,
    required this.shell,
    required this.workingDirectory,
    required VoidCallback onChanged,
  }) : _onChanged = onChanged,
       terminal = Terminal(
         maxLines: _scrollbackLines,
         platform: _terminalTargetPlatform(),
       ) {
    terminal
      ..resize(_defaultColumns, _defaultRows)
      ..onOutput = writeInput
      ..onResize = _handleResize
      ..write(_welcomeBanner());
  }

  final String id;
  final String sessionId;
  final String identity;
  final String shell;
  final String workingDirectory;
  final VoidCallback _onChanged;
  final Terminal terminal;

  Pty? _pty;
  Pty? _stoppingPty;
  Future<void>? _startFuture;
  Future<void>? _stopFuture;
  Future<void>? _failedPtyCleanupFuture;
  StreamSubscription<String>? _outputSubscription;
  DateTime _startedAt = DateTime.now();
  DateTime _updatedAt = DateTime.now();
  MachineTerminalStatus _status = MachineTerminalStatus.idle;
  String? _errorMessage;
  int? _pid;
  int? _exitCode;
  int _rows = _defaultRows;
  int _columns = _defaultColumns;
  int _startGeneration = 0;
  final BoundedTextBuffer _output = BoundedTextBuffer(
    maxCharacters: _maxRetainedOutputCharacters,
  );
  final BoundedTextBuffer _historyOutput = BoundedTextBuffer(
    maxCharacters: _maxRetainedHistoryCharacters,
    initialValue: _welcomeBanner(),
  );
  final List<MachineTerminalCommandRecord> _commandHistory =
      <MachineTerminalCommandRecord>[];
  Future<MachineTerminalCommandResult>? _commandExecution;
  Future<void>? _uploadExecution;
  int _historyRecordingSuppressionDepth = 0;
  int _commandSequence = 0;
  bool _attached = true;
  bool _hasUserActivity = false;
  bool _forceStopRequested = false;

  MachineTerminalStatus get status => _status;
  bool get attached => _attached;
  bool get hasUserActivity => _hasUserActivity || _commandSequence > 0;
  bool get shouldRetainOnClose => hasUserActivity;
  int? get pid => _pid;
  int? get exitCode => _exitCode;
  String? get errorMessage => _errorMessage;
  bool get isRunningOrStarting =>
      _status == MachineTerminalStatus.running ||
      _status == MachineTerminalStatus.starting;

  MachineTerminalSnapshot snapshot() {
    final output = sanitizedOutput();
    final ansiOutput = _clipString(_output.text, _maxToolOutputCharacters);
    final historyOutput = _clipString(
      _plainText(_historyOutput.text),
      _maxReplayOutputCharacters,
    );
    final historyAnsiOutput = _clipString(
      _historyOutput.text,
      _maxReplayOutputCharacters,
    );
    return MachineTerminalSnapshot(
      sessionId: sessionId,
      terminalId: id,
      identity: identity,
      status: _status,
      shell: shell,
      workingDirectory: workingDirectory,
      rows: _rows,
      columns: _columns,
      output: output,
      ansiOutput: ansiOutput,
      outputCharacters: _output.length,
      historyOutput: historyOutput,
      historyAnsiOutput: historyAnsiOutput,
      historyOutputCharacters: _historyOutput.length,
      commandCount: _commandSequence,
      commandHistory: List<MachineTerminalCommandRecord>.unmodifiable(
        _commandHistory,
      ),
      startedAt: _startedAt,
      updatedAt: _updatedAt,
      attached: _attached,
      hasUserActivity: hasUserActivity,
      pid: _pid,
      exitCode: _exitCode,
      errorMessage: _errorMessage,
    );
  }

  void restoreFromJson(Map<String, Object?> raw) {
    _rows = _coerceRows(optionalIntFromValue(raw['rows']) ?? _defaultRows);
    _columns = _coerceColumns(
      optionalIntFromValue(raw['columns']) ?? _defaultColumns,
    );
    terminal.resize(_columns, _rows);
    _output.replace('${raw['ansi_output'] ?? raw['output'] ?? ''}');
    final history =
        '${raw['history_ansi_output'] ?? raw['history_output'] ?? _output.text}';
    _historyOutput.replace(history.trim().isEmpty ? _welcomeBanner() : history);
    _commandHistory
      ..clear()
      ..addAll(
        _restoredCommandHistory(raw['command_history'], fallbackTerminalId: id),
      );
    _commandSequence = math.min(
      _maxRestoredCommandSequence,
      math.max(
        math.max(
          0,
          optionalIntFromValue(raw['command_count']) ?? _commandHistory.length,
        ),
        _restoredCommandSequence(_commandHistory),
      ),
    );
    _hasUserActivity = raw.containsKey('has_user_activity')
        ? boolFromValue(raw['has_user_activity']) ||
              _commandSequence > 0 ||
              _commandHistory.isNotEmpty
        : _commandSequence > 0 ||
              _commandHistory.isNotEmpty ||
              history.trim().isNotEmpty;
    _attached = raw.containsKey('attached')
        ? boolFromValue(raw['attached'])
        : !boolFromValue(raw['closed']);
    final now = DateTime.now();
    _startedAt = utcDateTimeFromValue(raw['started_at'])?.toLocal() ?? now;
    _updatedAt =
        utcDateTimeFromValue(raw['updated_at'])?.toLocal() ?? _startedAt;
    _status = _restorableStatusFromValue(raw['status']);
    if (!_attached) {
      _status = MachineTerminalStatus.stopped;
    }
    _pid = null;
    _exitCode = optionalIntFromValue(raw['exit_code']);
    _errorMessage = nullIfBlank('${raw['error_message'] ?? ''}') == null
        ? null
        : _terminalRestoredFailureMessage;
    final visibleOutput = _output.text.trim().isEmpty
        ? _clipString(_historyOutput.text, _maxToolOutputCharacters)
        : _output.text;
    terminal.write('\x1b[2J\x1b[H$visibleOutput');
  }

  void markAttached() {
    if (_attached) return;
    _attached = true;
    _touch();
  }

  void markDetached() {
    if (!_attached) return;
    _attached = false;
    _status = MachineTerminalStatus.stopped;
    _pid = null;
    _touch();
  }

  Future<void> start() {
    if (_status == MachineTerminalStatus.running && _pty != null) {
      return Future<void>.value();
    }
    final activeStart = _startFuture;
    if (activeStart != null) return activeStart;
    final generation = ++_startGeneration;
    final activeStop = _stopFuture;

    final completer = Completer<void>();
    final startFuture = completer.future;
    _startFuture = startFuture;
    final Future<void> launch;
    if (activeStop == null) {
      launch = Future<void>.sync(() => _startPty(generation));
    } else {
      launch = activeStop.then<void>((_) async {
        if (generation == _startGeneration) await _startPty(generation);
      });
    }
    unawaited(
      launch.then<void>(
        (_) {
          if (identical(_startFuture, startFuture)) _startFuture = null;
          completer.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_startFuture, startFuture)) _startFuture = null;
          completer.completeError(error, stack);
        },
      ),
    );
    return startFuture;
  }

  Future<bool> ensureRunning() async {
    await start();
    return _status == MachineTerminalStatus.running && _pty != null;
  }

  Future<void> _startPty(int generation) async {
    final failedPtyCleanup = _failedPtyCleanupFuture;
    if (failedPtyCleanup != null) await failedPtyCleanup;
    if (generation != _startGeneration) return;
    if (_status == MachineTerminalStatus.running && _pty != null) return;
    _status = MachineTerminalStatus.starting;
    _errorMessage = null;
    _exitCode = null;
    _startedAt = DateTime.now();
    _touch();
    try {
      final resolvedWorkingDirectory = await _existingWorkingDirectory(
        workingDirectory,
      );
      if (generation != _startGeneration ||
          _status != MachineTerminalStatus.starting) {
        return;
      }
      final pty = Pty.start(
        shell,
        arguments: _shellArguments(shell),
        workingDirectory: resolvedWorkingDirectory,
        rows: _rows,
        columns: _columns,
        environment: const <String, String>{
          'TERM_PROGRAM': 'OpenHand',
          'COLORTERM': 'truecolor',
        },
      );
      _pty = pty;
      _pid = pty.pid;
      _status = MachineTerminalStatus.running;
      _outputSubscription = pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            _handleOutput,
            onError: (Object error, StackTrace stack) {
              _handlePtyChannelFailure(
                pty,
                message: _terminalOutputFailureMessage,
                action: '读取 PTY 输出',
                error: error,
                stack: stack,
              );
            },
          );
      unawaited(
        pty.exitCode
            .then((code) {
              if (!identical(_pty, pty)) {
                return;
              }
              _exitCode = code;
              _pty = null;
              _pid = null;
              final outputSubscription = _outputSubscription;
              _outputSubscription = null;
              unawaited(_cancelOutputSubscription(outputSubscription));
              if (_status != MachineTerminalStatus.failed) {
                _status = MachineTerminalStatus.stopped;
              }
              _appendPlain('\r\n[OpenHand 终端已退出：$code]\r\n');
              _touch();
            })
            .catchError((Object error, StackTrace stack) {
              _handlePtyChannelFailure(
                pty,
                message: _terminalExitFailureMessage,
                action: '读取 PTY 退出码',
                error: error,
                stack: stack,
              );
            }),
      );
    } catch (error, stack) {
      final pty = _pty;
      if (pty == null) {
        _status = MachineTerminalStatus.failed;
        _errorMessage = _terminalStartFailureMessage;
        _appendPlain('\r\n[OpenHand $_terminalStartFailureMessage]\r\n');
        silentLog('machine_terminal', '启动 PTY', error, stack);
      } else {
        _handlePtyChannelFailure(
          pty,
          message: _terminalStartFailureMessage,
          action: '完成 PTY 启动',
          error: error,
          stack: stack,
        );
      }
    } finally {
      _touch();
    }
  }

  Future<void> stop({bool force = false}) {
    _startGeneration += 1;
    final pendingStart = _startFuture;
    _startFuture = null;
    final activeStop = _stopFuture;
    if (activeStop != null) {
      if (force) {
        _forceStopRequested = true;
        try {
          _stoppingPty?.kill(ProcessSignal.sigkill);
        } catch (error, stack) {
          silentLog('machine_terminal', '升级为强制停止 PTY', error, stack);
        }
      }
      return activeStop;
    }
    _forceStopRequested = force;

    final completer = Completer<void>();
    final stopFuture = completer.future;
    _stopFuture = stopFuture;
    unawaited(
      Future<void>.sync(() => _stopPty(pendingStart: pendingStart)).then<void>(
        (_) {
          if (identical(_stopFuture, stopFuture)) _stopFuture = null;
          completer.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_stopFuture, stopFuture)) _stopFuture = null;
          completer.completeError(error, stack);
        },
      ),
    );
    return stopFuture;
  }

  Future<void> _stopPty({required Future<void>? pendingStart}) async {
    if (pendingStart != null) {
      await pendingStart;
    }
    final failedPtyCleanup = _failedPtyCleanupFuture;
    if (failedPtyCleanup != null) await failedPtyCleanup;
    final pty = _pty;
    if (pty == null) {
      _status = MachineTerminalStatus.stopped;
      _pid = null;
      _touch();
      return;
    }
    final outputSubscription = _outputSubscription;
    _pty = null;
    _outputSubscription = null;
    _pid = null;
    _status = MachineTerminalStatus.stopped;
    _touch();
    _stoppingPty = pty;
    try {
      final force = _forceStopRequested;
      pty.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
      if (force) {
        _exitCode = await pty.exitCode.timeout(_terminalForceStopWaitDuration);
      } else {
        try {
          _exitCode = await pty.exitCode.timeout(_terminalStopGraceDuration);
        } on TimeoutException {
          pty.kill(ProcessSignal.sigkill);
          _exitCode = await pty.exitCode.timeout(
            _terminalForceStopWaitDuration,
          );
        }
      }
    } on TimeoutException catch (error, stack) {
      silentLog('machine_terminal', '等待 PTY 停止', error, stack);
    } catch (error, stack) {
      silentLog('machine_terminal', '停止 PTY', error, stack);
    } finally {
      if (identical(_stoppingPty, pty)) _stoppingPty = null;
      _forceStopRequested = false;
      await _cancelOutputSubscription(outputSubscription);
      _status = MachineTerminalStatus.stopped;
      _touch();
    }
  }

  Future<void> _cancelOutputSubscription(
    StreamSubscription<String>? subscription,
  ) async {
    await cancelStreamSubscriptionBounded<String>(
      subscription,
      timeout: _terminalForceStopWaitDuration,
      onError: (error, stack) =>
          silentLog('machine_terminal', '取消 PTY 输出订阅', error, stack),
    );
  }

  void _handlePtyChannelFailure(
    Pty pty, {
    required String message,
    required String action,
    required Object error,
    required StackTrace stack,
  }) {
    if (!identical(_pty, pty)) return;
    final outputSubscription = _outputSubscription;
    _pty = null;
    _outputSubscription = null;
    _pid = null;
    _status = MachineTerminalStatus.failed;
    _errorMessage = message;
    _appendPlain('\r\n[OpenHand $message]\r\n');
    silentLog('machine_terminal', action, error, stack);
    _touch();

    late final Future<void> cleanup;
    cleanup = _cleanupFailedPty(pty, outputSubscription).whenComplete(() {
      if (identical(_failedPtyCleanupFuture, cleanup)) {
        _failedPtyCleanupFuture = null;
      }
    });
    _failedPtyCleanupFuture = cleanup;
  }

  Future<void> _cleanupFailedPty(
    Pty pty,
    StreamSubscription<String>? outputSubscription,
  ) async {
    _stoppingPty = pty;
    try {
      pty.kill();
      try {
        _exitCode = await pty.exitCode.timeout(_terminalStopGraceDuration);
      } on TimeoutException {
        pty.kill(ProcessSignal.sigkill);
        _exitCode = await pty.exitCode.timeout(_terminalForceStopWaitDuration);
      }
    } catch (error, stack) {
      silentLog('machine_terminal', '清理异常 PTY', error, stack);
    } finally {
      if (identical(_stoppingPty, pty)) _stoppingPty = null;
      await _cancelOutputSubscription(outputSubscription);
    }
  }

  Future<void> restart() async {
    await stop(force: true);
    clear();
    await start();
  }

  void clear() {
    _output.clear();
    _appendHistory('\r\n[OpenHand 终端已清空]\r\n${_welcomeBanner()}');
    terminal.write('\x1b[2J\x1b[H${_welcomeBanner()}');
    _touch();
  }

  void writeInput(String data) {
    if (_uploadExecution != null) return;
    _writePty(data, markUserActivity: true);
  }

  void _writePty(String data, {bool markUserActivity = false}) {
    final pty = _pty;
    if (pty == null || _status != MachineTerminalStatus.running) {
      return;
    }
    if (markUserActivity && data.isNotEmpty) {
      _hasUserActivity = true;
    }
    pty.write(Uint8List.fromList(utf8.encode(data)));
  }

  Future<void> _writePtyPaced(String data) async {
    final pty = _pty;
    if (pty == null || _status != MachineTerminalStatus.running) {
      throw StateError(_terminalNotRunningError);
    }
    final bytes = Uint8List.fromList(utf8.encode(data));
    for (
      var offset = 0;
      offset < bytes.length;
      offset += _terminalPtyWriteChunkBytes
    ) {
      if (!identical(_pty, pty) || _status != MachineTerminalStatus.running) {
        throw StateError(_terminalNotRunningError);
      }
      final end = math.min(offset + _terminalPtyWriteChunkBytes, bytes.length);
      pty.write(Uint8List.sublistView(bytes, offset, end));
      if (end < bytes.length) {
        await Future<void>.delayed(_terminalPtyWritePace);
      }
    }
  }

  Future<void> uploadFile({
    required String sourcePath,
    required String targetDirectory,
    required String targetName,
    required MachineTerminalUploadProgress onProgress,
    required MachineTerminalUploadPauseWaiter waitWhilePaused,
    required MachineTerminalUploadCancelCheck isCancelled,
    bool recordHistory = true,
  }) {
    if (_commandExecution != null || _uploadExecution != null) {
      return Future<void>.error(StateError(_terminalBusyError));
    }
    late final Future<void> tracked;
    tracked =
        _runWithHistoryPolicy(
          recordHistory: recordHistory,
          operation: () {
            if (!recordHistory) {
              _appendTransientCommandEcho(
                '文件上传: $sourcePath -> $targetDirectory/$targetName',
              );
            }
            return _uploadFile(
              sourcePath: sourcePath,
              targetDirectory: targetDirectory,
              targetName: targetName,
              onProgress: onProgress,
              waitWhilePaused: waitWhilePaused,
              isCancelled: isCancelled,
            );
          },
        ).whenComplete(() {
          if (identical(_uploadExecution, tracked)) _uploadExecution = null;
        });
    _uploadExecution = tracked;
    return tracked;
  }

  Future<void> _uploadFile({
    required String sourcePath,
    required String targetDirectory,
    required String targetName,
    required MachineTerminalUploadProgress onProgress,
    required MachineTerminalUploadPauseWaiter waitWhilePaused,
    required MachineTerminalUploadCancelCheck isCancelled,
  }) async {
    if (_pty == null || _status != MachineTerminalStatus.running) {
      throw StateError(_terminalNotRunningError);
    }
    final source = File(sourcePath);
    final sourceStat = await source.stat();
    if (sourceStat.type != FileSystemEntityType.file) {
      throw FileSystemException('上传源不是普通文件。', sourcePath);
    }
    final transferToken =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_'
        '${sourceStat.size.toRadixString(36)}';
    final beginMarker = '__OHUB_$transferToken';
    final endMarker = '__OHUE_$transferToken';
    final doneMarker = '__OHUD_$transferToken';
    final cancelMarker = '__OHUC_$transferToken';
    final startOffset = _output.endOffset;
    final startGeneration = _startGeneration;
    final payload = _uploadCommandPayload(
      beginMarker: beginMarker,
      endMarker: endMarker,
      doneMarker: doneMarker,
      cancelMarker: cancelMarker,
      targetDirectory: targetDirectory,
      targetName: targetName,
      token: transferToken,
    );
    RandomAccessFile? reader;
    var transferred = 0;
    var protocolDispatched = false;
    var protocolFinished = false;
    Future<void> cancelProtocol() async {
      if (!protocolDispatched || protocolFinished) return;
      _writePty('$cancelMarker\n');
      try {
        await _waitForCommandOutput(
          begin: beginMarker,
          end: endMarker,
          startOffset: startOffset,
          startGeneration: startGeneration,
          timeout: _terminalUploadReadyTimeout,
        );
      } catch (_) {
        _writePty('\x03');
      } finally {
        protocolFinished = true;
      }
    }

    try {
      await _disableEchoForCommand();
      await _writePtyPaced(payload);
      protocolDispatched = true;
      await _waitForOutputMarker(
        marker: beginMarker,
        startOffset: startOffset,
        startGeneration: startGeneration,
        timeout: _terminalUploadReadyTimeout,
      );
      reader = await source.open();
      while (transferred < sourceStat.size) {
        await waitWhilePaused();
        if (isCancelled()) throw const MachineTerminalUploadCancelled();
        final remaining = sourceStat.size - transferred;
        final chunk = await reader.read(
          math.min(_terminalUploadChunkBytes, remaining),
        );
        if (chunk.isEmpty) {
          throw FileSystemException('上传源在传输期间被截断。', sourcePath);
        }
        await _writePtyPaced('${base64Encode(chunk)}\n');
        transferred += chunk.length;
        onProgress(transferred);
        await Future<void>.delayed(Duration.zero);
      }
      if (isCancelled()) throw const MachineTerminalUploadCancelled();
      final beforeFinalizeStat = await source.stat();
      if (beforeFinalizeStat.size != sourceStat.size ||
          beforeFinalizeStat.modified != sourceStat.modified) {
        throw FileSystemException('上传源在传输期间发生变化。', sourcePath);
      }
      _writePty('$doneMarker\n');
      final result = await _waitForCommandOutput(
        begin: beginMarker,
        end: endMarker,
        startOffset: startOffset,
        startGeneration: startGeneration,
        timeout: _terminalUploadFinalizeTimeout,
      );
      protocolFinished = true;
      if (result.exitCode != 0) {
        throw FileSystemException(
          '远端文件写入失败，退出码 ${result.exitCode}。',
          targetName,
        );
      }
      final finalStat = await source.stat();
      if (finalStat.size != sourceStat.size ||
          finalStat.modified != sourceStat.modified) {
        throw FileSystemException('上传源在传输期间发生变化。', sourcePath);
      }
    } on MachineTerminalUploadCancelled {
      await cancelProtocol();
      rethrow;
    } catch (_) {
      await cancelProtocol();
      rethrow;
    } finally {
      await reader?.close();
      if (!Platform.isWindows) {
        _writePty('stty echo icanon 2>/dev/null\n');
      }
    }
  }

  void resize({required int columns, required int rows}) {
    final nextColumns = _coerceColumns(columns);
    final nextRows = _coerceRows(rows);
    if (_columns == nextColumns &&
        _rows == nextRows &&
        terminal.viewWidth == nextColumns &&
        terminal.viewHeight == nextRows) {
      return;
    }
    terminal.resize(nextColumns, nextRows);
  }

  Future<MachineTerminalCommandResult> executeCommand({
    required String command,
    required String beginMarker,
    required String endMarker,
    required Duration timeout,
    bool recordHistory = true,
  }) {
    if (_commandExecution != null || _uploadExecution != null) {
      return Future<MachineTerminalCommandResult>.value(
        MachineTerminalCommandResult(
          terminalId: id,
          command: command,
          output: '',
          status: _status,
          durationMs: 0,
          error: _terminalBusyError,
        ),
      );
    }
    late final Future<MachineTerminalCommandResult> tracked;
    tracked =
        _runWithHistoryPolicy(
          recordHistory: recordHistory,
          operation: () => _executeCommand(
            command: command,
            beginMarker: beginMarker,
            endMarker: endMarker,
            timeout: timeout,
            recordHistory: recordHistory,
          ),
        ).whenComplete(() {
          if (identical(_commandExecution, tracked)) {
            _commandExecution = null;
          }
        });
    _commandExecution = tracked;
    return tracked;
  }

  Future<MachineTerminalCommandResult> _executeCommand({
    required String command,
    required String beginMarker,
    required String endMarker,
    required Duration timeout,
    required bool recordHistory,
  }) async {
    final stopwatch = Stopwatch()..start();
    final startedAt = DateTime.now();
    if (_pty == null || _status != MachineTerminalStatus.running) {
      return _recordedCommandResult(
        startedAt: startedAt,
        command: command,
        output: '',
        durationMs: stopwatch.elapsedMilliseconds,
        error: _terminalNotRunningError,
      );
    }
    if (!recordHistory) _appendTransientCommandEcho(command);
    final startGeneration = _startGeneration;
    final begin = '__${beginMarker}__';
    final end = '__${endMarker}__';
    final startOffset = _output.endOffset;
    try {
      await _disableEchoForCommand();
      final payload = _commandPayload(
        command: command,
        beginMarker: beginMarker,
        endMarker: endMarker,
      );
      await _writePtyPaced(payload);
      final parsed = await _waitForCommandOutput(
        begin: begin,
        end: end,
        startOffset: startOffset,
        startGeneration: startGeneration,
        timeout: timeout,
      );
      return _recordedCommandResult(
        startedAt: startedAt,
        command: command,
        output: _clipToolOutput(parsed.output.trim()),
        exitCode: parsed.exitCode,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      final output = _clipToolOutput(
        _plainText(_outputSince(startOffset)).trimRight(),
      );
      await _interruptTimedOutCommandPreservingSession(
        begin: begin,
        end: end,
        startOffset: startOffset,
        startGeneration: startGeneration,
      );
      return _recordedCommandResult(
        startedAt: startedAt,
        command: command,
        output: output,
        durationMs: stopwatch.elapsedMilliseconds,
        timedOut: true,
        error:
            '命令执行超过 ${timeout.inMilliseconds} 毫秒，已向当前命令发送中断信号；'
            '为保护 relay/SSH 会话，未重启终端。',
      );
    } catch (error, stack) {
      silentLog('machine_terminal', '执行终端命令', error, stack);
      return _recordedCommandResult(
        startedAt: startedAt,
        command: command,
        output: _clipToolOutput(
          _plainText(_outputSince(startOffset)).trimRight(),
        ),
        durationMs: stopwatch.elapsedMilliseconds,
        error: '命令执行失败。',
      );
    }
  }

  MachineTerminalCommandResult _recordedCommandResult({
    required DateTime startedAt,
    required String command,
    required String output,
    required int durationMs,
    int? exitCode,
    bool timedOut = false,
    String? error,
  }) {
    final result = MachineTerminalCommandResult(
      terminalId: id,
      command: command,
      output: output,
      exitCode: exitCode,
      status: _status,
      durationMs: durationMs,
      timedOut: timedOut,
      error: error,
    );
    _recordCommandResult(result, startedAt: startedAt);
    return result;
  }

  void _recordCommandResult(
    MachineTerminalCommandResult result, {
    required DateTime startedAt,
  }) {
    if (_historyRecordingSuppressionDepth > 0) return;
    _hasUserActivity = true;
    _commandSequence += 1;
    _commandHistory.add(
      MachineTerminalCommandRecord(
        id: 'cmd-$_commandSequence',
        terminalId: id,
        command: _clipString(
          result.command,
          _maxCommandHistoryCommandCharacters,
        ),
        output: _clipString(result.output, _maxCommandHistoryOutputCharacters),
        startedAt: startedAt,
        completedAt: DateTime.now(),
        durationMs: result.durationMs,
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        error: _clipNullableString(
          result.error,
          _maxCommandHistoryErrorCharacters,
        ),
      ),
    );
    _trimCommandHistory(_commandHistory);
    _touch();
  }

  String sanitizedOutput({int maxCharacters = _maxToolOutputCharacters}) {
    return _clipString(_plainText(_output.text), maxCharacters);
  }

  void dispose() {
    unawaited(
      stop(force: true).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            silentLog('machine_terminal', '释放终端会话', error, stack),
      ),
    );
  }

  void _handleResize(int width, int height, int pixelWidth, int pixelHeight) {
    final nextColumns = _coerceColumns(width);
    final nextRows = _coerceRows(height);
    final changed = _columns != nextColumns || _rows != nextRows;
    if (!changed) return;
    _columns = nextColumns;
    _rows = nextRows;
    try {
      _pty?.resize(_rows, _columns);
    } catch (error, stack) {
      silentLog('machine_terminal', '调整 PTY 尺寸', error, stack);
    }
    _touch();
  }

  void _handleOutput(String text) {
    _output.append(text);
    terminal.write(text);
    if (_historyRecordingSuppressionDepth == 0) {
      _appendHistory(text);
    }
    _touch();
  }

  void _appendTransientCommandEcho(String command) {
    final text = _clipString(
      command.trimRight(),
      _maxCommandHistoryCommandCharacters,
    );
    if (text.isEmpty) return;
    final echoed = '\r\n\x1b[38;5;75m\$ $text\x1b[0m\r\n';
    terminal.write(echoed);
    _output.append(echoed);
    _touch();
  }

  Future<T> _runWithHistoryPolicy<T>({
    required bool recordHistory,
    required Future<T> Function() operation,
  }) async {
    if (recordHistory) return operation();
    _historyRecordingSuppressionDepth += 1;
    try {
      return await operation();
    } finally {
      _historyRecordingSuppressionDepth -= 1;
    }
  }

  void _appendPlain(String text) {
    terminal.write(text);
    _appendRaw(text);
  }

  void _appendRaw(String text) {
    _output.append(text);
    _appendHistory(text);
  }

  void _appendHistory(String text) {
    _historyOutput.append(text);
  }

  void _touch() {
    _updatedAt = DateTime.now();
    _onChanged();
  }

  Future<void> _disableEchoForCommand() async {
    if (Platform.isWindows) return;
    final marker =
        '__OPENHAND_ECHO_READY_${DateTime.now().microsecondsSinceEpoch}__';
    final startOffset = _output.endOffset;
    final startGeneration = _startGeneration;
    _writePty("stty -echo 2>/dev/null; printf '\\n%s\\n' '$marker'\n");
    await _waitForOutputMarker(
      marker: marker,
      startOffset: startOffset,
      startGeneration: startGeneration,
      timeout: _terminalEchoReadyTimeout,
    );
  }

  Future<void> _interruptTimedOutCommand() async {
    writeInput('\x03');
    await Future<void>.delayed(_commandInterruptSettleDelay);
    if (!Platform.isWindows) {
      writeInput('stty echo 2>/dev/null\n');
    }
  }

  Future<void> _waitForOutputMarker({
    required String marker,
    required int startOffset,
    required int startGeneration,
    required Duration timeout,
  }) async {
    final deadline = MonotonicDeadline(
      timeout,
      timeoutMessage: '等待文件传输通道就绪超时。',
    );
    try {
      while (true) {
        if (_plainText(_outputSince(startOffset)).contains(marker)) return;
        if (_startGeneration != startGeneration ||
            _pty == null ||
            _status != MachineTerminalStatus.running) {
          throw StateError(_terminalNotRunningError);
        }
        final remaining = deadline.remainingOrNull();
        if (remaining == null) throw deadline.timeoutException();
        await Future<void>.delayed(
          remaining < _commandPollInterval ? remaining : _commandPollInterval,
        );
      }
    } finally {
      deadline.stop();
    }
  }

  Future<void> _interruptTimedOutCommandPreservingSession({
    required String begin,
    required String end,
    required int startOffset,
    required int startGeneration,
  }) async {
    await _interruptTimedOutCommand();
    try {
      await _waitForCommandOutput(
        begin: begin,
        end: end,
        startOffset: startOffset,
        startGeneration: startGeneration,
        timeout: _commandRecoveryTimeout,
      );
    } catch (_) {
      // 未恢复结束标记时保留原 PTY，禁止自动重启导致 relay/SSH 会话丢失。
    }
  }

  Future<_ParsedCommandOutput> _waitForCommandOutput({
    required String begin,
    required String end,
    required int startOffset,
    required int startGeneration,
    required Duration timeout,
  }) async {
    final deadline = MonotonicDeadline(timeout, timeoutMessage: '等待终端命令标记超时。');
    // 增量剥离：每轮只对新增的原始输出跑一次 _plainText，而不是对最多 24 万
    // 字符的整段缓冲重跑四遍全文替换。刷屏型命令（npm install / find /）此前
    // 每秒要在 UI isolate 上做数百万字符的字符串工作，直接表现为掉帧。
    final plainBuffer = StringBuffer();
    var scannedOffset = startOffset;
    try {
      while (true) {
        if (_output.discardedSince(scannedOffset)) {
          // 缓冲已滚过尚未扫描的区间，增量状态不再可信，退回整段剥离。
          plainBuffer.clear();
          scannedOffset = _output.endOffset;
          plainBuffer.write(_plainText(_outputSince(startOffset)));
        } else {
          final rawTail = _output.textFrom(scannedOffset);
          final consumable = _ansiSafeSplitLength(rawTail);
          if (consumable > 0) {
            plainBuffer.write(_plainText(rawTail.substring(0, consumable)));
            scannedOffset += consumable;
          }
        }
        final segment = plainBuffer.toString();
        final beginIndex = segment.indexOf(begin);
        final outputStart = beginIndex >= 0
            ? beginIndex + begin.length
            : _output.discardedSince(startOffset)
            ? 0
            : -1;
        final endIndex = outputStart < 0
            ? -1
            : segment.indexOf(end, outputStart);
        if (endIndex >= outputStart && outputStart >= 0) {
          final afterEnd = segment.substring(endIndex + end.length);
          final exitCodeMatch = _markerExitCodePattern.firstMatch(afterEnd);
          final exitCode = optionalIntFromValue(exitCodeMatch?.group(1));
          if (exitCode != null) {
            final output = segment.substring(outputStart, endIndex);
            return _ParsedCommandOutput(
              output: _removeMarkerNoise(output),
              exitCode: exitCode,
            );
          }
        }
        if (_startGeneration != startGeneration ||
            _pty == null ||
            _status != MachineTerminalStatus.running) {
          throw StateError(_terminalNotRunningError);
        }
        final remaining = deadline.remainingOrNull();
        if (remaining == null) throw deadline.timeoutException();
        await Future<void>.delayed(
          remaining < _commandPollInterval ? remaining : _commandPollInterval,
        );
      }
    } finally {
      deadline.stop();
    }
  }

  String _outputSince(int offset) {
    return _output.textFrom(offset);
  }
}

class _MachineTerminalWorkspace {
  _MachineTerminalWorkspace({
    required this.sessionId,
    required this.defaultWorkingDirectory,
  });

  final String sessionId;
  final String defaultWorkingDirectory;
  final List<MachineTerminalSession> terminals = <MachineTerminalSession>[];
  String activeTerminalId = '';

  MachineTerminalSession? get activeTerminal => terminalById(activeTerminalId);

  List<MachineTerminalSession> get attachedTerminals =>
      terminals.where((terminal) => terminal.attached).toList(growable: false);

  void add(MachineTerminalSession terminal, {bool activate = true}) {
    if (terminals.any((item) => item.id == terminal.id)) {
      throw StateError('终端 ID 重复：${terminal.id}。');
    }
    if (terminals.length >= _maxTerminalSessionsPerWorkspace) {
      final evictedIndex = terminals.indexWhere((item) => !item.attached);
      if (evictedIndex < 0) {
        throw StateError(
          '一个工作区最多保留 $_maxTerminalSessionsPerWorkspace 个终端会话，'
          '请先关闭或删除旧终端。',
        );
      }
      terminals.removeAt(evictedIndex).dispose();
    }
    terminals.add(terminal);
    if (terminal.attached && (activate || activeTerminalId.isEmpty)) {
      activeTerminalId = terminal.id;
    }
  }

  MachineTerminalSession? remove(String terminalId) {
    final index = terminals.indexWhere((item) => item.id == terminalId);
    if (index < 0) return null;
    final removed = terminals.removeAt(index);
    if (activeTerminalId == terminalId) {
      _selectFallbackActive();
    }
    return removed;
  }

  void detach(String terminalId) {
    final terminal = terminalById(terminalId);
    if (terminal == null) return;
    terminal.markDetached();
    if (activeTerminalId == terminalId) {
      _selectFallbackActive();
    }
  }

  void restore(String terminalId) {
    final terminal = terminalById(terminalId, includeDetached: true);
    if (terminal == null) return;
    terminal.markAttached();
    activeTerminalId = terminal.id;
  }

  void select(String terminalId) {
    if (terminals.any((item) => item.attached && item.id == terminalId)) {
      activeTerminalId = terminalId;
    }
  }

  MachineTerminalSession? terminalById(
    String? terminalId, {
    bool includeDetached = false,
  }) {
    final id = nullIfBlank(terminalId) ?? activeTerminalId;
    if (id.isEmpty) {
      for (final terminal in terminals) {
        if (includeDetached || terminal.attached) return terminal;
      }
      return null;
    }
    for (final terminal in terminals) {
      if (terminal.id == id && (includeDetached || terminal.attached)) {
        return terminal;
      }
    }
    return null;
  }

  MachineTerminalWorkspaceSnapshot snapshot() {
    return MachineTerminalWorkspaceSnapshot(
      sessionId: sessionId,
      activeTerminalId: activeTerminalId,
      terminals: terminals.map((item) => item.snapshot()).toList(),
    );
  }

  void _selectFallbackActive() {
    for (final terminal in terminals.reversed) {
      if (terminal.attached) {
        activeTerminalId = terminal.id;
        return;
      }
    }
    activeTerminalId = '';
  }

  void dispose() {
    for (final terminal in terminals) {
      terminal.dispose();
    }
    terminals.clear();
    activeTerminalId = '';
  }

  Future<void> shutdown() async {
    final closing = List<MachineTerminalSession>.from(terminals);
    terminals.clear();
    activeTerminalId = '';
    await Future.wait<void>(
      closing.map((terminal) => terminal.stop(force: true)),
    );
  }
}

class _ParsedCommandOutput {
  const _ParsedCommandOutput({required this.output, this.exitCode});

  final String output;
  final int? exitCode;
}

List<MachineTerminalCommandRecord> _restoredCommandHistory(
  Object? value, {
  required String fallbackTerminalId,
}) {
  if (value is! List) return const <MachineTerminalCommandRecord>[];
  final records = <MachineTerminalCommandRecord>[];
  final seenIds = <String>{};
  final firstIndex = math.max(0, value.length - _maxCommandHistoryEntries);
  for (var index = firstIndex; index < value.length; index++) {
    final record = MachineTerminalCommandRecord.fromJson(
      value[index],
      fallbackTerminalId: fallbackTerminalId,
      fallbackRecordId: 'cmd-${index + 1}',
    );
    if (record != null && seenIds.add(record.id)) {
      records.add(record);
    }
  }
  _trimCommandHistory(records);
  return records;
}

int _restoredCommandSequence(List<MachineTerminalCommandRecord> records) {
  var maxSequence = 0;
  final pattern = RegExp(r'^cmd-(\d+)$');
  for (final record in records) {
    final match = pattern.firstMatch(record.id);
    final value = optionalIntFromValue(match?.group(1));
    if (value != null && value > maxSequence) {
      maxSequence = value;
    }
  }
  return maxSequence;
}

void _trimCommandHistory(List<MachineTerminalCommandRecord> records) {
  if (records.length > _maxCommandHistoryEntries) {
    records.removeRange(0, records.length - _maxCommandHistoryEntries);
  }
  var retainedCharacters = records.fold<int>(
    0,
    (total, record) => total + _commandRecordCharacters(record),
  );
  while (records.length > 1 &&
      retainedCharacters > _maxCommandHistoryRetainedCharacters) {
    retainedCharacters -= _commandRecordCharacters(records.removeAt(0));
  }
}

int _commandRecordCharacters(MachineTerminalCommandRecord record) {
  return record.command.length +
      record.output.length +
      (record.error?.length ?? 0);
}

MachineTerminalStatus _restorableStatusFromValue(Object? value) {
  final status = switch ('${value ?? ''}'.trim().toLowerCase()) {
    'starting' => MachineTerminalStatus.starting,
    'running' => MachineTerminalStatus.running,
    'stopped' => MachineTerminalStatus.stopped,
    'failed' => MachineTerminalStatus.failed,
    _ => MachineTerminalStatus.idle,
  };
  return switch (status) {
    MachineTerminalStatus.starting ||
    MachineTerminalStatus.running => MachineTerminalStatus.stopped,
    _ => status,
  };
}

String _resolveShellExecutable() {
  if (Platform.isWindows) {
    return Platform.environment['COMSPEC'] ?? 'cmd.exe';
  }
  return nullIfBlank(Platform.environment['SHELL']) ?? '/bin/zsh';
}

String _normalizeSessionId(String sessionId) {
  return requireSafeStorageIdentifier(
    sessionId,
    label: '会话标识符',
    errorFactory: (message) =>
        ArgumentError.value(sessionId, 'sessionId', message),
  );
}

List<String> _shellArguments(String shell) {
  if (Platform.isWindows) return const <String>[];
  final basename = shell.split(Platform.pathSeparator).last;
  if (basename == 'zsh' || basename == 'bash') {
    return const <String>['-l'];
  }
  return const <String>[];
}

String _normalizedWorkingDirectory(String value) {
  return Directory(
    nullIfBlank(value) ?? OpenHandPaths.applicationDirectoryPath(),
  ).path;
}

Future<String> _existingWorkingDirectory(String value) async {
  final normalized = _normalizedWorkingDirectory(value);
  try {
    final type = await FileSystemEntity.type(
      normalized,
    ).timeout(_terminalFilesystemProbeTimeout);
    if (type == FileSystemEntityType.directory) return normalized;
  } catch (_) {
    // 应用目录是稳定的兜底工作目录。
  }
  return OpenHandPaths.applicationDirectoryPath();
}

TerminalTargetPlatform _terminalTargetPlatform() {
  if (Platform.isMacOS) return TerminalTargetPlatform.macos;
  if (Platform.isLinux) return TerminalTargetPlatform.linux;
  if (Platform.isWindows) return TerminalTargetPlatform.windows;
  if (Platform.isAndroid) return TerminalTargetPlatform.android;
  if (Platform.isIOS) return TerminalTargetPlatform.ios;
  return TerminalTargetPlatform.unknown;
}

String _welcomeBanner() => '\x1b[38;5;108mOpenHand 机器终端\x1b[0m\r\n';

String _commandPayload({
  required String command,
  required String beginMarker,
  required String endMarker,
}) {
  if (Platform.isWindows) {
    return 'set "__OPENHAND_BEGIN=$beginMarker"\r\n'
        'set "__OPENHAND_END=$endMarker"\r\n'
        'echo __%__OPENHAND_BEGIN%__\r\n'
        '$command\r\n'
        'echo __%__OPENHAND_END%__:%ERRORLEVEL%\r\n'
        'set "__OPENHAND_BEGIN="\r\n'
        'set "__OPENHAND_END="\r\n';
  }
  return "printf '\\n__%s__\\n' '$beginMarker'\n"
      '(\n'
      '$command\n'
      ')\n'
      '__openhand_status=\$?\n'
      'stty echo 2>/dev/null\n'
      "printf '\\n__%s__:%s\\n' '$endMarker' \"\$__openhand_status\"\n";
}

String _uploadCommandPayload({
  required String beginMarker,
  required String endMarker,
  required String doneMarker,
  required String cancelMarker,
  required String targetDirectory,
  required String targetName,
  required String token,
}) {
  final separator = Platform.isWindows ? r'\' : '/';
  final targetPath =
      targetDirectory.endsWith('/') || targetDirectory.endsWith(r'\')
      ? '$targetDirectory$targetName'
      : '$targetDirectory$separator$targetName';
  final temporaryPath = '$targetPath.openhand-$token.tmp';
  final base64Path = '$temporaryPath.b64';
  if (Platform.isWindows) {
    final script =
        r'''
$ErrorActionPreference = 'Stop'
$beginMarker = '__BEGIN__'
$endMarker = '__END__'
$doneMarker = '__DONE__'
$cancelMarker = '__CANCEL__'
$targetPath = '__TARGET__'
$temporaryPath = '__TEMP__'
$base64Path = '__BASE64__'
$status = 0
Write-Output $beginMarker
try {
  $writer = [IO.StreamWriter]::new($base64Path, $false, [Text.Encoding]::ASCII)
  try {
    while (($line = [Console]::In.ReadLine()) -ne $null) {
      if ($line -eq $doneMarker) { break }
      if ($line -eq $cancelMarker) { $status = 130; break }
      $writer.Write($line)
    }
  } finally {
    $writer.Dispose()
  }
  if ($status -eq 0) {
    $inputStream = [IO.File]::OpenRead($base64Path)
    $outputStream = [IO.File]::Create($temporaryPath)
    $transform = [Security.Cryptography.FromBase64Transform]::new(
      [Security.Cryptography.FromBase64TransformMode]::IgnoreWhiteSpaces
    )
    $decoder = [Security.Cryptography.CryptoStream]::new(
      $inputStream,
      $transform,
      [Security.Cryptography.CryptoStreamMode]::Read
    )
    try { $decoder.CopyTo($outputStream) } finally {
      $decoder.Dispose()
      $outputStream.Dispose()
      $inputStream.Dispose()
      $transform.Dispose()
    }
    Move-Item -LiteralPath $temporaryPath -Destination $targetPath -Force
  }
} catch {
  $status = 1
} finally {
  Remove-Item -LiteralPath $base64Path -Force -ErrorAction SilentlyContinue
  if ($status -ne 0) {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
  }
}
Write-Output ($endMarker + ':' + $status)
'''
            .replaceAll('__BEGIN__', _escapePowerShellLiteral(beginMarker))
            .replaceAll('__END__', _escapePowerShellLiteral(endMarker))
            .replaceAll('__DONE__', _escapePowerShellLiteral(doneMarker))
            .replaceAll('__CANCEL__', _escapePowerShellLiteral(cancelMarker))
            .replaceAll('__TARGET__', _escapePowerShellLiteral(targetPath))
            .replaceAll('__TEMP__', _escapePowerShellLiteral(temporaryPath))
            .replaceAll('__BASE64__', _escapePowerShellLiteral(base64Path));
    return '@powershell.exe -NoProfile -NonInteractive -EncodedCommand '
        '${_encodePowerShellCommand(script)}\r\n';
  }

  final target = _quotePosixShell(targetPath);
  final begin = _quotePosixShell(beginMarker);
  final end = _quotePosixShell(endMarker);
  final done = _quotePosixShell(doneMarker);
  final cancel = _quotePosixShell(cancelMarker);
  return '(__oh_b=$begin;__oh_e=$end;__oh_d=$done;__oh_c=$cancel;'
      '__oh_t=$target;__oh_x="\$__oh_t.openhand-$token.tmp";'
      '__oh_y="\$__oh_x.b64";__oh_s=0;: >"\$__oh_y"||__oh_s=1;'
      "printf '\\n%s\\n' \"\$__oh_b\";"
      'stty -echo -icanon min 1 time 0 2>/dev/null||true;'
      'while [ "\$__oh_s" -eq 0 ]&&IFS= read -r __oh_l;do '
      '[ "\$__oh_l" = "\$__oh_d" ]&&break;'
      'if [ "\$__oh_l" = "\$__oh_c" ];then __oh_s=130;break;fi;'
      'printf "%s" "\$__oh_l">>"\$__oh_y"||__oh_s=1;done;'
      'stty echo icanon 2>/dev/null||true;'
      'if [ "\$__oh_s" -eq 0 ];then '
      'base64 -d<"\$__oh_y">"\$__oh_x"&&'
      'mv -f -- "\$__oh_x" "\$__oh_t"||__oh_s=1;fi;'
      'rm -f -- "\$__oh_y";'
      '[ "\$__oh_s" -eq 0 ]||rm -f -- "\$__oh_x";'
      "printf '\\n%s:%s\\n' \"\$__oh_e\" \"\$__oh_s\")\n";
}

String _quotePosixShell(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _escapePowerShellLiteral(String value) => value.replaceAll("'", "''");

String _encodePowerShellCommand(String command) {
  final bytes = <int>[];
  for (final codeUnit in command.codeUnits) {
    bytes
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return base64Encode(bytes);
}

/// ANSI CSI / OSC / ESC 序列。提到顶层复用：命令等待循环每 80ms 调一次
/// [_plainText]，就地构造正则等于每秒白白编译 25 次。
final RegExp _ansiCsiPattern = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final RegExp _markerExitCodePattern = RegExp(r'^:(-?\d+)\n');
final RegExp _ansiOscPattern = RegExp(r'\x1B\][^\x07]*(\x07|\x1B\\)');
final RegExp _ansiEscapePattern = RegExp(r'\x1B[ -/]*[0-~]');

String _plainText(String value) {
  return value
      .replaceAll(_ansiCsiPattern, '')
      .replaceAll(_ansiOscPattern, '')
      .replaceAll(_ansiEscapePattern, '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
}

/// 返回 [raw] 中可以安全做 [_plainText] 剥离的前缀长度。
///
/// 增量剥离要求切点不能落在「跨增量才完整」的序列中间，否则剥离结果与整段
/// 剥离不等价：
///   * 未闭合的 ESC 序列会被原样保留成乱码；
///   * 结尾的裸 `\r` 会先变成 `\n`，下一增量的 `\n` 再补一个，`\r\n` 就成了两行。
/// 这两种情况都把切点回退到该字符之前，等下一批数据到齐再处理。
int _ansiSafeSplitLength(String raw) {
  if (raw.isEmpty) return 0;
  var limit = raw.length;
  // 必须从前往后逐个跳过完整序列，不能直接找最后一个 ESC：OSC 的字符串终止符
  // 本身就是 `ESC \`，反向查找会落到终止符上，把前面那段完整的 OSC 误判为
  // 未闭合。matchAsPrefix 带起始下标，全程不做 substring 拷贝。
  var cursor = 0;
  var lastPlainIndex = -1;
  while (true) {
    final escape = raw.indexOf('\x1B', cursor);
    final plainEnd = (escape < 0 || escape >= limit) ? limit : escape;
    if (plainEnd > cursor) lastPlainIndex = plainEnd - 1;
    if (escape < 0 || escape >= limit) break;
    final nextCodeUnit = escape + 1 < limit ? raw.codeUnitAt(escape + 1) : null;
    final match = switch (nextCodeUnit) {
      0x5b => _ansiCsiPattern.matchAsPrefix(raw, escape),
      0x5d => _ansiOscPattern.matchAsPrefix(raw, escape),
      _ => _ansiEscapePattern.matchAsPrefix(raw, escape),
    };
    if (match == null || match.end > limit) {
      limit = escape;
      break;
    }
    cursor = match.end;
  }
  // 剥离 ANSI 之后，末尾可能露出一个原本被转义序列挡住的 `\r`。它有可能是
  // 跨增量的 `\r\n` 前半段，必须留到下一批一起处理，否则会先被替换成 `\n`、
  // 下一批的 `\n` 再补一个，一行变两行。
  if (lastPlainIndex >= 0 && raw.codeUnitAt(lastPlainIndex) == 0x0D) {
    limit = lastPlainIndex;
  }
  return limit < 0 ? 0 : limit;
}

String _removeMarkerNoise(String value) {
  final lines = value.split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

String? _isoTimeFromValue(Object? value) {
  final text = optionalStringFromValue(value);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  return parsed?.toUtc().toIso8601String();
}

String _clipToolOutput(String value) =>
    _clipString(value, _maxToolOutputCharacters);

String? _clipNullableString(String? value, int maxCharacters) {
  return value == null ? null : _clipString(value, maxCharacters);
}

String _clipString(String value, int maxCharacters) {
  if (value.length <= maxCharacters) return value;
  if (maxCharacters <= 0) return '';
  var omitted = value.length - maxCharacters;
  for (var attempt = 0; attempt < 8; attempt++) {
    final marker = '\n[... 已省略 $omitted 个字符 ...]\n';
    if (marker.length >= maxCharacters) {
      return value.substring(0, safeUtf16PrefixCodeUnits(value, maxCharacters));
    }
    final retained = maxCharacters - marker.length;
    final requestedHead = retained ~/ 2;
    final headEnd = safeUtf16PrefixCodeUnits(value, requestedHead);
    final tailStart = safeUtf16SuffixStart(
      value,
      value.length - (retained - headEnd),
    );
    final actualOmitted = tailStart - headEnd;
    if (actualOmitted == omitted) {
      return '${value.substring(0, headEnd)}$marker${value.substring(tailStart)}';
    }
    omitted = actualOmitted;
  }
  throw StateError('终端文本截断长度计算失败。');
}

int _coerceRows(int value) => math.min(math.max(1, value), _maxRows);

int _coerceColumns(int value) => math.min(math.max(1, value), _maxColumns);
