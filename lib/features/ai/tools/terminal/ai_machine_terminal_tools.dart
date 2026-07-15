import '../../../../app/support/silent_log.dart';
import '../../../machine_terminal/index.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

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
      stderr:
          'Machine terminal service is not available for this session. Use this tool only inside the machine_expert template.',
      durationMs: 0,
      resultText:
          'status: failed\nerror: Machine terminal service is unavailable for this session.',
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
      start: AiToolUtils.readBool(args['start_if_needed']) != false,
    );
    final active = terminalId == null
        ? snapshot.activeTerminal
        : _terminalById(snapshot.terminals, terminalId);
    if (active == null) {
      return AiToolUtils.invalidResult(
        'MachineTerminalRead',
        'Terminal not found: ${terminalId ?? snapshot.activeTerminalId}',
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
    final data = AiToolUtils.readFirstString(args, const <String>[
      'data',
      'text',
      'input',
    ]);
    if (data.isEmpty) {
      return AiToolUtils.invalidResult(
        'MachineTerminalWrite',
        'data must not be empty.',
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      await service.writeInput(
        sessionId: context.sessionId,
        terminalId: readTerminalId(args),
        data: data,
        appendNewline:
            AiToolUtils.readBool(args['append_newline']) == true ||
            AiToolUtils.readBool(args['enter']) == true,
      );
    } catch (error, stack) {
      silentLog('ai_machine_terminal_tools', 'write', error, stack);
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'MachineTerminalWrite',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'Machine terminal write failed.',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: Machine terminal write failed.',
      );
    }
    final snapshot = service.snapshot(context.sessionId)?.activeTerminal;
    final output =
        'terminal_id: ${snapshot?.terminalId ?? ''}\n'
        'status: ${snapshot?.status.storageValue ?? 'running'}\n'
        'written_chars: ${data.length}';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: 'MachineTerminalWrite',
      workingDirectory:
          snapshot?.workingDirectory ?? AiToolUtils.defaultWorkingDirectory(),
      stdout: output,
      stderr: '',
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: output,
      metadata: <String, Object?>{
        'terminal_id': snapshot?.terminalId,
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
    final command = AiToolUtils.readFirstString(args, const <String>[
      'command',
      'cmd',
    ]);
    if (command.trim().isEmpty) {
      return AiToolUtils.invalidResult(
        'MachineTerminalExec',
        'command must not be empty.',
      );
    }
    final timeoutMs = _clampedTimeoutMs(args);
    final result = await service.executeCommand(
      sessionId: context.sessionId,
      terminalId: readTerminalId(args),
      command: command,
      timeout: Duration(milliseconds: timeoutMs),
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
        'action is required.',
      );
    }
    final stopwatch = Stopwatch()..start();
    late final MachineTerminalWorkspaceSnapshot snapshot;
    try {
      snapshot = await service.control(
        sessionId: context.sessionId,
        action: action,
        terminalId: readTerminalId(args),
        workingDirectory: AiToolUtils.readFirstString(args, const <String>[
          'working_directory',
          'cwd',
        ]),
        columns: AiToolUtils.readInt(args['columns']),
        rows: AiToolUtils.readInt(args['rows']),
      );
    } on ArgumentError {
      return AiToolUtils.invalidResult(
        'MachineTerminalControl',
        'Invalid terminal control arguments.',
      );
    } catch (error, stack) {
      silentLog('ai_machine_terminal_tools', 'control', error, stack);
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'MachineTerminalControl',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'Machine terminal control failed.',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: Machine terminal control failed.',
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

MachineTerminalSnapshot? _terminalById(
  List<MachineTerminalSnapshot> terminals,
  String terminalId,
) {
  for (final terminal in terminals) {
    if (terminal.terminalId == terminalId) {
      return terminal;
    }
  }
  return null;
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
