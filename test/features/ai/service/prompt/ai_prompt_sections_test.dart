import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_sections.dart';

void main() {
  test('internal prompt leak headers cover restored contexts and reminders', () {
    expect(aiInternalPromptLeakHeaders, contains(AiPromptSectionHeaders.systemInstructions));
    expect(aiInternalPromptLeakHeaders, contains(AiPromptSectionHeaders.restoredFileContext));
    expect(aiInternalPromptLeakHeaders, contains(AiPromptSectionHeaders.restoredSkillContext));
    expect(aiInternalPromptLeakHeaders, contains(AiPromptSectionHeaders.restoredPlanContext));
    expect(aiInternalPromptLeakHeaders, contains(AiPromptSectionHeaders.restoredMcpContext));
    expect(
      aiInternalPromptLeakHeaders,
      contains(AiPromptSectionHeaders.restoredSessionStartHookContext),
    );
    expect(
      aiInternalPromptLeakHeaders,
      contains(AiPromptSectionHeaders.restoredToolAndAgentListing),
    );
    expect(
      aiInternalPromptLeakHeaders,
      contains(AiPromptSectionHeaders.restoredAgentResultContext),
    );
    expect(aiInternalPromptLeakHeaders, contains(AiPromptSectionHeaders.outputFormatReminder));
    expect(aiInternalPromptLeakHeaders, contains(AiPromptSectionHeaders.gptChatRulesReminder));
  });

  test('internal prompt leak headers stay deduplicated', () {
    expect(
      aiInternalPromptLeakHeaders.length,
      equals(aiInternalPromptLeakHeaders.toSet().length),
    );
  });
}
