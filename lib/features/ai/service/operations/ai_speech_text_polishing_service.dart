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

const String speechTextPolishingEmptyMarker = '<EMPTY>';

final RegExp _speechNonSemanticCharacterPattern = RegExp(
  r'[^0-9A-Za-z\u00C0-\u02FF\u0370-\u052F\u0590-\u0FFF\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF]+',
);
final RegExp _speechFillerOnlyPattern = RegExp(
  r'^(?:嗯+|啊+|呃+|额+|哦+|噢+|哎+|唉+|唔+|哼+|诶+|欸+|呐+|え+|あ+|うん+|음+|어+|um+|uh+|hm+|ah+|oh+|erm+)$',
  caseSensitive: false,
);
final RegExp _speechNoContentPattern = RegExp(
  r'^(?:empty|无(?:有效)?(?:内容|文本)(?:可|需要)?(?:整理|润色)?|没有(?:可|需要)?(?:整理|润色)的?(?:有效)?(?:内容|文本)|(?:未|没有)(?:提供|检测到|识别到)(?:有效)?(?:内容|文本|语音识别文本)?|请(?:先)?提供(?:需要|待)?(?:整理|润色)?的?(?:语音识别)?文本)$',
  caseSensitive: false,
);

bool hasMeaningfulSpeechText(String value) {
  final compact = value
      .trim()
      .replaceAll(_speechNonSemanticCharacterPattern, '')
      .toLowerCase();
  return compact.isNotEmpty &&
      !_speechFillerOnlyPattern.hasMatch(compact) &&
      !_speechNoContentPattern.hasMatch(compact);
}

class AiSpeechTextPolishingService {
  AiSpeechTextPolishingService({AiChatClient? chatClient})
    : _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null;

  static const Duration _timeout = Duration(minutes: 1);
  static const int _maxOutputTokens = 4096;
  static const String _systemPrompt =
      '你是语音转写编辑器。将识别结果整理为可直接发送、自然清晰的文本：\n'
      '- 删除语气词、口头禅、停顿、重复及已被改口否定的内容；\n'
      '- 合并同义反复，修正错字、语序、措辞、标点和断句；\n'
      '- 仅保留说话者最终表达的意图；无法确认的专有名词、代码、路径和数字保持原样。\n'
      '仅含噪音、标点或语气词时输出 $speechTextPolishingEmptyMarker。不要回答、解释或补充事实。只输出整理后的文本。';
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
    if (!hasMeaningfulSpeechText(source)) return '';
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
      if (polished == speechTextPolishingEmptyMarker ||
          !hasMeaningfulSpeechText(polished)) {
        return '';
      }
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
    final profileOutputLimit = profile.maxOutputLength;
    final outputTokens = profileOutputLimit == null
        ? _maxOutputTokens
        : profileOutputLimit.clamp(1, _maxOutputTokens).toInt();
    return provider.copyWith(
      modelId: modelId,
      streamEnabled: false,
      temperature: provider.resolvedThinkingEnabled ? null : 0,
      clearTemperature: provider.resolvedThinkingEnabled,
      maxTokens: outputTokens,
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
