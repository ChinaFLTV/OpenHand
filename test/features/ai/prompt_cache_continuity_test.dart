import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/chat/ai_transport_diagnostic_messages.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/memory/index.dart';

void main() {
  group('unified prompt cache continuity', () {
    test('every template uses the same round-anchor assembly layout', () async {
      final layouts = <Object?>{};
      for (final entry in AiPromptTemplatePolicies.entries) {
        final user = _user('user-${entry.id}', 'Inspect the workspace.');
        final result = await const AiPromptBuilder().buildConversationPrompt(
          templateBundle: _bundle(entry.info),
          session: _session(entry.info, <AiSessionMessage>[user]),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(entry.id),
          memoryEntries: const <UserMemoryEntry>[],
          historyMessages: const <AiSessionMessage>[],
          latestUserMessage: user,
        );

        layouts.add(result.metadata['prompt_assembly_layout']);
        expect(
          result.metadata['runtime_tail_anchor_message_id'],
          user.id,
          reason: '${entry.id} must bind runtime context to its round anchor.',
        );
        expect(
          result.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
          isA<List<Object?>>(),
        );
      }

      expect(layouts, <Object?>{
        'stable_prefix.runtime_prefix.history.round_anchor_tail.v2',
      });
    });

    test(
      'persisted runtime tail makes the next request prefix-extending',
      () async {
        final info = AiPromptTemplatePolicies.resolveEntry(
          AiPromptTemplatePolicies.machineExpertTemplateId,
        ).info;
        final firstUser = _user('user-1', 'Inspect the machine.');
        const builder = AiPromptBuilder();
        final first = await builder.buildConversationPrompt(
          templateBundle: _bundle(info),
          session: _session(info, <AiSessionMessage>[firstUser]),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(info.id),
          memoryEntries: const <UserMemoryEntry>[],
          historyMessages: const <AiSessionMessage>[],
          latestUserMessage: firstUser,
        );
        final snapshot =
            first.metadata[aiPromptRuntimeTailSnapshotMetadataKey]
                as List<Object?>;
        final persistedFirstUser = firstUser.copyWith(
          metadata: <String, Object?>{
            ...firstUser.metadata,
            aiPromptRuntimeTailSnapshotMetadataKey: snapshot,
          },
        );
        final firstRetry = await builder.buildConversationPrompt(
          templateBundle: _bundle(info),
          session: _session(info, <AiSessionMessage>[persistedFirstUser]),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(info.id),
          memoryEntries: const <UserMemoryEntry>[],
          historyMessages: const <AiSessionMessage>[],
          latestUserMessage: persistedFirstUser,
        );
        expect(firstRetry.metadata['runtime_tail_snapshot_reused'], isTrue);
        expect(
          firstRetry.metadata['runtime_tail_replayed_from_history'],
          isFalse,
        );
        _expectTurnsEqual(first.messages, firstRetry.messages);
        await _expectRequestJsonEqual(first.messages, firstRetry.messages);

        final assistant = AiSessionMessage.assistant(
          id: 'assistant-1',
          content: 'Working on it.',
          createdAt: _now.add(const Duration(seconds: 1)),
        );
        final secondUser = _user('user-2', 'Continue.');
        final secondHistory = <AiSessionMessage>[persistedFirstUser, assistant];
        final secondMessages = <AiSessionMessage>[...secondHistory, secondUser];
        final second = await builder.buildConversationPrompt(
          templateBundle: _bundle(info),
          session: _session(info, secondMessages),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(info.id),
          memoryEntries: const <UserMemoryEntry>[],
          historyMessages: secondHistory,
          latestUserMessage: secondUser,
        );

        expect(second.messages.length, greaterThan(first.messages.length));
        for (var index = 0; index < first.messages.length; index += 1) {
          expect(
            _turnSignature(second.messages[index]),
            _turnSignature(first.messages[index]),
            reason: 'request prefix drifted at turn $index',
          );
        }
      },
    );

    test(
      'tool continuations replay the previous round tail in place',
      () async {
        final info = AiPromptTemplatePolicies.resolveEntry(
          AiPromptTemplatePolicies.machineExpertTemplateId,
        ).info;
        const builder = AiPromptBuilder();
        final firstUser = _user('tool-user-1', 'Inspect the machine.');
        final first = await builder.buildConversationPrompt(
          templateBundle: _bundle(info),
          session: _session(info, <AiSessionMessage>[firstUser]),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(info.id),
          memoryEntries: const <UserMemoryEntry>[],
          historyMessages: const <AiSessionMessage>[],
          latestUserMessage: firstUser,
        );
        final persistedFirstUser = firstUser.copyWith(
          metadata: <String, Object?>{
            ...firstUser.metadata,
            aiPromptRuntimeTailSnapshotMetadataKey:
                first.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
          },
        );
        final toolCall = AiSessionMessage.toolCall(
          id: 'tool-call-message-1',
          content: 'Tool call: Read',
          createdAt: _now.add(const Duration(seconds: 1)),
          metadata: const <String, Object?>{
            'tool_calls': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'call-1',
                'name': 'Read',
                'arguments': '{"file_path":"/tmp/a"}',
              },
            ],
          },
        );
        final toolResult = AiSessionMessage.toolResult(
          id: 'tool-result-1',
          content: 'file contents',
          createdAt: _now.add(const Duration(seconds: 2)),
          metadata: const <String, Object?>{
            'tool_call_id': 'call-1',
            'tool_name': 'Read',
            'status': 'success',
          },
        );
        final secondMessages = <AiSessionMessage>[
          persistedFirstUser,
          toolCall,
          toolResult,
        ];
        final second = await builder.buildSessionPrompt(
          templateBundle: _bundle(info),
          session: _session(info, secondMessages),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(info.id),
          memoryEntries: const <UserMemoryEntry>[],
          sessionMessages: secondMessages,
          runtimeContextAnchorMessageId: toolResult.id,
        );
        _expectTurnPrefix(first.messages, second.messages);
        await _expectRequestJsonPrefix(first.messages, second.messages);

        final persistedToolResult = toolResult.copyWith(
          metadata: <String, Object?>{
            ...toolResult.metadata,
            aiPromptRuntimeTailSnapshotMetadataKey:
                second.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
          },
        );
        final retryMessages = <AiSessionMessage>[
          persistedFirstUser,
          toolCall,
          persistedToolResult,
        ];
        final secondRetry = await builder.buildSessionPrompt(
          templateBundle: _bundle(info),
          session: _session(info, retryMessages),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(info.id),
          memoryEntries: const <UserMemoryEntry>[],
          sessionMessages: retryMessages,
          runtimeContextAnchorMessageId: persistedToolResult.id,
        );
        expect(secondRetry.metadata['runtime_tail_snapshot_reused'], isTrue);
        expect(
          secondRetry.metadata['runtime_tail_replayed_from_history'],
          isTrue,
        );
        _expectTurnsEqual(second.messages, secondRetry.messages);
        await _expectRequestJsonEqual(second.messages, secondRetry.messages);

        final assistant = AiSessionMessage.assistant(
          id: 'tool-assistant-1',
          content: 'Inspection complete.',
          createdAt: _now.add(const Duration(seconds: 3)),
        );
        final nextUser = _user('tool-user-2', 'Summarize.');
        final thirdHistory = <AiSessionMessage>[
          persistedFirstUser,
          toolCall,
          persistedToolResult,
          assistant,
        ];
        final third = await builder.buildConversationPrompt(
          templateBundle: _bundle(info),
          session: _session(info, <AiSessionMessage>[
            ...thirdHistory,
            nextUser,
          ]),
          model: _gatewayModel,
          runtimeContext: _runtimeContext(info.id),
          memoryEntries: const <UserMemoryEntry>[],
          historyMessages: thirdHistory,
          latestUserMessage: nextUser,
        );
        _expectTurnPrefix(second.messages, third.messages);
        await _expectRequestJsonPrefix(second.messages, third.messages);
      },
    );

    test(
      'compatible gateways receive body and route affinity markers',
      () async {
        final request = await const OpenAiProtocolAdapter(AiProtocolType.openai)
            .buildChatRequest(
              model: _gatewayModel,
              messages: const <AiChatTurn>[
                AiChatTurn(role: AiChatRole.system, content: 'Stable system.'),
                AiChatTurn(role: AiChatRole.user, content: 'Question.'),
              ],
              inputCacheConfig: _cacheConfig,
            );

        expect(
          AiPromptCacheAffinity.kindForModel(_gatewayModel),
          AiPromptCacheAffinityKind.openAiCompatibleGateway,
        );
        expect(
          request.headers[AiPromptCacheAffinity.standardSessionAffinityHeader],
          'session-1',
        );
        expect(
          request.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
          'stable-key-1',
        );
        expect(request.body.keys.last, AiPromptCacheAffinity.messagesBodyField);
      },
    );

    test(
      'official OpenAI endpoint keeps prompt key without gateway header',
      () async {
        final model = _gatewayModel.copyWith(
          baseUrl: 'https://api.openai.com/v1',
        );
        final request = await const OpenAiProtocolAdapter(AiProtocolType.openai)
            .buildChatRequest(
              model: model,
              messages: const <AiChatTurn>[
                AiChatTurn(role: AiChatRole.user, content: 'Question.'),
              ],
              inputCacheConfig: _cacheConfig,
            );

        expect(
          AiPromptCacheAffinity.kindForModel(model),
          AiPromptCacheAffinityKind.openAiPromptCacheKey,
        );
        expect(
          request.headers.containsKey(
            AiPromptCacheAffinity.standardSessionAffinityHeader,
          ),
          isFalse,
        );
        expect(
          request.body[AiPromptCacheAffinity.openAiPromptCacheKeyBodyField],
          'stable-key-1',
        );
      },
    );

    test(
      'transient retry policy recognizes overload without retrying auth',
      () {
        expect(
          AiTransportDiagnosticMessages.isRetryableTransportError(
            const AiChatException(
              'Our servers are currently overloaded. Please try again later.',
            ),
          ),
          isTrue,
        );
        expect(
          AiTransportDiagnosticMessages.isRetryableTransportError(
            const AiChatException('HTTP 401: invalid API key'),
          ),
          isFalse,
        );
      },
    );
  });
}

const AiModelConfig _gatewayModel = AiModelConfig(
  id: 'model-1',
  baseUrl: 'https://api.krill-ai.com/codex/v1',
  authScheme: AiAuthScheme.bearer,
  token: 'token',
  modelId: 'gpt-cache-test',
  protocolType: AiProtocolType.openai,
);

const AiInputCacheRuntimeConfig _cacheConfig = AiInputCacheRuntimeConfig(
  enabled: true,
  mode: 'allMessages',
  updateInterval: 10,
  breakpointCount: 4,
  cacheAffinityId: 'session-1',
  promptCacheKey: 'stable-key-1',
);

final DateTime _now = DateTime.utc(2026, 7, 14, 12);

AiSessionMessage _user(String id, String content) {
  return AiSessionMessage.user(id: id, content: content, createdAt: _now);
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
  return AiSession(
    id: 'session-${info.id}',
    title: 'Cache continuity',
    templateId: info.id,
    templateName: info.name,
    templateIconName: info.iconName,
    templateInternalVersion: info.internalVersion,
    createdAt: _now,
    updatedAt: _now,
    messages: messages,
    environment: _environment,
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

final AiSessionEnvironment _environment = AiSessionEnvironment(
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
);

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
    memoryEntries: const <UserMemoryEntry>[],
    templateId: templateId,
    platformName: 'macos',
    workingDirectory: '/workspace',
    timeZoneName: 'CST',
  );
}

String _turnSignature(AiChatTurn turn) {
  return <Object?>[
    turn.roleName,
    turn.content,
    turn.toolCallId,
    turn.reasoningContent,
    for (final call in turn.toolCalls) ...<String>[
      call.id,
      call.name,
      call.arguments,
    ],
  ].join('\u001f');
}

void _expectTurnPrefix(List<AiChatTurn> prefix, List<AiChatTurn> turns) {
  expect(turns.length, greaterThan(prefix.length));
  for (var index = 0; index < prefix.length; index += 1) {
    expect(
      _turnSignature(turns[index]),
      _turnSignature(prefix[index]),
      reason: 'request prefix drifted at turn $index',
    );
  }
}

void _expectTurnsEqual(List<AiChatTurn> expected, List<AiChatTurn> actual) {
  expect(actual.length, expected.length);
  for (var index = 0; index < expected.length; index += 1) {
    expect(
      _turnSignature(actual[index]),
      _turnSignature(expected[index]),
      reason: 'retry request drifted at turn $index',
    );
  }
}

Future<void> _expectRequestJsonPrefix(
  List<AiChatTurn> prefix,
  List<AiChatTurn> turns,
) async {
  const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
  final previousRequest = await adapter.buildChatRequest(
    model: _gatewayModel,
    messages: prefix,
    inputCacheConfig: _cacheConfig,
  );
  final currentRequest = await adapter.buildChatRequest(
    model: _gatewayModel,
    messages: turns,
    inputCacheConfig: _cacheConfig,
  );
  final previousJson = jsonEncode(previousRequest.body);
  final currentJson = jsonEncode(currentRequest.body);
  var commonPrefix = 0;
  while (commonPrefix < previousJson.length &&
      commonPrefix < currentJson.length &&
      previousJson.codeUnitAt(commonPrefix) ==
          currentJson.codeUnitAt(commonPrefix)) {
    commonPrefix += 1;
  }
  expect(
    commonPrefix,
    greaterThanOrEqualTo(previousJson.length - 4),
    reason: 'serialized request body is not prefix-extending',
  );
}

Future<void> _expectRequestJsonEqual(
  List<AiChatTurn> expected,
  List<AiChatTurn> actual,
) async {
  const adapter = OpenAiProtocolAdapter(AiProtocolType.openai);
  final expectedRequest = await adapter.buildChatRequest(
    model: _gatewayModel,
    messages: expected,
    inputCacheConfig: _cacheConfig,
  );
  final actualRequest = await adapter.buildChatRequest(
    model: _gatewayModel,
    messages: actual,
    inputCacheConfig: _cacheConfig,
  );
  expect(jsonEncode(actualRequest.body), jsonEncode(expectedRequest.body));
}
