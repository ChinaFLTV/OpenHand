class AiPlanModeGuidance {
  const AiPlanModeGuidance._();

  static const String planningReminder =
      'This session is in Plan mode. Inspect first, use AskUserChoice only for '
      'a small deterministic choice that blocks the plan, use read-only code '
      'search/intelligence tools as needed, then use TodoWrite to create or '
      'refresh the execution todo list before calling '
      'ExitPlanMode. Keep at least one todo item pending or in_progress until '
      'ExitPlanMode captures the plan; otherwise the runtime may not expose '
      'ExitPlanMode. Do not call editing, write-oriented, Bash, or other '
      'implementation tools until the user approves the captured plan. If the '
      'user has already endorsed the plan in this turn (for example "去写吧", '
      '"去做吧", "do it", "ship it"), call ExitPlanMode immediately with the '
      'concise numbered plan and wait for the next turn to execute.';

  static const String approvalExecutionReminder =
      'The user is approving the existing plan. Do not call ExitPlanMode again '
      'or restate the plan. Start executing now, use TodoWrite to track '
      'concrete implementation steps, and keep the todo list current as work '
      'progresses. The tool catalog should now include implementation tools '
      'such as Write/Edit/MultiEdit/Bash; use exact names from the catalog. '
      'Never ask the user to copy-paste code because a write tool appears '
      'missing; re-check the current tool list first.';

  static const String pendingApprovalNoPlanReminder =
      'A plan is pending user approval. Present the captured plan clearly, ask '
      'for explicit approval, and wait before implementation. Do not call any '
      'tools in this turn, including read-only research tools; the runtime '
      'keeps the execution catalog empty until approval is granted.';

  static String pendingApprovalReminder(String pendingPlan) {
    final trimmedPlan = pendingPlan.trim();
    if (trimmedPlan.isEmpty) {
      return pendingApprovalNoPlanReminder;
    }
    return '$pendingApprovalNoPlanReminder\n\n$trimmedPlan';
  }

  static const String emptyCatalogAwaitingApproval =
      'Tool catalog is intentionally empty for this turn because the system is '
      'waiting for the user to approve your plan. Present the captured plan '
      'and ask for explicit confirmation. As soon as the user endorses it '
      '(English or Chinese, e.g. "do it", "ship it", "去写吧", "去做吧"), the '
      'next turn will restore the full execution toolkit automatically. Never '
      'tell the user that Write/Edit do not exist and never dump code into '
      'chat as a workaround.';

  static const String unsupportedEmptyCatalog =
      ' The tool catalog is empty for this turn, usually because the system is '
      'waiting for the user to approve a pending plan. Do NOT invent tool '
      'names or dump code into chat. Present the captured plan and ask for '
      'explicit confirmation; after approval, the next turn will restore the '
      'execution toolkit automatically.';
}
