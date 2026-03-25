import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      expect(find.textContaining(r'$ flutter test'), findsOneWidget);
      expect(
        find.textContaining('"working_directory": "/tmp/demo"'),
        findsOneWidget,
      );
      expect(find.text('stdout'), findsOneWidget);
      expect(find.text('00:00 +1'), findsOneWidget);
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
        find.textContaining('"uri": "file:///workspace/lib/main.dart"'),
        findsNothing,
      );
      expect(find.textContaining('stdout · No diagnostics'), findsOneWidget);

      await tester.tap(find.text('Tool Input'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('"uri": "file:///workspace/lib/main.dart"'),
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
        theme: OpenHandTheme.light(OpenHandThemePreset.deepSeaBlue),
        home: const Scaffold(body: OpenHandHomePage()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}
