class AiPromptSectionHeaders {
  const AiPromptSectionHeaders._();

  static const String systemInstructions = '# [0] System Instructions';
  static const String developerInstructions = '# [1] Developer Instructions';
  static const String toolCatalog = '# [2] Tool Catalog';
  static const String staticSessionState = '# [3s] Static Session State';
  static const String dynamicSessionState = '# [3d] Dynamic Session State';
  static const String userMemory = '# [4] User Memory';
  static const String userMemoryLongTermFacts =
      '# [4] User Memory (long-term facts)';
  static const String userInstructions = '# [4.5] User Instructions';
  static const String conversationContext = '# [5] Conversation Context';
  static const String recentConversationSummary =
      '# [5] Recent Conversations Summary (past chats, titles + snippets)';
  static const String focusContext = '# [5.5] Focus Context';
  static const String restoredFileContext = '# [5.6] Restored File Context';
  static const String restoredSkillContext = '# [5.7] Restored Skill Context';
  static const String restoredPlanContext = '# [5.8] Restored Plan Context';
  static const String restoredMcpContext = '# [5.9] Restored MCP Context';
  static const String restoredSessionStartHookContext =
      '# [5.10] Restored SessionStart Hook Context';
  static const String restoredToolAndAgentListing =
      '# [5.11] Restored Tool and Agent Listing';
  static const String restoredAgentResultContext =
      '# [5.12] Restored Agent Result Context';
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
  AiPromptSectionHeaders.userMemoryLongTermFacts,
  AiPromptSectionHeaders.userInstructions,
  AiPromptSectionHeaders.conversationContext,
  AiPromptSectionHeaders.recentConversationSummary,
  AiPromptSectionHeaders.focusContext,
  AiPromptSectionHeaders.restoredFileContext,
  AiPromptSectionHeaders.restoredSkillContext,
  AiPromptSectionHeaders.restoredPlanContext,
  AiPromptSectionHeaders.restoredMcpContext,
  AiPromptSectionHeaders.restoredSessionStartHookContext,
  AiPromptSectionHeaders.restoredToolAndAgentListing,
  AiPromptSectionHeaders.restoredAgentResultContext,
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
