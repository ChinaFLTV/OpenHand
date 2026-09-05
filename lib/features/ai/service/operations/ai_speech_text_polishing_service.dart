import 'dart:async';

import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_config.dart';
import '../../model/offline_speech_model.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../usage/ai_usage_tracker.dart';

AiModelConfig? resolveSpeechTextPolishingModel(
  OfflineSpeechTextPolishingSettings settings,
  Iterable<AiModelConfig> availableModels,
) {
  final configId = optionalStringFromValue(settings.modelConfigId);
  final modelId = optionalStringFromValue(settings.modelId);
  if (configId == null || modelId == null) return null;
  for (final candidate in availableModels) {
    if (candidate.id == configId && candidate.allModelIds.contains(modelId)) {
      return candidate.copyWith(modelId: modelId);
    }
  }
  return null;
}

class AiSpeechTextPolishingService {
  AiSpeechTextPolishingService({AiChatClient? chatClient})
    : _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null;

  static const Duration _timeout = Duration(seconds: 30);
  static const String _systemPrompt =
      '你是语音转写编辑器。将识别结果整理为可直接发送、自然清晰的文本：\n'
      '- 删除语气词、口头禅、停顿、重复及已被改口否定的内容；\n'
      '- 合并同义反复，修正错字、语序、措辞、标点和断句；\n'
      '- 仅保留说话者最终表达的意图；无法确认的专有名词、代码、路径和数字保持原样。\n'
      '不要回答、解释或补充事实。只输出整理后的文本。';
  static final RegExp _responseLabelPattern = RegExp(
    r'^(?:润色|整理|修改)(?:后的?)?文本\s*[:：]\s*',
  );

  final AiChatClient _chatClient;
  final bool _ownsChatClient;
  final Set<Completer<void>> _cancellations = <Completer<void>>{};
  bool _disposed = false;

  Future<String> polish({
    required String text,
    required OfflineSpeechTextPolishingSettings settings,
    required List<AiModelConfig> availableModels,
    Future<void>? cancelSignal,
  }) async {
    if (_disposed) throw StateError('文本润色服务已关闭。');
    final source = text.trim();
    if (!settings.enabled || source.isEmpty) return source;
    final model = _resolveModel(settings, availableModels);
    if (model == null) throw StateError('文本润色模型不可用，请在设置中重新选择。');

    final cancellation = Completer<void>();
    _cancellations.add(cancellation);
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      cancelSignal,
      cancellation.future,
    ]);
    try {
      final completion = await AiUsageTraceContext.runDerived(
        source: AiUsageSource.speechCommunication,
        operation: 'speech_text_polishing',
        body: () => _chatClient.sendMessage(
          model: model,
          messages: <AiChatTurn>[
            const AiChatTurn(role: AiChatRole.system, content: _systemPrompt),
            AiChatTurn(role: AiChatRole.user, content: '请整理以下语音识别文本：\n$source'),
          ],
          creationRequest: AiCreationRequest.none,
          timeout: _timeout,
          cancelSignal: effectiveCancelSignal,
        ),
      );
      final polished = _clean(completion.reply);
      if (polished.isEmpty) throw StateError('润色模型未返回有效文本。');
      return polished;
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      _cancellations.remove(cancellation);
    }
  }

  AiModelConfig? _resolveModel(
    OfflineSpeechTextPolishingSettings settings,
    List<AiModelConfig> availableModels,
  ) {
    final provider = resolveSpeechTextPolishingModel(settings, availableModels);
    if (provider == null) return null;
    final modelId = provider.modelId;
    final effort = optionalStringFromValue(settings.reasoningEffort);
    final profile = provider.profileFor(modelId);
    return provider.copyWith(
      modelId: modelId,
      streamEnabled: false,
      temperature: 0,
      maxTokens: 1024,
      modelProfiles: <String, AiModelProfile>{
        ...provider.modelProfiles,
        modelId: profile.copyWith(
          reasoningEffort: effort,
          clearReasoningEffort: effort == null,
        ),
      },
    );
  }

  String _clean(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'^```(?:text)?\s*([\s\S]*?)\s*```$').firstMatch(text);
    if (fence != null) text = (fence.group(1) ?? '').trim();
    return text.replaceFirst(_responseLabelPattern, '').trim();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final cancellation in _cancellations.toList(growable: false)) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _cancellations.clear();
    if (_ownsChatClient) _chatClient.dispose();
  }
}
