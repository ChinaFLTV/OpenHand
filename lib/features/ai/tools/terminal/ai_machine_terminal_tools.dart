import '../../../../app/support/silent_log.dart';
import '../../../machine_terminal/index.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

abstract final class AiMachineTerminalBoundaryPolicy {
  static const Set<String> allowedControlActions = <String>{'clear', 'resize'};

  static const Map<int, String> _blockedControlCharacters = <int, String>{
    0x04: 'Ctrl-D/EOF',
    0x1a: 'Ctrl-Z',
    0x1c: r'Ctrl-\',
    0x1d: 'Ctrl-]',
  };

  static final RegExp _sessionExitCommandPattern = RegExp(
    r'(?:^|[\r\n;]|&&|\|\||\|)\s*(?:(?:then|do|else|\{)\s+)?(?:(?:builtin|command|exec)\s+)?(?:exit|logout|suspend)(?=$|[\s;&|}<])',
    caseSensitive: false,
  );
  static final RegExp _shellReplacementPattern = RegExp(
    r'(?:^|[\r\n;]|&&|\|\||\|)\s*(?:(?:command|builtin)\s+)?exec(?=$|[\s;&|])',
    caseSensitive: false,
  );
  static final RegExp _sshDisconnectPattern = RegExp(r'(?:^|[\r\n])\s*~\.');
  static final RegExp _currentShellKillPattern = RegExp(
    r'(?:^|[\r\n;]|&&|\|\||\|)\s*(?:(?:command|builtin|sudo)\s+)*(?:[^\s;&|]*/)?kill\b[^\r\n;&|]*(?:\$\$|\$\{?PPID\}?)',
    caseSensitive: false,
  );

  static String? inputViolation(String value) {
    for (final codeUnit in value.codeUnits) {
      final label = _blockedControlCharacters[codeUnit];
      if (label != null) {
        return '禁止 AI 发送 $label，以免中断 relay/SSH 或退出当前终端。';
      }
    }
    final shellText = _maskQuotedShellText(value);
    if (_sshDisconnectPattern.hasMatch(shellText)) {
      return '禁止 AI 发送 SSH 断连转义“~.”。';
    }
    if (_sessionExitCommandPattern.hasMatch(shellText) ||
        _shellReplacementPattern.hasMatch(shellText)) {
      return '禁止 AI 执行会退出、挂起或替换当前交互 Shell 的命令。';
    }
    if (_currentShellKillPattern.hasMatch(shellText)) {
      return '禁止 AI 终止当前 Shell 或其父进程。';
    }
    return null;
  }

  static bool allowsControlAction(String action) {
    return allowedControlActions.contains(action.trim().toLowerCase());
  }

  static String _maskQuotedShellText(String value) {
    final buffer = StringBuffer();
    var quote = 0;
    var escaped = false;
    for (final codeUnit in value.codeUnits) {
      if (escaped) {
        buffer.writeCharCode(0x20);
        escaped = false;
        continue;
      }
      if (codeUnit == 0x5c && quote != 0x27) {
        buffer.writeCharCode(0x20);
        escaped = true;
        continue;
      }
      if (quote == 0) {
        if (codeUnit == 0x27 || codeUnit == 0x22 || codeUnit == 0x60) {
          quote = codeUnit;
          buffer.writeCharCode(0x20);
        } else {
          buffer.writeCharCode(codeUnit);
        }
        continue;
      }
      buffer.writeCharCode(0x20);
      if (codeUnit == quote) quote = 0;
    }
    return buffer.toString();
  }
}

abstract class AiMachineTerminalToolBase extends AiTool {
  MachineTerminalService? terminalService(AiToolExecutionContext context) {
    final raw = context.metadata['machine_terminal_service'];
    if (raw is! MachineTerminalService) return null;
    raw.rememberSessionMetadata(
      sessionId: context.sessionId,
      metadata: context.metadata[kMachineTerminalMetadataKey],
    );
    return raw;
  }

  AiToolExecutionResult missingServiceResult(String toolName) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: toolName,
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: '当前会话不可用机器终端服务，请仅在 machine_expert 模板中使用此工具。',
      durationMs: 0,
      resultText: 'status: failed\nerror: 当前会话不可用机器终端服务。',
    );
  }

  AiToolExecutionResult? inactiveTerminalResult({
    required MachineTerminalService service,
    required AiToolExecutionContext context,
    required MachineTerminalWorkspaceSnapshot snapshot,
    required String toolName,
    required String? terminalId,
  }) {
    final activeTerminalId = snapshot.activeTerminalId.trim();
    if (terminalId == null ||
        activeTerminalId.isEmpty ||
        terminalId == activeTerminalId) {
      return null;
    }
    return boundaryDeniedResult(
      service: service,
      context: context,
      toolName: toolName,
      reason: 'AI 只能操作当前活动终端，禁止切换执行目标。',
      metadata: <String, Object?>{
        'active_terminal_id': activeTerminalId,
        'requested_terminal_id': terminalId,
      },
    );
  }

  AiToolExecutionResult boundaryDeniedResult({
    required MachineTerminalService service,
    required AiToolExecutionContext context,
    required String toolName,
    required String reason,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final active = service.snapshot(context.sessionId)?.activeTerminal;
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.denied,
      command: toolName,
      workingDirectory:
          active?.workingDirectory ?? AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: reason,
      durationMs: 0,
      resultText:
          'status: denied\nerror: $reason\nterminal_boundary_preserved: true',
      metadata: <String, Object?>{
        'terminal_boundary_preserved': true,
        'terminal_boundary_guard': 'ai_session_boundary',
        if (active != null) 'terminal_id': active.terminalId,
        ...metadata,
      },
    );
  }

  String? readTerminalId(Map<String, Object?> args) {
    final id = AiToolUtils.readFirstString(args, const <String>[
      'terminal_id',
      'terminalId',
      'id',
    ]).trim();
    return id.isEmpty ? null : id;
  }
}

class AiMachineTerminalReadTool extends AiMachineTerminalToolBase {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.machineTerminalRead;

  @override
  List<String> get aliases => const <String>[
    'MachineTerminalRead',
    'TerminalRead',
  ];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final service = terminalService(context);
    if (service == null) return missingServiceResult('MachineTerminalRead');
    final stopwatch = Stopwatch()..start();
    final args = context.decodedArguments;
    final terminalId = readTerminalId(args);
    final snapshot = await service.ensureWorkspace(
      sessionId: context.sessionId,
      start: false,
    );
    final inactiveResult = inactiveTerminalResult(
      service: service,
      context: context,
      snapshot: snapshot,
      toolName: 'MachineTerminalRead',
      terminalId: terminalId,
    );
    if (inactiveResult != null) return inactiveResult;
    final active = snapshot.activeTerminal;
    if (active == null) {
      return AiToolUtils.invalidResult(
        'MachineTerminalRead',
        '找不到终端：${terminalId ?? snapshot.activeTerminalId}',
      );
    }
    final terminalMetadata = service.sessionMetadata(
      sessionId: context.sessionId,
      existingMetadata: context.metadata[kMachineTerminalMetadataKey],
      snapshot: snapshot,
    );
    final output = _terminalSnapshotText(snapshot, active, terminalMetadata);
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: 'MachineTerminalRead',
      workingDirectory: active.workingDirectory,
      stdout: output,
      stderr: '',
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: output,
      metadata: <String, Object?>{
        'machine_terminal_snapshot': _snapshotMetadata(snapshot),
        'machine_terminal_metadata': terminalMetadata,
        'terminal_id': active.terminalId,
      },
    );
  }
}

class AiMachineTerminalWriteTool extends AiMachineTerminalToolBase {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.machineTerminalWrite;

  @override
  List<String> get aliases => const <String>[
    'MachineTerminalWrite',
    'TerminalWrite',
  ];

  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final service = terminalService(context);
    if (service == null) return missingServiceResult('MachineTerminalWrite');
    final args = context.decodedArguments;
    final terminalId = readTerminalId(args);
    final snapshot = await service.ensureWorkspace(
      sessionId: context.sessionId,
      start: false,
    );
    final inactiveResult = inactiveTerminalResult(
      service: service,
      context: context,
      snapshot: snapshot,
      toolName: 'MachineTerminalWrite',
      terminalId: terminalId,
    );
    if (inactiveResult != null) return inactiveResult;
    if (snapshot.activeTerminal?.status != MachineTerminalStatus.running) {
      return boundaryDeniedResult(
        service: service,
        context: context,
        toolName: 'MachineTerminalWrite',
        reason: '当前终端未运行，请用户在左侧面板启动或重新连接。',
      );
    }
    final data = AiToolUtils.readFirstString(args, const <String>[
      'data',
      'text',
      'input',
    ]);
    if (data.isEmpty) {
      return AiToolUtils.invalidResult('MachineTerminalWrite', 'data 不能为空。');
    }
    final violation = AiMachineTerminalBoundaryPolicy.inputViolation(data);
    if (violation != null) {
      return boundaryDeniedResult(
        service: service,
        context: context,
        toolName: 'MachineTerminalWrite',
        reason: violation,
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      await service.writeInput(
        sessionId: context.sessionId,
        terminalId: terminalId,
        data: data,
        appendNewline:
            AiToolUtils.readBool(args['append_newline']) == true ||
            AiToolUtils.readBool(args['enter']) == true,
        startIfNeeded: false,
      );
    } catch (error, stack) {
      silentLog('ai_machine_terminal_tools', '写入机器终端', error, stack);
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'MachineTerminalWrite',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: '写入机器终端失败。',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: 写入机器终端失败。',
      );
    }
    final active = service.snapshot(context.sessionId)?.activeTerminal;
    final output =
        'terminal_id: ${active?.terminalId ?? ''}\n'
        'status: ${active?.status.storageValue ?? 'running'}\n'
        'written_chars: ${data.length}';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: 'MachineTerminalWrite',
      workingDirectory:
          active?.workingDirectory ?? AiToolUtils.defaultWorkingDirectory(),
      stdout: output,
      stderr: '',
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: output,
      metadata: <String, Object?>{
        'terminal_id': active?.terminalId,
        'written_chars': data.length,
      },
    );
  }
}

class AiMachineTerminalExecTool extends AiMachineTerminalToolBase {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.machineTerminalExec;

  @override
  List<String> get aliases => const <String>[
    'MachineTerminalExec',
    'TerminalExec',
    'TerminalCommand',
  ];

  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final service = terminalService(context);
    if (service == null) return missingServiceResult('MachineTerminalExec');
    final args = context.decodedArguments;
    final terminalId = readTerminalId(args);
    final snapshot = await service.ensureWorkspace(
      sessionId: context.sessionId,
      start: false,
    );
    final inactiveResult = inactiveTerminalResult(
      service: service,
      context: context,
      snapshot: snapshot,
      toolName: 'MachineTerminalExec',
      terminalId: terminalId,
    );
    if (inactiveResult != null) return inactiveResult;
    if (snapshot.activeTerminal?.status != MachineTerminalStatus.running) {
      return boundaryDeniedResult(
        service: service,
        context: context,
        toolName: 'MachineTerminalExec',
        reason: '当前终端未运行，请用户在左侧面板启动或重新连接。',
      );
    }
    final command = AiToolUtils.readFirstString(args, const <String>[
      'command',
      'cmd',
    ]);
    if (command.trim().isEmpty) {
      return AiToolUtils.invalidResult('MachineTerminalExec', 'command 不能为空。');
    }
    final violation = AiMachineTerminalBoundaryPolicy.inputViolation(command);
    if (violation != null) {
      return boundaryDeniedResult(
        service: service,
        context: context,
        toolName: 'MachineTerminalExec',
        reason: violation,
      );
    }
    final timeoutMs = _clampedTimeoutMs(args);
    final result = await service.executeCommand(
      sessionId: context.sessionId,
      terminalId: terminalId,
      command: command,
      timeout: Duration(milliseconds: timeoutMs),
      startIfNeeded: false,
    );
    return AiToolExecutionResult(
      status: result.timedOut
          ? BashToolExecutionStatus.timedOut
          : result.succeeded
          ? BashToolExecutionStatus.success
          : BashToolExecutionStatus.failed,
      command: command,
      workingDirectory:
          service
              .snapshot(context.sessionId)
              ?.activeTerminal
              ?.workingDirectory ??
          AiToolUtils.defaultWorkingDirectory(),
      stdout: result.output,
      stderr: result.error ?? '',
      durationMs: result.durationMs,
      resultText: result.toToolOutput(),
      metadata: <String, Object?>{
        'terminal_id': result.terminalId,
        'exit_code': result.exitCode,
        'timed_out': result.timedOut,
      },
    );
  }

  int _clampedTimeoutMs(Map<String, Object?> args) {
    final raw =
        AiToolUtils.readInt(args['timeout_ms']) ??
        AiToolUtils.readInt(args['timeout']) ??
        kMachineTerminalDefaultCommandTimeout.inMilliseconds;
    return clampMachineTerminalCommandTimeoutMs(raw);
  }
}

class AiMachineTerminalControlTool extends AiMachineTerminalToolBase {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.machineTerminalControl;

  @override
  List<String> get aliases => const <String>[
    'MachineTerminalControl',
    'TerminalControl',
  ];

  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final service = terminalService(context);
    if (service == null) return missingServiceResult('MachineTerminalControl');
    final args = context.decodedArguments;
    final action = AiToolUtils.readString(args['action']).trim();
    if (action.isEmpty) {
      return AiToolUtils.invalidResult(
        'MachineTerminalControl',
        '必须提供 action。',
      );
    }
    final terminalId = readTerminalId(args);
    final snapshotBeforeControl = await service.ensureWorkspace(
      sessionId: context.sessionId,
      start: false,
    );
    final inactiveResult = inactiveTerminalResult(
      service: service,
      context: context,
      snapshot: snapshotBeforeControl,
      toolName: 'MachineTerminalControl',
      terminalId: terminalId,
    );
    if (inactiveResult != null) return inactiveResult;
    if (!AiMachineTerminalBoundaryPolicy.allowsControlAction(action)) {
      return boundaryDeniedResult(
        service: service,
        context: context,
        toolName: 'MachineTerminalControl',
        reason: '终端生命周期和执行目标只能由用户在左侧面板管理。',
        metadata: <String, Object?>{'requested_action': action.toLowerCase()},
      );
    }
    final stopwatch = Stopwatch()..start();
    late final MachineTerminalWorkspaceSnapshot snapshot;
    try {
      snapshot = await service.control(
        sessionId: context.sessionId,
        action: action,
        terminalId: terminalId,
        workingDirectory: AiToolUtils.readFirstString(args, const <String>[
          'working_directory',
          'cwd',
        ]),
        columns: AiToolUtils.readInt(args['columns']),
        rows: AiToolUtils.readInt(args['rows']),
      );
    } on ArgumentError {
      return AiToolUtils.invalidResult('MachineTerminalControl', '终端控制参数无效。');
    } catch (error, stack) {
      silentLog('ai_machine_terminal_tools', '控制机器终端', error, stack);
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'MachineTerminalControl',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: '控制机器终端失败。',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: 控制机器终端失败。',
      );
    }
    final active = snapshot.activeTerminal;
    final output =
        'action: $action\n'
        'active_terminal_id: ${snapshot.activeTerminalId}\n'
        'terminal_count: ${snapshot.terminals.length}\n'
        'status: ${active?.status.storageValue ?? 'idle'}';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: 'MachineTerminalControl',
      workingDirectory:
          active?.workingDirectory ?? AiToolUtils.defaultWorkingDirectory(),
      stdout: output,
      stderr: '',
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: output,
      metadata: <String, Object?>{
        'machine_terminal_snapshot': _snapshotMetadata(snapshot),
        'machine_terminal_metadata': service.sessionMetadata(
          sessionId: context.sessionId,
          existingMetadata: context.metadata[kMachineTerminalMetadataKey],
          snapshot: snapshot,
        ),
      },
    );
  }
}

Map<String, Object?> _snapshotMetadata(
  MachineTerminalWorkspaceSnapshot snapshot,
) {
  final activeTerminal = snapshot.activeTerminal;
  return <String, Object?>{
    'session_id': snapshot.sessionId,
    'active_terminal_id': snapshot.activeTerminalId,
    'terminals': snapshot.terminals
        .map((terminal) => terminal.toMetadataJson())
        .toList(growable: false),
    if (activeTerminal != null)
      'active_terminal': activeTerminal.toMetadataJson(),
  };
}

String _terminalSnapshotText(
  MachineTerminalWorkspaceSnapshot workspace,
  MachineTerminalSnapshot terminal,
  Map<String, Object?> metadata,
) {
  return 'session_id: ${workspace.sessionId}\n'
      'metadata_schema_version: ${metadata['schema_version'] ?? ''}\n'
      'workflow: ${metadata['workflow'] ?? ''}\n'
      'default_working_directory: ${metadata['default_working_directory'] ?? ''}\n'
      'active_terminal_id: ${workspace.activeTerminalId}\n'
      'terminal_id: ${terminal.terminalId}\n'
      'identity: ${terminal.identity}\n'
      'status: ${terminal.status.storageValue}\n'
      'attached: ${terminal.attached}\n'
      'pid: ${terminal.pid ?? ''}\n'
      'exit_code: ${terminal.exitCode ?? ''}\n'
      'shell: ${terminal.shell}\n'
      'working_directory: ${terminal.workingDirectory}\n'
      'size: ${terminal.columns}x${terminal.rows}\n'
      'terminal_count: ${workspace.terminals.length}\n'
      'output_characters: ${terminal.outputCharacters}\n'
      'output:\n${terminal.output.trimRight()}';
}
