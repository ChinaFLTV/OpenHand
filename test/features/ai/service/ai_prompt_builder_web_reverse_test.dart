import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  test(
    'includes Web Reverse CDP runtime and current target in prompt state',
    () {
      final now = DateTime.utc(2026, 5, 19);
      final latestUserMessage = AiSessionMessage.user(
        id: 'user-1',
        content: 'Start reversing https://example.test',
        createdAt: now,
      );
      final session = AiSession(
        id: 'session-1',
        title: 'Web Reverse',
        templateId: 'web_reverse_expert',
        templateName: 'Web Reverse Expert',
        templateIconName: 'travel_explore_rounded',
        templateInternalVersion: '1.1.0',
        createdAt: now,
        updatedAt: now,
        messages: <AiSessionMessage>[latestUserMessage],
        environment: const AiSessionEnvironment(
          localeTag: 'zh-CN',
          platform: 'macos',
          appVersion: '0.1.0',
          appBuildNumber: '1',
          applicationDirectory: '/tmp/openhand',
          homeDirectory: '/tmp',
          settingsFilePath: '/tmp/openhand/settings.json',
          skillsStoragePath: '/tmp/openhand/skills',
          mcpServersFilePath: '/tmp/openhand/mcp_servers.json',
          userMemoryFilePath: '/tmp/openhand/memory.json',
          sessionsDirectoryPath: '/tmp/openhand/sessions',
          compressionThresholdChars: 100000,
        ),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
        metadata: const <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'target_url': 'https://example.test',
            'cdp_port': 9222,
          },
          'web_reverse_cdp_runtime': <String, Object?>{
            'cdp_port': 9233,
            'cdp_http_endpoint': 'http://127.0.0.1:9233',
            'json_list_url': 'http://127.0.0.1:9233/json/list',
            'browser_alive': true,
          },
          'web_reverse_browser_current_target': <String, Object?>{
            'id': 'target-1',
            'url': 'https://example.test/app',
            'title': 'Example App',
          },
        },
      );

      final result = const AiPromptBuilder().buildConversationPrompt(
        templateBundle: const AiPromptTemplateBundle(
          template: AiThreadTemplate(
            id: 'web_reverse_expert',
            name: 'Web Reverse Expert',
            iconName: 'travel_explore_rounded',
            description: 'Reverse a browser target through CDP.',
            internalVersion: '1.1.0',
            promptAssetDirectory: 'assets/prompts/web_reverse_expert',
          ),
          systemInstructions: 'system',
          developerInstructions: 'developer',
          compressionSummaryInstructions: 'compress',
        ),
        session: session,
        model: const AiModelConfig(
          id: 'test-model',
          baseUrl: 'http://localhost/v1',
          authScheme: AiAuthScheme.none,
          token: '',
          modelId: 'openhand-test-model',
          protocolType: AiProtocolType.openai,
        ),
        runtimeContext: const AiSessionRuntimeContext(
          localeTag: 'zh-CN',
          appVersion: '0.1.0',
          appBuildNumber: '1',
          settingsFilePath: '/tmp/openhand/settings.json',
          skillsStoragePath: '/tmp/openhand/skills',
          mcpServersFilePath: '/tmp/openhand/mcp_servers.json',
          userMemoryFilePath: '/tmp/openhand/memory.json',
          compressionThresholdChars: 100000,
          memoryEnabled: false,
          memoryEntries: <Never>[],
          templateId: 'web_reverse_expert',
          platformName: 'macos',
          workingDirectory: '/tmp/openhand',
          todayLocalDate: '2026-05-19',
          timeZoneName: 'UTC',
        ),
        memoryEntries: const <Never>[],
        historyMessages: const <AiSessionMessage>[],
        latestUserMessage: latestUserMessage,
      );

      final webReverseRuntime = result.metadata['web_reverse_runtime'];
      expect(webReverseRuntime, isA<Map<String, Object?>>());
      final runtimeMap = webReverseRuntime! as Map<String, Object?>;
      expect(runtimeMap['cdp_first_required'], true);
      expect(
        runtimeMap['dashboard_visible_metadata_keys'],
        containsAll(<String>[
          'web_reverse_browser_current_target',
          'web_reverse_cdp_runtime',
          'web_reverse_config',
        ]),
      );
      expect(
        runtimeMap['cdp_runtime'],
        containsPair('json_list_url', 'http://127.0.0.1:9233/json/list'),
      );
      expect(
        runtimeMap['dashboard_state'],
        containsPair(
          'browser_current_target',
          containsPair('url', 'https://example.test/app'),
        ),
      );

      final sessionStateText = result.messages
          .map((turn) => turn.content)
          .firstWhere((content) => content.contains('# [3] Session State'));
      expect(sessionStateText, contains('"cdp_runtime"'));
      expect(sessionStateText, contains('http://127.0.0.1:9233/json/list'));
      expect(sessionStateText, contains('"browser_current_target"'));

      final fullPromptText = result.messages
          .map((turn) => turn.content)
          .join('\n');
      expect(fullPromptText, isNot(contains('OpenHand CDP Bridge')));
      expect(fullPromptText, isNot(contains('CDP Bridge')));
    },
  );
}
