import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/hook/ai_claude_hook_service.dart';

class AiBashWriteConfirmationGate {
  AiBashWriteConfirmationGate({
    required this._hookService,
    required this._sessionId,
    required this._toolName,
    required this._userConfirmation,
  });

  final AiClaudeHookService _hookService;
  final String _sessionId;
  final String _toolName;
  final Future<BashCommandApprovalDecision> Function(
    BashCommandApprovalRequest request,
  )?
  _userConfirmation;
  final List<String> _systemReminders = <String>[];

  Future<BashCommandApprovalDecision> Function(
    BashCommandApprovalRequest request,
  )?
  get callback => _userConfirmation == null ? null : _confirmWriteCommand;

  Map<String, Object?> get metadata {
    if (_systemReminders.isEmpty) return const <String, Object?>{};
    return <String, Object?>{
      aiHookSystemRemindersMetadataKey: List<String>.from(_systemReminders),
    };
  }

  Future<BashCommandApprovalDecision> _confirmWriteCommand(
    BashCommandApprovalRequest request,
  ) async {
    final permissionHookResult = await _hookService.runHooks(
      eventName: 'PermissionRequest',
      sessionId: _sessionId,
      matcherValue: _toolName,
      cwd: request.workingDirectory,
      payload: <String, Object?>{
        'tool_name': _toolName,
        'toolName': _toolName,
        'command': request.command,
        'working_directory': request.workingDirectory,
        'permission_type': 'write_command_confirmation',
        'is_write_command': request.isWriteCommand,
      },
    );
    _systemReminders.addAll(permissionHookResult.systemReminders);
    if (permissionHookResult.blocked) {
      final notificationHookResult = await _runAuxiliaryHook(
        eventName: 'Notification',
        matcherValue: 'permission_prompt',
        cwd: request.workingDirectory,
        payload: <String, Object?>{
          'notification_type': 'permission_prompt',
          'tool_name': _toolName,
          'command': request.command,
          'status': 'blocked',
        },
      );
      _systemReminders.addAll(notificationHookResult.systemReminders);
      return BashCommandApprovalDecision.rejected;
    }

    final userConfirmation = _userConfirmation;
    if (userConfirmation == null) {
      return BashCommandApprovalDecision.rejected;
    }
    final decision = await userConfirmation(request);
    final notificationHookResult = await _runAuxiliaryHook(
      eventName: 'Notification',
      matcherValue: 'permission_prompt',
      cwd: request.workingDirectory,
      payload: <String, Object?>{
        'notification_type': 'permission_prompt',
        'tool_name': _toolName,
        'command': request.command,
        'status': decision.name,
      },
    );
    _systemReminders.addAll(notificationHookResult.systemReminders);
    return decision;
  }

  Future<AiClaudeHookInvocationResult> _runAuxiliaryHook({
    required String eventName,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    try {
      return await _hookService.runHooks(
        eventName: eventName,
        sessionId: _sessionId,
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
