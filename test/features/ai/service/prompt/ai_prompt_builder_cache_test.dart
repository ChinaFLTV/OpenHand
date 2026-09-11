import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  group('AiPromptBuilder 工具结果缓存稳定性', () {
    test('所有线程模板首次即压缩超限结果且后续前缀不变', () async {
      for (final entry in AiPromptTemplatePolicies.entries) {
        final fixture = _PromptFixture(
          templateId: entry.id,
          compressionEnabled: true,
        );
        final first = await fixture.build(fixture.messages);
        final summarizedToolResult = first.messages.singleWhere(
          (turn) => turn.role == AiChatRole.tool,
        );

        expect(
          summarizedToolResult.content,
          startsWith('[tool_result_summary] Read'),
          reason: entry.id,
        );
        expect(
          summarizedToolResult.content.length,
          lessThan(fixture.largeToolResult.length),
          reason: entry.id,
        );
        expect(first.metadata['tool_result_prompt_guard_enabled'], isTrue);

        final resultWithRuntimeTail = fixture.messages[2].copyWith(
          metadata: <String, Object?>{
            ...fixture.messages[2].metadata,
            aiPromptRuntimeTailSnapshotMetadataKey:
                first.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
          },
        );
        final secondMessages = <AiSessionMessage>[
          fixture.messages[0],
          fixture.messages[1],
          resultWithRuntimeTail,
          AiSessionMessage.assistant(
            id: 'assistant',
            content: '已处理。',
            createdAt: fixture.now.add(const Duration(seconds: 1)),
          ),
        ];
        final second = await fixture.build(secondMessages);

        expect(
          _turnSignatures(second.messages.take(first.messages.length)),
          _turnSignatures(first.messages),
          reason: entry.id,
        );
      }
    });

    test('关闭压缩时保留原始工具结果', () async {
      final fixture = _PromptFixture(
        templateId: AiPromptTemplatePolicies.defaultTemplateId,
        compressionEnabled: false,
      );
      final result = await fixture.build(fixture.messages);

      expect(
        result.messages
            .singleWhere((turn) => turn.role == AiChatRole.tool)
            .content,
        fixture.largeToolResult,
      );
      expect(result.metadata['tool_result_prompt_guard_enabled'], isFalse);
      expect(
        fixture.buildCompressionPrompt(fixture.messages).last.content,
        contains(fixture.largeToolResult),
      );
    });

    test('阈值内结果保留原文', () async {
      final fixture = _PromptFixture(
        templateId: AiPromptTemplatePolicies.defaultTemplateId,
        compressionEnabled: true,
      );
      final messages = <AiSessionMessage>[
        ...fixture.messages.take(2),
        fixture.messages[2].copyWith(content: '小型结果'),
      ];
      final result = await fixture.build(messages);

      expect(
        result.messages
            .singleWhere((turn) => turn.role == AiChatRole.tool)
            .content,
        '小型结果',
      );
    });

    test('并行工具结果统一压缩且不改写历史', () async {
      final fixture = _PromptFixture(
        templateId: AiPromptTemplatePolicies.defaultTemplateId,
        compressionEnabled: true,
      );
      final messages = fixture.parallelMessages(4);
      final first = await fixture.build(
        messages,
        runtimeContextAnchorMessageId: 'result-3',
      );
      final toolTurns = first.messages
          .where((turn) => turn.role == AiChatRole.tool)
          .toList(growable: false);

      expect(toolTurns, hasLength(4));
      expect(
        toolTurns.every(
          (turn) => turn.content.startsWith('[tool_result_summary] Read'),
        ),
        isTrue,
      );

      final lastResult = messages.last.copyWith(
        metadata: <String, Object?>{
          ...messages.last.metadata,
          aiPromptRuntimeTailSnapshotMetadataKey:
              first.metadata[aiPromptRuntimeTailSnapshotMetadataKey],
        },
      );
      final second = await fixture.build(<AiSessionMessage>[
        ...messages.take(messages.length - 1),
        lastResult,
        AiSessionMessage.assistant(
          id: 'assistant',
          content: '继续处理。',
          createdAt: fixture.now.add(const Duration(seconds: 1)),
        ),
      ], runtimeContextAnchorMessageId: 'result-3');

      expect(
        _turnSignatures(second.messages.take(first.messages.length)),
        _turnSignatures(first.messages),
      );
    });
  });
}

List<String> _turnSignatures(Iterable<AiChatTurn> turns) {
  return turns
      .map(
        (turn) => jsonEncode(<String, Object?>{
          'role': turn.roleName,
          'content': turn.content,
          'tool_call_id': turn.toolCallId,
          'tool_calls': turn.toolCalls
              .map(
                (call) => <String, String>{
                  'id': call.id,
                  'name': call.name,
                  'arguments': call.arguments,
                },
              )
              .toList(growable: false),
          'reasoning': turn.reasoningContent,
        }),
      )
      .toList(growable: false);
}

class _PromptFixture {
  _PromptFixture({required this.templateId, required bool compressionEnabled})
    : runtimeContext = AiSessionRuntimeContext(
        localeTag: 'zh-CN',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        settingsFilePath: '/tmp/settings.json',
        skillsStoragePath: '/tmp/skills',
        mcpServersFilePath: '/tmp/mcp.json',
        userMemoryFilePath: '/tmp/memory.json',
        compressionThresholdChars: 100000,
        toolResultCompressionEnabled: compressionEnabled,
        memoryEnabled: false,
        memoryEntries: const [],
        workingDirectory: '/tmp/project',
        platformName: 'macos',
        todayLocalDate: '2026-09-11',
        timeZoneName: 'Asia/Shanghai',
        templateId: templateId,
      );

  final String templateId;
  final AiSessionRuntimeContext runtimeContext;
  final DateTime now = DateTime.utc(2026, 9, 11);
  final String largeToolResult = 'HEAD\n${'0123456789' * 500}\nTAIL';

  List<AiSessionMessage> get messages => <AiSessionMessage>[
    AiSessionMessage.user(id: 'user', content: '读取文件', createdAt: now),
    AiSessionMessage.toolCall(
      id: 'call',
      content: '',
      createdAt: now,
      metadata: const <String, Object?>{
        'tool_calls': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'call-1',
            'name': 'Read',
            'arguments': '{"file_path":"/tmp/project/demo.txt"}',
          },
        ],
      },
    ),
    AiSessionMessage.toolResult(
      id: 'result',
      content: largeToolResult,
      createdAt: now,
      metadata: const <String, Object?>{
        'tool_call_id': 'call-1',
        'tool_name': 'Read',
        'status': 'success',
        'tool_arguments': <String, Object?>{
          'file_path': '/tmp/project/demo.txt',
          'purpose': '读取测试文件',
        },
      },
    ),
  ];

  List<AiSessionMessage> parallelMessages(int count) {
    return <AiSessionMessage>[
      AiSessionMessage.user(id: 'user', content: '并行读取', createdAt: now),
      for (var index = 0; index < count; index++)
        AiSessionMessage.toolCall(
          id: 'call-$index',
          content: '',
          createdAt: now,
          metadata: <String, Object?>{
            'tool_calls': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'tool-call-$index',
                'name': 'Read',
                'arguments': '{"file_path":"/tmp/project/$index.txt"}',
              },
            ],
          },
        ),
      for (var index = 0; index < count; index++)
        AiSessionMessage.toolResult(
          id: 'result-$index',
          content: '$largeToolResult-$index',
          createdAt: now,
          metadata: <String, Object?>{
            'tool_call_id': 'tool-call-$index',
            'tool_name': 'Read',
            'status': 'success',
          },
        ),
    ];
  }

  Future<AiPromptBuildResult> build(
    List<AiSessionMessage> messages, {
    String runtimeContextAnchorMessageId = 'result',
  }) {
    final template = AiPromptTemplateRepository().resolveTemplate(templateId);
    final session = _session(template, messages);
    return const AiPromptBuilder().buildSessionPrompt(
      templateBundle: AiPromptTemplateBundle(
        template: template,
        systemInstructions: '系统指令',
        developerInstructions: '开发者指令',
        compressionSummaryInstructions: '压缩指令',
      ),
      session: session,
      model: const AiModelConfig(
        id: 'model',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-test',
        protocolType: AiProtocolType.openai,
      ),
      runtimeContext: runtimeContext,
      memoryEntries: const [],
      sessionMessages: messages,
      latestUserMessageId: 'user',
      runtimeContextAnchorMessageId: runtimeContextAnchorMessageId,
    );
  }

  List<AiChatTurn> buildCompressionPrompt(List<AiSessionMessage> messages) {
    final template = AiPromptTemplateRepository().resolveTemplate(templateId);
    final session = _session(template, messages);
    return const AiPromptBuilder().buildCompressionPrompt(
      templateBundle: AiPromptTemplateBundle(
        template: template,
        systemInstructions: '系统指令',
        developerInstructions: '开发者指令',
        compressionSummaryInstructions: '压缩指令',
      ),
      template: template,
      session: session,
      runtimeContext: runtimeContext,
      messagesToCompress: messages,
      previousCompressionPoint: null,
    );
  }

  AiSession _session(
    AiThreadTemplate template,
    List<AiSessionMessage> messages,
  ) {
    return AiSession(
      id: 'session-$templateId',
      title: '测试',
      templateId: template.id,
      templateName: template.name,
      templateIconName: template.iconName,
      templateInternalVersion: template.internalVersion,
      createdAt: now,
      updatedAt: now,
      messages: messages,
      environment: AiSessionEnvironment.fromJson(const <String, Object?>{}),
      statistics: AiSessionStatistics.fromJson(const <String, Object?>{}),
      recentErrors: const [],
    );
  }
}
