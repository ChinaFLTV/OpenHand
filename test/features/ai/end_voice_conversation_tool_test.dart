import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
import 'package:openhand/features/ai/service/runtime/ai_plan_mode_tool_gate.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/voice/ai_end_voice_conversation_tool.dart';

void main() {
  final tool = AiEndVoiceConversationTool();
  AiToolExecutionContext context(Map<String, Object?> metadata) =>
      AiToolExecutionContext(
        sessionId: '当前线程',
        catalog: const AiResolvedToolCatalog(definitions: [], toolsByName: {}),
        toolCall: const AiToolCall(
          id: '调用',
          name: 'EndVoiceConversation',
          arguments: '{}',
        ),
        decodedArguments: const {},
        model: AiModelConfig.fromJson({}),
        previouslyReadFiles: {},
        denyCommandRules: [],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        metadata: metadata,
      );

  test('文本请求不能结束语音通话', () async {
    for (final value in [null, '', 42]) {
      final result = await tool.execute(context({aiVoiceCallIdKey: value}));
      expect(result.metadata.containsKey(aiEndedVoiceCallIdKey), isFalse);
      expect(result.stderr, contains('不属于语音通话'));
    }
  });

  test('退出结果只携带本次通话标识，重复调用保持幂等', () async {
    final first = await tool.execute(context({aiVoiceCallIdKey: '通话甲'}));
    final repeated = await tool.execute(context({aiVoiceCallIdKey: '通话甲'}));
    final next = await tool.execute(context({aiVoiceCallIdKey: '通话乙'}));
    expect(first.metadata[aiEndedVoiceCallIdKey], '通话甲');
    expect(repeated.metadata, first.metadata);
    expect(next.metadata[aiEndedVoiceCallIdKey], '通话乙');
  });

  test('默认懒加载，可通过工具搜索发现，计划模式也允许挂断', () {
    const kind = AiBuiltinToolKind.endVoiceConversation;
    expect(
      AiBuiltinToolConfig.defaultLoadStrategyForKind(kind),
      AiBuiltinToolLoadStrategy.lazy,
    );
    expect(AiBuiltinToolConfig.defaultForceLoadForKind(kind), isFalse);
    final end = AiToolRuntimeService.builtinToolDefault(kind)!;
    final search = AiToolRuntimeService.builtinToolDefault(
      AiBuiltinToolKind.toolSearch,
    )!;
    final catalog = AiResolvedToolCatalog(
      definitions: [end.definition, search.definition],
      toolsByName: {end.name: end, search.name: search},
    );
    final deferred = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 8000,
      charsPerToken: 4,
    );
    expect(deferred.find(end.name), isNull);
    expect(deferred.findDeferredTool(end.name)?.builtinKind, kind);
    expect(
      AiPlanModeToolGate.isAllowedPlanningTool(
        end.name,
        allowExitPlanMode: false,
      ),
      isTrue,
    );
  });
}
