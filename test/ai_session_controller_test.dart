import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/ai_attachment_service.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';
import 'package:openhand/features/ai/service/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/ai_tool_runtime_service.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';
import 'package:openhand/features/skills/model/local_skill.dart';

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
      expect(
        currentSession.messages.map((message) => message.id).toList(),
        equals(<String>[
          'message-1',
          'message-3',
          'message-2',
          'message-4',
          'message-5',
        ]),
      );
      expect(currentSession.statistics.compressionRunCount, 1);
      expect(currentSession.statistics.totalTokens, 29);
      expect(currentSession.statistics.promptBuildCount, 4);
      expect(currentSession.lastPromptMetadata['session_id'], 'session-1');
      expect(chatClient.requests, hasLength(4));
      expect(chatClient.requests.last.first.role, AiChatRole.system);
      expect(
        chatClient.requests.last.any(
          (turn) =>
              turn.role == AiChatRole.system &&
              turn.content.contains('Compressed summary'),
        ),
        isTrue,
      );
      expect(
        chatClient.requests.last.map((turn) => turn.content).join('\n'),
        isNot(contains('Need detailed plan')),
      );
      expect(
        chatClient.requests.last.last.content,
        contains('# [6] Your latest message'),
      );
    },
  );

  test(
    'AiSessionController keeps compression flags scoped to the session that compressed history',
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
          AiChatCompletion(reply: 'Compressed summary'),
          AiChatCompletion(reply: 'Second answer'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Thread A'),
            AiChatCompletion(reply: 'Thread B'),
          ],
        ),
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(
          List<String>.generate(16, (index) => 'compression-id-$index'),
        ),
        clock: () => DateTime.utc(2026, 3, 25, 5, 0, 0),
      );
      addTearDown(controller.dispose);
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
        id: 'model-compression-scope',
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
      final sessionAId = controller.currentSessionId!;

      expect(
        await controller.sendMessage(
          sessionId: sessionAId,
          content: 'Need detailed plan',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await controller.sendMessage(
          sessionId: sessionAId,
          content: 'Continue',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(controller.didCompressInLastSendForSession(sessionAId), isTrue);

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionBId = controller.currentSessionId!;

      expect(controller.didCompressInLastSendForSession(sessionAId), isTrue);
      expect(controller.didCompressInLastSendForSession(sessionBId), isFalse);
      expect(controller.didCompressInLastSend, isFalse);
    },
  );

  test(
    'AiSessionController stores attachment metadata and injects attachment parts into the prompt',
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
        responses: const <AiChatCompletion>[AiChatCompletion(reply: 'Done')],
      );
      final backgroundClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[],
        autoTitleResponses: const <AiChatCompletion>[
          AiChatCompletion(reply: 'Attachment Thread'),
        ],
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-session-attachments-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final attachmentDirectory = Directory(
        '${tempDirectory.path}/stored-attachments',
      );
      final markdownFile = File('${tempDirectory.path}/notes.md');
      await markdownFile.writeAsString(
        '# Release Notes\n- attachment preview\n- keep the important lines',
        flush: true,
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        attachmentService: AiAttachmentService(
          attachmentsDirectoryPath: attachmentDirectory.path,
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-attachment',
          'user-message',
          'attachment-1',
          'assistant-message',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 10, 0, 0),
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
        id: 'model-attachment',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-4o-mini',
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
          content: 'Inspect the attached notes',
          model: model,
          runtimeContext: runtimeContext,
          attachmentFilePaths: <String>[markdownFile.path],
        ),
        isTrue,
      );

      final currentSession = controller.currentSession;
      expect(currentSession, isNotNull);
      final userMessage = currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.user,
      );
      final attachments = AiMessageAttachment.listFromMetadata(
        userMessage.metadata[aiSessionMessageAttachmentsMetadataKey],
      );
      expect(attachments, hasLength(1));
      expect(attachments.single.name, 'notes.md');
      expect(await File(attachments.single.storagePath).exists(), isTrue);
      final latestPrompt = chatClient.requests.single.last;
      expect(latestPrompt.role, AiChatRole.user);
      expect(
        latestPrompt.parts
            .where((part) => part.kind == AiChatContentPartKind.text)
            .map((part) => part.text ?? '')
            .join('\n'),
        contains('Attachment: notes.md'),
      );
    },
  );

  test(
    'AiSessionController blocks attachments for non-multimodal models',
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
        responses: const <AiChatCompletion>[AiChatCompletion(reply: 'Done')],
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-session-attachment-block-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final markdownFile = File('${tempDirectory.path}/notes.md');
      await markdownFile.writeAsString('plain attachment', flush: true);
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        attachmentService: AiAttachmentService(
          attachmentsDirectoryPath: '${tempDirectory.path}/stored-attachments',
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-plain',
          'user-message',
          'attachment-1',
          'assistant-message',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 11, 0, 0),
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
        id: 'model-plain',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-3.5-turbo',
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
          content: 'Inspect the file',
          model: model,
          runtimeContext: runtimeContext,
          attachmentFilePaths: <String>[markdownFile.path],
        ),
        isFalse,
      );
      expect(
        controller.lastErrorMessage,
        contains('does not support file attachments'),
      );
      expect(chatClient.requests, isEmpty);
    },
  );

  test(
    'AiSessionController removes imported attachments when persisting the user message fails',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-session-attachment-save-failure-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final sourceFile = File('${tempDirectory.path}/attachment.txt');
      await sourceFile.writeAsString('attachment content', flush: true);
      final store = _FailingSaveAiSessionStore(
        sessionsDirectoryPath: '${tempDirectory.path}/sessions',
        failOnSaveNumber: 2,
      );
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
        responses: const <AiChatCompletion>[AiChatCompletion(reply: 'unused')],
      );
      final controller = await AiSessionController.create(
        store: store,
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-save-failure',
          'message-user-save-failure',
          'attachment-save-failure',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 12, 0, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-attachment-save-failure',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-4o-mini',
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
          content: 'Inspect this file',
          model: model,
          runtimeContext: runtimeContext,
          attachmentFilePaths: <String>[sourceFile.path],
        ),
        isFalse,
      );
      expect(
        Directory(
          '${store.sessionAttachmentsDirectoryPath('session-save-failure')}/message-user-save-failure',
        ).existsSync(),
        isFalse,
      );
      expect(chatClient.requests, isEmpty);
    },
  );

  test(
    'AiSessionController does not resurrect a session after a partial persisted delete failure',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-session-partial-delete-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final store = _PartiallyFailingDeleteAiSessionStore(
        sessionsDirectoryPath: '${tempDirectory.path}/sessions',
      );
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
      final controller = await AiSessionController.create(
        store: store,
        chatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[],
        ),
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>['session-partial-delete']),
        clock: () => DateTime.utc(2026, 3, 25, 13, 0, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(await controller.deleteSession('session-partial-delete'), isTrue);
      expect(controller.sessions, isEmpty);
      expect(await store.exists('session-partial-delete'), isFalse);
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
    'AiSessionController records an error when persisting an auto title fails',
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
      final controller = await AiSessionController.create(
        store: _AutoTitleFailingAiSessionStore(),
        chatClient: streamingClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-auto-title-persist-failure',
          'message-user-auto-title-persist-failure',
          'message-assistant-auto-title-persist-failure',
          'error-auto-title-persist-failure',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 14, 0, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-auto-title-persist-failure',
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
        content: 'Please keep trying to save the generated title',
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

      final currentSession = controller.currentSession;
      expect(currentSession, isNotNull);
      expect(currentSession!.title, '新会话');
      expect(currentSession.recentErrors, isNotEmpty);
      expect(currentSession.recentErrors.first.stage, 'title_generation');
      expect(
        currentSession.recentErrors.first.detail,
        contains('Injected auto title save failure'),
      );

      streamingClient.completeStream();
      expect(await pendingSend, isTrue);
      expect(controller.currentSession!.title, '新会话');
    },
  );

  test(
    'AiSessionController keeps send errors scoped to the session that failed',
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
      final chatClient = _DelayedFailingStreamingChatClient(
        delayedPrompt: 'slow failure',
        failureMessage: 'Session A failed.',
        successReply: 'Session B succeeded.',
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Thread A'),
            AiChatCompletion(reply: 'Thread B'),
          ],
        ),
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(
          List<String>.generate(20, (index) => 'error-scope-id-$index'),
        ),
        clock: () => DateTime.utc(2026, 3, 25, 6, 0, 0),
      );
      addTearDown(controller.dispose);
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
        id: 'model-error-scope',
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
      final sessionAId = controller.currentSessionId!;

      expect(
        await controller.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionBId = controller.currentSessionId!;

      final pendingFailure = controller.sendMessage(
        sessionId: sessionAId,
        content: 'trigger slow failure',
        model: model,
        runtimeContext: runtimeContext,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.sendMessage(
          sessionId: sessionBId,
          content: 'quick success',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(controller.currentSessionId, sessionBId);
      expect(controller.lastErrorMessage, isNull);

      chatClient.completeFailure();
      expect(await pendingFailure, isFalse);

      expect(
        controller.lastErrorMessageForSession(sessionAId),
        'Session A failed.',
      );
      expect(controller.lastErrorMessageForSession(sessionBId), isNull);
      expect(controller.currentSessionId, sessionBId);
      expect(controller.lastErrorMessage, isNull);

      await controller.selectSession(sessionAId);
      expect(controller.lastErrorMessage, 'Session A failed.');
      await controller.selectSession(sessionBId);
      expect(controller.lastErrorMessage, isNull);
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
    'AiSessionController reconciles final stream reply and reasoning when deltas are partial',
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
      final chatClient = _PartialDeltaStreamingChatClient();
      final generatedIds = <String>[
        'session-final-stream-sync',
        'message-user-final-stream-sync',
        'message-reasoning-final-stream-sync',
        'message-assistant-final-stream-sync',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 25, 16, 0, 0),
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
        id: 'model-final-stream-sync',
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
          content: 'Return the final answer after partial deltas.',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final assistantMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.assistant,
      );
      final reasoningMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.reasoning,
      );
      expect(assistantMessage.content, 'Partial answer completed');
      expect(reasoningMessage.content, 'Step 1 complete');
      expect(
        reasoningMessage.metadata[aiSessionMessageMetadataStreamingKey],
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
    'AiSessionController strengthens auto title instructions and strips markdown wrappers',
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
          AiChatCompletion(reply: '**Markdown配色优化**'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: streamingClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: () => 'prompt-${DateTime.now().microsecondsSinceEpoch}',
        clock: () => DateTime.utc(2026, 3, 23, 7, 5, 0),
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
        id: 'model-auto-title-prompt',
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
        content: '请帮我优化 Markdown 在深浅色主题下的引用块配色',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(backgroundClient.requests, hasLength(1));
      final systemPrompt = backgroundClient.requests.single.first.content;
      expect(systemPrompt, contains('Generate a concise chat title.'));
      expect(
        systemPrompt,
        contains('Avoid titles that are too short, generic'),
      );
      expect(systemPrompt, contains('combine the main themes'));
      expect(controller.currentSession!.title, 'Markdown配色优化');

      streamingClient.completeStream();
      expect(await pendingSend, isTrue);
    },
  );

  test(
    'AiSessionController falls back to a readable local title when auto title is too generic',
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
          AiChatCompletion(reply: '优化'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: streamingClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: () => 'fallback-${DateTime.now().microsecondsSinceEpoch}',
        clock: () => DateTime.utc(2026, 3, 23, 7, 10, 0),
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
        id: 'model-auto-title-fallback',
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
        content: '请帮我修复 Markdown 配色问题',
        model: model,
        runtimeContext: runtimeContext,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession!.title, '修复 Markdown 配色问题');

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
    'AiSessionController registers local skills as callable tools and returns the manifest content',
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
                id: 'tool-call-skill',
                name: 'skill__planner-skill',
                arguments: '{"task":"Plan the implementation"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Skill applied'),
        ],
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-skill-test',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final skillDirectory = Directory('${tempDirectory.path}/planner-skill')
        ..createSync(recursive: true);
      final manifestFile = File('${skillDirectory.path}/SKILL.md')
        ..writeAsStringSync('''
# Planner Skill

Use this skill when the task requires careful planning.
''');
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-skill',
          'message-user-skill',
          'message-tool-call-skill',
          'message-tool-result-skill',
          'message-assistant-skill',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 12, 0, 0),
      );
      final runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: const <UserMemoryEntry>[],
        availableSkills: <LocalSkill>[
          LocalSkill(
            name: 'Planner Skill',
            description: 'Structured planning workflow.',
            directoryPath: skillDirectory.path,
            manifestPath: manifestFile.path,
            relativeDirectoryPath: 'planner-skill',
            defaultPrompt: 'Plan before implementing.',
          ),
        ],
      );
      const model = AiModelConfig(
        id: 'model-skill',
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
          content: 'Use the planning skill',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final toolNames = chatClient.requestedTools
          .expand((item) => item)
          .map((item) => item.name)
          .toSet();
      expect(toolNames, contains('skill__planner-skill'));
      final toolCallMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.toolCall,
      );
      final toolMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.skill,
      );
      expect(toolCallMessage.metadata['tool_source'], 'skill');
      expect(toolCallMessage.metadata['skill_name'], 'Planner Skill');
      expect(toolCallMessage.metadata['tool_execution_status'], 'success');
      expect(
        '${toolCallMessage.metadata['tool_execution_stdout'] ?? ''}',
        contains('Planner Skill'),
      );
      expect(toolMessage.content, contains('skill_name: Planner Skill'));
      expect(toolMessage.content, contains('manifest:'));
      expect(toolMessage.content, contains('Planner Skill'));
      expect(toolMessage.metadata['tool_source'], 'skill');
      expect(controller.currentSession!.statistics.skillMessageCount, 1);
      final followUpRequest = chatClient.requests.last;
      expect(
        followUpRequest.any(
          (turn) =>
              turn.role == AiChatRole.tool &&
              turn.content.contains('skill_name: Planner Skill'),
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController registers MCP tools dynamically and executes them',
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
      final mcpService = _FakeAiMcpToolDiscoveryService(
        catalog: const McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'getDiagnostics',
              name: 'Get Diagnostics',
              description: 'Return workspace diagnostics.',
              inputSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'uri': <String, Object?>{'type': 'string'},
                },
                'additionalProperties': false,
              },
            ),
          ],
        ),
        callResult: const McpToolCallResult(
          outputText: 'is_error: false\ncontent:\nNo diagnostics',
        ),
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-mcp',
                name: 'mcp__ide__getDiagnostics',
                arguments: '{"uri":"file:///workspace/lib/main.dart"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Diagnostics checked'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        mcpToolService: mcpService,
        idGenerator: _fixedIdGenerator(<String>[
          'session-mcp',
          'message-user-mcp',
          'message-tool-call-mcp',
          'message-tool-result-mcp',
          'message-assistant-mcp',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 13, 0, 0),
      );
      final runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: const <UserMemoryEntry>[],
        availableMcpServers: const <McpServer>[
          McpServer(
            name: 'ide',
            type: McpServerType.streamableHttp,
            enabled: true,
            url: 'https://mcp.example/v1',
          ),
        ],
      );
      const model = AiModelConfig(
        id: 'model-mcp',
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
          content: 'Check diagnostics',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final toolNames = chatClient.requestedTools
          .expand((item) => item)
          .map((item) => item.name)
          .toSet();
      expect(toolNames, contains('mcp__ide__getDiagnostics'));
      expect(mcpService.calledToolNames, contains('getDiagnostics'));
      final toolCallMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.toolCall,
      );
      final toolMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.mcp,
      );
      expect(toolCallMessage.metadata['tool_source'], 'mcp');
      expect(toolCallMessage.metadata['mcp_server_name'], 'ide');
      expect(toolCallMessage.metadata['mcp_tool_id'], 'getDiagnostics');
      expect(toolCallMessage.metadata['tool_execution_status'], 'success');
      expect(
        '${toolCallMessage.metadata['tool_execution_stdout'] ?? ''}',
        contains('No diagnostics'),
      );
      expect(toolMessage.content, contains('No diagnostics'));
      expect(toolMessage.metadata['tool_source'], 'mcp');
      expect(toolMessage.metadata['mcp_server_name'], 'ide');
      expect(toolMessage.metadata['mcp_tool_id'], 'getDiagnostics');
      expect(controller.currentSession!.statistics.mcpMessageCount, 1);
      final followUpRequest = chatClient.requests.last;
      expect(
        followUpRequest.any(
          (turn) =>
              turn.role == AiChatRole.tool &&
              turn.content.contains('No diagnostics'),
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController marks MCP tool results as failed when the server returns isError',
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
      final mcpService = _FakeAiMcpToolDiscoveryService(
        catalog: McpToolCatalog(
          status: McpToolCatalogStatus.ready,
          tools: <McpTool>[
            McpTool(
              id: 'applyEdit',
              name: 'Apply Edit',
              description: 'Apply a workspace edit.',
              inputSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'uri': <String, Object?>{'type': 'string'},
                },
                'additionalProperties': false,
              },
            ),
          ],
        ),
        callResult: const McpToolCallResult(
          outputText: 'is_error: true\ncontent:\nAccess denied',
          isError: true,
        ),
      );
      final chatClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-mcp-error',
                name: 'mcp__ide__applyEdit',
                arguments: '{"uri":"file:///workspace/lib/main.dart"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'MCP failure handled'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        mcpToolService: mcpService,
        idGenerator: _fixedIdGenerator(<String>[
          'session-mcp-error',
          'message-user-mcp-error',
          'message-tool-call-mcp-error',
          'message-tool-result-mcp-error',
          'message-assistant-mcp-error',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 13, 30, 0),
      );
      final runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: const <UserMemoryEntry>[],
        availableMcpServers: const <McpServer>[
          McpServer(
            name: 'ide',
            type: McpServerType.streamableHttp,
            enabled: true,
            url: 'https://mcp.example/v1',
          ),
        ],
      );
      const model = AiModelConfig(
        id: 'model-mcp-error',
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
          content: 'Try applying the edit',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final toolMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.mcp,
      );
      expect(toolMessage.content, contains('Access denied'));
      expect(toolMessage.metadata['tool_source'], 'mcp');
      expect(toolMessage.metadata['mcp_is_error'], isTrue);
      expect(toolMessage.metadata['status'], 'failed');
      final followUpRequest = chatClient.requests.last;
      expect(
        followUpRequest.any(
          (turn) =>
              turn.role == AiChatRole.tool &&
              turn.content.contains('Access denied'),
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController persists TodoWrite state into the session prompt metadata',
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
                id: 'tool-call-todo',
                name: 'TodoWrite',
                arguments:
                    '{"todos":[{"id":"t1","content":"Inspect runtime","status":"completed"},{"id":"t2","content":"Patch MCP tool execution","status":"in_progress"}]}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Todo updated'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-todo',
          'message-user-todo',
          'message-tool-call-todo',
          'message-tool-result-todo',
          'message-assistant-todo',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 14, 0, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-todo',
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
          content: 'Track the work with todos',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final todoItems = controller.currentSession!.todoItems;
      expect(todoItems, hasLength(2));
      expect(todoItems.first.id, 't1');
      expect(todoItems.last.status, 'in_progress');
      final followUpMetadataMessage = chatClient.requests.last.firstWhere(
        (turn) =>
            turn.role == AiChatRole.system &&
            turn.content.contains('# [2] Session Metadata'),
      );
      expect(
        followUpMetadataMessage.content,
        contains('"current_todo_count": 2'),
      );
      expect(followUpMetadataMessage.content, contains('"id": "t1"'));
      expect(followUpMetadataMessage.content, contains('"id": "t2"'));
    },
  );

  test(
    'AiSessionController clears TodoWrite state when the tool sends an empty list',
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
                id: 'tool-call-todo-seed',
                name: 'TodoWrite',
                arguments:
                    '{"todos":[{"id":"t1","content":"Keep tracking","status":"in_progress"}]}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Todo created'),
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-todo-clear',
                name: 'TodoWrite',
                arguments: '{"todos":[]}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Todo cleared'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-todo-clear',
          'message-user-todo-seed',
          'message-tool-call-todo-seed',
          'message-tool-result-todo-seed',
          'message-assistant-todo-seed',
          'message-user-todo-clear',
          'message-tool-call-todo-clear',
          'message-tool-result-todo-clear',
          'message-assistant-todo-clear',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 14, 30, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-todo-clear',
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
          content: 'Track the work with todos',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(controller.currentSession!.todoItems, hasLength(1));

      expect(
        await controller.sendMessage(
          content: 'The list can be cleared now',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(controller.currentSession!.todoItems, isEmpty);
      final followUpMetadataMessage = chatClient.requests.last.firstWhere(
        (turn) =>
            turn.role == AiChatRole.system &&
            turn.content.contains('# [2] Session Metadata'),
      );
      expect(
        followUpMetadataMessage.content,
        contains('"current_todo_count": 0'),
      );
      expect(followUpMetadataMessage.content, contains('"current_todos": []'));
    },
  );

  test(
    'AiSessionController lets Task run a background sub-agent with tools',
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
                id: 'tool-call-task',
                name: 'Task',
                arguments:
                    '{"description":"inspect runtime","prompt":"Use tools if needed and report back.","subagent_type":"general-purpose"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Parent task complete'),
        ],
      );
      final backgroundClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'task-todo',
                name: 'TodoWrite',
                arguments:
                    '{"todos":[{"id":"bg-1","content":"Inspect runtime","status":"completed"}]}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Background inspection finished'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-task',
          'message-user-task',
          'message-tool-call-task',
          'message-tool-result-task',
          'message-assistant-task',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 15, 0, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-task',
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
          content: 'Investigate this with a sub-agent',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final backgroundToolNames = backgroundClient.requestedTools
          .expand((item) => item)
          .map((item) => item.name)
          .toSet();
      expect(backgroundToolNames, contains('TodoWrite'));
      expect(backgroundToolNames, isNot(contains('Task')));
      expect(backgroundToolNames, isNot(contains('ExitPlanMode')));
      final taskResultMessage = controller.currentSession!.messages.firstWhere(
        (message) =>
            message.kind == AiSessionMessageKind.tool &&
            message.metadata['tool_name'] == 'Task',
      );
      expect(
        taskResultMessage.content,
        contains('Background inspection finished'),
      );
    },
  );

  test(
    'AiSessionController gates implementation after ExitPlanMode until the user approves',
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
                id: 'tool-call-plan',
                name: 'ExitPlanMode',
                arguments:
                    '{"plan":"1. Inspect the current runtime\\n2. Patch the tool pipeline\\n3. Run tests"}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Plan ready. Confirm before I implement it.'),
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-approved',
                name: 'TodoWrite',
                arguments:
                    '{"todos":[{"id":"p1","content":"Implement the approved plan","status":"in_progress"}]}',
              ),
            ],
          ),
          AiChatCompletion(reply: 'Implementation started'),
        ],
      );
      final backgroundClient = _QueuedChatClient(
        responses: const <AiChatCompletion>[],
        autoTitleResponses: const <AiChatCompletion>[
          AiChatCompletion(reply: 'Planned Session'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        backgroundChatClient: backgroundClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-plan',
          'message-user-plan',
          'message-tool-call-plan',
          'message-tool-result-plan',
          'message-assistant-plan',
          'message-status-approved',
          'message-user-approved',
          'message-tool-call-approved',
          'message-tool-result-approved',
          'message-assistant-approved',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 15, 30, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-plan',
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
          content: 'Plan this change first',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(controller.currentSession!.awaitingPlanApproval, isTrue);
      expect(
        controller.currentSession!.pendingPlan,
        contains('Inspect the current runtime'),
      );
      expect(chatClient.requestedTools[1], isEmpty);

      expect(
        await controller.sendMessage(
          content: '确认执行',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(controller.currentSession!.awaitingPlanApproval, isFalse);
      expect(controller.currentSession!.pendingPlan, isNull);
      expect(
        chatClient.requestedTools.last.map((item) => item.name),
        contains('TodoWrite'),
      );
      expect(controller.currentSession!.todoItems, hasLength(1));
    },
  );

  test(
    'AiSessionController rejects Write on an existing file that was not read first',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-write-guard-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final file = File('${tempDirectory.path}/notes.txt');
      await file.writeAsString('original', flush: true);
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
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-write-guard',
                name: 'Write',
                arguments:
                    '{"file_path":"${file.path.replaceAll('\\', '\\\\')}","content":"updated"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'Write failure observed'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-write-guard',
          'message-user-write-guard',
          'message-tool-call-write-guard',
          'message-tool-result-write-guard',
          'message-assistant-write-guard',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 16, 0, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-write-guard',
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
          content: 'Overwrite the existing file',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(await file.readAsString(), 'original');
      final toolMessage = controller.currentSession!.messages.firstWhere(
        (message) =>
            message.kind == AiSessionMessageKind.tool &&
            message.metadata['tool_name'] == 'Write',
      );
      expect(toolMessage.metadata['status'], 'invalid_arguments');
      expect(
        toolMessage.content,
        contains('requires reading the file with Read'),
      );
    },
  );

  test(
    'AiSessionController allows a same-round Read followed by Write on the same file',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-read-write-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final file = File('${tempDirectory.path}/notes.txt');
      await file.writeAsString('original', flush: true);
      final escapedPath = file.path.replaceAll('\\', '\\\\');
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
          AiChatCompletion(
            reply: '',
            toolCalls: <AiToolCall>[
              AiToolCall(
                id: 'tool-call-read-first',
                name: 'Read',
                arguments: '{"file_path":"$escapedPath"}',
              ),
              AiToolCall(
                id: 'tool-call-write-after-read',
                name: 'Write',
                arguments: '{"file_path":"$escapedPath","content":"updated"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'File updated'),
        ],
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-read-write',
          'message-user-read-write',
          'message-tool-call-read',
          'message-tool-call-write',
          'message-tool-result-read',
          'message-tool-result-write',
          'message-assistant-read-write',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 16, 30, 0),
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
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-read-write',
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
          content: 'Read then update the same file',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(await file.readAsString(), 'updated');
      final writeMessage = controller.currentSession!.messages.firstWhere(
        (message) =>
            message.kind == AiSessionMessageKind.tool &&
            message.metadata['tool_call_id'] == 'tool-call-write-after-read',
      );
      expect(writeMessage.metadata['status'], 'success');
    },
  );

  test(
    'AiSessionController sends every tool result back after a multi-tool round',
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
                arguments: '{"cmd":"pwd"}',
              ),
              AiToolCall(
                id: 'tool-call-2',
                name: 'bash',
                arguments: '{"cmd":"ls -la"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'All checks finished'),
        ],
      );
      final generatedIds = <String>[
        'session-multi-tool',
        'message-user',
        'message-tool-call-1',
        'message-tool-call-2',
        'message-tool-result-1',
        'message-tool-result-2',
        'message-assistant',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        bashToolService: _QueuedBashToolService(
          results: const <BashToolExecutionResult>[
            BashToolExecutionResult(
              status: BashToolExecutionStatus.success,
              command: 'pwd',
              workingDirectory: '/tmp/demo',
              stdout: '/tmp/demo',
              stderr: '',
              durationMs: 40,
              exitCode: 0,
            ),
            BashToolExecutionResult(
              status: BashToolExecutionStatus.success,
              command: 'ls -la',
              workingDirectory: '/tmp/demo',
              stdout: 'README.md',
              stderr: '',
              durationMs: 45,
              exitCode: 0,
            ),
          ],
        ),
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 24, 10, 0, 0),
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
        id: 'model-multi-tool',
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
          content: 'Inspect the workspace',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(controller.sendPhase, AiSendPhase.idle);
      expect(chatClient.requests, hasLength(3));

      final followUpRequest = chatClient.requests[2];
      final assistantToolTurn = followUpRequest.singleWhere(
        (turn) =>
            turn.role == AiChatRole.assistant && turn.toolCalls.isNotEmpty,
      );
      final toolTurns = followUpRequest
          .where((turn) => turn.role == AiChatRole.tool)
          .toList(growable: false);

      expect(assistantToolTurn.toolCalls, hasLength(2));
      expect(
        assistantToolTurn.toolCalls.map((item) => item.id).toList(),
        <String>['tool-call-1', 'tool-call-2'],
      );
      expect(toolTurns.map((item) => item.toolCallId).toList(), <String>[
        'tool-call-1',
        'tool-call-2',
      ]);
      expect(toolTurns, hasLength(2));
      expect(toolTurns.first.content, contains('status: success'));
      expect(toolTurns.last.content, contains('status: success'));
      expect(
        controller.currentSession!.messages.any(
          (message) =>
              message.kind == AiSessionMessageKind.assistant &&
              message.content == 'All checks finished',
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController executes safe read-only tool batches in parallel',
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
                id: 'parallel-read-1',
                name: 'Read',
                arguments: '{"file_path":"README.md"}',
              ),
              AiToolCall(
                id: 'parallel-glob-1',
                name: 'Glob',
                arguments: '{"pattern":"*.md"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'Parallel reads done'),
        ],
      );
      final toolRuntimeService = _ParallelAwareToolRuntimeService();
      var nextId = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        toolRuntimeService: toolRuntimeService,
        idGenerator: () => 'id-${nextId++}',
        clock: () => DateTime.utc(2026, 3, 24, 11, 0, nextId),
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
        id: 'model-parallel-tools',
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

      final sendFuture = controller.sendMessage(
        content: 'Read the repo state in parallel',
        model: model,
        runtimeContext: runtimeContext,
      );
      await toolRuntimeService.waitForParallel();
      toolRuntimeService.release();

      expect(await sendFuture, isTrue);
      expect(toolRuntimeService.observedParallelExecution, isTrue);
    },
  );

  test(
    'AiSessionController executes read-only Bash batches in parallel with isolated sessions',
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
                id: 'parallel-bash-1',
                name: 'Bash',
                arguments: '{"cmd":"pwd"}',
              ),
              AiToolCall(
                id: 'parallel-bash-2',
                name: 'Bash',
                arguments: '{"cmd":"ls"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'Parallel bash done'),
        ],
      );
      final toolRuntimeService = _ParallelAwareToolRuntimeService();
      var nextId = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        toolRuntimeService: toolRuntimeService,
        idGenerator: () => 'id-${nextId++}',
        clock: () => DateTime.utc(2026, 3, 25, 0, 5, nextId),
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
        id: 'model-parallel-bash',
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

      final sendFuture = controller.sendMessage(
        content: 'Run two read-only commands',
        model: model,
        runtimeContext: runtimeContext,
      );
      await toolRuntimeService.waitForParallel();
      toolRuntimeService.release();

      expect(await sendFuture, isTrue);
      expect(toolRuntimeService.observedParallelExecution, isTrue);
    },
  );

  test(
    'AiSessionController previews running stdout for parallel read-only Bash batches',
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
                id: 'parallel-stream-bash-1',
                name: 'Bash',
                arguments: '{"cmd":"pwd"}',
              ),
              AiToolCall(
                id: 'parallel-stream-bash-2',
                name: 'Bash',
                arguments: '{"cmd":"ls"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'Parallel bash done'),
        ],
      );
      final toolRuntimeService = _ParallelStreamingToolRuntimeService();
      var nextId = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        toolRuntimeService: toolRuntimeService,
        idGenerator: () => 'parallel-stream-id-${nextId++}',
        clock: () => DateTime.utc(2026, 3, 25, 0, 5, nextId),
      );
      addTearDown(controller.dispose);
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
        id: 'model-parallel-stream-bash',
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

      final sendFuture = controller.sendMessage(
        content: 'Run two read-only commands with live previews',
        model: model,
        runtimeContext: runtimeContext,
      );
      await toolRuntimeService.waitForParallel();

      final toolCallMessages = controller.currentSession!.messages
          .where((message) => message.kind == AiSessionMessageKind.toolCall)
          .toList(growable: false);
      expect(toolCallMessages, hasLength(2));
      expect(
        toolCallMessages
            .firstWhere(
              (message) =>
                  '${message.metadata['tool_call_id'] ?? ''}' ==
                  'parallel-stream-bash-1',
            )
            .metadata['tool_execution_stdout'],
        contains('parallel-stream-bash-1 running'),
      );
      expect(
        toolCallMessages
            .firstWhere(
              (message) =>
                  '${message.metadata['tool_call_id'] ?? ''}' ==
                  'parallel-stream-bash-2',
            )
            .metadata['tool_execution_stdout'],
        contains('parallel-stream-bash-2 running'),
      );

      toolRuntimeService.release();
      expect(await sendFuture, isTrue);
      expect(toolRuntimeService.observedParallelExecution, isTrue);
    },
  );

  test('AiSessionController executes Task batches in parallel', () async {
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
              id: 'parallel-task-1',
              name: 'Task',
              arguments:
                  '{"description":"task-1","prompt":"inspect A","subagent_type":"general-purpose"}',
            ),
            AiToolCall(
              id: 'parallel-task-2',
              name: 'Task',
              arguments:
                  '{"description":"task-2","prompt":"inspect B","subagent_type":"general-purpose"}',
            ),
          ],
        ),
        const AiChatCompletion(reply: 'Parallel task done'),
      ],
    );
    final toolRuntimeService = _ParallelAwareToolRuntimeService();
    var nextId = 0;
    final controller = await AiSessionController.create(
      store: _InMemoryAiSessionStore(),
      chatClient: chatClient,
      templateRepository: promptRepository,
      toolRuntimeService: toolRuntimeService,
      idGenerator: () => 'id-${nextId++}',
      clock: () => DateTime.utc(2026, 3, 25, 0, 10, nextId),
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
      id: 'model-parallel-task',
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

    final sendFuture = controller.sendMessage(
      content: 'Run two subagents',
      model: model,
      runtimeContext: runtimeContext,
    );
    await toolRuntimeService.waitForParallel();
    toolRuntimeService.release();

    expect(await sendFuture, isTrue);
    expect(toolRuntimeService.observedParallelExecution, isTrue);
  });

  test(
    'AiSessionController keeps mixed read-write tool batches serial',
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
                id: 'serial-read-1',
                name: 'Read',
                arguments: '{"file_path":"README.md"}',
              ),
              AiToolCall(
                id: 'serial-write-1',
                name: 'Write',
                arguments: '{"file_path":"README.md","content":"updated"}',
              ),
            ],
          ),
          const AiChatCompletion(reply: 'Serial batch done'),
        ],
      );
      final toolRuntimeService = _ParallelAwareToolRuntimeService();
      var nextId = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        toolRuntimeService: toolRuntimeService,
        idGenerator: () => 'id-${nextId++}',
        clock: () => DateTime.utc(2026, 3, 24, 11, 30, nextId),
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
        id: 'model-serial-tools',
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

      final sendFuture = controller.sendMessage(
        content: 'Read then write serially',
        model: model,
        runtimeContext: runtimeContext,
      );
      await toolRuntimeService.waitForFirstExecution();
      await expectLater(
        toolRuntimeService.waitForParallel(),
        throwsA(isA<TimeoutException>()),
      );
      toolRuntimeService.release();

      expect(await sendFuture, isTrue);
      expect(toolRuntimeService.observedParallelExecution, isFalse);
    },
  );

  test(
    'AiSessionController prefetches official Claude Code docs base page and matching subpage before product questions',
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
          const AiChatCompletion(reply: 'Claude Code docs summary'),
        ],
      );
      final toolRuntimeService = _ClaudeDocsPrefetchToolRuntimeService();
      var nextId = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        toolRuntimeService: toolRuntimeService,
        idGenerator: () => 'id-${nextId++}',
        clock: () => DateTime.utc(2026, 3, 25, 0, 20, nextId),
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
        id: 'model-claude-docs',
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
          content: 'How do Claude Code hooks work?',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(toolRuntimeService.executedToolNames, everyElement('WebFetch'));
      expect(toolRuntimeService.executedToolArguments, hasLength(2));
      expect(
        toolRuntimeService.executedToolArguments.first['url'],
        'https://docs.anthropic.com/en/docs/claude-code',
      );
      expect(
        toolRuntimeService.executedToolArguments.last['url'],
        'https://docs.anthropic.com/en/docs/claude-code/hooks',
      );
      final firstRequest = chatClient.requests.firstWhere(
        (request) => request.any((turn) => turn.role == AiChatRole.tool),
      );
      expect(
        firstRequest.where((turn) => turn.role == AiChatRole.tool),
        isNotEmpty,
      );
      expect(
        controller.currentSession!.messages.any(
          (message) =>
              message.metadata['claude_code_docs_prefetch'] == true &&
              '${message.metadata['claude_code_docs_prefetch_url'] ?? ''}'
                  .contains('/hooks') &&
              message.kind == AiSessionMessageKind.tool,
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController prefetches multiple matching Claude Code doc subpages for broader product questions',
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
          const AiChatCompletion(reply: 'Claude Code docs summary'),
        ],
      );
      final toolRuntimeService = _ClaudeDocsPrefetchToolRuntimeService();
      var nextId = 0;
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        toolRuntimeService: toolRuntimeService,
        idGenerator: () => 'multi-docs-id-${nextId++}',
        clock: () => DateTime.utc(2026, 3, 25, 0, 21, nextId),
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
        id: 'model-claude-docs-multi',
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
          content: 'How do Claude Code settings and permissions work together?',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(toolRuntimeService.executedToolArguments, hasLength(3));
      final prefetchedUrls = toolRuntimeService.executedToolArguments
          .map((item) => '${item['url'] ?? ''}')
          .toList(growable: false);
      expect(
        prefetchedUrls,
        equals(<String>[
          'https://docs.anthropic.com/en/docs/claude-code',
          'https://docs.anthropic.com/en/docs/claude-code/settings',
          'https://docs.anthropic.com/en/docs/claude-code/iam',
        ]),
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
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Tool Limit Thread'),
          ],
        ),
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
      final toolCallMessages = currentSession.messages
          .where((message) => message.kind == AiSessionMessageKind.toolCall)
          .toList(growable: false);
      expect(toolCallMessages.length, 9);
      expect(
        currentSession.messages
            .where((message) => message.kind == AiSessionMessageKind.tool)
            .length,
        8,
      );
      expect(toolCallMessages.last.metadata['tool_execution_status'], 'failed');
      expect(
        '${toolCallMessages.last.metadata['tool_execution_result'] ?? ''}',
        contains('sequential tool round safety limit'),
      );
    },
  );

  test(
    'AiSessionController posts a warning and stops gracefully when tool calls exceed the per-response limit',
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
      final responses = <AiChatCompletion>[
        AiChatCompletion(
          reply: '',
          toolCalls: List<AiToolCall>.generate(
            41,
            (index) => AiToolCall(
              id: 'tool-limit-${index + 1}',
              name: 'bash',
              arguments: '{"cmd":"pwd"}',
            ),
          ),
        ),
      ];
      final generatedIds = List<String>.generate(
        96,
        (index) => 'tool-limit-id-$index',
      );
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
        clock: () => DateTime.utc(2026, 3, 25, 4, 0, 0),
      );
      addTearDown(controller.dispose);
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 5000,
        singleRoundToolCallLimit: 40,
        memoryEnabled: true,
        memoryEntries: [],
      );
      const model = AiModelConfig(
        id: 'model-tool-limit',
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

      final sessionId = controller.currentSessionId!;
      expect(
        await controller.sendMessage(
          sessionId: sessionId,
          content: 'Keep using tools until the limit is reached.',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final currentSession = controller.currentSession;
      expect(currentSession, isNotNull);
      expect(controller.lastErrorMessage, isNull);
      final warningMessage = currentSession!.messages.last;
      expect(warningMessage.kind, AiSessionMessageKind.status);
      expect(warningMessage.metadata['tool_call_limit_exceeded'], true);
      expect(warningMessage.metadata['tool_call_count'], 41);
      expect(warningMessage.metadata['tool_call_limit'], 40);
      expect(warningMessage.content, contains('超过当前设置的上限 40 次'));
      expect(
        currentSession.messages
            .where((message) => message.kind == AiSessionMessageKind.tool)
            .length,
        0,
      );
      final toolCallMessages = currentSession.messages
          .where((message) => message.kind == AiSessionMessageKind.toolCall)
          .toList(growable: false);
      expect(toolCallMessages, hasLength(41));
      expect(
        toolCallMessages.every(
          (message) => message.metadata['tool_execution_status'] == 'failed',
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController marks streamed tool call previews as failed when the stream errors',
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
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _ToolCallDeltaErrorStreamingChatClient(),
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-tool-call-stream-error',
          'message-user-tool-call-stream-error',
          'message-tool-call-stream-error',
          'error-record-tool-call-stream-error',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 2, 5, 0),
      );
      addTearDown(controller.dispose);

      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'en',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/tmp/settings.toml',
        skillsStoragePath: '/tmp/skills',
        mcpServersFilePath: '/tmp/mcp_servers.json',
        userMemoryFilePath: '/tmp/memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: true,
        memoryEntries: <UserMemoryEntry>[],
      );
      const model = AiModelConfig(
        id: 'model-tool-call-stream-error',
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
          content: 'Please prepare the todo list',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isFalse,
      );

      final session = controller.currentSession;
      expect(session, isNotNull);
      expect(session!.recentErrors.first.stage, 'chat_stream');
      final toolCallMessage = session.messages.singleWhere(
        (message) => message.kind == AiSessionMessageKind.toolCall,
      );
      expect(toolCallMessage.metadata['tool_execution_status'], 'failed');
      expect(
        '${toolCallMessage.metadata['tool_execution_result'] ?? ''}',
        contains('stream failed before the pending tool call completed'),
      );
    },
  );

  test(
    'AiSessionController marks streamed tool call previews as cancelled when responding is stopped',
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
      final chatClient = _ToolCallDeltaStreamingChatClient();
      final generatedIds = <String>[
        'session-stop-tool-preview',
        'message-user-stop-tool-preview',
        'message-tool-call-stop-tool-preview',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 25, 3, 0, 0),
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
        id: 'model-stop-tool-preview',
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

      final sendFuture = controller.sendMessage(
        content: 'Start preparing the todo list.',
        model: model,
        runtimeContext: runtimeContext,
      );

      await _waitForCondition(() {
        final session = controller.currentSession;
        return session != null &&
            session.messages.any(
              (message) => message.kind == AiSessionMessageKind.toolCall,
            );
      });
      await controller.stopResponding('session-stop-tool-preview');
      expect(await sendFuture, isTrue);

      final toolCallMessage = controller.currentSession!.messages.firstWhere(
        (message) => message.kind == AiSessionMessageKind.toolCall,
      );
      expect(toolCallMessage.metadata['tool_execution_status'], 'cancelled');
      expect(
        '${toolCallMessage.metadata['tool_execution_result'] ?? ''}',
        contains('status: cancelled'),
      );
      expect(chatClient.cancelInvoked, isTrue);
      expect(
        controller.currentSession!.messages
            .where((message) => message.kind == AiSessionMessageKind.tool)
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'AiSessionController removes streamed tool call previews that are absent from the final stream result',
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
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _ToolCallDeltaDroppedStreamingChatClient(),
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-tool-call-preview-dropped',
          'message-user-tool-call-preview-dropped',
          'message-tool-call-preview-dropped',
          'message-assistant-tool-call-preview-dropped',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 20, 0),
      );
      addTearDown(controller.dispose);

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
        id: 'model-tool-call-preview-dropped',
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
          content: 'Stream a temporary tool call, then finish normally.',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      expect(
        controller.currentSession!.messages
            .where(
              (message) =>
                  !message.isDeleted &&
                  message.kind == AiSessionMessageKind.toolCall,
            )
            .isEmpty,
        isTrue,
      );
      expect(
        controller.currentSession!.messages.any(
          (message) =>
              message.kind == AiSessionMessageKind.assistant &&
              message.content == 'Finished without tool calls',
        ),
        isTrue,
      );
    },
  );

  test(
    'AiSessionController stops queued tool calls after the running tool is cancelled',
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
                id: 'tool-call-running-stop',
                name: 'bash',
                arguments: '{"cmd":"pwd"}',
              ),
              AiToolCall(
                id: 'tool-call-pending-stop',
                name: 'bash',
                arguments: '{"cmd":"touch /tmp/stop-after-cancel.txt"}',
              ),
            ],
          ),
        ],
      );
      final bashService = _CancelAwarePendingBashToolService();
      final generatedIds = <String>[
        'session-stop-tool-running',
        'message-user-stop-tool-running',
        'message-tool-call-running-stop',
        'message-tool-call-pending-stop',
        'message-tool-result-running-stop',
        'message-unused-stop-tool-running-1',
        'message-unused-stop-tool-running-2',
        'message-unused-stop-tool-running-3',
      ];
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        templateRepository: promptRepository,
        bashToolService: bashService,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => DateTime.utc(2026, 3, 25, 3, 5, 0),
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
        id: 'model-stop-tool-running',
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

      final sendFuture = controller.sendMessage(
        content: 'Run the queued tools.',
        model: model,
        runtimeContext: runtimeContext,
      );

      await bashService.waitForExecutionStart();
      await controller.stopResponding('session-stop-tool-running');
      expect(await sendFuture, isTrue);

      final toolCallMessages = controller.currentSession!.messages
          .where((message) => message.kind == AiSessionMessageKind.toolCall)
          .toList(growable: false);
      expect(toolCallMessages, hasLength(2));
      expect(
        toolCallMessages[0].metadata['tool_execution_status'],
        'cancelled',
      );
      expect(
        toolCallMessages[1].metadata['tool_execution_status'],
        'cancelled',
      );
      expect(bashService.executeCount, 1);
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

      expect(await pendingSend.timeout(const Duration(seconds: 1)), isTrue);
      expect(chatClient.cancelInvoked, isTrue);
      expect(chatClient.disposeCount, 1);
    },
  );

  test(
    'AiSessionController injects hidden user-prompt hook feedback into the next prompt',
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
        responses: const <AiChatCompletion>[AiChatCompletion(reply: 'Done')],
      );
      final hookService = _FakeClaudeHookService(
        userPromptSubmitResult: const AiClaudeHookInvocationResult(
          userFeedback: <String>['Follow the repository checklist.'],
        ),
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        hookService: hookService,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-hook-user',
          'message-user-hook',
          'message-assistant-hook',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 3, 0, 0),
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
        id: 'model-hook-user',
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
          content: 'Continue implementation.',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final request = chatClient.requests.last;
      expect(
        request.last.content,
        contains(
          '<user-prompt-submit-hook>Follow the repository checklist.</user-prompt-submit-hook>',
        ),
      );
      expect(
        controller.currentSession!.messages
            .where((item) => item.kind == AiSessionMessageKind.user)
            .single
            .content,
        'Continue implementation.',
      );
    },
  );

  test(
    'AiSessionController stops before persistence when a user-prompt hook blocks',
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
        responses: const <AiChatCompletion>[AiChatCompletion(reply: 'Done')],
      );
      final hookService = _FakeClaudeHookService(
        userPromptSubmitResult: const AiClaudeHookInvocationResult(
          blocked: true,
          blockReason: 'Prompt blocked by policy hook.',
        ),
      );
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        hookService: hookService,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-hook-block',
          'error-1',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 3, 10, 0),
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
        id: 'model-hook-block',
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
          content: 'Continue implementation.',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isFalse,
      );
      expect(chatClient.requests, isEmpty);
      expect(controller.lastErrorMessage, 'Prompt blocked by policy hook.');
      expect(controller.currentSession!.messages, isEmpty);
      expect(
        controller.currentSession!.recentErrors.first.stage,
        'user_prompt_hook',
      );
    },
  );

  test(
    'AiSessionController emits lifecycle and runtime compatibility hook events',
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
          AiChatCompletion(reply: 'Compressed summary'),
          AiChatCompletion(reply: 'Second answer'),
        ],
      );
      final hookService = _FakeClaudeHookService();
      final controller = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: chatClient,
        hookService: hookService,
        templateRepository: promptRepository,
        idGenerator: _fixedIdGenerator(<String>[
          'session-hook-lifecycle',
          'message-user-1',
          'message-assistant-1',
          'message-checkpoint',
          'message-user-2',
          'message-assistant-2',
        ]),
        clock: () => DateTime.utc(2026, 3, 24, 4, 0, 0),
      );
      final runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
        skillsStoragePath: '/Users/example/.openhand/skills',
        mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
        userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
        compressionThresholdChars: 10,
        memoryEnabled: true,
        memoryEntries: const [],
        workspaceInstructionDocuments: const <AiWorkspaceInstructionDocument>[
          AiWorkspaceInstructionDocument(
            path: '/workspace/.claude/rules/policy.md',
            name: 'policy.md',
            content: 'Always follow the policy.',
          ),
        ],
      );
      const model = AiModelConfig(
        id: 'model-hook-lifecycle',
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
          content: 'Need detailed plan',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await controller.sendMessage(
          content: 'Continue',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(await controller.deleteSession('session-hook-lifecycle'), isTrue);

      expect(hookService.recordedEventNames, contains('SessionStart'));
      expect(hookService.recordedEventNames, contains('InstructionsLoaded'));
      expect(hookService.recordedEventNames, contains('ConfigChange'));
      expect(hookService.recordedEventNames, contains('PreCompact'));
      expect(hookService.recordedEventNames, contains('PostCompact'));
      expect(hookService.recordedEventNames, contains('Stop'));
      expect(hookService.recordedEventNames, contains('SessionEnd'));
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

  @override
  Future<bool> exists(String sessionId) async {
    return _sessions.containsKey(sessionId);
  }
}

class _FailingSaveAiSessionStore extends AiSessionStore {
  _FailingSaveAiSessionStore({
    required super.sessionsDirectoryPath,
    required this.failOnSaveNumber,
  });

  final int failOnSaveNumber;
  final Map<String, AiSession> _sessions = <String, AiSession>{};
  int _saveCount = 0;

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
    _saveCount += 1;
    if (_saveCount >= failOnSaveNumber) {
      throw const FileSystemException('Injected save failure');
    }
    _sessions[session.id] = session;
  }

  @override
  Future<bool> exists(String sessionId) async {
    return _sessions.containsKey(sessionId);
  }
}

class _AutoTitleFailingAiSessionStore extends AiSessionStore {
  _AutoTitleFailingAiSessionStore()
    : super(
        sessionsDirectoryPath: '/tmp/openhand-auto-title-persist-failure-test',
      );

  final Map<String, AiSession> _sessions = <String, AiSession>{};
  bool _didFailAutoTitleSave = false;

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
    if (!_didFailAutoTitleSave && session.autoTitleGeneratedAt != null) {
      _didFailAutoTitleSave = true;
      throw const FileSystemException('Injected auto title save failure');
    }
    _sessions[session.id] = session;
  }

  @override
  Future<bool> exists(String sessionId) async {
    return _sessions.containsKey(sessionId);
  }
}

class _PartiallyFailingDeleteAiSessionStore extends AiSessionStore {
  _PartiallyFailingDeleteAiSessionStore({required super.sessionsDirectoryPath});

  @override
  Future<void> delete(String sessionId) async {
    final file = File(sessionFilePath(sessionId));
    if (await file.exists()) {
      await file.delete();
    }
    throw const FileSystemException('Injected partial delete failure');
  }
}

class _FakeClaudeHookService extends AiClaudeHookService {
  _FakeClaudeHookService({
    this.userPromptSubmitResult = const AiClaudeHookInvocationResult(),
  });

  final AiClaudeHookInvocationResult userPromptSubmitResult;
  final List<String> recordedEventNames = <String>[];

  @override
  Future<AiClaudeHookInvocationResult> runHooks({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    recordedEventNames.add(eventName);
    return switch (eventName) {
      'UserPromptSubmit' => userPromptSubmitResult,
      _ => const AiClaudeHookInvocationResult(),
    };
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
  final List<List<AiToolDefinition>> requestedTools =
      <List<AiToolDefinition>>[];
  final List<AiModelConfig> requestModels = <AiModelConfig>[];

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    requests.add(List<AiChatTurn>.from(messages));
    requestedTools.add(List<AiToolDefinition>.from(tools));
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

String Function() _fixedIdGenerator(List<String> ids) {
  final pendingIds = List<String>.from(ids);
  return () => pendingIds.removeAt(0);
}

class _FakeAiMcpToolDiscoveryService implements McpToolDiscoveryService {
  _FakeAiMcpToolDiscoveryService({
    required McpToolCatalog catalog,
    required McpToolCallResult callResult,
  }) : _catalog = catalog,
       _callResult = callResult;

  final McpToolCatalog _catalog;
  final McpToolCallResult _callResult;
  final List<String> requestedServerNames = <String>[];
  final List<String> calledToolNames = <String>[];

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    requestedServerNames.add(server.name);
    return _catalog;
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    calledToolNames.add(toolName);
    return _callResult;
  }

  @override
  void dispose() {}
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

class _DelayedFailingStreamingChatClient implements AiChatClient {
  _DelayedFailingStreamingChatClient({
    required this.delayedPrompt,
    required this.failureMessage,
    required this.successReply,
  });

  final String delayedPrompt;
  final String failureMessage;
  final String successReply;
  final Completer<void> _failureCompleter = Completer<void>();

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
    final prompt = messages.isEmpty ? '' : messages.last.content;
    if (prompt.contains(delayedPrompt)) {
      Stream<AiChatStreamEvent> events() async* {
        await _failureCompleter.future;
      }

      return AiChatStreamingResponse(
        events: events(),
        result: _failureCompleter.future.then<AiChatStreamResult>((_) {
          throw AiChatException(failureMessage);
        }),
      );
    }

    return AiChatStreamingResponse(
      events: Stream<AiChatStreamEvent>.fromIterable(<AiChatStreamEvent>[
        AiChatStreamEvent.textDelta(successReply),
      ]),
      result: Future<AiChatStreamResult>.value(
        AiChatStreamResult(
          reply: successReply,
          reasoning: '',
          toolCalls: const <AiToolCall>[],
        ),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  void completeFailure() {
    if (_failureCompleter.isCompleted) {
      return;
    }
    _failureCompleter.complete();
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

class _PartialDeltaStreamingChatClient implements AiChatClient {
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
      events: Stream<AiChatStreamEvent>.fromIterable(const <AiChatStreamEvent>[
        AiChatStreamEvent.reasoningDelta('Step'),
        AiChatStreamEvent.textDelta('Partial'),
      ]),
      result: Future<AiChatStreamResult>.value(
        const AiChatStreamResult(
          reply: 'Partial answer completed',
          reasoning: 'Step 1 complete',
          toolCalls: <AiToolCall>[],
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
    String? sessionId,
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

class _QueuedBashToolService extends AiBashToolService {
  _QueuedBashToolService({required List<BashToolExecutionResult> results})
    : _results = List<BashToolExecutionResult>.from(results);

  final List<BashToolExecutionResult> _results;

  @override
  Future<BashToolExecutionResult> execute({
    required String command,
    String? sessionId,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = AiBashToolService.defaultTimeoutMs,
  }) async {
    return _results.removeAt(0);
  }
}

class _PendingBashToolService extends AiBashToolService {
  final Completer<BashToolExecutionResult> _completer =
      Completer<BashToolExecutionResult>();

  @override
  Future<BashToolExecutionResult> execute({
    required String command,
    String? sessionId,
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

class _CancelAwarePendingBashToolService extends AiBashToolService {
  final Completer<void> _executionStarted = Completer<void>();
  int executeCount = 0;

  Future<void> waitForExecutionStart() {
    return _executionStarted.future.timeout(const Duration(milliseconds: 250));
  }

  @override
  Future<BashToolExecutionResult> execute({
    required String command,
    String? sessionId,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = AiBashToolService.defaultTimeoutMs,
  }) async {
    executeCount += 1;
    if (!_executionStarted.isCompleted) {
      _executionStarted.complete();
    }
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
    await (cancelSignal ?? Future<void>.value());
    return BashToolExecutionResult(
      status: BashToolExecutionStatus.cancelled,
      command: command,
      workingDirectory: (workingDirectory ?? '').trim(),
      stdout: '',
      stderr: '',
      durationMs: 1,
    );
  }
}

class _ParallelAwareToolRuntimeService extends AiToolRuntimeService {
  _ParallelAwareToolRuntimeService()
    : super(
        bashToolService: AiBashToolService(),
        hookService: AiClaudeHookService(),
        mcpToolService: _NoopMcpToolDiscoveryService(),
        backgroundChatClient: _IdleChatClient(),
      );

  final Completer<void> _firstExecutionCompleter = Completer<void>();
  final Completer<void> _parallelExecutionCompleter = Completer<void>();
  final Completer<void> _releaseCompleter = Completer<void>();
  int _activeExecutions = 0;
  bool observedParallelExecution = false;

  Future<void> waitForFirstExecution() {
    return _firstExecutionCompleter.future.timeout(
      const Duration(milliseconds: 250),
    );
  }

  Future<void> waitForParallel() {
    return _parallelExecutionCompleter.future.timeout(
      const Duration(milliseconds: 250),
    );
  }

  void release() {
    if (_releaseCompleter.isCompleted) {
      return;
    }
    _releaseCompleter.complete();
  }

  @override
  Future<AiToolExecutionResult> execute({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required AiModelConfig model,
    required Set<String> previouslyReadFiles,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
  }) async {
    if (!_firstExecutionCompleter.isCompleted) {
      _firstExecutionCompleter.complete();
    }
    _activeExecutions += 1;
    if (_activeExecutions >= 2) {
      observedParallelExecution = true;
      if (!_parallelExecutionCompleter.isCompleted) {
        _parallelExecutionCompleter.complete();
      }
    }
    await _releaseCompleter.future;
    _activeExecutions -= 1;
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: toolCall.name,
      workingDirectory: '/workspace',
      stdout: '${toolCall.name} finished',
      stderr: '',
      durationMs: 1,
      exitCode: 0,
      resultText: 'status: success\nresult: ${toolCall.name} finished',
    );
  }
}

class _ParallelStreamingToolRuntimeService extends AiToolRuntimeService {
  _ParallelStreamingToolRuntimeService()
    : super(
        bashToolService: AiBashToolService(),
        hookService: AiClaudeHookService(),
        mcpToolService: _NoopMcpToolDiscoveryService(),
        backgroundChatClient: _IdleChatClient(),
      );

  final Completer<void> _parallelExecutionCompleter = Completer<void>();
  final Completer<void> _releaseCompleter = Completer<void>();
  int _activeExecutions = 0;
  bool observedParallelExecution = false;

  Future<void> waitForParallel() {
    return _parallelExecutionCompleter.future.timeout(
      const Duration(milliseconds: 250),
    );
  }

  void release() {
    if (_releaseCompleter.isCompleted) {
      return;
    }
    _releaseCompleter.complete();
  }

  @override
  Future<AiToolExecutionResult> execute({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required AiModelConfig model,
    required Set<String> previouslyReadFiles,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
  }) async {
    onBashUpdate?.call(
      BashToolExecutionUpdate(
        phase: BashToolExecutionPhase.running,
        command: '${toolCall.name} ${toolCall.id}',
        workingDirectory: '/workspace',
        stdout: '${toolCall.id} running',
        stderr: '',
        durationMs: 1,
      ),
    );
    _activeExecutions += 1;
    if (_activeExecutions >= 2) {
      observedParallelExecution = true;
      if (!_parallelExecutionCompleter.isCompleted) {
        _parallelExecutionCompleter.complete();
      }
    }
    await _releaseCompleter.future;
    _activeExecutions -= 1;
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: toolCall.name,
      workingDirectory: '/workspace',
      stdout: '${toolCall.id} finished',
      stderr: '',
      durationMs: 2,
      exitCode: 0,
      resultText: 'status: success\nresult: ${toolCall.id} finished',
    );
  }
}

class _ClaudeDocsPrefetchToolRuntimeService extends AiToolRuntimeService {
  _ClaudeDocsPrefetchToolRuntimeService()
    : super(
        bashToolService: AiBashToolService(),
        hookService: AiClaudeHookService(),
        mcpToolService: _NoopMcpToolDiscoveryService(),
        backgroundChatClient: _IdleChatClient(),
      );

  final List<String> executedToolNames = <String>[];
  final List<Map<String, Object?>> executedToolArguments =
      <Map<String, Object?>>[];

  @override
  Future<AiToolExecutionResult> execute({
    required String sessionId,
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required AiModelConfig model,
    required Set<String> previouslyReadFiles,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate update)? onBashUpdate,
  }) async {
    executedToolNames.add(toolCall.name);
    final decodedArguments = jsonDecode(toolCall.arguments);
    if (decodedArguments is Map) {
      executedToolArguments.add(Map<String, Object?>.from(decodedArguments));
    }
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: toolCall.name,
      workingDirectory: '/workspace',
      stdout: 'Official Claude Code docs summary',
      stderr: '',
      durationMs: 1,
      exitCode: 0,
      resultText: 'status: success\nresult: Official Claude Code docs summary',
    );
  }
}

class _NoopMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return const McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: <McpTool>[],
    );
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth(status: McpServerHealthStatus.healthy);
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}

class _IdleChatClient implements AiChatClient {
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
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  @override
  void dispose() {}
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

class _ToolCallDeltaStreamingChatClient implements AiChatClient {
  final StreamController<AiChatStreamEvent> _events =
      StreamController<AiChatStreamEvent>();
  final Completer<AiChatStreamResult> _resultCompleter =
      Completer<AiChatStreamResult>();
  bool cancelInvoked = false;
  bool _started = false;

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
    if (!_started) {
      _started = true;
      scheduleMicrotask(() {
        _events.add(
          const AiChatStreamEvent.toolCallDelta(
            AiToolCallDelta(
              index: 0,
              id: 'tool-call-stop-preview',
              name: 'TodoWrite',
              argumentsFragment:
                  '{"todos":[{"id":"1","content":"Create .finops/data and .finops/output","status":"pending"}]}',
            ),
          ),
        );
      });
    }
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
  void dispose() {}
}

class _ToolCallDeltaErrorStreamingChatClient implements AiChatClient {
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
      events: Stream<AiChatStreamEvent>.fromIterable(const <AiChatStreamEvent>[
        AiChatStreamEvent.toolCallDelta(
          AiToolCallDelta(
            index: 0,
            id: 'tool-call-stream-error',
            name: 'TodoWrite',
            argumentsFragment:
                '{"todos":[{"id":"1","content":"Prepare a summary","status":"pending"}]}',
          ),
        ),
      ]),
      result: Future<AiChatStreamResult>.delayed(
        const Duration(milliseconds: 20),
        () => throw StateError('stream failure'),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  @override
  void dispose() {}
}

class _ToolCallDeltaDroppedStreamingChatClient implements AiChatClient {
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
      events: Stream<AiChatStreamEvent>.fromIterable(const <AiChatStreamEvent>[
        AiChatStreamEvent.toolCallDelta(
          AiToolCallDelta(
            index: 0,
            id: 'tool-call-preview-dropped',
            name: 'TodoWrite',
            argumentsFragment:
                '{"todos":[{"id":"1","content":"Temporary preview","status":"pending"}]}',
          ),
        ),
      ]),
      result: Future<AiChatStreamResult>.value(
        const AiChatStreamResult(
          reply: 'Finished without tool calls',
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

  @override
  void dispose() {}
}

Future<void> _waitForCondition(
  bool Function() predicate, {
  Duration timeout = const Duration(milliseconds: 250),
  Duration pollInterval = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(pollInterval);
  }
  if (!predicate()) {
    throw TimeoutException('Condition was not met in time.');
  }
}
