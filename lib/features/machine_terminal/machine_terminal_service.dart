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
import '../../shared/util/input_value_parsing.dart';
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
const int _maxCommandHistoryOutputCharacters = 40000;
const int _maxPersistedTerminalSnapshots = 48;
const Duration _commandPollInterval = Duration(milliseconds: 80);
const Duration _metadataPersistDebounce = Duration(milliseconds: 700);
const Duration _historyPersistDebounce = Duration(milliseconds: 650);
const Duration _terminalStopGraceDuration = Duration(milliseconds: 900);
const Duration _terminalFilesystemProbeTimeout = Duration(seconds: 3);
const int _shutdownConcurrency = 4;
const Duration _shutdownStepTimeout = Duration(milliseconds: 1500);
const String _machineTerminalSurface = 'openhand_machine_terminal';
const String _machineTerminalWorkflow = 'builtin_terminal_panel';
const String _machineTerminalWorkspacePrefix = 'machine-terminal';
const String _machineTerminalHistoryFileName = 'machine-terminal-history.json';
const int _machineTerminalHistoryStorageSchemaVersion = 1;
const int _machineTerminalHistoryMaxBytes = 32 * 1024 * 1024;

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

  bool get succeeded => !timedOut && error == null && (exitCode ?? 0) == 0;

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
      'command': command,
      'output': _clipString(output, _maxCommandHistoryOutputCharacters),
      'exit_code': exitCode,
      'timed_out': timedOut,
      'duration_ms': durationMs,
      'started_at': startedAt.toUtc().toIso8601String(),
      'completed_at': completedAt.toUtc().toIso8601String(),
      if (error != null) 'error': error,
    };
  }

  static MachineTerminalCommandRecord? fromJson(
    Object? value, {
    required String fallbackTerminalId,
  }) {
    final raw = stringKeyedMapFromValue(value);
    final command = '${raw['command'] ?? ''}';
    if (raw.isEmpty || command.trim().isEmpty) return null;
    final terminalId =
        nullIfBlank('${raw['terminal_id'] ?? ''}') ?? fallbackTerminalId;
    final now = DateTime.now();
    final startedAt = utcDateTimeFromValue(raw['started_at'])?.toLocal() ?? now;
    final completedAt =
        utcDateTimeFromValue(raw['completed_at'])?.toLocal() ?? startedAt;
    return MachineTerminalCommandRecord(
      id: nullIfBlank('${raw['id'] ?? ''}') ?? 'cmd-restored',
      terminalId: terminalId,
      command: command,
      output: _clipString(
        '${raw['output'] ?? ''}',
        _maxCommandHistoryOutputCharacters,
      ),
      startedAt: startedAt,
      completedAt: completedAt,
      durationMs: optionalIntFromValue(raw['duration_ms']) ?? 0,
      exitCode: optionalIntFromValue(raw['exit_code']),
      timedOut: boolFromValue(raw['timed_out']),
      error: nullIfBlank('${raw['error'] ?? ''}'),
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

  static int? schemaVersionFrom(Object? metadata) {
    final raw = stringKeyedMapFromValue(metadata);
    return optionalIntFromValue(raw['schema_version']);
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
  Future<void>? _shutdownFuture;

  int _terminalCounter = 0;
  int _commandCounter = 0;
  bool _isDisposed = false;
  bool _notifierDisposed = false;
  bool _notificationScheduled = false;
  MachineTerminalMetadataPersister? _metadataPersister;

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
      throw StateError('MachineTerminalService is shut down.');
    }
    if (start) {
      final active = workspace.activeTerminal;
      if (active != null && !active.isRunningOrStarting) {
        unawaited(
          active.start().whenComplete(
            () => _scheduleMetadataPersist(workspace.sessionId),
          ),
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
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null) return Future<void>.value();
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
        onError: (error, stack) => silentLog(
          'machine_terminal',
          'dispose workspace persist',
          error,
          stack,
        ),
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
        onError: (error, stack) => silentLog(
          'machine_terminal',
          'dispose workspace terminals',
          error,
          stack,
        ),
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
    workspace.add(terminal);
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
      throw StateError('Terminal not found: $terminalId.');
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
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    var started = false;
    if (!terminal.isRunningOrStarting) {
      await terminal.start();
      started = true;
    }
    terminal.writeInput(appendNewline ? '$data\n' : data);
    if (started) {
      _scheduleMetadataPersist(terminal.sessionId);
    }
    _scheduleHistoryPersist(terminal.sessionId);
  }

  Future<MachineTerminalCommandResult> executeCommand({
    required String sessionId,
    required String command,
    String? terminalId,
    Duration timeout = kMachineTerminalDefaultCommandTimeout,
  }) async {
    final terminal = await _requireTerminal(sessionId, terminalId);
    if (!terminal.isRunningOrStarting) {
      await terminal.start();
    }
    final trimmed = command.trimRight();
    if (trimmed.isEmpty) {
      return MachineTerminalCommandResult(
        terminalId: terminal.id,
        command: command,
        output: '',
        status: terminal.status,
        durationMs: 0,
        error: 'Command is empty.',
      );
    }
    final counter = ++_commandCounter;
    final token = 'OPENHAND_${DateTime.now().microsecondsSinceEpoch}_$counter';
    final result = await terminal.executeCommand(
      command: trimmed,
      beginMarker: '${token}_BEGIN',
      endMarker: '${token}_END',
      timeout: timeout,
    );
    _scheduleMetadataPersist(terminal.sessionId);
    _scheduleHistoryPersist(terminal.sessionId);
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
          throw ArgumentError('resize requires columns and rows.');
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
          throw ArgumentError('restore requires terminal_id.');
        }
        await restoreTerminal(sessionId: sessionId, terminalId: id);
      case 'delete':
      case 'delete_terminal':
      case 'delete_history':
      case 'purge':
      case 'remove':
        final id = nullIfBlank(terminalId);
        if (id == null) {
          throw ArgumentError('delete requires terminal_id.');
        }
        await deleteTerminal(sessionId: sessionId, terminalId: id);
      case 'select':
        final id = nullIfBlank(terminalId);
        if (id == null) {
          throw ArgumentError('select requires terminal_id.');
        }
        await selectTerminal(sessionId: sessionId, terminalId: id);
      default:
        throw ArgumentError(
          'Unsupported terminal action "$action". Use start, stop, restart, clear, resize, new, duplicate, close, restore, delete, remove, or select.',
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

  /// Flushes metadata/history and waits for all owned PTYs to stop. Repeated
  /// calls share one future so root shutdown and notifier disposal cannot race.
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _isDisposed = true;
    final shutdown = () async {
      try {
        await _shutdownResources();
      } catch (error, stack) {
        silentLog('machine_terminal', 'shutdown', error, stack);
      }
    }();
    _shutdownFuture = shutdown;
    return shutdown;
  }

  Future<void> _shutdownResources() async {
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
          onError: (error, stack) => silentLog(
            'machine_terminal',
            'await workspace load',
            error,
            stack,
          ),
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
            onError: (error, stack) => silentLog(
              'machine_terminal',
              'await pending persist',
              error,
              stack,
            ),
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
                silentLog('machine_terminal', 'flush workspace', error, stack),
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
                silentLog('machine_terminal', 'stop workspace', error, stack),
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
      throw StateError('MachineTerminalService is shut down.');
    }
    final normalizedSessionId = _normalizeSessionId(sessionId);
    if (_workspaceDisposals.containsKey(normalizedSessionId)) {
      throw StateError('Machine terminal workspace is being disposed.');
    }
    final loaded = _workspaces[normalizedSessionId];
    if (loaded != null) return Future<_MachineTerminalWorkspace>.value(loaded);
    final activeLoad = _workspaceLoads[normalizedSessionId];
    if (activeLoad != null) return activeLoad;

    final generation = _workspaceLoadGenerations[normalizedSessionId] ?? 0;
    late final Future<_MachineTerminalWorkspace> tracked;
    tracked =
        _loadWorkspace(
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
      throw StateError('Machine terminal workspace load was cancelled.');
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
      throw StateError('No terminal is available for session $sessionId.');
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
      () {
        if (_isDisposed || terminal.isRunningOrStarting) return;
        unawaited(
          terminal.start().whenComplete(
            () => _scheduleMetadataPersist(terminal.sessionId),
          ),
        );
      },
      onError: (error, stack) => silentLog(
        'machine_terminal',
        'deferred terminal start',
        error,
        stack,
      ),
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
      throw FileSystemException(
        'Machine terminal history is not a regular file.',
        file.path,
      );
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
      final retained = terminalsJson.take(_maxPersistedTerminalSnapshots);
      for (final item in retained) {
        final terminalJson = stringKeyedMapFromValue(item);
        final terminalId = nullIfBlank('${terminalJson['terminal_id'] ?? ''}');
        if (terminalId == null) continue;
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
      final persistedTerminals = _retainedPersistedTerminals(
        snapshot.terminals,
      ).map((terminal) => terminal.toJson()).toList(growable: false);
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
      silentLog('machine_terminal', 'restore terminal history', error, stack);
      return null;
    }
  }

  void _scheduleHistoryPersist(String sessionId) {
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null || _isDisposed) return;
    _historyPersistTimers[normalizedSessionId]?.cancel();
    _historyPersistTimers[normalizedSessionId] = startSafeTimer(
      _historyPersistDebounce,
      () {
        _historyPersistTimers.remove(normalizedSessionId);
        final previous =
            _historyPersistChains[normalizedSessionId] ?? Future<void>.value();
        late final Future<void> tracked;
        tracked = previous
            .catchError((Object error, StackTrace stack) {
              silentLog(
                'machine_terminal',
                'history persist queue',
                error,
                stack,
              );
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
      onError: (error, stack) => silentLog(
        'machine_terminal',
        'schedule history persist',
        error,
        stack,
      ),
    );
  }

  Future<void> _persistWorkspaceHistoryNow(String sessionId) async {
    final workspace = _workspaces[sessionId];
    if (workspace == null) return;
    final snapshot = workspace.snapshot();
    final terminals = _retainedPersistedTerminals(snapshot.terminals);
    final terminalsJson = terminals
        .map((terminal) => terminal.toJson())
        .toList(growable: false);
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
    try {
      if (utf8.encode(content).length > _machineTerminalHistoryMaxBytes) {
        throw StateError('Machine terminal history exceeds its size limit.');
      }
      await writeFileAtomically(_workspaceHistoryFile(sessionId), content);
      _lastPersistedHistoryDigestBySession[sessionId] = digest;
    } catch (error, stack) {
      silentLog('machine_terminal', 'persist terminal history', error, stack);
    }
  }

  List<MachineTerminalSnapshot> _retainedPersistedTerminals(
    List<MachineTerminalSnapshot> terminals,
  ) {
    if (terminals.length <= _maxPersistedTerminalSnapshots) {
      return terminals;
    }
    final byRecent = List<MachineTerminalSnapshot>.from(terminals)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final retainedIds = byRecent
        .take(_maxPersistedTerminalSnapshots)
        .map((terminal) => terminal.terminalId)
        .toSet();
    return terminals
        .where((terminal) => retainedIds.contains(terminal.terminalId))
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
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error, stack) {
      silentLog(
        'machine_terminal',
        'delete terminal history file',
        error,
        stack,
      );
    }
  }

  File _workspaceHistoryFile(String sessionId) {
    return File(
      p.join(
        _sessionsDirectoryPath,
        _safeSessionStorageSegment(sessionId),
        _machineTerminalHistoryFileName,
      ),
    );
  }

  void _scheduleMetadataPersist(String sessionId) {
    final normalizedSessionId = nullIfBlank(sessionId);
    if (normalizedSessionId == null || _metadataPersister == null) return;
    _metadataPersistTimers[normalizedSessionId]?.cancel();
    _metadataPersistTimers[normalizedSessionId] = startSafeTimer(
      _metadataPersistDebounce,
      () {
        _metadataPersistTimers.remove(normalizedSessionId);
        final previous =
            _metadataPersistChains[normalizedSessionId] ?? Future<void>.value();
        late final Future<void> tracked;
        tracked = previous
            .catchError((Object error, StackTrace stack) {
              silentLog(
                'machine_terminal',
                'metadata persist queue',
                error,
                stack,
              );
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
      onError: (error, stack) => silentLog(
        'machine_terminal',
        'schedule metadata persist',
        error,
        stack,
      ),
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
      silentLog('machine_terminal', 'persist metadata', error, stack);
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
  String _output = '';
  String _historyOutput = _welcomeBanner();
  final List<MachineTerminalCommandRecord> _commandHistory =
      <MachineTerminalCommandRecord>[];
  int _commandSequence = 0;
  bool _attached = true;
  bool _hasUserActivity = false;

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
    final ansiOutput = _clipString(_output, _maxToolOutputCharacters);
    final historyOutput = _clipString(
      _plainText(_historyOutput),
      _maxReplayOutputCharacters,
    );
    final historyAnsiOutput = _clipString(
      _historyOutput,
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
    _output = _clipString(
      '${raw['ansi_output'] ?? raw['output'] ?? ''}',
      _maxRetainedOutputCharacters,
    );
    final history =
        '${raw['history_ansi_output'] ?? raw['history_output'] ?? _output}';
    _historyOutput = _clipString(
      history.trim().isEmpty ? _welcomeBanner() : history,
      _maxRetainedHistoryCharacters,
    );
    _commandHistory
      ..clear()
      ..addAll(
        _restoredCommandHistory(raw['command_history'], fallbackTerminalId: id),
      );
    _commandSequence = math.max(
      optionalIntFromValue(raw['command_count']) ?? _commandHistory.length,
      _maxRestoredCommandSequence(_commandHistory),
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
    _errorMessage = nullIfBlank('${raw['error_message'] ?? ''}');
    final visibleOutput = _output.trim().isEmpty
        ? _clipString(_historyOutput, _maxToolOutputCharacters)
        : _output;
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

  Future<void> start() async {
    if (isRunningOrStarting) return;
    final generation = ++_startGeneration;
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
              if (!identical(_pty, pty)) return;
              _status = MachineTerminalStatus.failed;
              _errorMessage = '$error';
              silentLog('machine_terminal', 'pty output', error, stack);
              _touch();
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
              _appendPlain('\r\n[OpenHand terminal exited: $code]\r\n');
              _touch();
            })
            .catchError((Object error, StackTrace stack) {
              if (!identical(_pty, pty)) return;
              _status = MachineTerminalStatus.failed;
              _errorMessage = '$error';
              silentLog('machine_terminal', 'pty exitCode', error, stack);
              _touch();
            }),
      );
    } catch (error, stack) {
      _status = MachineTerminalStatus.failed;
      _errorMessage = '$error';
      _appendPlain('\r\n[OpenHand terminal failed: $error]\r\n');
      silentLog('machine_terminal', 'start pty', error, stack);
    } finally {
      _touch();
    }
  }

  Future<void> stop({bool force = false}) async {
    _startGeneration += 1;
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
    try {
      pty.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
      if (!force) {
        await pty.exitCode.timeout(
          _terminalStopGraceDuration,
          onTimeout: () {
            pty.kill(ProcessSignal.sigkill);
            return _exitCode ?? -1;
          },
        );
      }
    } catch (error, stack) {
      silentLog('machine_terminal', 'stop pty', error, stack);
    } finally {
      unawaited(_cancelOutputSubscription(outputSubscription));
      _status = MachineTerminalStatus.stopped;
      _touch();
    }
  }

  Future<void> _cancelOutputSubscription(
    StreamSubscription<String>? subscription,
  ) async {
    await cancelStreamSubscriptionBounded<String>(
      subscription,
      onError: (error, stack) => silentLog(
        'machine_terminal',
        'cancel PTY output subscription',
        error,
        stack,
      ),
    );
  }

  Future<void> restart() async {
    await stop(force: true);
    clear();
    await start();
  }

  void clear() {
    _output = '';
    _appendHistory('\r\n[OpenHand terminal cleared]\r\n${_welcomeBanner()}');
    terminal.write('\x1b[2J\x1b[H${_welcomeBanner()}');
    _touch();
  }

  void writeInput(String data) {
    final pty = _pty;
    if (pty == null || _status != MachineTerminalStatus.running) {
      return;
    }
    if (data.isNotEmpty) {
      _hasUserActivity = true;
    }
    pty.write(Uint8List.fromList(utf8.encode(data)));
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
  }) async {
    final stopwatch = Stopwatch()..start();
    final startedAt = DateTime.now();
    final begin = '__${beginMarker}__';
    final end = '__${endMarker}__';
    final startOffset = _output.length;
    try {
      await _disableEchoForCommand();
      final payload = _commandPayload(command: command, begin: begin, end: end);
      writeInput(payload);
      final parsed = await _waitForCommandOutput(
        begin: begin,
        end: end,
        startOffset: startOffset,
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
      writeInput('stty echo 2>/dev/null\n');
      return _recordedCommandResult(
        startedAt: startedAt,
        command: command,
        output: _clipToolOutput(
          _plainText(_outputSince(startOffset)).trimRight(),
        ),
        durationMs: stopwatch.elapsedMilliseconds,
        timedOut: true,
        error: 'Timed out after ${timeout.inMilliseconds}ms.',
      );
    } catch (error, stack) {
      silentLog('machine_terminal', 'execute command', error, stack);
      return _recordedCommandResult(
        startedAt: startedAt,
        command: command,
        output: _clipToolOutput(
          _plainText(_outputSince(startOffset)).trimRight(),
        ),
        durationMs: stopwatch.elapsedMilliseconds,
        error: '$error',
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
    _hasUserActivity = true;
    _commandSequence += 1;
    _commandHistory.add(
      MachineTerminalCommandRecord(
        id: 'cmd-$_commandSequence',
        terminalId: id,
        command: result.command,
        output: result.output,
        startedAt: startedAt,
        completedAt: DateTime.now(),
        durationMs: result.durationMs,
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        error: result.error,
      ),
    );
    if (_commandHistory.length > _maxCommandHistoryEntries) {
      _commandHistory.removeRange(
        0,
        _commandHistory.length - _maxCommandHistoryEntries,
      );
    }
    _touch();
  }

  String sanitizedOutput({int maxCharacters = _maxToolOutputCharacters}) {
    return _clipString(_plainText(_output), maxCharacters);
  }

  void dispose() {
    unawaited(stop(force: true));
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
      silentLog('machine_terminal', 'resize pty', error, stack);
    }
    _touch();
  }

  void _handleOutput(String text) {
    terminal.write(text);
    _appendRaw(text);
    _touch();
  }

  void _appendPlain(String text) {
    terminal.write(text);
    _appendRaw(text);
  }

  void _appendRaw(String text) {
    _output += text;
    if (_output.length > _maxRetainedOutputCharacters) {
      _output = _output.substring(
        _output.length - _maxRetainedOutputCharacters,
      );
    }
    _appendHistory(text);
  }

  void _appendHistory(String text) {
    _historyOutput += text;
    if (_historyOutput.length > _maxRetainedHistoryCharacters) {
      _historyOutput = _historyOutput.substring(
        _historyOutput.length - _maxRetainedHistoryCharacters,
      );
    }
  }

  void _touch() {
    _updatedAt = DateTime.now();
    _onChanged();
  }

  Future<void> _disableEchoForCommand() async {
    if (Platform.isWindows) return;
    writeInput('stty -echo 2>/dev/null\n');
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  Future<_ParsedCommandOutput> _waitForCommandOutput({
    required String begin,
    required String end,
    required int startOffset,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final segment = _plainText(_outputSince(startOffset));
      final beginIndex = segment.indexOf(begin);
      final endIndex = segment.indexOf(end, beginIndex < 0 ? 0 : beginIndex);
      if (beginIndex >= 0 && endIndex > beginIndex) {
        final afterEnd = segment.substring(endIndex + end.length);
        final exitCodeMatch = RegExp(r':(-?\d+)').firstMatch(afterEnd);
        final output = segment.substring(beginIndex + begin.length, endIndex);
        return _ParsedCommandOutput(
          output: _removeMarkerNoise(output),
          exitCode: optionalIntFromValue(exitCodeMatch?.group(1)),
        );
      }
      await Future<void>.delayed(_commandPollInterval);
    }
    throw TimeoutException('Timed out waiting for terminal marker.', timeout);
  }

  String _outputSince(int offset) {
    final safeOffset = offset.clamp(0, _output.length).toInt();
    return _output.substring(safeOffset);
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
  for (final item in value) {
    final record = MachineTerminalCommandRecord.fromJson(
      item,
      fallbackTerminalId: fallbackTerminalId,
    );
    if (record != null) {
      records.add(record);
    }
  }
  if (records.length <= _maxCommandHistoryEntries) {
    return records;
  }
  return records.sublist(records.length - _maxCommandHistoryEntries);
}

int _maxRestoredCommandSequence(List<MachineTerminalCommandRecord> records) {
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

String _safeSessionStorageSegment(String sessionId) {
  final normalized = _normalizeSessionId(sessionId);
  return normalized.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

String _resolveShellExecutable() {
  if (Platform.isWindows) {
    return Platform.environment['COMSPEC'] ?? 'cmd.exe';
  }
  return nullIfBlank(Platform.environment['SHELL']) ?? '/bin/zsh';
}

String _normalizeSessionId(String sessionId) {
  final normalized = nullIfBlank(sessionId);
  if (normalized == null) {
    throw ArgumentError('sessionId must not be empty.');
  }
  return normalized;
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
    // The application directory below is the stable fallback.
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

String _welcomeBanner() {
  return '\x1b[38;5;108mOpenHand machine terminal\x1b[0m\r\n';
}

String _commandPayload({
  required String command,
  required String begin,
  required String end,
}) {
  if (Platform.isWindows) {
    return 'echo $begin\r\n$command\r\necho $end:%ERRORLEVEL%\r\n';
  }
  return "printf '\\n$begin\\n'\n"
      '(\n'
      '$command\n'
      ')\n'
      '__openhand_status=\$?\n'
      "printf '\\n$end:%s\\n' \"\$__openhand_status\"\n"
      'stty echo 2>/dev/null\n';
}

String _plainText(String value) {
  return value
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'\x1B\][^\x07]*(\x07|\x1B\\)'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
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

String _clipString(String value, int maxCharacters) {
  if (value.length <= maxCharacters) return value;
  final head = maxCharacters ~/ 2;
  final tail = maxCharacters - head;
  return '${value.substring(0, head)}\n[... clipped ${value.length - maxCharacters} chars ...]\n${value.substring(value.length - tail)}';
}

int _coerceRows(int value) => math.min(math.max(1, value), _maxRows);

int _coerceColumns(int value) => math.min(math.max(1, value), _maxColumns);
