import '../service/ai_bash_tool_service.dart';
import '../service/ai_claude_hook_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

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
    final sessionId = context.sessionId;
    final cancelSignal = context.cancelSignal;
    final onBashUpdate = context.onBashUpdate;
    final confirmWriteCommand = context.confirmWriteCommand;

    final permissionHookReminders = <String>[];
    final wrappedConfirmWriteCommand = confirmWriteCommand == null
        ? null
        : (BashCommandApprovalRequest request) async {
            final permissionHookResult = await _hookService.runHooks(
              eventName: 'PermissionRequest',
              sessionId: sessionId,
              matcherValue: 'Bash',
              cwd: request.workingDirectory,
              payload: <String, Object?>{
                'tool_name': 'Bash',
                'toolName': 'Bash',
                'command': request.command,
                'working_directory': request.workingDirectory,
                'permission_type': 'write_command_confirmation',
                'is_write_command': request.isWriteCommand,
              },
            );
            permissionHookReminders.addAll(
              permissionHookResult.systemReminders,
            );
            if (permissionHookResult.blocked) {
              final notificationHookResult = await _runAuxiliaryHook(
                eventName: 'Notification',
                sessionId: sessionId,
                matcherValue: 'permission_prompt',
                cwd: request.workingDirectory,
                payload: <String, Object?>{
                  'notification_type': 'permission_prompt',
                  'tool_name': 'Bash',
                  'command': request.command,
                  'status': 'blocked',
                },
              );
              permissionHookReminders.addAll(
                notificationHookResult.systemReminders,
              );
              return BashCommandApprovalDecision.rejected;
            }
            final decision = await confirmWriteCommand(request);
            final notificationHookResult = await _runAuxiliaryHook(
              eventName: 'Notification',
              sessionId: sessionId,
              matcherValue: 'permission_prompt',
              cwd: request.workingDirectory,
              payload: <String, Object?>{
                'notification_type': 'permission_prompt',
                'tool_name': 'Bash',
                'command': request.command,
                'status': decision.name,
              },
            );
            permissionHookReminders.addAll(
              notificationHookResult.systemReminders,
            );
            return decision;
          };

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
      sessionId: sessionId,
      workingDirectory: '${args['working_directory'] ?? args['cwd'] ?? ''}'
          .trim(),
      denyRules: context.denyCommandRules,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: wrappedConfirmWriteCommand,
      cancelSignal: cancelSignal,
      onUpdate: onBashUpdate,
      timeoutMs: timeoutMs,
      toolCallId: context.toolCall.id,
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
        if (permissionHookReminders.isNotEmpty)
          aiHookSystemRemindersMetadataKey: permissionHookReminders,
      },
    );
  }

  Future<AiClaudeHookInvocationResult> _runAuxiliaryHook({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    try {
      return await _hookService.runHooks(
        eventName: eventName,
        sessionId: sessionId,
        matcherValue: matcherValue,
        cwd: cwd,
        payload: payload,
      );
    } catch (error) {
      return AiClaudeHookInvocationResult(
        systemReminders: <String>['Hook event $eventName failed: $error'],
      );
    }
  }
}
