import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/home/index.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  group('Grok multi-turn cache continuity', () {
    test('all templates inherit one shared prompt baseline', () {
      const baselineTags = <String>[
        'identity',
        'refusal_handling',
        'tone_and_formatting',
        'workflow',
      ];

      for (final entry in AiPromptTemplatePolicies.entries) {
        expect(
          entry.policy.sharedSections
              .map((section) => section.tag)
              .take(baselineTags.length),
          baselineTags,
          reason: '${entry.id} must inherit the unified prompt baseline.',
        );
      }
    });

    test('reasoning echo capability covers native and compatible gateways', () {
      for (final model in <AiModelConfig>[
        _grokModel(AiProtocolType.grok, 'https://api.x.ai'),
        _grokModel(AiProtocolType.openai, 'http://127.0.0.1:8317'),
      ]) {
        expect(model.resolvedThinkingEnabled, isTrue);
        expect(model.requiresReasoningEcho, isTrue);
      }
    });

    test('every thread template echoes prior Grok reasoning uniformly', () {
      const builder = AiPromptBuilder();
      final model = _grokModel(AiProtocolType.openai, 'http://127.0.0.1:8317');
      final layouts = <Object?>{};

      for (final entry in AiPromptTemplatePolicies.entries) {
        final messages = _conversationMessages();
        final result = builder.buildConversationPrompt(
          templateBundle: _bundle(entry.info),
          session: _session(entry.info, messages),
          model: model,
          runtimeContext: _runtimeContext(entry.id),
          memoryEntries: const [],
          historyMessages: messages.take(3).toList(growable: false),
          latestUserMessage: messages.last,
        );
        final assistant = result.messages.singleWhere(
          (turn) =>
              turn.role == AiChatRole.assistant &&
              turn.content == 'First answer.',
        );

        expect(
          assistant.reasoningContent,
          'encrypted-reasoning-content',
          reason: '${entry.id} must use the unified reasoning history policy.',
        );
        expect(result.metadata['reasoning_history_echo_required'], isTrue);
        expect(result.metadata['reasoning_history_source_count'], 1);
        expect(result.metadata['reasoning_history_echo_turn_count'], 1);
        expect(result.metadata['reasoning_history_echo_complete'], isTrue);
        layouts.add(result.metadata['prompt_assembly_layout']);
      }

      expect(layouts, <Object?>{
        'stable_prefix.runtime_prefix.history.latest_user.volatile_tail.v1',
      });
    });

    test('OpenAI-compatible request retains reasoning_content', () async {
      final request = await const OpenAiProtocolAdapter(AiProtocolType.openai)
          .buildChatRequest(
            model: _grokModel(AiProtocolType.openai, 'http://127.0.0.1:8317'),
            messages: const <AiChatTurn>[
              AiChatTurn(role: AiChatRole.system, content: 'Stable system.'),
              AiChatTurn(role: AiChatRole.user, content: 'First question.'),
              AiChatTurn(
                role: AiChatRole.assistant,
                content: 'First answer.',
                reasoningContent: 'encrypted-reasoning-content',
              ),
              AiChatTurn(role: AiChatRole.user, content: 'Second question.'),
            ],
            inputCacheConfig: const AiInputCacheRuntimeConfig(
              enabled: true,
              mode: 'allMessages',
              updateInterval: 10,
              breakpointCount: 4,
              cacheAffinityId: 'session-1',
              promptCacheKey: 'stable-key-1',
            ),
          );
      final messages = (request.body['messages'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final assistant = messages.singleWhere(
        (message) => message['role'] == 'assistant',
      );

      expect(assistant['reasoning_content'], 'encrypted-reasoning-content');
      expect(
        request.headers[AiPromptCacheAffinity.grokConversationHeader],
        'session-1',
      );
      expect(
        request.headers[AiPromptCacheAffinity.standardSessionAffinityHeader],
        'session-1',
      );
    });

    testWidgets('cache trend mode chips stay inline without first-round hint', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 380,
              child: TokenPopupCacheHitTrendChart(
                trend: SessionCacheHitTrend(
                  points: List<SessionCacheHitTurnPoint>.generate(
                    6,
                    _cacheHitPoint,
                    growable: false,
                  ),
                  averageHitRatio: 0,
                  claudeStyle: false,
                ),
                displayMode: SessionCacheHitDisplayMode.includeExpiredMisses,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final excludeChip = find.text('不含过期异常');
      final includeChip = find.text('含过期异常');
      expect(excludeChip, findsOneWidget);
      expect(includeChip, findsOneWidget);
      expect(
        tester.getTopLeft(excludeChip).dy,
        tester.getTopLeft(includeChip).dy,
      );
      expect(find.text('首轮不计平均'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

SessionCacheHitTurnPoint _cacheHitPoint(int index) {
  return SessionCacheHitTurnPoint(
    turnIndex: index + 1,
    starterMessageId: 'user-$index',
    starterMessageKind: 'user',
    starterOrigin: 'user',
    timestamp: DateTime.utc(2026, 7, 11, 12, index),
    hitRatio: 0,
    averageHitRatio: 0,
    promptTokens: 100,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    idleGapSeconds: index == 0 ? null : 10,
    ttlSuspected: false,
    prefixDriftSuspected: false,
    automaticProviderMissSuspected: index > 0,
  );
}

AiModelConfig _grokModel(AiProtocolType protocol, String baseUrl) {
  return AiModelConfig(
    id: 'grok-provider',
    baseUrl: baseUrl,
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'grok-4.5',
    protocolType: protocol,
  );
}

List<AiSessionMessage> _conversationMessages() {
  final now = DateTime.utc(2026, 7, 11, 12);
  return <AiSessionMessage>[
    AiSessionMessage.user(
      id: 'user-1',
      content: 'First question.',
      createdAt: now,
    ),
    AiSessionMessage.reasoning(
      id: 'reasoning-1',
      content: 'encrypted-reasoning-content',
      createdAt: now,
    ),
    AiSessionMessage.assistant(
      id: 'assistant-1',
      content: 'First answer.',
      createdAt: now,
    ),
    AiSessionMessage.user(
      id: 'user-2',
      content: 'Second question.',
      createdAt: now,
    ),
  ];
}

AiPromptTemplateBundle _bundle(AiPromptTemplateInfo info) {
  return AiPromptTemplateBundle(
    template: AiThreadTemplate(
      id: info.id,
      name: info.name,
      iconName: info.iconName,
      description: info.description,
      internalVersion: info.internalVersion,
      promptAssetDirectory: info.promptAssetDirectory,
    ),
    systemInstructions: 'Stable system instructions.',
    developerInstructions: 'Stable developer instructions.',
    compressionSummaryInstructions: 'Stable compression instructions.',
  );
}

AiSession _session(AiPromptTemplateInfo info, List<AiSessionMessage> messages) {
  final now = DateTime.utc(2026, 7, 11, 12);
  return AiSession(
    id: 'session-${info.id}',
    title: 'Cache regression',
    templateId: info.id,
    templateName: info.name,
    templateIconName: info.iconName,
    templateInternalVersion: info.internalVersion,
    createdAt: now,
    updatedAt: now,
    messages: messages,
    environment: AiSessionEnvironment(
      localeTag: 'zh-CN',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/app',
      homeDirectory: '/home',
      settingsFilePath: '/settings.json',
      skillsStoragePath: '/skills',
      mcpServersFilePath: '/mcp.json',
      userMemoryFilePath: '/memory.json',
      sessionsDirectoryPath: '/sessions',
      compressionThresholdChars: 1000000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
  );
}

AiSessionRuntimeContext _runtimeContext(String templateId) {
  return AiSessionRuntimeContext(
    localeTag: 'zh-CN',
    appVersion: '0.1.0',
    appBuildNumber: '1',
    settingsFilePath: '/settings.json',
    skillsStoragePath: '/skills',
    mcpServersFilePath: '/mcp.json',
    userMemoryFilePath: '/memory.json',
    compressionThresholdChars: 1000000,
    memoryEnabled: false,
    memoryEntries: const [],
    templateId: templateId,
    platformName: 'macos',
    workingDirectory: '/workspace',
    timeZoneName: 'CST',
  );
}
