import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

void main() {
  test(
    'AiSessionController creates sessions, compresses history, and tracks usage totals',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: <AiChatCompletion>[
          const AiChatCompletion(
            reply: 'First answer',
            usage: AiTokenUsage(
              promptTokens: 10,
              completionTokens: 5,
              totalTokens: 15,
            ),
          ),
          const AiChatCompletion(
            reply: 'Compressed summary',
            usage: AiTokenUsage(
              promptTokens: 3,
              completionTokens: 2,
              totalTokens: 5,
            ),
          ),
          const AiChatCompletion(
            reply: 'Second answer',
            usage: AiTokenUsage(
              promptTokens: 4,
              completionTokens: 3,
              totalTokens: 7,
            ),
          ),
        ],
        autoTitleResponses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: 'Plan Chat',
            usage: AiTokenUsage(
              promptTokens: 1,
              completionTokens: 1,
              totalTokens: 2,
            ),
          ),
        ],
      );
      final generatedIds = <String>[
        'session-1',
        'message-1',
        'message-2',
        'message-3',
        'message-4',
        'message-5',
        'error-1',
      ];
      var tick = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 22, 9, 0, tick++),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'en-US',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath:
            '/workspace/openhand/.openhand/memory/user-memory.json',
        compressionThresholdChars: 10,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-1',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(controller.sessions.single.id, 'session-1');

      expect(
        await controller.sendMessage(
          content: 'Need detailed plan',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(controller.didCompressInLastSend, isFalse);

      expect(
        await controller.sendMessage(
          content: 'Continue',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final currentSession = controller.currentSession;
      expect(currentSession, isNotNull);
      expect(controller.didCompressInLastSend, isTrue);
      expect(currentSession!.latestCompressionCheckpointMessageId, 'message-3');
      expect(
        currentSession.messages
            .where(
              (message) =>
                  message.kind == AiSessionMessageKind.compressionPoint,
            )
            .length,
        1,
      );
      expect(currentSession.statistics.compressionRunCount, 1);
      expect(currentSession.statistics.totalTokens, 29);
      expect(currentSession.statistics.promptBuildCount, 4);
      expect(currentSession.lastPromptMetadata['session_id'], 'session-1');
      expect(chatClient.requests, hasLength(4));
      expect(chatClient.requests.last.first.role, AiChatRole.system);
      expect(
        chatClient.requests.last.last.content,
        contains('# [6] Your latest message'),
      );
    },
  );

  test(
    'AiSessionController generates the first auto title while the reply is still streaming',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _AutoTitleStreamingChatClient();
      final generatedIds = <String>[
        'session-auto-title',
        'message-user-auto-title',
        'message-assistant-auto-title',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 6, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-auto-title',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        content: 'Need a concise title for this thread',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(chatClient.autoTitleRequestCount, 1);
      expect(controller.sendPhase, AiSendPhase.responding);
      expect(controller.currentSession, isNotNull);
      expect(controller.currentSession!.title, 'Quick Title');

      chatClient.completeStream();

      expect(await pendingSend, isTrue);
      expect(
        controller.currentSession!.messages.any(
          (message) =>
              message.kind == AiSessionMessageKind.assistant &&
              message.content == 'Slow answer',
        ),
        isTrue,
      );
      expect(controller.currentSession!.title, 'Quick Title');
    },
  );

  test(
    'AiSessionController keeps 新会话 until the async auto title finishes',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final streamingClient = _AutoTitleStreamingChatClient();
      final backgroundClient = _DelayedAutoTitleChatClient();
      final generatedIds = <String>[
        'session-delayed-auto-title',
        'message-user-delayed-auto-title',
        'message-assistant-delayed-auto-title',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: streamingClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 6, 30, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-delayed-auto-title',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        content: 'Need a concise delayed title for this thread',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(backgroundClient.requestCount, 1);
      expect(controller.currentSession, isNotNull);
      expect(controller.currentSession!.title, '新会话');

      backgroundClient.completeTitle();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession!.title, 'Delayed Title');

      streamingClient.completeStream();
      expect(await pendingSend, isTrue);
      expect(controller.currentSession!.title, 'Delayed Title');
    },
  );

  test(
    'AiSessionController marks reasoning messages as streaming only while reasoning deltas are active',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _ReasoningStreamingChatClient();
      final generatedIds = <String>[
        'session-reasoning',
        'message-user-reasoning',
        'message-reasoning',
        'message-assistant-reasoning',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 8, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-reasoning',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        content: 'Please reason this through.',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final reasoningWhileStreaming = controller.currentSession!.messages
          .firstWhere(
            (message) => message.kind == AiSessionMessageKind.reasoning,
          );
      expect(
        reasoningWhileStreaming.metadata[aiSessionMessageMetadataStreamingKey],
        isTrue,
      );

      chatClient.completeStream();

      expect(await pendingSend, isTrue);

      final reasoningAfterCompletion = controller.currentSession!.messages
          .firstWhere(
            (message) => message.kind == AiSessionMessageKind.reasoning,
          );
      expect(
        reasoningAfterCompletion.metadata[aiSessionMessageMetadataStreamingKey],
        isFalse,
      );
    },
  );

  test(
    'AiSessionController exposes compressing, sending, and responding phases in order when history compression runs',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _CompressionPhaseChatClient();
      final generatedIds = <String>[
        'session-compressing',
        'message-user-first',
        'message-assistant-first',
        'checkpoint-compressed',
        'message-user-second',
        'message-assistant-second',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 9, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 10,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-compressing',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(
        await controller.sendMessage(
          content: '12345678901',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        content: 'second',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.sendPhase, AiSendPhase.compressing);

      chatClient.completeCompression();

      await Future<void>.delayed(Duration.zero);
      expect(controller.sendPhase, AiSendPhase.sendingMessage);

      await Future<void>.delayed(Duration.zero);
      expect(controller.sendPhase, AiSendPhase.responding);

      chatClient.completeResponseStream();
      expect(await pendingSend, isTrue);
      expect(controller.sendPhase, AiSendPhase.idle);
    },
  );

  test(
    'AiSessionController strips leaked internal prompt headers from assistant replies',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply:
                '[[5] Current Session Messages]\n\n# [1] Developer Instructions\n\nVisible answer',
          ),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => 'strip-${DateTime.now().microsecondsSinceEpoch}',
        clock: () => DateTime.utc(2026, 3, 23, 6, 10, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-strip',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(
        await controller.sendMessage(
          content: 'Say hi',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final assistantMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.assistant,
      );
      expect(assistantMessage.content, 'Visible answer');
      expect(
        assistantMessage.content,
        isNot(contains('[[5] Current Session Messages]')),
      );
      expect(
        assistantMessage.content,
        isNot(contains('# [1] Developer Instructions')),
      );
    },
  );

  test('AiSessionController uses 新会话 as the default session title', () async {
    final controller = await AiSessionController.create(
      store: _InMemoryAiSessionStore(),
      chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
      templateRepository: AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' => 'System',
            'assets/prompts/default/developer_instructions.md' => 'Developer',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      ),
    );
    const runtimeContext = AiSessionRuntimeContext(
      localeTag: 'zh-CN',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
      skillsStoragePath: '/Users/example/.openhand/skills',
      mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
      userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
      compressionThresholdChars: 5000,
      memoryEnabled: true,
      memoryEntries: [],
    );

    expect(
      await controller.createSession(
        templateId: 'default',
        runtimeContext: runtimeContext,
      ),
      isTrue,
    );

    expect(controller.sessions.single.title, '新会话');
  });

  test(
    'AiSessionController routes auto title generation through the background chat client',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final streamingClient = _AutoTitleStreamingChatClient();
      final backgroundClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[],
        autoTitleResponses: const <AiChatCompletion>[
          AiChatCompletion(reply: 'Background Title'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: streamingClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: () =>
            'background-${DateTime.now().microsecondsSinceEpoch}',
        clock: () => DateTime.utc(2026, 3, 23, 7, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-background-title',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'deepseek-reasoner',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        content: 'Please create a background title immediately',
        model: model,
        runtimeContext: runtimeContext,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(streamingClient.autoTitleRequestCount, 0);
      expect(backgroundClient.requests, hasLength(1));
      expect(backgroundClient.requestModels.single.modelId, 'deepseek-chat');
      expect(controller.currentSession!.title, 'Background Title');

      streamingClient.completeStream();
      expect(await pendingSend, isTrue);
    },
  );

  test(
    'AiSessionController retries auto title after a timeout once the session becomes idle',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final streamingClient = _AutoTitleStreamingChatClient();
      final backgroundClient = _RetryingAutoTitleChatClient();
      final generatedIds = <String>[
        'session-retry-auto-title',
        'message-user-retry-auto-title',
        'message-assistant-retry-auto-title',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: streamingClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 7, 15, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-retry-auto-title',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        content: 'Please retry the title after the response finishes',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(backgroundClient.requestCount, 1);
      expect(controller.currentSession!.title, '新会话');

      streamingClient.completeStream();
      expect(await pendingSend, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(backgroundClient.requestCount, 2);
      expect(controller.currentSession!.title, 'Recovered Title');
    },
  );

  test(
    'AiSessionController restores logically deleted messages when edit is cancelled',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(reply: 'First answer'),
          AiChatCompletion(reply: 'Second answer'),
        ],
      );
      final generatedIds = <String>[
        'session-restore',
        'message-user-1',
        'message-assistant-1',
        'message-user-2',
        'message-assistant-2',
      ];
      var tick = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 22, 10, 0, tick++),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'en-US',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath:
            '/workspace/openhand/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-restore',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await controller.renameSession('session-restore', 'Manual Thread'),
        isTrue,
      );
      expect(
        await controller.sendMessage(
          content: 'First message',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await controller.sendMessage(
          content: 'Second message',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final firstUserMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.user,
      );
      final draft = await controller.beginEditingMessage(firstUserMessage.id);

      expect(draft, 'First message');
      expect(controller.editingMessageId, firstUserMessage.id);
      expect(controller.currentSession!.visibleMessages, hasLength(1));

      expect(await controller.cancelEditingMessage(), isTrue);
      expect(controller.editingMessageId, isNull);
      expect(controller.currentSession!.visibleMessages, hasLength(4));
      expect(
        controller.currentSession!.visibleMessages
            .where((message) => message.kind == AiSessionMessageKind.user)
            .length,
        2,
      );
      expect(
        controller.currentSession!.messages.any(
          (message) => '${message.metadata['deleted_by_edit_message_id'] ?? ''}'
              .isNotEmpty,
        ),
        isFalse,
      );
    },
  );

  test('AiSessionController marks session errors as presented once', () async {
    final promptRepository = AiPromptTemplateRepository(
      loader: (assetPath) async {
        return switch (assetPath) {
          'assets/prompts/default/system_instructions.md' =>
            'System instructions',
          'assets/prompts/default/developer_instructions.md' =>
            'Developer instructions',
          'assets/prompts/default/compression_summary_instructions.md' =>
            'Compression instructions',
          _ => throw ArgumentError('Unexpected asset path: $assetPath'),
        };
      },
    );
    final generatedIds = <String>[
      'session-error',
      'message-user-error',
      'error-presented',
    ];
    final controller = await AiSessionController.create(
      store: _InMemoryAiSessionStore(),
      chatClient: _FailingChatClient(
        const AiChatException('Messages with role tool are invalid.'),
      ),
      templateRepository: promptRepository,
      idGenerator: () => generatedIds.removeAt(0),
      clock: () => DateTime.utc(2026, 3, 23, 2, 0, 0),
    );
    const runtimeContext = AiSessionRuntimeContext(
      localeTag: 'en-US',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
      skillsStoragePath: '/Users/example/.openhand/skills',
      mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
      userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
      compressionThresholdChars: 5000,
      memoryEnabled: true,
      memoryEntries: [],
    );
    const model = AiModelConfig(
      id: 'model-error',
      baseUrl: 'https://api.example.com',
      authScheme: AiAuthScheme.none,
      token: '',
      modelId: 'gpt-test',
      protocolType: AiProtocolType.openai,
    );

    expect(
      await controller.createSession(
        templateId: 'default',
        runtimeContext: runtimeContext,
      ),
      isTrue,
    );
    expect(
      await controller.renameSession('session-error', 'Manual Error Thread'),
      isTrue,
    );
    expect(
      await controller.sendMessage(
        content: 'Trigger an error',
        model: model,
        runtimeContext: runtimeContext,
      ),
      isFalse,
    );

    final sessionWithError = controller.currentSession;
    expect(sessionWithError, isNotNull);
    expect(sessionWithError!.recentErrors, isNotEmpty);
    final error = sessionWithError.recentErrors.first;
    expect(error.hasBeenPresented, isFalse);
    final previousUpdatedAt = sessionWithError.updatedAt;

    expect(
      await controller.markErrorAsPresented(
        sessionId: sessionWithError.id,
        errorId: error.id,
      ),
      isTrue,
    );

    final updatedSession = controller.currentSession;
    expect(updatedSession, isNotNull);
    expect(updatedSession!.recentErrors.first.hasBeenPresented, isTrue);
    expect(updatedSession.updatedAt, previousUpdatedAt);
  });

  test(
    'AiSessionController persists bash execution details on tool-call messages',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: <AiChatCompletion>[
          const AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-1',
                name: 'bash',
                arguments:
                    '{"cmd":"flutter test","working_directory":"/tmp/demo"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'All done'),
        ],
      );
      final generatedIds = <String>[
        'session-bash',
        'message-user',
        'message-tool-call',
        'message-tool-result',
        'message-assistant',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        bashToolService: _FakeBashToolService(
          result: const BashToolExecutionResult(
            status: BashToolExecutionStatus.success,
            command: 'flutter test',
            workingDirectory: '/tmp/demo',
            stdout: '00:00 +1: all tests passed',
            stderr: '',
            durationMs: 8200,
            exitCode: 0,
            isWriteCommand: true,
            writeAnalysisReason: 'mutating command flutter',
          ),
          updates: const <BashToolExecutionUpdate>[
            BashToolExecutionUpdate(
              phase: BashToolExecutionPhase.running,
              command: 'flutter test',
              workingDirectory: '/tmp/demo',
              stdout: '00:00 +1',
              stderr: '',
              durationMs: 1200,
            ),
          ],
        ),
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 1, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-bash',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await controller.renameSession('session-bash', 'Manual Bash Thread'),
        isTrue,
      );
      expect(
        await controller.sendMessage(
          content: 'Run the test suite',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final toolCallMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.toolCall,
      );
      final toolResultMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.tool,
      );

      expect(
        toolCallMessage.metadata['tool_execution_command'],
        'flutter test',
      );
      expect(
        toolCallMessage.metadata['tool_execution_working_directory'],
        '/tmp/demo',
      );
      expect(toolCallMessage.metadata['tool_execution_status'], 'success');
      expect(toolCallMessage.metadata['tool_execution_exit_code'], 0);
      expect(
        toolCallMessage.metadata['tool_execution_stdout'],
        contains('all tests passed'),
      );
      expect(
        toolCallMessage.metadata['tool_execution_is_write_command'],
        isTrue,
      );
      expect(
        toolCallMessage.metadata['tool_execution_write_analysis_reason'],
        'mutating command flutter',
      );
      expect(
        toolResultMessage.metadata['stdout'],
        contains('all tests passed'),
      );
      expect(toolResultMessage.metadata['exit_code'], 0);
      expect(toolResultMessage.metadata['is_write_command'], isTrue);
      expect(
        toolResultMessage.metadata['write_analysis_reason'],
        'mutating command flutter',
      );
    },
  );

  test(
    'AiSessionController stops after too many sequential tool rounds',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final responses = List<AiChatCompletion>.generate(
        9,
        (index) => AiChatCompletion(
          reply: '',
          toolCalls: <AiToolCall>[
            AiToolCall(
              id: 'tool-loop-${index + 1}',
              name: 'bash',
              arguments: '{"cmd":"pwd"}',
            ),
          ],
        ),
      );
      final generatedIds = List<String>.generate(
        24,
        (index) => 'tool-loop-id-$index',
      );
      final sessionId = generatedIds.first;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _QueuedChatClient(responses: responses),
        templateRepository: promptRepository,
        bashToolService: _FakeBashToolService(
          result: const BashToolExecutionResult(
            status: BashToolExecutionStatus.success,
            command: 'pwd',
            workingDirectory: '/tmp',
            stdout: '/tmp',
            stderr: '',
            durationMs: 25,
            exitCode: 0,
          ),
        ),
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 2, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-tool-loop',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await controller.renameSession(sessionId, 'Tool Loop Thread'),
        isTrue,
      );

      expect(
        await controller.sendMessage(
          sessionId: sessionId,
          content: 'Keep checking the environment',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isFalse,
      );

      final currentSession = controller.currentSession;
      expect(currentSession, isNotNull);
      expect(
        controller.lastErrorMessage,
        'The assistant requested too many sequential tool rounds and was stopped for safety.',
      );
      expect(currentSession!.recentErrors.first.stage, 'tool_loop');
      expect(
        currentSession.messages
            .where((message) => message.kind == AiSessionMessageKind.toolCall)
            .length,
        9,
      );
      expect(
        currentSession.messages
            .where((message) => message.kind == AiSessionMessageKind.tool)
            .length,
        8,
      );
    },
  );

  test(
    'AiSessionController creates a new session while another tool call is still running',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-pending',
                name: 'bash',
                arguments: '{"cmd":"pwd"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Done'),
        ],
      );
      final bashService = _PendingBashToolService();
      final generatedIds = <String>[
        'session-busy',
        'message-user-busy',
        'message-tool-call-busy',
        'session-new',
        'message-tool-result-busy',
        'message-assistant-busy',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        bashToolService: bashService,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 3, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-busy',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await controller.renameSession('session-busy', 'Busy Thread'),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        sessionId: 'session-busy',
        content: 'Run pwd',
        model: model,
        runtimeContext: runtimeContext,
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.sendPhase, AiSendPhase.responding);
      expect(controller.activeSendSessionId, 'session-busy');
      expect(
        controller.sendPhaseForSession('session-busy'),
        AiSendPhase.responding,
      );
      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(controller.currentSessionId, 'session-new');
      expect(controller.sessions, hasLength(2));
      expect(controller.sendPhaseForSession('session-new'), AiSendPhase.idle);

      bashService.complete(
        const BashToolExecutionResult(
          status: BashToolExecutionStatus.success,
          command: 'pwd',
          workingDirectory: '/tmp',
          stdout: '/tmp',
          stderr: '',
          durationMs: 100,
          exitCode: 0,
        ),
      );

      expect(await pendingSend, isTrue);
      expect(controller.sendPhase, AiSendPhase.idle);
      expect(controller.activeSendSessionId, isNull);
    },
  );

  test(
    'AiSessionController allows another session to send while a bash tool is still running',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-session-a',
                name: 'bash',
                arguments: '{"cmd":"pwd"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Thread B ready'),
          AiChatCompletion(reply: 'Thread A finished'),
        ],
      );
      final bashService = _PendingBashToolService();
      final generatedIds = <String>[
        'session-a',
        'message-user-a',
        'message-tool-call-a',
        'session-b',
        'message-user-b',
        'message-assistant-b',
        'message-tool-result-a',
        'message-assistant-a',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        bashToolService: bashService,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 3, 30, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-concurrent',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(await controller.renameSession('session-a', 'Thread A'), isTrue);

      final pendingSendA = controller.sendMessage(
        sessionId: 'session-a',
        content: 'Run pwd for session A',
        model: model,
        runtimeContext: runtimeContext,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.sendPhaseForSession('session-a'),
        AiSendPhase.responding,
      );
      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(await controller.renameSession('session-b', 'Thread B'), isTrue);

      expect(
        await controller.sendMessage(
          sessionId: 'session-b',
          content: 'Hello from session B',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(controller.sendPhaseForSession('session-b'), AiSendPhase.idle);
      final sessionB = controller.sessions.firstWhere(
        (session) => session.id == 'session-b',
      );
      expect(
        sessionB.messages.any(
          (message) =>
              message.kind == AiSessionMessageKind.assistant &&
              message.content == 'Thread B ready',
        ),
        isTrue,
      );

      bashService.complete(
        const BashToolExecutionResult(
          status: BashToolExecutionStatus.success,
          command: 'pwd',
          workingDirectory: '/tmp',
          stdout: '/tmp',
          stderr: '',
          durationMs: 100,
          exitCode: 0,
        ),
      );

      expect(await pendingSendA, isTrue);
      final sessionA = controller.sessions.firstWhere(
        (session) => session.id == 'session-a',
      );
      expect(
        sessionA.messages.any(
          (message) =>
              message.kind == AiSessionMessageKind.assistant &&
              message.content == 'Thread A finished',
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController does not resurrect a deleted session while its tool call is still finishing',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-delete',
                name: 'bash',
                arguments: '{"cmd":"pwd"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'This reply should stay deleted'),
        ],
      );
      final bashService = _PendingBashToolService();
      final generatedIds = <String>[
        'session-delete',
        'message-user-delete',
        'message-tool-call-delete',
        'message-tool-result-delete',
        'message-assistant-delete',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        bashToolService: bashService,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 4, 0, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-delete',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        sessionId: 'session-delete',
        content: 'Run pwd',
        model: model,
        runtimeContext: runtimeContext,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await controller.deleteSession('session-delete'), isTrue);
      expect(controller.sessions, isEmpty);
      expect(controller.currentSessionId, isNull);

      bashService.complete(
        const BashToolExecutionResult(
          status: BashToolExecutionStatus.success,
          command: 'pwd',
          workingDirectory: '/tmp',
          stdout: '/tmp',
          stderr: '',
          durationMs: 100,
          exitCode: 0,
        ),
      );

      expect(await pendingSend, isTrue);
      expect(controller.sessions, isEmpty);
      expect(controller.currentSessionId, isNull);
    },
  );

  test(
    'AiSessionController preserves a manual rename while a session is still responding',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-rename',
                name: 'bash',
                arguments: '{"cmd":"pwd"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Renamed thread finished'),
        ],
      );
      final bashService = _PendingBashToolService();
      final generatedIds = <String>[
        'session-rename',
        'message-user-rename',
        'message-tool-call-rename',
        'message-tool-result-rename',
        'message-assistant-rename',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        bashToolService: bashService,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 23, 4, 30, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-rename',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        sessionId: 'session-rename',
        content: 'Run pwd',
        model: model,
        runtimeContext: runtimeContext,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.renameSession('session-rename', 'Manual Rename'),
        isTrue,
      );

      bashService.complete(
        const BashToolExecutionResult(
          status: BashToolExecutionStatus.success,
          command: 'pwd',
          workingDirectory: '/tmp',
          stdout: '/tmp',
          stderr: '',
          durationMs: 100,
          exitCode: 0,
        ),
      );

      expect(await pendingSend, isTrue);
      final session = controller.currentSession;
      expect(session, isNotNull);
      expect(session!.title, 'Manual Rename');
      expect(session.isTitleManuallyEdited, isTrue);
    },
  );

  test(
    'AiSessionController cancels active streaming work during dispose',
    () async {
      final promptRepository = AiPromptTemplateRepository(
        loader: (assetPath) async {
          return switch (assetPath) {
            'assets/prompts/default/system_instructions.md' =>
              'System instructions',
            'assets/prompts/default/developer_instructions.md' =>
              'Developer instructions',
            'assets/prompts/default/compression_summary_instructions.md' =>
              'Compression instructions',
            _ => throw ArgumentError('Unexpected asset path: $assetPath'),
          };
        },
      );
      final chatClient = _DisposableStreamingChatClient();
      final generatedIds = <String>['session-dispose', 'message-user-dispose'];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 24, 2, 30, 0),
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-dispose',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final pendingSend = controller.sendMessage(
        content: 'Keep streaming until dispose.',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.sendPhase, AiSendPhase.responding);

      controller.dispose();

      expect(
        await pendingSend.timeout(const Duration(seconds: 1)),
        isTrue,
      );
      expect(chatClient.cancelInvoked, isTrue);
      expect(chatClient.disposeCount, 1);
    },
  );
}

class _InMemoryAiSessionStore extends AiSessionStore {
  _InMemoryAiSessionStore()
    : super(sessionsDirectoryPath: '/tmp/openhand-ai-session-controller-test');

  final Map<String, AiSession> _sessions = <String, AiSession>{};

  @override
  Future<AiSessionLoadResult> loadAll() async {
    final sessions = _sessions.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return AiSessionLoadResult(
      sessions: sessions,
      issues: const <AiSessionPersistenceIssue>[],
    );
  }

  @override
  Future<void> save(AiSession session) async {
    _sessions[session.id] = session;
  }
}

class _QueuedChatClient implements AiChatClient {
  _QueuedChatClient({
    required List<AiChatCompletion> responses,
    List<AiChatCompletion> autoTitleResponses = const <AiChatCompletion>[],
  }) : _responses = List<AiChatCompletion>.from(responses),
       _autoTitleResponses = List<AiChatCompletion>.from(autoTitleResponses);

  final List<AiChatCompletion> _responses;
  final List<AiChatCompletion> _autoTitleResponses;
  final List<List<AiChatTurn>> requests = <List<AiChatTurn>>[];
  final List<AiModelConfig> requestModels = <AiModelConfig>[];

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    requests.add(List<AiChatTurn>.from(messages));
    requestModels.add(model);
    if (_isAutoTitleRequest(messages)) {
      if (_autoTitleResponses.isEmpty) {
        return const AiChatCompletion(reply: '');
      }
      return _autoTitleResponses.removeAt(0);
    }
    return _responses.removeAt(0);
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final completion = await sendMessage(
      model: model,
      messages: messages,
      tools: tools,
      timeout: timeout,
    );
    final events = <AiChatStreamEvent>[];
    if (completion.reply.isNotEmpty) {
      events.add(AiChatStreamEvent.textDelta(completion.reply));
    }
    if (completion.usage != null && !completion.usage!.isEmpty) {
      events.add(AiChatStreamEvent.usage(completion.usage!));
    }
    return AiChatStreamingResponse(
      events: Stream<AiChatStreamEvent>.fromIterable(events),
      result: Future<AiChatStreamResult>.value(
        AiChatStreamResult(
          reply: completion.reply,
          reasoning: '',
          toolCalls: completion.toolCalls,
          usage: completion.usage,
          rawResponse: completion.rawResponse,
        ),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  @override
  void dispose() {}

  bool _isAutoTitleRequest(List<AiChatTurn> messages) {
    if (messages.isEmpty) {
      return false;
    }
    return messages.first.content.contains('Generate a concise chat title.');
  }
}

class _AutoTitleStreamingChatClient implements AiChatClient {
  int autoTitleRequestCount = 0;
  final Completer<void> _streamCompleter = Completer<void>();

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final firstMessage = messages.isEmpty ? null : messages.first;
    if (firstMessage?.content.contains('Generate a concise chat title.') ??
        false) {
      autoTitleRequestCount++;
      return const AiChatCompletion(reply: 'Quick Title');
    }
    return const AiChatCompletion(reply: 'Unexpected request');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    Stream<AiChatStreamEvent> events() async* {
      await _streamCompleter.future;
      yield AiChatStreamEvent.textDelta('Slow answer');
    }

    return AiChatStreamingResponse(
      events: events(),
      result: _streamCompleter.future.then(
        (_) => const AiChatStreamResult(
          reply: 'Slow answer',
          reasoning: '',
          toolCalls: <AiToolCall>[],
        ),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  void completeStream() {
    if (_streamCompleter.isCompleted) {
      return;
    }
    _streamCompleter.complete();
  }

  @override
  void dispose() {}
}

class _DelayedAutoTitleChatClient implements AiChatClient {
  final Completer<void> _titleCompleter = Completer<void>();
  int requestCount = 0;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    requestCount++;
    await _titleCompleter.future;
    return const AiChatCompletion(reply: 'Delayed Title');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw UnimplementedError('Streaming is not used for delayed auto titles.');
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  void completeTitle() {
    if (_titleCompleter.isCompleted) {
      return;
    }
    _titleCompleter.complete();
  }

  @override
  void dispose() {}
}

class _RetryingAutoTitleChatClient implements AiChatClient {
  int requestCount = 0;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    requestCount++;
    if (requestCount == 1) {
      throw const AiChatException('Request timed out.');
    }
    return const AiChatCompletion(reply: 'Recovered Title');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw UnimplementedError('Streaming is not used for retrying auto titles.');
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  @override
  void dispose() {}
}

class _ReasoningStreamingChatClient implements AiChatClient {
  final Completer<void> _streamCompleter = Completer<void>();

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return const AiChatCompletion(reply: '');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    Stream<AiChatStreamEvent> events() async* {
      yield AiChatStreamEvent.reasoningDelta('Step 1');
      await _streamCompleter.future;
      yield AiChatStreamEvent.textDelta('Done');
    }

    return AiChatStreamingResponse(
      events: events(),
      result: _streamCompleter.future.then(
        (_) => const AiChatStreamResult(
          reply: 'Done',
          reasoning: 'Step 1',
          toolCalls: <AiToolCall>[],
        ),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  void completeStream() {
    if (_streamCompleter.isCompleted) {
      return;
    }
    _streamCompleter.complete();
  }

  @override
  void dispose() {}
}

class _CompressionPhaseChatClient implements AiChatClient {
  final Completer<void> _compressionCompleter = Completer<void>();
  final Completer<void> _responseStreamCompleter = Completer<void>();
  int _streamRequestCount = 0;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final hasAutoTitlePrompt = messages.any(
      (message) => message.content.contains('Generate a concise chat title.'),
    );
    if (hasAutoTitlePrompt) {
      return const AiChatCompletion(reply: '');
    }
    final hasCompressionPrompt = messages.any(
      (message) => message.content.contains('Compression instructions'),
    );
    if (hasCompressionPrompt) {
      await _compressionCompleter.future;
      return const AiChatCompletion(reply: 'Compressed summary');
    }
    return const AiChatCompletion(reply: '');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final streamIndex = _streamRequestCount++;
    if (streamIndex == 0) {
      return AiChatStreamingResponse(
        events: Stream<AiChatStreamEvent>.fromIterable(
          const <AiChatStreamEvent>[
            AiChatStreamEvent.textDelta('first-answer'),
          ],
        ),
        result: Future<AiChatStreamResult>.value(
          const AiChatStreamResult(
            reply: 'first-answer',
            reasoning: '',
            toolCalls: <AiToolCall>[],
          ),
        ),
      );
    }

    Stream<AiChatStreamEvent> events() async* {
      await _responseStreamCompleter.future;
      yield AiChatStreamEvent.textDelta('second-answer');
    }

    return AiChatStreamingResponse(
      events: events(),
      result: _responseStreamCompleter.future.then(
        (_) => const AiChatStreamResult(
          reply: 'second-answer',
          reasoning: '',
          toolCalls: <AiToolCall>[],
        ),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  void completeCompression() {
    if (_compressionCompleter.isCompleted) {
      return;
    }
    _compressionCompleter.complete();
  }

  void completeResponseStream() {
    if (_responseStreamCompleter.isCompleted) {
      return;
    }
    _responseStreamCompleter.complete();
  }

  @override
  void dispose() {}
}

class _FailingChatClient implements AiChatClient {
  _FailingChatClient(this.error);

  final Object error;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw error;
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw error;
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    throw error;
  }

  @override
  void dispose() {}
}

class _FakeBashToolService extends AiBashToolService {
  _FakeBashToolService({
    required this.result,
    this.updates = const <BashToolExecutionUpdate>[],
  });

  final BashToolExecutionResult result;
  final List<BashToolExecutionUpdate> updates;

  @override
  Future<BashToolExecutionResult> execute({
    required String command,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = AiBashToolService.defaultTimeoutMs,
  }) async {
    for (final update in updates) {
      onUpdate?.call(update);
    }
    return result;
  }
}

class _PendingBashToolService extends AiBashToolService {
  final Completer<BashToolExecutionResult> _completer =
      Completer<BashToolExecutionResult>();

  @override
  Future<BashToolExecutionResult> execute({
    required String command,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = AiBashToolService.defaultTimeoutMs,
  }) async {
    onUpdate?.call(
      BashToolExecutionUpdate(
        phase: BashToolExecutionPhase.running,
        command: command,
        workingDirectory: (workingDirectory ?? '').trim(),
        stdout: '',
        stderr: '',
        durationMs: 0,
      ),
    );
    return _completer.future;
  }

  void complete(BashToolExecutionResult result) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete(result);
  }
}

class _DisposableStreamingChatClient implements AiChatClient {
  final StreamController<AiChatStreamEvent> _events =
      StreamController<AiChatStreamEvent>();
  final Completer<AiChatStreamResult> _resultCompleter =
      Completer<AiChatStreamResult>();
  bool cancelInvoked = false;
  int disposeCount = 0;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return const AiChatCompletion(reply: '');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return AiChatStreamingResponse(
      events: _events.stream,
      result: _resultCompleter.future,
      cancel: () async {
        cancelInvoked = true;
        if (!_resultCompleter.isCompleted) {
          _resultCompleter.complete(
            const AiChatStreamResult(
              reply: '',
              reasoning: '',
              toolCalls: <AiToolCall>[],
              wasCancelled: true,
            ),
          );
        }
        if (!_events.isClosed) {
          await _events.close();
        }
      },
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  @override
  void dispose() {
    disposeCount += 1;
  }
}
