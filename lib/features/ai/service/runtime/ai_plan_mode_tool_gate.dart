import '../../../../shared/util/text_normalization.dart';

/// 计划模式的统一工具准入规则。控制器与提示词共用此规则，
/// 保证模型看到的工具状态与当前运行时一致。
abstract final class AiPlanModeToolGate {
  static const List<String> planningToolNames = <String>[
    'AskUserChoice',
    'Task',
    'Glob',
    'Grep',
    'LS',
    'Read',
    'LSP',
    'CodebaseSearch',
    'WebFetch',
    'WebSearch',
    'TodoWrite',
  ];

  static const String exitPlanModeToolName = 'ExitPlanMode';
  static const String exitPlanModeToken = 'exitplanmode';

  static const Set<String> _planningToolTokens = <String>{
    'askuserchoice',
    'task',
    'glob',
    'grep',
    'ls',
    'read',
    'lsp',
    'codebasesearch',
    'webfetch',
    'websearch',
    'todowrite',
  };

  static String normalizeToolName(String value) {
    return normalizeAsciiLookupKey(value);
  }

  static bool isPlanningTool(String toolName) {
    return _planningToolTokens.contains(normalizeToolName(toolName));
  }

  static bool isExitPlanModeTool(String toolName) {
    return normalizeToolName(toolName) == exitPlanModeToken;
  }

  static bool isAllowedPlanningTool(
    String toolName, {
    required bool allowExitPlanMode,
  }) {
    return isPlanningTool(toolName) ||
        (allowExitPlanMode && isExitPlanModeTool(toolName));
  }

  static bool hasExitPlanModeTool(Iterable<String> toolNames) {
    return toolNames.any(isExitPlanModeTool);
  }

  static bool hasExecutionTool(Iterable<String> toolNames) {
    for (final name in toolNames) {
      final normalized = normalizeToolName(name);
      if (normalized.isEmpty ||
          normalized == exitPlanModeToken ||
          _planningToolTokens.contains(normalized)) {
        continue;
      }
      return true;
    }
    return false;
  }

  static String gateReason({
    required bool isPlanMode,
    required bool awaitingPlanApproval,
    required bool executionApprovedForSend,
    required bool recoveryInspectionRequired,
    required Iterable<String> availableToolNames,
  }) {
    if (awaitingPlanApproval) {
      return 'awaiting_plan_approval';
    }
    if (!isPlanMode) {
      return availableToolNames.isEmpty ? 'chat_mode_no_tools' : 'chat_mode';
    }
    if (recoveryInspectionRequired) {
      return 'plan_mode_recovery_inspection';
    }
    if (executionApprovedForSend || hasExecutionTool(availableToolNames)) {
      return 'plan_mode_execution';
    }
    return hasExitPlanModeTool(availableToolNames)
        ? 'plan_mode_planning_with_exit_allowed'
        : 'plan_mode_planning_only';
  }
}
