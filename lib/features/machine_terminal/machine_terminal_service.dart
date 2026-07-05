import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../app/support/openhand_paths.dart';
import '../../app/support/silent_log.dart';
import '../../shared/util/input_value_parsing.dart';

const String kMachineExpertTemplateId = 'machine_expert';
const String kMachineTerminalMetadataKey = 'machine_terminal';

const int _defaultRows = 30;
const int _defaultColumns = 100;
const int _maxRows = 240;
const int _maxColumns = 400;
const int _maxRetainedOutputCharacters = 240000;
const int _maxToolOutputCharacters = 120000;
const Duration _defaultCommandTimeout = Duration(seconds: 120);
const Duration _commandPollInterval = Duration(milliseconds: 80);

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
    required this.startedAt,
    required this.updatedAt,
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
  final DateTime startedAt;
  final DateTime updatedAt;
  final int? pid;
  final int? exitCode;
  final String? errorMessage;

  Map<String, Object?> toJson() {
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
      if (terminal.terminalId == activeTerminalId) {
        return terminal;
      }
    }
    return terminals.isEmpty ? null : terminals.first;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'session_id': sessionId,
      'active_terminal_id': activeTerminalId,
      'terminals': terminals.map((item) => item.toJson()).toList(),
      'active_terminal': activeTerminal?.toJson(),
    };
  }
}

class MachineTerminalService extends ChangeNotifier {
  final Map<String, _MachineTerminalWorkspace> _workspaces =
      <String, _MachineTerminalWorkspace>{};

  int _terminalCounter = 0;
  int _commandCounter = 0;

  MachineTerminalWorkspaceSnapshot ensureWorkspace({
    required String sessionId,
    String? workingDirectory,
    bool start = true,
  }) {
    final workspace = _workspaceFor(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
    );
    if (start) {
      final active = workspace.activeTerminal;
      if (active != null && !active.isRunningOrStarting) {
        unawaited(active.start());
      }
    }
    return workspace.snapshot();
  }

  MachineTerminalWorkspaceSnapshot? snapshot(String sessionId) {
    return _workspaces[sessionId.trim()]?.snapshot();
  }

  MachineTerminalSession? activeTerminal(String sessionId) {
    return _workspaces[sessionId.trim()]?.activeTerminal;
  }

  Future<void> disposeWorkspace(String sessionId) async {
    final workspace = _workspaces.remove(sessionId.trim());
    if (workspace == null) return;
    await workspace.shutdown();
    notifyListeners();
  }

  Future<MachineTerminalSession> newTerminal({
    required String sessionId,
    String? workingDirectory,
    bool start = true,
  }) async {
    final workspace = _workspaceFor(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
    );
    final terminal = _createTerminal(
      sessionId: workspace.sessionId,
      workingDirectory:
          nullIfBlank(workingDirectory) ?? workspace.defaultWorkingDirectory,
    );
    workspace.add(terminal);
    notifyListeners();
    if (start) {
      await terminal.start();
    }
    return terminal;
  }

  Future<MachineTerminalSession> duplicateTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final workspace = _requireWorkspace(sessionId);
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
    final workspace = _requireWorkspace(sessionId);
    workspace.select(terminalId);
    notifyListeners();
  }

  Future<void> closeTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final workspace = _requireWorkspace(sessionId);
    final terminal =
        workspace.terminalById(terminalId) ?? workspace.activeTerminal;
    if (terminal == null) return;
    await terminal.stop(force: true);
    workspace.remove(terminal.id);
    if (workspace.terminals.isEmpty) {
      workspace.add(
        _createTerminal(
          sessionId: workspace.sessionId,
          workingDirectory: workspace.defaultWorkingDirectory,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> startTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final terminal = _requireTerminal(sessionId, terminalId);
    await terminal.start();
  }

  Future<void> stopTerminal({
    required String sessionId,
    String? terminalId,
    bool force = false,
  }) async {
    final terminal = _requireTerminal(sessionId, terminalId);
    await terminal.stop(force: force);
  }

  Future<void> restartTerminal({
    required String sessionId,
    String? terminalId,
  }) async {
    final terminal = _requireTerminal(sessionId, terminalId);
    await terminal.restart();
  }

  void clearTerminal({required String sessionId, String? terminalId}) {
    final terminal = _requireTerminal(sessionId, terminalId);
    terminal.clear();
  }

  void resizeTerminal({
    required String sessionId,
    String? terminalId,
    required int columns,
    required int rows,
  }) {
    final terminal = _requireTerminal(sessionId, terminalId);
    terminal.resize(columns: columns, rows: rows);
  }

  Future<void> writeInput({
    required String sessionId,
    required String data,
    String? terminalId,
    bool appendNewline = false,
  }) async {
    final terminal = _requireTerminal(sessionId, terminalId);
    if (!terminal.isRunningOrStarting) {
      await terminal.start();
    }
    terminal.writeInput(appendNewline ? '$data\n' : data);
  }

  Future<MachineTerminalCommandResult> executeCommand({
    required String sessionId,
    required String command,
    String? terminalId,
    Duration timeout = _defaultCommandTimeout,
  }) async {
    final terminal = _requireTerminal(sessionId, terminalId);
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
    return terminal.executeCommand(
      command: trimmed,
      beginMarker: '${token}_BEGIN',
      endMarker: '${token}_END',
      timeout: timeout,
    );
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
        clearTerminal(sessionId: sessionId, terminalId: terminalId);
      case 'resize':
        final safeColumns = columns;
        final safeRows = rows;
        if (safeColumns == null || safeRows == null) {
          throw ArgumentError('resize requires columns and rows.');
        }
        resizeTerminal(
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
      case 'select':
        final id = nullIfBlank(terminalId);
        if (id == null) {
          throw ArgumentError('select requires terminal_id.');
        }
        await selectTerminal(sessionId: sessionId, terminalId: id);
      default:
        throw ArgumentError(
          'Unsupported terminal action "$action". Use start, stop, restart, clear, resize, new, duplicate, close, or select.',
        );
    }
    return ensureWorkspace(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
      start: false,
    );
  }

  Map<String, Object?> initialMetadata({
    required String sessionId,
    String? workingDirectory,
  }) {
    final snapshot = ensureWorkspace(
      sessionId: sessionId,
      workingDirectory: workingDirectory,
      start: false,
    );
    return <String, Object?>{
      'schema_version': 1,
      'active_terminal_id': snapshot.activeTerminalId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'working_directory':
          nullIfBlank(workingDirectory) ??
          OpenHandPaths.applicationDirectoryPath(),
    };
  }

  @override
  void dispose() {
    for (final workspace in _workspaces.values) {
      workspace.dispose();
    }
    _workspaces.clear();
    super.dispose();
  }

  _MachineTerminalWorkspace _workspaceFor({
    required String sessionId,
    String? workingDirectory,
  }) {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw ArgumentError('sessionId must not be empty.');
    }
    return _workspaces.putIfAbsent(normalizedSessionId, () {
      final workspace = _MachineTerminalWorkspace(
        sessionId: normalizedSessionId,
        defaultWorkingDirectory:
            nullIfBlank(workingDirectory) ??
            OpenHandPaths.applicationDirectoryPath(),
      );
      workspace.add(
        _createTerminal(
          sessionId: normalizedSessionId,
          workingDirectory: workspace.defaultWorkingDirectory,
        ),
      );
      return workspace;
    });
  }

  _MachineTerminalWorkspace _requireWorkspace(String sessionId) {
    return _workspaceFor(sessionId: sessionId);
  }

  MachineTerminalSession _requireTerminal(
    String sessionId,
    String? terminalId,
  ) {
    final workspace = _requireWorkspace(sessionId);
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
  }) {
    final id = 'term-${++_terminalCounter}';
    final shell = _resolveShellExecutable();
    final terminal = MachineTerminalSession(
      id: id,
      sessionId: sessionId,
      identity: 'machine-$id',
      shell: shell,
      workingDirectory: workingDirectory,
      onChanged: notifyListeners,
    );
    return terminal;
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
         maxLines: 5000,
         platform: _terminalTargetPlatform(),
       ) {
    terminal
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
  String _output = '';

  MachineTerminalStatus get status => _status;
  int? get pid => _pid;
  int? get exitCode => _exitCode;
  String? get errorMessage => _errorMessage;
  bool get isRunningOrStarting =>
      _status == MachineTerminalStatus.running ||
      _status == MachineTerminalStatus.starting;

  MachineTerminalSnapshot snapshot() {
    final output = sanitizedOutput();
    final ansiOutput = _clipString(_output, _maxToolOutputCharacters);
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
      startedAt: _startedAt,
      updatedAt: _updatedAt,
      pid: _pid,
      exitCode: _exitCode,
      errorMessage: _errorMessage,
    );
  }

  Future<void> start() async {
    if (isRunningOrStarting) return;
    _status = MachineTerminalStatus.starting;
    _errorMessage = null;
    _exitCode = null;
    _startedAt = DateTime.now();
    _touch();
    try {
      final pty = Pty.start(
        shell,
        arguments: _shellArguments(shell),
        workingDirectory: _safeWorkingDirectory(workingDirectory),
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
              _status = MachineTerminalStatus.failed;
              _errorMessage = '$error';
              silentLog('machine_terminal', 'pty output', error, stack);
              _touch();
            },
          );
      unawaited(
        pty.exitCode
            .then((code) {
              _exitCode = code;
              if (_status != MachineTerminalStatus.failed) {
                _status = MachineTerminalStatus.stopped;
              }
              _appendPlain('\r\n[OpenHand terminal exited: $code]\r\n');
              _touch();
            })
            .catchError((Object error, StackTrace stack) {
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
    final pty = _pty;
    if (pty == null) {
      _status = MachineTerminalStatus.stopped;
      _touch();
      return;
    }
    try {
      pty.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
      if (!force) {
        await pty.exitCode.timeout(
          const Duration(milliseconds: 900),
          onTimeout: () {
            pty.kill(ProcessSignal.sigkill);
            return _exitCode ?? -1;
          },
        );
      }
    } catch (error, stack) {
      silentLog('machine_terminal', 'stop pty', error, stack);
    } finally {
      await _outputSubscription?.cancel();
      _outputSubscription = null;
      _pty = null;
      _status = MachineTerminalStatus.stopped;
      _touch();
    }
  }

  Future<void> restart() async {
    await stop(force: true);
    clear();
    await start();
  }

  void clear() {
    _output = '';
    terminal.write('\x1b[2J\x1b[H${_welcomeBanner()}');
    _touch();
  }

  void writeInput(String data) {
    final pty = _pty;
    if (pty == null || _status != MachineTerminalStatus.running) {
      return;
    }
    pty.write(Uint8List.fromList(utf8.encode(data)));
  }

  void resize({required int columns, required int rows}) {
    terminal.resize(_coerceColumns(columns), _coerceRows(rows));
  }

  Future<MachineTerminalCommandResult> executeCommand({
    required String command,
    required String beginMarker,
    required String endMarker,
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
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
      return MachineTerminalCommandResult(
        terminalId: id,
        command: command,
        output: _clipToolOutput(parsed.output.trim()),
        exitCode: parsed.exitCode,
        status: _status,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      writeInput('stty echo 2>/dev/null\n');
      return MachineTerminalCommandResult(
        terminalId: id,
        command: command,
        output: _clipToolOutput(
          _plainText(_outputSince(startOffset)).trimRight(),
        ),
        status: _status,
        durationMs: stopwatch.elapsedMilliseconds,
        timedOut: true,
        error: 'Timed out after ${timeout.inMilliseconds}ms.',
      );
    } catch (error, stack) {
      silentLog('machine_terminal', 'execute command', error, stack);
      return MachineTerminalCommandResult(
        terminalId: id,
        command: command,
        output: _clipToolOutput(
          _plainText(_outputSince(startOffset)).trimRight(),
        ),
        status: _status,
        durationMs: stopwatch.elapsedMilliseconds,
        error: '$error',
      );
    }
  }

  String sanitizedOutput({int maxCharacters = _maxToolOutputCharacters}) {
    return _clipString(_plainText(_output), maxCharacters);
  }

  void dispose() {
    unawaited(stop(force: true));
  }

  void _handleResize(int width, int height, int pixelWidth, int pixelHeight) {
    _columns = _coerceColumns(width);
    _rows = _coerceRows(height);
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

  void add(MachineTerminalSession terminal) {
    terminals.add(terminal);
    activeTerminalId = terminal.id;
  }

  void remove(String terminalId) {
    terminals.removeWhere((item) => item.id == terminalId);
    if (activeTerminalId == terminalId) {
      activeTerminalId = terminals.isEmpty ? '' : terminals.last.id;
    }
  }

  void select(String terminalId) {
    if (terminals.any((item) => item.id == terminalId)) {
      activeTerminalId = terminalId;
    }
  }

  MachineTerminalSession? terminalById(String? terminalId) {
    final id = nullIfBlank(terminalId) ?? activeTerminalId;
    if (id.isEmpty) return terminals.isEmpty ? null : terminals.first;
    for (final terminal in terminals) {
      if (terminal.id == id) return terminal;
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

String _resolveShellExecutable() {
  if (Platform.isWindows) {
    return Platform.environment['COMSPEC'] ?? 'cmd.exe';
  }
  return nullIfBlank(Platform.environment['SHELL']) ?? '/bin/zsh';
}

List<String> _shellArguments(String shell) {
  if (Platform.isWindows) return const <String>[];
  final basename = shell.split(Platform.pathSeparator).last;
  if (basename == 'zsh' || basename == 'bash') {
    return const <String>['-l'];
  }
  return const <String>[];
}

String _safeWorkingDirectory(String value) {
  final normalized =
      nullIfBlank(value) ?? OpenHandPaths.applicationDirectoryPath();
  try {
    final directory = Directory(normalized);
    if (directory.existsSync()) return directory.path;
  } catch (_) {}
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
