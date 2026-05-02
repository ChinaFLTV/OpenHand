import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

void main() {
  test('compression prompt uses concise no-tools identity', () {
    const template = AiThreadTemplate(
      id: 'machine_expert',
      name: '机器专家',
      iconName: 'build_circle_rounded',
      description: 'terminal workflow',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/machine_expert',
    );
    const bundle = AiPromptTemplateBundle(
      template: template,
      systemInstructions: 'FULL SYSTEM INSTRUCTIONS SHOULD NOT BE INCLUDED',
      developerInstructions: 'developer instructions',
      compressionSummaryInstructions: 'KEEP TERMINAL BINDING STATE',
    );
    final now = DateTime.utc(2026, 5, 3);
    final session = _session(
      template: template,
      now: now,
      messages: <AiSessionMessage>[
        AiSessionMessage.user(id: 'm1', content: '继续排查远端终端问题', createdAt: now),
      ],
    );

    final prompt = const AiPromptBuilder().buildCompressionPrompt(
      templateBundle: bundle,
      template: template,
      session: session,
      runtimeContext: _runtimeContext(),
      messagesToCompress: session.messages,
      previousCompressionPoint: null,
    );

    expect(prompt.first.content, contains('TEXT ONLY'));
    expect(prompt.first.content, contains('Do not call tools'));
    expect(
      prompt.first.content,
      isNot(contains('FULL SYSTEM INSTRUCTIONS SHOULD NOT BE INCLUDED')),
    );
    expect(prompt[1].content, contains('KEEP TERMINAL BINDING STATE'));
    expect(prompt.last.content, contains('继续排查远端终端问题'));
  });
}

AiSession _session({
  required AiThreadTemplate template,
  required DateTime now,
  required List<AiSessionMessage> messages,
}) {
  return AiSession(
    id: 'session-1',
    title: 'Compression Test',
    templateId: template.id,
    templateName: template.name,
    templateIconName: template.iconName,
    templateInternalVersion: template.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp/openhand',
      homeDirectory: '/tmp',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.md',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 12000,
    ),
    statistics: AiSessionStatistics.fromMessages(
      messages,
      totalPromptCharacters: 0,
      promptBuildCount: 0,
      compressionRunCount: 0,
      totalUsage: const AiTokenUsage(),
      lastPromptSystemMessageCount: 0,
      lastPromptHistoryMessageCount: 0,
    ),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: '0.1.0',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.md',
    compressionThresholdChars: 12000,
    memoryEnabled: true,
    memoryEntries: <UserMemoryEntry>[],
  );
}
