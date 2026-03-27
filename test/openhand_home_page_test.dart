import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:openhand/app/model/app_info.dart';
import 'package:openhand/app/model/app_language.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/app/theme/openhand_theme.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';
import 'package:openhand/features/home/openhand_home_page.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/memory/data/memory_store.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/features/skills/data/skills_repository.dart';
import 'package:openhand/features/skills/model/local_skill.dart';
import 'package:openhand/features/skills/skills_controller.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/widgets/openhand_dialog_action_button.dart';

void main() {
  testWidgets(
    'OpenHandHomePage shows message actions when tapping assistant text',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Assistant reply'),
          ],
        ),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Thread Title'),
          ],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-home-page',
          'message-user',
          'message-assistant',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 0, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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
        id: 'model-home-page',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await sessionController.sendMessage(
          content: 'Hello',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppInfo>.value(value: AppInfo.fallback()),
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<AiSessionController>.value(
              value: sessionController,
            ),
            ChangeNotifierProvider<MemoryController>.value(
              value: memoryController,
            ),
            ChangeNotifierProvider<SkillsController>.value(
              value: skillsController,
            ),
            ChangeNotifierProvider<McpController>.value(value: mcpController),
          ],
          child: MaterialApp(
            locale: settingsController.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: OpenHandTheme.light(OpenHandThemePreset.deepSeaBlue),
            home: const Scaffold(body: OpenHandHomePage()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Assistant reply'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);

      await tester.tap(find.text('Assistant reply'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'OpenHandHomePage deletes the selected message and later messages from the transcript',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-delete-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Assistant delete reply'),
          ],
        ),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Delete Thread Title'),
          ],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-home-page-delete',
          'message-home-page-delete-user',
          'message-home-page-delete-assistant',
        ]),
        clock: () => DateTime.utc(2026, 3, 27, 8, 0, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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
        id: 'model-home-page-delete',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      expect(
        await sessionController.sendMessage(
          content: 'Delete target message',
          model: model,
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('Delete target message'), findsOneWidget);
      expect(find.text('Assistant delete reply'), findsOneWidget);

      await tester.tap(find.text('Delete target message'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Delete From Here'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OpenHandDialogActionButton, 'Delete'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(OpenHandDialogActionButton, 'Delete'),
      );
      await tester.pump();

      expect(find.text('Delete target message'), findsOneWidget);
      expect(find.text('Assistant delete reply'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();

      expect(find.text('Delete target message'), findsNothing);
      expect(find.text('Assistant delete reply'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'OpenHandHomePage keeps auto follow pinned to the bottom while a long reply streams',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _StepStreamingChatClient(
          replyChunks: List<String>.generate(12, (index) {
            final startLine = index * 8;
            final lines = List<String>.generate(
              8,
              (offset) => 'stream-line-${startLine + offset}',
            );
            return '${lines.join('\n')}\n';
          }),
        ),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Thread Title'),
          ],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-auto-follow',
          'message-user-auto-follow',
          'message-assistant-auto-follow',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 0, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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
        id: 'model-auto-follow',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppInfo>.value(value: AppInfo.fallback()),
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<AiSessionController>.value(
              value: sessionController,
            ),
            ChangeNotifierProvider<MemoryController>.value(
              value: memoryController,
            ),
            ChangeNotifierProvider<SkillsController>.value(
              value: skillsController,
            ),
            ChangeNotifierProvider<McpController>.value(value: mcpController),
          ],
          child: MaterialApp(
            locale: settingsController.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: OpenHandTheme.light(OpenHandThemePreset.deepSeaBlue),
            home: const Scaffold(body: OpenHandHomePage()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final sendFuture = sessionController.sendMessage(
        content: 'Please stream a very long answer.',
        model: model,
        runtimeContext: runtimeContext,
      );

      for (var index = 0; index < 20; index++) {
        await tester.pump(const Duration(milliseconds: 24));
      }
      expect(await sendFuture, isTrue);
      await tester.pumpAndSettle();

      final transcriptList = tester.widget<ListView>(
        find.byKey(const ValueKey<String>('session-transcript-list')),
      );
      final controller = transcriptList.controller!;

      expect(controller.hasClients, isTrue);
      expect(controller.position.maxScrollExtent, greaterThan(0));
      expect(
        controller.position.maxScrollExtent - controller.position.pixels,
        lessThanOrEqualTo(1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'OpenHandHomePage keeps the token pill typography aligned with toolbar pills',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-toolbar-token-pill']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 5, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-toolbar-token-pill',
          content: 'Show me the toolbar',
          createdAt: DateTime.utc(2026, 3, 25, 3, 5, 0),
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 5, 1),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(totalTokens: 12097),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      final tokenIcon = tester.widget<Icon>(
        find.byIcon(Icons.confirmation_number_rounded),
      );
      expect(tokenIcon.size, 14);

      final tokenCountText = tester.widget<Text>(find.text('12097'));
      final tokenLabelText = tester.widget<Text>(find.text('Token'));
      final metadataLabelText = tester.widget<Text>(
        find.text('Session Metadata'),
      );

      expect(tokenCountText.style?.fontSize, metadataLabelText.style?.fontSize);
      expect(tokenLabelText.style?.fontSize, metadataLabelText.style?.fontSize);
    },
  );

  testWidgets(
    'OpenHandHomePage rearms auto follow after a new UI send from an older scroll position',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _StepStreamingChatClient(
          replyChunks: List<String>.generate(12, (index) {
            final startLine = index * 8;
            final lines = List<String>.generate(
              8,
              (offset) => 'follow-line-${startLine + offset}',
            );
            return '${lines.join('\n')}\n';
          }),
        ),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Thread Title'),
          ],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-rearm-auto-follow',
          'message-user-seed',
          'message-assistant-seed',
          'message-user-ui',
          'message-assistant-ui',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 20, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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
        id: 'model-rearm-auto-follow',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(await settingsController.saveAiModel(model), isTrue);
      expect(await settingsController.updateSelectedAiModel(model.id), isTrue);
      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      final seedSendFuture = sessionController.sendMessage(
        content: 'Seed the transcript with a long answer.',
        model: model,
        runtimeContext: runtimeContext,
      );
      for (var index = 0; index < 24; index++) {
        await tester.pump(const Duration(milliseconds: 24));
      }
      expect(await seedSendFuture, isTrue);
      await tester.pumpAndSettle();

      final transcriptFinder = find.byKey(
        const ValueKey<String>('session-transcript-list'),
      );
      final firstController = tester
          .widget<ListView>(transcriptFinder)
          .controller!;
      expect(firstController.position.maxScrollExtent, greaterThan(0));

      await tester.drag(transcriptFinder, const Offset(0, 260));
      await tester.pumpAndSettle();

      expect(
        firstController.position.maxScrollExtent -
            firstController.position.pixels,
        greaterThan(96),
      );

      await tester.enterText(
        find.byType(TextField).first,
        'Send another long answer from the composer.',
      );
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      for (var index = 0; index < 24; index++) {
        await tester.pump(const Duration(milliseconds: 24));
      }

      final secondController = tester
          .widget<ListView>(transcriptFinder)
          .controller!;
      expect(
        secondController.position.maxScrollExtent -
            secondController.position.pixels,
        lessThanOrEqualTo(1),
      );
    },
  );

  testWidgets(
    'OpenHandHomePage keeps composer drafts isolated per session when switching threads',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-a', 'session-b']),
        clock: () => DateTime.utc(2026, 3, 25, 4, 0, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionAId = sessionController.currentSessionId!;
      expect(
        await sessionController.renameSession(sessionAId, 'Thread A'),
        isTrue,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionBId = sessionController.currentSessionId!;
      expect(
        await sessionController.renameSession(sessionBId, 'Thread B'),
        isTrue,
      );

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      await tester.tap(find.text('Thread A').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final composerField = find.byType(TextField).first;
      await tester.enterText(composerField, 'Draft for A');
      await tester.pump();

      await tester.tap(find.text('Thread B').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.widget<TextField>(composerField).controller!.text, isEmpty);

      await tester.enterText(composerField, 'Draft for B');
      await tester.pump();

      await tester.tap(find.text('Thread A').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<TextField>(composerField).controller!.text,
        'Draft for A',
      );

      await tester.tap(find.text('Thread B').first);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(composerField).controller!.text,
        'Draft for B',
      );
    },
  );

  testWidgets(
    'OpenHandHomePage restores a failed send draft to its original thread after switching away',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _DelayedFailingUserMessageSessionStore(),
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(
          List<String>.generate(16, (index) => 'send-failure-id-$index'),
        ),
        clock: () => DateTime.utc(2026, 3, 25, 4, 20, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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
        id: 'model-send-failure-restore',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );
      expect(await settingsController.saveAiModel(model), isTrue);
      expect(await settingsController.updateSelectedAiModel(model.id), isTrue);

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionAId = sessionController.currentSessionId!;
      expect(
        await sessionController.renameSession(sessionAId, 'Thread A'),
        isTrue,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionBId = sessionController.currentSessionId!;
      expect(
        await sessionController.renameSession(sessionBId, 'Thread B'),
        isTrue,
      );

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      await tester.tap(find.text('Thread A').first);
      await tester.pumpAndSettle();

      final composerField = find.byType(TextField).first;
      await tester.enterText(composerField, 'Keep this draft in A');
      await tester.pump();

      await tester.tap(find.text('Send'));
      await tester.pump(const Duration(milliseconds: 40));

      await tester.tap(find.text('Thread B').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.widget<TextField>(composerField).controller!.text, isEmpty);

      await tester.pump(const Duration(milliseconds: 640));

      expect(tester.widget<TextField>(composerField).controller!.text, isEmpty);

      await tester.tap(find.text('Thread A').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<TextField>(composerField).controller!.text,
        'Keep this draft in A',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'OpenHandHomePage pauses auto follow for wheel-like user scroll notifications',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _StepStreamingChatClient(
          replyChunks: List<String>.generate(18, (index) {
            final startLine = index * 8;
            final lines = List<String>.generate(
              8,
              (offset) => 'wheel-line-${startLine + offset}',
            );
            return '${lines.join('\n')}\n';
          }),
        ),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Thread Title'),
          ],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-wheel-auto-follow',
          'message-user-wheel-auto-follow',
          'message-assistant-wheel-auto-follow',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 25, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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
        id: 'model-wheel-auto-follow',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      final sendFuture = sessionController.sendMessage(
        content: 'Stream a long answer and let me scroll away with the wheel.',
        model: model,
        runtimeContext: runtimeContext,
      );

      final transcriptFinder = find.byKey(
        const ValueKey<String>('session-transcript-list'),
      );
      ScrollController? maybeTranscriptController;
      for (var index = 0; index < 18; index++) {
        await tester.pump(const Duration(milliseconds: 24));
        maybeTranscriptController ??= tester
            .widget<ListView>(transcriptFinder)
            .controller;
        if (maybeTranscriptController!.hasClients &&
            maybeTranscriptController.position.maxScrollExtent > 180) {
          break;
        }
      }

      final transcriptController =
          (maybeTranscriptController ??
          tester.widget<ListView>(transcriptFinder).controller)!;
      expect(transcriptController.hasClients, isTrue);
      expect(transcriptController.position.maxScrollExtent, greaterThan(180));

      final olderOffset = (transcriptController.position.maxScrollExtent - 180)
          .clamp(
            transcriptController.position.minScrollExtent,
            transcriptController.position.maxScrollExtent,
          )
          .toDouble();
      transcriptController.jumpTo(olderOffset);
      final transcriptContext = tester.element(transcriptFinder);
      UserScrollNotification(
        metrics: transcriptController.position,
        context: transcriptContext,
        direction: ScrollDirection.forward,
      ).dispatch(transcriptContext);
      await tester.pump();
      expect(
        transcriptController.position.maxScrollExtent -
            transcriptController.position.pixels,
        greaterThan(96),
      );

      for (var index = 0; index < 24; index++) {
        await tester.pump(const Duration(milliseconds: 24));
      }
      expect(await sendFuture, isTrue);
      await tester.pumpAndSettle();

      expect(
        transcriptController.position.maxScrollExtent -
            transcriptController.position.pixels,
        greaterThan(96),
      );
    },
  );

  testWidgets(
    'OpenHandHomePage shows an active thread badge while a session is responding',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _StepStreamingChatClient(
          replyChunks: List<String>.generate(18, (index) => 'chunk-$index\n'),
        ),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Thread Title'),
          ],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-thread-active',
          'message-user-thread-active',
          'message-assistant-thread-active',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 30, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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
        id: 'model-thread-active',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      const badgeKey = ValueKey<String>('thread-active-session-thread-active');
      expect(find.byKey(badgeKey), findsNothing);

      final sendFuture = sessionController.sendMessage(
        content: 'Keep responding for a bit.',
        model: model,
        runtimeContext: runtimeContext,
      );
      await tester.pump(const Duration(milliseconds: 24));

      expect(find.byKey(badgeKey), findsOneWidget);

      for (var index = 0; index < 18; index++) {
        await tester.pump(const Duration(milliseconds: 24));
      }
      expect(await sendFuture, isTrue);
      await tester.pump(const Duration(milliseconds: 24));

      expect(find.byKey(badgeKey), findsNothing);
    },
  );

  testWidgets(
    'OpenHandHomePage windows long transcripts and loads older messages on demand',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-windowed-transcript']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 31, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = List<AiSessionMessage>.generate(180, (index) {
        return AiSessionMessage.assistant(
          id: 'message-window-$index',
          content: 'Windowed transcript message $index',
          createdAt: DateTime.utc(2026, 3, 25, 3, 31, index),
          modelLabel: 'gpt-test',
        );
      });
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 34, 0),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('Windowed transcript message 100'), findsOneWidget);
      expect(find.text('Windowed transcript message 0'), findsNothing);

      final transcriptFinder = find.byKey(
        const ValueKey<String>('session-transcript-list'),
      );
      final transcriptController = tester
          .widget<ListView>(transcriptFinder)
          .controller!;
      transcriptController.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Load earlier messages (100)'), findsOneWidget);
      await tester.tap(find.text('Load earlier messages (100)'));
      await tester.pump(const Duration(milliseconds: 300));
      transcriptController.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Windowed transcript message 0'), findsNothing);
      expect(find.text('Load earlier messages (20)'), findsOneWidget);

      await tester.tap(find.text('Load earlier messages (20)'));
      await tester.pump(const Duration(milliseconds: 300));
      transcriptController.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Windowed transcript message 0'), findsOneWidget);
      expect(find.textContaining('Load earlier messages'), findsNothing);
    },
  );

  testWidgets(
    'OpenHandHomePage shows a loading placeholder before mounting a long transcript',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-placeholder-short',
          'session-placeholder-long',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 36, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final shortSession = sessionController.currentSession!;

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final longSession = sessionController.currentSession!;

      final shortMessages = <AiSessionMessage>[
        AiSessionMessage.assistant(
          id: 'message-placeholder-short',
          content: 'Short transcript message',
          createdAt: DateTime.utc(2026, 3, 25, 3, 36, 1),
          modelLabel: 'gpt-test',
        ),
      ];
      final longMessages = List<AiSessionMessage>.generate(180, (index) {
        return AiSessionMessage.assistant(
          id: 'message-placeholder-long-$index',
          content: 'Placeholder transcript message $index',
          createdAt: DateTime.utc(2026, 3, 25, 3, 37, index),
          modelLabel: 'gpt-test',
        );
      });
      await sessionStore.save(
        shortSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 36, 1),
          messages: shortMessages,
          statistics: AiSessionStatistics.fromMessages(
            shortMessages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionStore.save(
        longSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 40, 0),
          messages: longMessages,
          statistics: AiSessionStatistics.fromMessages(
            longMessages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(shortSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('Short transcript message'), findsOneWidget);

      await sessionController.selectSession(longSession.id);
      await tester.pump();

      expect(
        find.byKey(
          ValueKey<String>('session-transcript-loading-${longSession.id}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-transcript-list')),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 80));

      expect(
        find.byKey(
          ValueKey<String>('session-transcript-loading-${longSession.id}'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('session-transcript-list')),
        findsOneWidget,
      );
      expect(find.text('Placeholder transcript message 100'), findsOneWidget);
    },
  );

  testWidgets(
    'OpenHandHomePage does not select a message when dragging the transcript',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-drag-selection']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 40, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = List<AiSessionMessage>.generate(36, (index) {
        return AiSessionMessage.assistant(
          id: 'message-drag-$index',
          content: 'Plain transcript message $index',
          createdAt: DateTime.utc(2026, 3, 25, 3, 40, index),
          modelLabel: 'gpt-test',
        );
      });
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 42, 0),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      final transcriptFinder = find.byKey(
        const ValueKey<String>('session-transcript-list'),
      );
      await tester.drag(transcriptFinder, const Offset(0, 180));
      await tester.pump();

      expect(find.text('Copy'), findsNothing);

      await tester.tap(find.textContaining('Plain transcript message').first);
      await tester.pump();

      expect(find.text('Copy'), findsOneWidget);
    },
  );

  testWidgets(
    'OpenHandHomePage keeps running tool calls expanded and streams their visible output',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-running-tool']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 0, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-running-tool',
          content: 'Run the test suite',
          createdAt: DateTime.utc(2026, 3, 25, 3, 0, 0),
        ),
        AiSessionMessage.toolCall(
          id: 'message-tool-call-running',
          content: '**Bash**',
          createdAt: DateTime.utc(2026, 3, 25, 3, 0, 1),
          metadata: <String, Object?>{
            'tool_call_id': 'tool-call-running',
            'tool_name': 'Bash',
            'tool_arguments':
                '{"cmd":"flutter test","working_directory":"/tmp/demo"}',
            'tool_execution_status': 'running',
            'tool_execution_command': 'flutter test',
            'tool_execution_working_directory': '/tmp/demo',
            'tool_execution_stdout': '00:00 +1',
            'tool_execution_elapsed_ms': 1200,
          },
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 0, 1),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('Bash'), findsWidgets);
      expect(find.textContaining('Bash · Running'), findsOneWidget);
      expect(find.text('Tool Input'), findsOneWidget);
      expect(find.text('Tool Output'), findsOneWidget);
      expect(_findTextSpanWidgetContaining(r'$ flutter test'), findsOneWidget);
      expect(
        _findTextSpanWidgetContaining('"working_directory": "/tmp/demo"'),
        findsOneWidget,
      );
      expect(find.text('stdout'), findsOneWidget);
      expect(_findTextSpanWidgetContaining('00:00 +1'), findsOneWidget);
    },
  );

  testWidgets(
    'OpenHandHomePage collapses completed tool calls by default and reveals arguments on demand',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-completed-tool']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 10, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-completed-tool',
          content: 'Check diagnostics',
          createdAt: DateTime.utc(2026, 3, 25, 3, 10, 0),
        ),
        AiSessionMessage.toolCall(
          id: 'message-tool-call-completed',
          content: '**mcp__ide__getDiagnostics**',
          createdAt: DateTime.utc(2026, 3, 25, 3, 10, 1),
          metadata: <String, Object?>{
            'tool_call_id': 'tool-call-completed',
            'tool_name': 'mcp__ide__getDiagnostics',
            'tool_arguments': '{"uri":"file:///workspace/lib/main.dart"}',
            'tool_source': 'mcp',
            'mcp_server_name': 'ide',
            'mcp_tool_id': 'getDiagnostics',
            'mcp_tool_name': 'Get Diagnostics',
            'tool_execution_status': 'success',
            'tool_execution_stdout':
                'is_error: false\ncontent:\nNo diagnostics',
            'tool_execution_result':
                'is_error: false\ncontent:\nNo diagnostics',
            'tool_execution_elapsed_ms': 800,
          },
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 10, 1),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('MCP: ide / Get Diagnostics'), findsOneWidget);
      expect(
        find.textContaining('ide / Get Diagnostics · Completed'),
        findsOneWidget,
      );
      expect(find.text('Tool Input'), findsOneWidget);
      expect(find.text('Tool Output'), findsOneWidget);
      expect(
        _findTextSpanWidgetContaining(
          '"uri": "file:///workspace/lib/main.dart"',
        ),
        findsNothing,
      );
      expect(find.textContaining('stdout · No diagnostics'), findsOneWidget);

      await tester.tap(find.text('Tool Input'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _findTextSpanWidgetContaining(
          '"uri": "file:///workspace/lib/main.dart"',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'OpenHandHomePage shows a localized safety-stop banner for tool loop errors',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-tool-loop-error',
          'error-tool-loop',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 3, 20, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.simplifiedChinese);
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-tool-loop',
          content: '分析账单',
          createdAt: DateTime.utc(2026, 3, 25, 3, 20, 0),
        ),
        AiSessionMessage.toolCall(
          id: 'message-tool-call-tool-loop',
          content: '**TodoWrite**',
          createdAt: DateTime.utc(2026, 3, 25, 3, 20, 1),
          metadata: <String, Object?>{
            'tool_call_id': 'tool-call-tool-loop',
            'tool_name': 'TodoWrite',
            'tool_arguments':
                '{"todos":[{"id":"1","content":"执行分析","status":"in_progress"}]}',
            'tool_execution_status': 'failed',
            'tool_execution_result':
                'status: failed\ndetail: The tool call was stopped because the assistant exceeded the sequential tool round safety limit.',
          },
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 20, 1),
          messages: messages,
          recentErrors: <AiSessionErrorRecord>[
            AiSessionErrorRecord(
              id: 'error-tool-loop',
              createdAt: DateTime.utc(2026, 3, 25, 3, 20, 2),
              stage: 'tool_loop',
              message:
                  'The assistant requested too many sequential tool rounds and was stopped for safety.',
              detail: 'tool_round_count=9 limit=8',
            ),
          ],
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('工具调用已安全停止'), findsOneWidget);
      expect(find.textContaining('本次会话连续触发了过多轮工具调用'), findsOneWidget);
      expect(
        find.text(
          'The assistant requested too many sequential tool rounds and was stopped for safety.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'OpenHandHomePage dismisses a visible session error banner and keeps it hidden after rebuild',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-error-dismiss-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-error-dismiss',
          'error-dismiss-banner',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 4, 0, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.simplifiedChinese);
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-error-dismiss-user',
          content: 'Show the warning banner',
          createdAt: DateTime.utc(2026, 3, 25, 4, 0, 0),
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 4, 0, 1),
          messages: messages,
          recentErrors: <AiSessionErrorRecord>[
            AiSessionErrorRecord(
              id: 'error-dismiss-banner',
              createdAt: DateTime.utc(2026, 3, 25, 4, 0, 1),
              stage: 'tool_loop',
              message:
                  'The assistant requested too many sequential tool rounds.',
              detail: 'tool_round_count=9 limit=8',
            ),
          ],
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('工具调用已安全停止'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('session-error-dismiss-error-dismiss-banner'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('工具调用已安全停止'), findsNothing);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('工具调用已安全停止'), findsNothing);
    },
  );

  testWidgets(
    'OpenHandHomePage applies workspace shortcuts for model and session actions',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-shortcut-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionController = await AiSessionController.create(
        store: _InMemoryAiSessionStore(),
        chatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Shortcut reply'),
          ],
        ),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
          autoTitleResponses: const <AiChatCompletion>[
            AiChatCompletion(reply: 'Shortcut Thread'),
          ],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>[
          'session-shortcut-a',
          'session-shortcut-b',
          'message-shortcut-user',
          'message-shortcut-assistant',
        ]),
        clock: () => DateTime.utc(2026, 3, 25, 4, 30, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
      const modelA = AiModelConfig(
        id: 'model-shortcut-a',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-shortcut-a',
        protocolType: AiProtocolType.openai,
      );
      const modelB = AiModelConfig(
        id: 'model-shortcut-b',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-shortcut-b',
        protocolType: AiProtocolType.openai,
      );
      expect(await settingsController.saveAiModel(modelA), isTrue);
      expect(await settingsController.saveAiModel(modelB), isTrue);
      expect(await settingsController.updateSelectedAiModel(modelA.id), isTrue);

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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionAId = sessionController.currentSessionId!;
      expect(
        await sessionController.renameSession(sessionAId, 'Thread A'),
        isTrue,
      );

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );
      final sessionBId = sessionController.currentSessionId!;
      expect(
        await sessionController.renameSession(sessionBId, 'Thread B'),
        isTrue,
      );

      final sessions = sessionController.sessions;
      final currentIndex = sessions.indexWhere(
        (session) => session.id == sessionController.currentSessionId,
      );
      final expectedNextSession =
          sessions[(currentIndex + 1) % sessions.length];

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text(modelA.displayName), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 250));

      expect(settingsController.selectedAiModelId, modelB.id);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 250));

      expect(sessionController.currentSessionId, expectedNextSession.id);
    },
  );

  testWidgets(
    'OpenHandHomePage formats compact structured tool output before rendering',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-formatted-tool']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 15, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-formatted-tool',
          content: 'Inspect the response payload',
          createdAt: DateTime.utc(2026, 3, 25, 3, 15, 0),
        ),
        AiSessionMessage.toolCall(
          id: 'message-tool-call-formatted',
          content: '**Bash**',
          createdAt: DateTime.utc(2026, 3, 25, 3, 15, 1),
          metadata: <String, Object?>{
            'tool_call_id': 'tool-call-formatted',
            'tool_name': 'Bash',
            'tool_arguments': '{"cmd":"cat response.json"}',
            'tool_execution_status': 'success',
            'tool_execution_stdout':
                '{"service":"openhand","metrics":{"latency_ms":12,"healthy":true}}',
            'tool_execution_elapsed_ms': 640,
          },
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 15, 1),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      await tester.tap(find.text('Tool Output'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('json'), findsOneWidget);
      expect(
        _findTextSpanWidgetContaining('"service": "openhand"'),
        findsOneWidget,
      );
      expect(_findTextSpanWidgetContaining('"latency_ms": 12'), findsOneWidget);
      expect(_findTextSpanWidgetContaining('"healthy": true'), findsOneWidget);
    },
  );

  testWidgets(
    'OpenHandHomePage uses multiple syntax colors for markdown code blocks in dark mode',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-dark-code-block']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 18, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
      await settingsController.updateThemeMode(ThemeMode.dark);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-dark-code-block',
          content: 'Show me a Dart example',
          createdAt: DateTime.utc(2026, 3, 25, 3, 18, 0),
        ),
        AiSessionMessage.assistant(
          id: 'message-assistant-dark-code-block',
          content: '```dart\nfinal name = "OpenHand";\nconst retries = 3;\n```',
          createdAt: DateTime.utc(2026, 3, 25, 3, 18, 1),
          modelLabel: 'gpt-test',
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 18, 1),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      final codeFinder = _findTextSpanWidgetContaining('final name');
      expect(codeFinder, findsOneWidget);
      final codeWidget = tester.widget(codeFinder);
      final colors = <Color>{};
      _collectRenderedTextSpanColors(_textSpanForWidget(codeWidget), colors);

      expect(colors.length, greaterThan(1));

      final languageFinder = find.text('dart');
      final copyFinder = find.text('Copy');
      expect(languageFinder, findsOneWidget);
      expect(copyFinder, findsOneWidget);

      final languageTopLeft = tester.getTopLeft(languageFinder);
      final copyTopLeft = tester.getTopLeft(copyFinder);
      expect(languageTopLeft.dx, lessThan(copyTopLeft.dx));
      expect((languageTopLeft.dy - copyTopLeft.dy).abs(), lessThan(12));

      await tester.tap(copyFinder);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Code copied.'), findsOneWidget);
    },
  );

  testWidgets(
    'OpenHandHomePage keeps markdown blockquotes readable in dark and light themes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-blockquote-theme']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 19, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-blockquote-theme',
          content: 'Show me a readable blockquote',
          createdAt: DateTime.utc(2026, 3, 25, 3, 19, 0),
        ),
        AiSessionMessage.assistant(
          id: 'message-assistant-blockquote-theme',
          content:
              '> Important note: this markdown blockquote should stay readable in every theme.',
          createdAt: DateTime.utc(2026, 3, 25, 3, 19, 1),
          modelLabel: 'gpt-test',
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 19, 1),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      Future<void> assertReadableQuote(ThemeMode themeMode) async {
        await settingsController.updateThemeMode(themeMode);
        await _pumpHomePage(
          tester,
          settingsController: settingsController,
          sessionController: sessionController,
          memoryController: memoryController,
          skillsController: skillsController,
          mcpController: mcpController,
        );

        final quoteFinder = _findTextSpanWidgetContaining(
          'Important note: this markdown blockquote should stay readable in every theme.',
        );
        expect(quoteFinder, findsOneWidget);

        final quoteWidget = tester.widget(quoteFinder);
        final colors = <Color>{};
        _collectRenderedTextSpanColors(_textSpanForWidget(quoteWidget), colors);
        expect(colors, isNotEmpty);

        final quoteElement = quoteFinder.evaluate().single;
        final quoteDecoration = _nearestBoxDecoration(quoteElement);
        expect(quoteDecoration, isNotNull);
        final quoteBackground = quoteDecoration!.color;
        expect(quoteBackground, isNotNull);

        final leftBorder = quoteDecoration.border;
        expect(leftBorder, isA<Border>());
        expect((leftBorder as Border).left.width, greaterThanOrEqualTo(3));

        final textColor = colors.first;
        expect(_contrastRatio(textColor, quoteBackground!), greaterThan(4.5));
      }

      await assertReadableQuote(ThemeMode.dark);
      await assertReadableQuote(ThemeMode.light);
    },
  );

  testWidgets(
    'OpenHandHomePage renders streaming reasoning code fences with highlight on dark surfaces',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final memoryStore = _InMemoryMemoryStore();
      final memoryController = await MemoryController.create(
        initialFilePath: memoryStore.userMemoryFilePath,
        store: memoryStore,
      );
      final skillsController = await SkillsController.create(
        initialStoragePath: '/tmp/openhand-home-page-test-skills',
        repository: _InMemorySkillsRepository(),
      );
      final mcpStore = _InMemoryMcpStore();
      final mcpController = await McpController.create(
        initialFilePath: mcpStore.serversFilePath,
        store: mcpStore,
      );
      final sessionStore = _InMemoryAiSessionStore();
      final sessionController = await AiSessionController.create(
        store: sessionStore,
        chatClient: _QueuedChatClient(responses: const <AiChatCompletion>[]),
        backgroundChatClient: _QueuedChatClient(
          responses: const <AiChatCompletion>[],
        ),
        templateRepository: AiPromptTemplateRepository(
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
        ),
        idGenerator: _fixedIdGenerator(<String>['session-streaming-reasoning']),
        clock: () => DateTime.utc(2026, 3, 25, 3, 20, 0),
      );
      addTearDown(settingsController.dispose);
      addTearDown(memoryController.dispose);
      addTearDown(skillsController.dispose);
      addTearDown(mcpController.dispose);
      addTearDown(sessionController.dispose);

      await settingsController.updateLanguage(AppLanguage.english);
      await settingsController.updateThemeMode(ThemeMode.light);
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

      expect(
        await sessionController.createSession(
          templateId: 'default',
          runtimeContext: runtimeContext,
        ),
        isTrue,
      );

      final baseSession = sessionController.currentSession!;
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'message-user-streaming-reasoning',
          content: 'Show me how merge sort works',
          createdAt: DateTime.utc(2026, 3, 25, 3, 20, 0),
        ),
        AiSessionMessage.reasoning(
          id: 'message-reasoning-streaming-code',
          content:
              'Let me reason it out first.\n```kotlin\nfun mergeSort(list: List<Int>): List<Int> {\n  return list\n}\n',
          createdAt: DateTime.utc(2026, 3, 25, 3, 20, 1),
          modelLabel: 'deepseek-reasoner',
          metadata: const <String, Object?>{
            aiSessionMessageMetadataStreamingKey: true,
          },
        ),
      ];
      await sessionStore.save(
        baseSession.copyWith(
          updatedAt: DateTime.utc(2026, 3, 25, 3, 20, 1),
          messages: messages,
          statistics: AiSessionStatistics.fromMessages(
            messages,
            totalPromptCharacters: 0,
            promptBuildCount: 0,
            compressionRunCount: 0,
            totalUsage: const AiTokenUsage(),
            lastPromptSystemMessageCount: 0,
            lastPromptHistoryMessageCount: 0,
          ),
        ),
      );
      await sessionController.refresh();
      await sessionController.selectSession(baseSession.id);

      await _pumpHomePage(
        tester,
        settingsController: settingsController,
        sessionController: sessionController,
        memoryController: memoryController,
        skillsController: skillsController,
        mcpController: mcpController,
      );

      expect(find.text('kotlin'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.textContaining('```'), findsNothing);

      final codeFinder = _findTextSpanWidgetContaining('fun mergeSort');
      expect(codeFinder, findsOneWidget);
      final codeWidget = tester.widget(codeFinder);
      final colors = <Color>{};
      _collectRenderedTextSpanColors(_textSpanForWidget(codeWidget), colors);
      expect(colors.length, greaterThan(1));

      final codeElement = codeFinder.evaluate().single;
      final codePanelBodyColor = _nearestDecoratedBoxColor(codeElement);
      expect(codePanelBodyColor, isNotNull);
      expect(codePanelBodyColor!.computeLuminance(), lessThan(0.1));
    },
  );
}

class _InMemorySettingsStore extends SettingsStore {
  _InMemorySettingsStore() : super(settingsFilePath: '/tmp/openhand-test.toml');

  AppSettingsSnapshot _snapshot = AppSettingsSnapshot.defaults();

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class _InMemoryAiSessionStore extends AiSessionStore {
  _InMemoryAiSessionStore()
    : super(sessionsDirectoryPath: '/tmp/openhand-home-page-test');

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

class _DelayedFailingUserMessageSessionStore extends _InMemoryAiSessionStore {
  static const Duration _delay = Duration(milliseconds: 180);

  @override
  Future<void> save(AiSession session) async {
    if (session.messages.isNotEmpty) {
      await Future<void>.delayed(_delay);
      throw StateError('Injected session save failure');
    }
    await super.save(session);
  }
}

class _InMemoryMemoryStore extends MemoryStore {
  _InMemoryMemoryStore()
    : super(userMemoryFilePath: '/tmp/openhand-memory.json');

  List<UserMemoryEntry> _entries = const <UserMemoryEntry>[];

  @override
  Future<MemoryLoadResult> load() async {
    return MemoryLoadResult(entries: _entries);
  }

  @override
  Future<void> save(List<UserMemoryEntry> entries) async {
    _entries = List<UserMemoryEntry>.from(entries);
  }
}

class _InMemorySkillsRepository extends SkillsRepository {
  @override
  Future<List<LocalSkill>> loadInstalledSkills(String storagePath) async {
    return const <LocalSkill>[];
  }
}

class _InMemoryMcpStore extends McpStore {
  _InMemoryMcpStore() : super(serversFilePath: '/tmp/openhand-mcp.json');

  List<McpServer> _servers = const <McpServer>[];

  @override
  Future<McpLoadResult> load() async {
    return McpLoadResult(servers: _servers);
  }

  @override
  Future<void> save(List<McpServer> servers) async {
    _servers = List<McpServer>.from(servers);
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

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
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

class _StepStreamingChatClient implements AiChatClient {
  _StepStreamingChatClient({required List<String> replyChunks})
    : _replyChunks = List<String>.from(replyChunks);

  final List<String> _replyChunks;
  static const Duration _chunkDelay = Duration(milliseconds: 18);

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return AiChatCompletion(reply: _replyChunks.join());
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final streamController = StreamController<AiChatStreamEvent>();
    unawaited(() async {
      for (final chunk in _replyChunks) {
        streamController.add(AiChatStreamEvent.textDelta(chunk));
        await Future<void>.delayed(_chunkDelay);
      }
      await streamController.close();
    }());
    return AiChatStreamingResponse(
      events: streamController.stream,
      result: () async {
        await streamController.done;
        return AiChatStreamResult(
          reply: _replyChunks.join(),
          reasoning: '',
          toolCalls: const <AiToolCall>[],
          usage: null,
          rawResponse: null,
        );
      }(),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'OK';
  }

  @override
  void dispose() {}
}

String Function() _fixedIdGenerator(List<String> ids) {
  final pendingIds = List<String>.from(ids);
  return () => pendingIds.removeAt(0);
}

Future<void> _pumpHomePage(
  WidgetTester tester, {
  required SettingsController settingsController,
  required AiSessionController sessionController,
  required MemoryController memoryController,
  required SkillsController skillsController,
  required McpController mcpController,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppInfo>.value(value: AppInfo.fallback()),
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<AiSessionController>.value(
          value: sessionController,
        ),
        ChangeNotifierProvider<MemoryController>.value(value: memoryController),
        ChangeNotifierProvider<SkillsController>.value(value: skillsController),
        ChangeNotifierProvider<McpController>.value(value: mcpController),
      ],
      child: MaterialApp(
        locale: settingsController.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        themeMode: settingsController.themeMode,
        theme: OpenHandTheme.light(OpenHandThemePreset.deepSeaBlue),
        darkTheme: OpenHandTheme.dark(OpenHandThemePreset.deepSeaBlue),
        home: const Scaffold(body: OpenHandHomePage()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void _collectRenderedTextSpanColors(
  InlineSpan span,
  Set<Color> colors, {
  TextStyle? inheritedStyle,
}) {
  if (span is! TextSpan) {
    return;
  }
  final mergedStyle = inheritedStyle?.merge(span.style) ?? span.style;
  if ((span.text ?? '').isNotEmpty) {
    final color = mergedStyle?.color;
    if (color != null) {
      colors.add(color);
    }
  }
  final children = span.children;
  if (children == null || children.isEmpty) {
    return;
  }
  for (final child in children) {
    _collectRenderedTextSpanColors(child, colors, inheritedStyle: mergedStyle);
  }
}

Finder _findTextSpanWidgetContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is SelectableText && widget.textSpan != null) {
      return widget.textSpan!.toPlainText().contains(text);
    }
    if (widget is RichText) {
      return widget.text.toPlainText().contains(text);
    }
    return false;
  });
}

InlineSpan _textSpanForWidget(Widget widget) {
  if (widget is SelectableText && widget.textSpan != null) {
    return widget.textSpan!;
  }
  if (widget is RichText) {
    return widget.text;
  }
  throw ArgumentError('Unsupported text span widget: ${widget.runtimeType}');
}

Color? _nearestDecoratedBoxColor(Element element) {
  return _nearestBoxDecoration(element)?.color;
}

BoxDecoration? _nearestBoxDecoration(Element element) {
  BoxDecoration? decoration;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      decoration = widget.decoration as BoxDecoration;
      return false;
    }
    return true;
  });
  return decoration;
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
