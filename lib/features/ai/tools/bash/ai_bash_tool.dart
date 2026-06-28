import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/hook/ai_claude_hook_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../android_reverse_adb_command_guard.dart';
import '../web_reverse_cdp_first_guard.dart';
import 'ai_bash_write_confirmation_gate.dart';

class AiBashTool extends AiTool {
  AiBashTool({
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
  }) : _bashToolService = bashToolService,
       _hookService = hookService;

  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.bash;

  /// 'bash' 是 Bash 工具的 legacy 别名，向后兼容旧会话记录。
  @override
  List<String> get aliases => const <String>['bash'];

  /// Bash 可执行写入、删除、网络请求等不可逆操作，标记为破坏性工具。
  @override
  bool get isDestructive => true;

  /// 用户发送新消息时取消正在运行的 Bash 命令（避免并发写冲突）。
  @override
  AiToolInterruptBehavior get interruptBehavior =>
      AiToolInterruptBehavior.cancel;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final cancelSignal = context.cancelSignal;
    final onBashUpdate = context.onBashUpdate;
    final command = '${args['cmd'] ?? args['command'] ?? ''}'.trim();
    final workingDirectory = '${args['working_directory'] ?? args['cwd'] ?? ''}'
        .trim();

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
    stdout:
        'cdp_first_required: true\n'
        'target_origin: ${decision.targetOrigin}\n'
        'requested_origin: ${decision.requestedOrigin}\n'
        'cdp_route: ${decision.routeKind}\n'
        'cdp_tools: ${decision.toolText}',
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
