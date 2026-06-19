import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/hook/ai_claude_hook_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
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
      throw ArgumentError(
        'Bash timeout must be between 1 and 600000 milliseconds.',
      );
    }
    final bashResult = await _bashToolService.execute(
      command: '${args['cmd'] ?? args['command'] ?? ''}'.trim(),
      sessionId: context.sessionId,
      workingDirectory: '${args['working_directory'] ?? args['cwd'] ?? ''}'
          .trim(),
      denyRules: context.denyCommandRules,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: confirmationGate.callback,
      cancelSignal: cancelSignal,
      onUpdate: onBashUpdate,
      timeoutMs: timeoutMs,
      toolCallId: context.toolCall.id,
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
