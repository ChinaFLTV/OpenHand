import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/hook/ai_claude_hook_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../android_reverse_adb_command_guard.dart';
import '../web_reverse_cdp_first_guard.dart';
import 'ai_bash_specialized_tool_policy.dart';
import 'ai_bash_write_confirmation_gate.dart';

class AiBashTool extends AiTool {
  AiBashTool({required this._bashToolService, required this._hookService});

  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.bash;

  /// `bash` 是兼容历史会话记录的工具别名。
  @override
  List<String> get aliases => const <String>['bash'];

  /// Bash 可执行写入、删除、网络请求等不可逆操作，标记为破坏性工具。
  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final cancelSignal = context.cancelSignal;
    final onBashUpdate = context.onBashUpdate;
    final command = AiToolUtils.readFirstString(args, const <String>[
      'cmd',
      'command',
    ]);
    final workingDirectory = AiToolUtils.readFirstString(args, const <String>[
      'working_directory',
      'cwd',
    ]);

    final confirmationGate = AiBashWriteConfirmationGate(
      hookService: _hookService,
      sessionId: context.sessionId,
      toolName: 'Bash',
      userConfirmation: context.confirmWriteCommand,
    );

    final timeoutMs =
        AiToolUtils.readInt(args['timeout']) ??
        AiToolUtils.readInt(args['timeout_ms']) ??
        AiBashToolService.defaultTimeoutMs;
    if (timeoutMs <= 0 || timeoutMs > 600000) {
      return AiToolUtils.invalidResult(
        'Bash',
        'Bash timeout must be between 1 and 600000 milliseconds.',
      );
    }
    final specializedToolDecision = AiBashSpecializedToolPolicy.evaluate(
      command: command,
      catalog: context.catalog,
    );
    if (specializedToolDecision != null) {
      return specializedToolDecision.toResult(
        command: command,
        workingDirectory: workingDirectory,
      );
    }
    final cdpFirstDecision = WebReverseCdpFirstGuard.evaluateCommand(
      command: command,
      metadata: context.metadata,
    );
    if (cdpFirstDecision != null) {
      return _webReverseBashCdpFirstBlock(
        decision: cdpFirstDecision,
        command: command,
        workingDirectory: workingDirectory,
      );
    }
    final forceWriteConfirmation =
        AndroidReverseAdbCommandGuard.requiresExplicitApproval(
          command: command,
          metadata: context.metadata,
        );
    final bashResult = await _bashToolService.execute(
      command: command,
      sessionId: context.sessionId,
      workingDirectory: workingDirectory,
      denyRules: context.denyCommandRules,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: confirmationGate.callback,
      cancelSignal: cancelSignal,
      onUpdate: onBashUpdate,
      timeoutMs: timeoutMs,
      toolCallId: context.toolCall.id,
      forceWriteConfirmation: forceWriteConfirmation,
      dangerouslyDisableSandbox:
          context.metadata['source'] != 'dingtalk_gateway' &&
          AiToolUtils.readBool(args['dangerouslyDisableSandbox']) == true,
    );
    final bashMetadata = <String, Object?>{
      if (bashResult.isWriteCommand) 'file_mutation_kind': 'bash_write',
      if (bashResult.isWriteCommand)
        'file_mutation_working_directory': bashResult.workingDirectory,
      if (bashResult.isWriteCommand)
        'file_mutation_command_char_count': bashResult.command.length,
      if (bashResult.isWriteCommand)
        'file_mutation_write_reason': bashResult.writeAnalysisReason,
      if (forceWriteConfirmation) ...AndroidReverseAdbCommandGuard.metadata,
    };
    return AiToolExecutionResult.fromBash(
      bashResult,
      metadata: <String, Object?>{
        ...bashMetadata,
        ...confirmationGate.metadata,
      },
    );
  }
}

AiToolExecutionResult _webReverseBashCdpFirstBlock({
  required WebReverseCdpFirstDecision decision,
  required String command,
  required String workingDirectory,
}) {
  final message = decision.blockedMessage('Bash');
  return AiToolExecutionResult(
    status: BashToolExecutionStatus.denied,
    command: command.isEmpty ? 'Bash' : command,
    workingDirectory: workingDirectory.isEmpty
        ? AiToolUtils.defaultWorkingDirectory()
        : AiToolUtils.resolvePath(workingDirectory),
    stdout: decision.diagnosticText(),
    stderr: message,
    durationMs: 0,
    resultText: 'status: denied\nerror: $message',
    metadata: <String, Object?>{
      'web_reverse_bash_blocked_command_char_count': command.length,
      ...decision.metadata(
        requestedUrl: decision.requestedUri.toString(),
        blockedFlag: 'web_reverse_bash_blocked_for_cdp_first',
      ),
    },
  );
}
