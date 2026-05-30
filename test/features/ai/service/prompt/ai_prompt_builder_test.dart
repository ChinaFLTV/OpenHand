import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

void main() {
  group('AiPromptBuilder', () {
    test('places latest user turn before volatile system tail', () {
      final now = DateTime.utc(2026, 5, 30, 12);
      final builder = const AiPromptBuilder();
      final session = AiSession(
        id: 'session-1',
        title: 'test',
        templateId: 'default',
        templateName: 'Default Assistant',
        templateIconName: 'auto_awesome_rounded',
        templateInternalVersion: '3.0.0',
        createdAt: now,
        updatedAt: now,
        messages: const <AiSessionMessage>[],
        environment: const AiSessionEnvironment(
          localeTag: 'zh-CN',
          platform: 'macos',
          appVersion: '1.0.0',
          appBuildNumber: '1',
          applicationDirectory: '/app',
          homeDirectory: '/home',
          settingsFilePath: '/settings.json',
          skillsStoragePath: '/skills',
          mcpServersFilePath: '/mcp.json',
          userMemoryFilePath: '/memory.md',
          sessionsDirectoryPath: '/sessions',
          compressionThresholdChars: 200000,
        ),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
        todoItems: const <AiSessionTodoItem>[
          AiSessionTodoItem(
            id: 'todo-1',
            content: 'follow up',
            status: 'pending',
          ),
        ],
      );
      final model = const AiModelConfig(
        id: 'provider-1',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.bearer,
        token: 'token',
        modelId: 'claude-sonnet-4-6',
        protocolType: AiProtocolType.claude,
      );
      final runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        settingsFilePath: '/settings.json',
        skillsStoragePath: '/skills',
        mcpServersFilePath: '/mcp.json',
        userMemoryFilePath: '/memory.md',
        compressionThresholdChars: 200000,
        memoryEnabled: false,
        memoryEntries: const <UserMemoryEntry>[],
        workingDirectory: '/workspace',
        timeZoneName: 'CST',
        platformName: 'macos',
        repositorySnapshot: const AiRepositorySnapshot(
          workingDirectory: '/workspace',
          isGitRepository: true,
          repositoryRootPath: '/workspace',
          currentBranch: 'main',
          mainBranch: 'main',
        ),
      );
      const template = AiThreadTemplate(
        id: 'default',
        name: 'Default Assistant',
        iconName: 'auto_awesome_rounded',
        description: 'test',
        internalVersion: '3.0.0',
        promptAssetDirectory: 'assets/prompts/default',
      );
      const bundle = AiPromptTemplateBundle(
        template: template,
        systemInstructions: 'system',
        developerInstructions: 'developer',
        compressionSummaryInstructions: 'compression',
      );

      final historyMessages = <AiSessionMessage>[
        AiSessionMessage.user(id: 'u1', content: 'old user', createdAt: now),
        AiSessionMessage.assistant(
          id: 'a1',
          content: 'old assistant',
          createdAt: now,
        ),
        AiSessionMessage.toolCall(
          id: 'tc1',
          content: 'Tool call: WebSearch',
          createdAt: now,
          metadata: const <String, Object?>{
            'tool_calls': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'call-1',
                'name': 'WebSearch',
                'arguments': '{"query":"foo"}',
              },
            ],
          },
        ),
        AiSessionMessage.toolResult(
          id: 'tr1',
          content:
              '[tool_result_summary] WebSearch\nstatus: success\nhead:\nfoo',
          createdAt: now,
          metadata: const <String, Object?>{
            'tool_call_id': 'call-1',
            'tool_name': 'WebSearch',
            'status': 'success',
            'command': 'WebSearch foo',
          },
        ),
        AiSessionMessage.assistant(
          id: 'a2',
          content: 'tool-assisted answer',
          createdAt: now,
        ),
      ];
      final latestUserMessage = AiSessionMessage.user(
        id: 'u2',
        content: 'follow up question',
        createdAt: now,
      );

      final result = builder.buildConversationPrompt(
        templateBundle: bundle,
        session: session,
        model: model,
        runtimeContext: runtimeContext,
        memoryEntries: const [],
        historyMessages: historyMessages,
        latestUserMessage: latestUserMessage,
        availableTools: const <AiToolDefinition>[
          AiToolDefinition(
            name: 'WebSearch',
            description: 'search web',
            parameters: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            },
          ),
        ],
      );

      final messages = result.messages;
      final latestUserIndex = messages.indexWhere(
        (m) =>
            m.role == AiChatRole.user &&
            m.content.contains('follow up question'),
      );
      final dynamicIndex = messages.indexWhere(
        (m) =>
            m.role == AiChatRole.system &&
            m.content.startsWith('# [3d] Dynamic Session State'),
      );
      final focusIndex = messages.indexWhere(
        (m) =>
            m.role == AiChatRole.system &&
            m.content.startsWith('# [5.5] Focus Context'),
      );

      expect(latestUserIndex, greaterThanOrEqualTo(0));
      expect(dynamicIndex, greaterThan(latestUserIndex));
      expect(focusIndex, equals(-1));
    });

    test('does not echo reasoning for optional-thinking chat models', () {
      final now = DateTime.utc(2026, 5, 30, 12);
      final builder = const AiPromptBuilder();
      final session = AiSession(
        id: 'session-2',
        title: 'test',
        templateId: 'default',
        templateName: 'Default Assistant',
        templateIconName: 'auto_awesome_rounded',
        templateInternalVersion: '3.0.0',
        createdAt: now,
        updatedAt: now,
        messages: const <AiSessionMessage>[],
        environment: const AiSessionEnvironment(
          localeTag: 'zh-CN',
          platform: 'macos',
          appVersion: '1.0.0',
          appBuildNumber: '1',
          applicationDirectory: '/app',
          homeDirectory: '/home',
          settingsFilePath: '/settings.json',
          skillsStoragePath: '/skills',
          mcpServersFilePath: '/mcp.json',
          userMemoryFilePath: '/memory.md',
          sessionsDirectoryPath: '/sessions',
          compressionThresholdChars: 200000,
        ),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );
      final model = const AiModelConfig(
        id: 'provider-2',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.bearer,
        token: 'token',
        modelId: 'deepseek-v4-flash',
        protocolType: AiProtocolType.deepseek,
      );
      final runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        settingsFilePath: '/settings.json',
        skillsStoragePath: '/skills',
        mcpServersFilePath: '/mcp.json',
        userMemoryFilePath: '/memory.md',
        compressionThresholdChars: 200000,
        memoryEnabled: false,
        memoryEntries: const <UserMemoryEntry>[],
        workingDirectory: '/workspace',
        timeZoneName: 'CST',
        platformName: 'macos',
      );
      const template = AiThreadTemplate(
        id: 'default',
        name: 'Default Assistant',
        iconName: 'auto_awesome_rounded',
        description: 'test',
        internalVersion: '3.0.0',
        promptAssetDirectory: 'assets/prompts/default',
      );
      const bundle = AiPromptTemplateBundle(
        template: template,
        systemInstructions: 'system',
        developerInstructions: 'developer',
        compressionSummaryInstructions: 'compression',
      );

      final historyMessages = <AiSessionMessage>[
        AiSessionMessage.user(id: 'u1', content: '泥嚎', createdAt: now),
        AiSessionMessage.reasoning(
          id: 'r1',
          content:
              'hidden reasoning that should stay out of second-turn history',
          createdAt: now,
        ),
        AiSessionMessage.assistant(
          id: 'a1',
          content: '泥嚎 想我了？',
          createdAt: now,
        ),
      ];
      final latestUserMessage = AiSessionMessage.user(
        id: 'u2',
        content: '没想你',
        createdAt: now,
      );

      final result = builder.buildConversationPrompt(
        templateBundle: bundle,
        session: session,
        model: model,
        runtimeContext: runtimeContext,
        memoryEntries: const <UserMemoryEntry>[],
        historyMessages: historyMessages,
        latestUserMessage: latestUserMessage,
      );

      final assistantTurn = result.messages.firstWhere(
        (m) => m.role == AiChatRole.assistant && m.content.contains('泥嚎 想我了？'),
      );
      expect(assistantTurn.reasoningContent, isNull);
    });

    test('keeps reasoning echo for required thinking models', () {
      final now = DateTime.utc(2026, 5, 30, 12);
      final builder = const AiPromptBuilder();
      final session = AiSession(
        id: 'session-3',
        title: 'test',
        templateId: 'default',
        templateName: 'Default Assistant',
        templateIconName: 'auto_awesome_rounded',
        templateInternalVersion: '3.0.0',
        createdAt: now,
        updatedAt: now,
        messages: const <AiSessionMessage>[],
        environment: const AiSessionEnvironment(
          localeTag: 'zh-CN',
          platform: 'macos',
          appVersion: '1.0.0',
          appBuildNumber: '1',
          applicationDirectory: '/app',
          homeDirectory: '/home',
          settingsFilePath: '/settings.json',
          skillsStoragePath: '/skills',
          mcpServersFilePath: '/mcp.json',
          userMemoryFilePath: '/memory.md',
          sessionsDirectoryPath: '/sessions',
          compressionThresholdChars: 200000,
        ),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );
      final model = const AiModelConfig(
        id: 'provider-3',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.bearer,
        token: 'token',
        modelId: 'deepseek-v4-pro',
        protocolType: AiProtocolType.deepseek,
      );
      final runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        settingsFilePath: '/settings.json',
        skillsStoragePath: '/skills',
        mcpServersFilePath: '/mcp.json',
        userMemoryFilePath: '/memory.md',
        compressionThresholdChars: 200000,
        memoryEnabled: false,
        memoryEntries: const <UserMemoryEntry>[],
        workingDirectory: '/workspace',
        timeZoneName: 'CST',
        platformName: 'macos',
      );
      const template = AiThreadTemplate(
        id: 'default',
        name: 'Default Assistant',
        iconName: 'auto_awesome_rounded',
        description: 'test',
        internalVersion: '3.0.0',
        promptAssetDirectory: 'assets/prompts/default',
      );
      const bundle = AiPromptTemplateBundle(
        template: template,
        systemInstructions: 'system',
        developerInstructions: 'developer',
        compressionSummaryInstructions: 'compression',
      );

      final historyMessages = <AiSessionMessage>[
        AiSessionMessage.user(id: 'u1', content: '泥嚎', createdAt: now),
        AiSessionMessage.reasoning(
          id: 'r1',
          content: 'required reasoning echo',
          createdAt: now,
        ),
        AiSessionMessage.assistant(
          id: 'a1',
          content: '泥嚎 想我了？',
          createdAt: now,
        ),
      ];
      final latestUserMessage = AiSessionMessage.user(
        id: 'u2',
        content: '没想你',
        createdAt: now,
      );

      final result = builder.buildConversationPrompt(
        templateBundle: bundle,
        session: session,
        model: model,
        runtimeContext: runtimeContext,
        memoryEntries: const <UserMemoryEntry>[],
        historyMessages: historyMessages,
        latestUserMessage: latestUserMessage,
      );

      final assistantTurn = result.messages.firstWhere(
        (m) => m.role == AiChatRole.assistant && m.content.contains('泥嚎 想我了？'),
      );
      expect(assistantTurn.reasoningContent, 'required reasoning echo');
    });
  });
}
