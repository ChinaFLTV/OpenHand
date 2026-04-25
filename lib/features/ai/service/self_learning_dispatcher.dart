/// Hermes Talker 自主学习 LLM dispatcher (Task 18 Step 4-5 / 2026-04-25).
///
/// 构造一个受限子 Agent：使用流式 chat 调用，把 `Memory` 和 `SkillManager`
/// 作为仅有的两个工具暴露给模型，然后在工具调用循环中真正执行模型请求的
/// 记忆/技能写入操作。每轮工具调用后把结果喂回模型继续对话，直到模型停止
/// 调用工具（或达到最大轮次）。
///
/// 设计要点：
/// * 只开放 `memory` + `skill_manager` 两个内置工具 — 没有 bash / web /
///   文件读写。即使 prompt 被注入也无法越权。
/// * 工具执行直接调用各自 `run(args)` 便捷入口，不走完整 runtime（省去
///   permission gate / catalog 解析，这两者在受限子 Agent 上下文里意义
///   不大），但依赖的持久化（MemoryController 队列 / 原子写）均已就绪。
/// * 流式输出同时驱动 self_learning 卡片的 `ai_response` / `ai_reasoning`
///   字段（通过 [SelfLearningContext.onProgress]）。多轮工具调用以
///   `\n\n[tool-call round N 之后]\n\n` 作为分隔符追加，让用户能看到
///   完整思考 → 调用 → 再思考 → 回答的轨迹。
library;

import '../../../app/state/settings_controller.dart';
import '../../memory/memory_controller.dart';
import '../model/ai_model_config.dart';
import '../model/ai_token_usage.dart';
import '../tools/ai_memory_tool.dart';
import '../tools/ai_skill_manager_tool.dart';
import '../tools/ai_tool_utils.dart';
import 'ai_chat_service.dart';
import 'ai_protocol_adapter.dart';
import 'ai_tool_runtime_service.dart';
import 'self_learning_runner.dart';

/// 构造生产用 Hermes Talker 自主学习 dispatcher。
SelfLearningLlmDispatcher buildSelfLearningDispatcher({
  required AiChatService chatClient,
  required SettingsController settingsController,
  required MemoryController memoryController,
  int maxToolCallRounds = 6,
}) {
  final memoryTool = AiMemoryTool(
    memoryControllerProvider: () => memoryController,
  );
  final skillManagerTool = AiSkillManagerTool(
    skillsDirProvider: () => settingsController.skillsStoragePath,
  );

  return (SelfLearningContext context) async {
    final session = context.session;

    // ---------- Resolve model ----------
    final providerConfigId = session.lastUsedModelId?.trim();
    final models = settingsController.aiModels;
    AiModelConfig? selected;
    if (providerConfigId != null && providerConfigId.isNotEmpty) {
      for (final candidate in models) {
        if (candidate.id == providerConfigId) {
          selected = candidate;
          break;
        }
      }
    }
    selected ??= settingsController.selectedAiModel;
    if (selected == null) {
      return const SelfLearningOutcome(
        summary: '未找到可用的 AI 模型配置，无法执行自主学习。',
        mutations: <String, Object?>{'status_detail': 'no_model'},
      );
    }

    // ---------- Tool catalog (restricted to memory + skill_manager) ----------
    final memoryDef = AiToolRuntimeService.builtinToolDefault(
      AiBuiltinToolKind.memory,
    )?.definition;
    final skillManagerDef = AiToolRuntimeService.builtinToolDefault(
      AiBuiltinToolKind.skillManager,
    )?.definition;
    final toolDefinitions = <AiToolDefinition>[
      if (memoryDef != null) memoryDef,
      if (skillManagerDef != null) skillManagerDef,
    ];

    // ---------- Loop state ----------
    final turns = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: context.prompt),
      const AiChatTurn(
        role: AiChatRole.user,
        content:
            '请按系统提示执行本轮自我学习，直接调用 memory / skill_manager '
            '工具完成记忆/画像/技能的持久化。完成后用一段中文简要总结本轮学到的要点。',
      ),
    ];

    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final progress = context.onProgress;
    final responseTimeout = Duration(
      seconds: settingsController.aiResponseTimeoutSeconds,
    );

    AiTokenUsage? aggregateUsage;
    var memoryCallsOk = 0;
    var memoryCallsError = 0;
    var skillCallsOk = 0;
    var skillCallsError = 0;
    final toolCallsLog = <Map<String, Object?>>[];
    // 2026-04-25: 把每一次成功的工具调用拆成 {id, summary} 卡片项，分别归类到
    // memory_changes / profile_changes / skill_changes，供 _SelfLearningCard
    // 渲染。仅记录成功的调用——失败的会进 toolCallsLog 但不影响 UI 摘要。
    final memoryChanges = <Map<String, Object?>>[];
    final profileChanges = <Map<String, Object?>>[];
    final skillChanges = <Map<String, Object?>>[];
    var lastReply = '';
    var roundsRun = 0;
    var terminatedReason = 'completed';

    for (var round = 0; round < maxToolCallRounds; round++) {
      roundsRun = round + 1;
      final streaming = await chatClient.sendMessageStream(
        model: selected,
        messages: List<AiChatTurn>.unmodifiable(turns),
        tools: toolDefinitions,
        timeout: responseTimeout,
      );

      final roundResponse = StringBuffer();
      final roundReasoning = StringBuffer();

      await streaming.events.listen((event) {
        switch (event.type) {
          case AiChatStreamEventType.textDelta:
            if (event.textDelta != null) {
              roundResponse.write(event.textDelta);
              responseBuffer.write(event.textDelta);
              if (progress != null) {
                progress(aiResponse: responseBuffer.toString());
              }
            }
            break;
          case AiChatStreamEventType.reasoningDelta:
            if (event.reasoningDelta != null) {
              roundReasoning.write(event.reasoningDelta);
              reasoningBuffer.write(event.reasoningDelta);
              if (progress != null) {
                progress(aiReasoning: reasoningBuffer.toString());
              }
            }
            break;
          case AiChatStreamEventType.toolCallDelta:
          case AiChatStreamEventType.usage:
            break;
        }
      }).asFuture<void>();

      final result = await streaming.result;
      if (result.usage != null) {
        aggregateUsage = aggregateUsage == null
            ? result.usage
            : aggregateUsage.merge(result.usage!);
      }
      lastReply = result.reply.trim();

      // No tool calls → done.
      if (result.toolCalls.isEmpty) {
        terminatedReason = 'no_tool_calls';
        break;
      }

      // Model invoked tools → append assistant turn then execute each.
      turns.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: result.reply,
          toolCalls: result.toolCalls,
        ),
      );

      for (final toolCall in result.toolCalls) {
        final args = AiToolUtils.decodeArguments(toolCall.arguments);
        final normalizedName = toolCall.name.trim().toLowerCase();
        String resultText;
        var ok = false;
        try {
          if (normalizedName == 'memory') {
            final r = await memoryTool.run(args);
            resultText = r.resultText;
            ok = r.stderr.isEmpty;
            if (ok) {
              memoryCallsOk += 1;
              final action = '${args['action'] ?? ''}'.trim().toLowerCase();
              final content = '${args['content'] ?? ''}';
              final id = '${args['id'] ?? ''}'.trim();
              final summary = _summariseMemoryArgs(action, content);
              if (action == 'upsert_profile') {
                profileChanges.add(<String, Object?>{
                  'id': id.isEmpty ? 'user_profile' : id,
                  'summary': summary,
                  'action': action,
                });
              } else if (action == 'append' ||
                  action == 'update' ||
                  action == 'delete') {
                memoryChanges.add(<String, Object?>{
                  'id': id.isEmpty
                      ? (action == 'append' ? '(new)' : '(unknown)')
                      : id,
                  'summary': summary,
                  'action': action,
                });
              }
            } else {
              memoryCallsError += 1;
            }
          } else if (normalizedName == 'skillmanager' ||
              normalizedName == 'skill_manager') {
            final r = await skillManagerTool.run(args);
            resultText = r.resultText;
            ok = r.stderr.isEmpty;
            if (ok) {
              skillCallsOk += 1;
              final action = '${args['action'] ?? ''}'.trim().toLowerCase();
              final id = '${args['name'] ?? args['id'] ?? ''}'.trim();
              final summary = _summariseSkillArgs(args);
              skillChanges.add(<String, Object?>{
                'id': id.isEmpty ? '(unnamed)' : id,
                'summary': summary,
                'action': action,
              });
            } else {
              skillCallsError += 1;
            }
          } else {
            resultText =
                'status: failure\nerror: unknown tool '
                '"${toolCall.name}" — only memory / skill_manager are allowed '
                'in the self-learning sub-agent.';
          }
        } catch (error, stack) {
          resultText = 'status: failure\nerror: $error\n$stack';
          if (normalizedName == 'memory') {
            memoryCallsError += 1;
          } else if (normalizedName == 'skillmanager' ||
              normalizedName == 'skill_manager') {
            skillCallsError += 1;
          }
        }

        toolCallsLog.add(<String, Object?>{
          'round': round,
          'tool': toolCall.name,
          'action': args['action'],
          'ok': ok,
        });

        turns.add(
          AiChatTurn(
            role: AiChatRole.tool,
            content: resultText,
            toolCallId: toolCall.id,
          ),
        );
      }

      // Drop a visual separator in the streamed response so the user can see
      // each round's final summary gets interleaved with tool-call rounds.
      if (progress != null) {
        const separator = '\n\n— 工具已执行，继续下一轮 —\n\n';
        responseBuffer.write(separator);
        progress(aiResponse: responseBuffer.toString());
      }
    }

    if (roundsRun >= maxToolCallRounds && terminatedReason == 'completed') {
      terminatedReason = 'max_rounds';
    }

    final finalReply = lastReply;
    final summary = finalReply.isEmpty
        ? (memoryCallsOk + skillCallsOk > 0
              ? '本轮已记录 $memoryCallsOk 条记忆变更、$skillCallsOk 条技能变更。'
              : '模型本轮未调用任何工具，也未产生文本结论。')
        : (finalReply.length <= 160
              ? finalReply
              : '${finalReply.substring(0, 157)}…');

    return SelfLearningOutcome(
      summary: summary,
      mutations: <String, Object?>{
        'model_id': selected.modelId,
        'provider_id': selected.id,
        'memory_updates': memoryCallsOk,
        'memory_errors': memoryCallsError,
        'skill_updates': skillCallsOk,
        'skill_errors': skillCallsError,
        'memory_changes': memoryChanges,
        'profile_changes': profileChanges,
        'skill_changes': skillChanges,
        'tool_call_rounds': roundsRun,
        'terminated_reason': terminatedReason,
        if (toolCallsLog.isNotEmpty) 'tool_calls': toolCallsLog,
        if (aggregateUsage != null) 'usage': aggregateUsage.toJson(),
      },
      aiResponse: responseBuffer.isEmpty ? null : responseBuffer.toString(),
      aiReasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
    );
  };
}

/// 把一次 memory 工具调用的 args 浓缩成一段中文摘要，最多 120 字。
String _summariseMemoryArgs(String action, String content) {
  final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  final preview = flat.length <= 120 ? flat : '${flat.substring(0, 117)}…';
  return switch (action) {
    'append' => preview.isEmpty ? '追加一条记忆' : preview,
    'update' => preview.isEmpty ? '更新记忆内容' : preview,
    'delete' => '删除该条记忆',
    'upsert_profile' => preview.isEmpty ? '更新用户画像' : preview,
    _ => preview,
  };
}

/// 把一次 skill_manager 工具调用的 args 浓缩成一段中文摘要。
String _summariseSkillArgs(Map<String, Object?> args) {
  final action = '${args['action'] ?? ''}'.trim().toLowerCase();
  final desc = '${args['description'] ?? args['summary'] ?? ''}';
  final flat = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
  final preview = flat.length <= 120 ? flat : '${flat.substring(0, 117)}…';
  if (preview.isNotEmpty) return preview;
  return switch (action) {
    'create' => '新增技能',
    'patch' => '细调技能',
    'edit' => '重写技能',
    'delete' => '删除技能',
    _ => action.isEmpty ? '技能操作' : action,
  };
}
