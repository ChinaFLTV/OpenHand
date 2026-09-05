import 'dart:async';

import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_config.dart';
import '../../model/offline_speech_model.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../usage/ai_usage_tracker.dart';

class AiSpeechTextPolishingService {
  AiSpeechTextPolishingService({AiChatClient? chatClient})
    : _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null;

  static const Duration _timeout = Duration(seconds: 15);
  static const String _systemPrompt =
      '整理语音识别文本。仅修正明显错字、标点和断句；保留原意、专有名词、代码、路径与数字；不要回答、解释或添加内容。只输出整理后的文本。';

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
            AiChatTurn(role: AiChatRole.user, content: source),
          ],
          creationRequest: AiCreationRequest.none,
          timeout: _timeout,
          cancelSignal: effectiveCancelSignal,
        ),
      );
      final polished = _clean(completion.reply);
      return polished.isEmpty ? source : polished;
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      _cancellations.remove(cancellation);
    }
  }

  AiModelConfig? _resolveModel(
    OfflineSpeechTextPolishingSettings settings,
    List<AiModelConfig> availableModels,
  ) {
    final configId = optionalStringFromValue(settings.modelConfigId);
    final modelId = optionalStringFromValue(settings.modelId);
    if (configId == null || modelId == null) return null;
    AiModelConfig? provider;
    for (final candidate in availableModels) {
      if (candidate.id == configId && candidate.allModelIds.contains(modelId)) {
        provider = candidate;
        break;
      }
    }
    if (provider == null) return null;
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
    return text;
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
