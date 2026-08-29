class AiPromptSectionHeaders {
  const AiPromptSectionHeaders._();

  static const String systemInstructions = '# [0] System Instructions';
  static const String developerInstructions = '# [1] Developer Instructions';
  static const String toolCatalog = '# [2] Tool Catalog';
  static const String staticSessionState = '# [3s] Static Session State';
  static const String dynamicSessionState = '# [3d] Dynamic Session State';
  static const String userMemory = '# [4] User Memory';
  static const String userInstructions = '# [4.5] User Instructions';
  static const String conversationContext = '# [5] Conversation Context';
  static const String focusContext = '# [5.5] Focus Context';
  static const String restoredFileContext = '# [5.6] Restored File Context';
  static const String restoredSkillContext = '# [5.7] Restored Skill Context';
  static const String restoredPlanContext = '# [5.8] Restored Plan Context';
  static const String restoredMcpContext = '# [5.9] Restored MCP Context';
  static const String restoredSessionStartHookContext =
      '# [5.10] Restored SessionStart Hook Context';
  static const String restoredToolAndSubagentListing =
      '# [5.11] Restored Tool and Subagent Listing';
  static const String restoredSubagentResultContext =
      '# [5.12] Restored Subagent Result Context';
  static const String systemReminder = '# System Reminder';
  static const String planModeReminder = '# Plan Mode Reminder';
  static const String workspaceInstructions = '# Workspace Instructions';
  static const String compressionSystemInstructions =
      '# Compression System Instructions';
  static const String compressionDeveloperInstructions =
      '# Compression Developer Instructions';
  static const String compressionTaskPayload = '# Compression Task Payload';
  static const String outputFormatReminder = '# Output Format Reminder';
  static const String gptChatRulesReminder = '# GPT Chat Rules Reminder';
  static const String themeContextReminder = '# Theme Context Reminder';
}

const Set<String> aiInternalPromptLeakHeaders = <String>{
  '# Runtime Environment Snapshot',
  '# [6] Your latest message',
  AiPromptSectionHeaders.systemInstructions,
  AiPromptSectionHeaders.developerInstructions,
  AiPromptSectionHeaders.toolCatalog,
  AiPromptSectionHeaders.staticSessionState,
  AiPromptSectionHeaders.dynamicSessionState,
  AiPromptSectionHeaders.userMemory,
  AiPromptSectionHeaders.userInstructions,
  AiPromptSectionHeaders.conversationContext,
  AiPromptSectionHeaders.focusContext,
  AiPromptSectionHeaders.restoredFileContext,
  AiPromptSectionHeaders.restoredSkillContext,
  AiPromptSectionHeaders.restoredPlanContext,
  AiPromptSectionHeaders.restoredMcpContext,
  AiPromptSectionHeaders.restoredSessionStartHookContext,
  AiPromptSectionHeaders.restoredToolAndSubagentListing,
  AiPromptSectionHeaders.restoredSubagentResultContext,
  AiPromptSectionHeaders.systemReminder,
  AiPromptSectionHeaders.planModeReminder,
  AiPromptSectionHeaders.workspaceInstructions,
  AiPromptSectionHeaders.compressionSystemInstructions,
  AiPromptSectionHeaders.compressionDeveloperInstructions,
  AiPromptSectionHeaders.compressionTaskPayload,
  AiPromptSectionHeaders.outputFormatReminder,
  AiPromptSectionHeaders.gptChatRulesReminder,
  AiPromptSectionHeaders.themeContextReminder,
};
