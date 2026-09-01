import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/net/http_error_message.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_base64.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../model/ai_api_dialect.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_attachment.dart';
import '../../model/ai_input_cache_runtime_config.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_session_message.dart';
import '../../model/ai_token_usage.dart';
import '../operations/ai_operation_http.dart';
import '../runtime/ai_endpoint_router.dart';
import '../session_io/ai_token_usage_parser.dart';

final RegExp _dataUriMimePattern = RegExp(r'data:([^;]+)');
final RegExp _markdownSeparatorTailPattern = RegExp(r'-+$');
const Duration _inlineImageReadIdleTimeout = Duration(seconds: 15);
const Duration _inlineImageReadTotalTimeout = Duration(minutes: 1);
const int _inlineMediaCacheScanLimit = 10000;
const int _inlineMediaCacheDeleteLimit = 2000;
const int _inlineMediaCacheMaxFiles = 2048;
const int _inlineMediaCacheMaxBytes = 4 * kBytesPerGiB;
const int _inlineMediaMaxDecodedBytes = 128 * kBytesPerMiB;
const Duration _inlineMediaCacheIdleTimeout = Duration(seconds: 2);
const Duration _inlineMediaCacheCleanupTimeout = Duration(seconds: 15);
const Duration _inlineMediaWriteTimeout = Duration(seconds: 30);

abstract final class AiThinkingRequestPolicy {
  static const int _defaultThinkingBudget = 8192;
  static const int _claudeMinimumBudget = 1024;
  static final RegExp _modelIdSeparatorPattern = RegExp(r'[^a-z0-9]+');
  static final RegExp _modelIdRepeatedDashPattern = RegExp(r'-+');
  static final RegExp _modelIdEdgeDashPattern = RegExp(r'^-|-$');
  static const String _reasoningField = 'reasoning';
  static const String _reasoningEffortField = 'reasoning_effort';
  static const String _includeReasoningField = 'include_reasoning';
  static const String _enableThinkingField = 'enable_thinking';
  static const String _thinkingField = 'thinking';
  static const String _thinkingConfigField = 'thinkingConfig';
  static const String _thinkingBudgetField = 'thinkingBudget';
  static const String _thinkingLevelField = 'thinkingLevel';
  static const String _outputConfigField = 'output_config';
  static const String _chatTemplateKwargsField = 'chat_template_kwargs';

  static const Set<String> _topLevelMarkerFields = <String>{
    _reasoningField,
    _reasoningEffortField,
    _includeReasoningField,
    _enableThinkingField,
    _thinkingField,
    _outputConfigField,
  };

  static bool shouldApply(AiModelConfig model) {
    return model.resolvedSupportsThinking || model.resolvedThinkingEnabled;
  }

  /// MiMo 的 thinking 开关：显式写 enabled / disabled，开启时移除采样参数。
  ///
  /// MiMo 的 OpenAI 与 Anthropic 两套端点都不接受 thinking 与
  /// temperature / top_p 同时出现，两个适配器必须写成同一形态。
  static void applyMimoThinking(
    Map<String, Object?> body,
    AiModelConfig model,
  ) {
    body[_thinkingField] = <String, Object?>{
      'type': model.resolvedThinkingEnabled ? 'enabled' : 'disabled',
    };
    if (!model.resolvedThinkingEnabled) return;
    body.remove('temperature');
    body.remove('top_p');
  }

  static void applyOpenAiCompatible(
    Map<String, Object?> body,
    AiModelConfig model,
  ) {
    if (!shouldApply(model)) return;
    final enabled = model.resolvedThinkingEnabled;
    final effortControlEnabled = model.resolvedReasoningEffortControlEnabled;
    final effort = model.resolvedReasoningEffort;
    final parameters = _supportedParameterSet(model);
    final protocol = model.protocolType;
    final normalizedModelId = lowercaseStringFromValue(model.modelId);

    if (protocol == AiProtocolType.mimo) {
      body[_thinkingField] = <String, Object?>{
        'type': enabled ? 'enabled' : 'disabled',
      };
      return;
    }

    // Dots 的 OpenAI 端点要求思考开关放在 chat_template_kwargs 中。
    if (protocol == AiProtocolType.dots) {
      final templateKwargs = stringKeyedMapFromValue(
        body[_chatTemplateKwargsField],
      );
      body[_chatTemplateKwargsField] = <String, Object?>{
        ...templateKwargs,
        _enableThinkingField: enabled,
      };
      return;
    }

    // MiniMax 的 OpenAI 兼容端点使用 Anthropic 自适应思考格式。
    if (protocol == AiProtocolType.minimax) {
      body[_thinkingField] = <String, Object?>{
        'type': enabled ? 'adaptive' : 'disabled',
      };
      return;
    }

    // Kimi K3 始终思考，仅接受顶层 reasoning_effort。
    if (protocol == AiProtocolType.kimi &&
        (normalizedModelId.contains('kimi-k3') || normalizedModelId == 'k3')) {
      if (effortControlEnabled && effort != null) {
        body[_reasoningEffortField] = effort;
      }
      body.remove(_thinkingField);
      return;
    }

    // Qwen3.8-Max 的 reasoning_effort 与 thinking_budget 互斥。
    if (protocol == AiProtocolType.qwen &&
        (normalizedModelId.contains('qwen3.8-max') ||
            normalizedModelId.contains('qwen3-8-max'))) {
      _setEnableThinking(body, enabled);
      if (enabled && effortControlEnabled && effort != null) {
        body[_reasoningEffortField] = effort;
      }
      body.remove('thinking_budget');
      return;
    }

    if (_prefersEnableThinking(protocol) ||
        parameters.contains(_enableThinkingField)) {
      _setEnableThinking(body, enabled);
      if (enabled && effortControlEnabled) {
        _setThinkingBudget(body, effort);
      }
      return;
    }

    if ((parameters.contains(_reasoningField) ||
            parameters.contains(_includeReasoningField) ||
            _looksLikeOpenRouterRoute(model)) &&
        !parameters.contains(_reasoningEffortField)) {
      _setReasoningObject(body, enabled, effortControlEnabled ? effort : null);
      if (parameters.contains(_includeReasoningField) ||
          _looksLikeOpenRouterRoute(model)) {
        body[_includeReasoningField] = enabled;
      }
      return;
    }

    final needsThinkingObject =
        parameters.contains(_thinkingField) ||
        _prefersThinkingObject(protocol, normalizedModelId);
    final sendsTopLevelReasoningEffort =
        effortControlEnabled &&
        (parameters.contains(_reasoningEffortField) ||
            _prefersReasoningEffort(protocol, normalizedModelId));
    if (needsThinkingObject) {
      body[_thinkingField] = _thinkingObject(
        enabled: enabled,
        effort: enabled && effortControlEnabled && !sendsTopLevelReasoningEffort
            ? effort
            : null,
      );
      if (sendsTopLevelReasoningEffort) {
        body[_reasoningEffortField] = effort ?? 'medium';
      }
      return;
    }

    if (sendsTopLevelReasoningEffort) {
      body[_reasoningEffortField] = effort ?? 'medium';
      return;
    }

    if (enabled && effortControlEnabled) {
      body[_reasoningEffortField] = effort ?? 'medium';
    }
  }

  static Object? responsesReasoningFor(AiModelConfig model) {
    if (!shouldApply(model)) return null;
    if (!model.resolvedThinkingEnabled) {
      return model.protocolType == AiProtocolType.minimax ||
              model.protocolType == AiProtocolType.mimo
          ? const <String, Object?>{'effort': 'none'}
          : null;
    }
    if (model.protocolType == AiProtocolType.minimax) {
      return <String, Object?>{
        'effort': model.resolvedReasoningEffort ?? 'medium',
      };
    }
    if (!model.resolvedReasoningEffortControlEnabled) return null;
    return <String, Object?>{
      'effort': model.resolvedReasoningEffort ?? 'medium',
    };
  }

  static int effectiveClaudeMaxTokens(AiModelConfig model, int requested) {
    if (!shouldApply(model) || !model.resolvedThinkingEnabled) {
      return requested;
    }
    return math.max(requested, _claudeMinimumBudget * 4);
  }

  static Map<String, Object?>? claudeThinkingFor({
    required AiModelConfig model,
    required int maxTokens,
  }) {
    if (!shouldApply(model)) return null;
    if (model.protocolType == AiProtocolType.minimax) {
      return <String, Object?>{
        'type': model.resolvedThinkingEnabled ? 'adaptive' : 'disabled',
      };
    }
    if (model.protocolType == AiProtocolType.dots) {
      return <String, Object?>{
        'type': model.resolvedThinkingEnabled ? 'adaptive' : 'disabled',
      };
    }
    // Fable 5 / Mythos 5 省略 thinking 时自动使用自适应思考。
    if (_usesAlwaysOnClaudeAdaptiveThinking(model)) return null;
    if (!model.resolvedThinkingEnabled) {
      return const <String, Object?>{'type': 'disabled'};
    }
    final roomForAnswer = math.min(1024, math.max(1, maxTokens ~/ 4));
    final ceiling = math.max(_claudeMinimumBudget, maxTokens - roomForAnswer);
    final requestedBudget = _thinkingBudget(
      model,
      fallback: _claudeMinimumBudget,
    );
    final effort = _normalizeReasoningEffort(model.resolvedReasoningEffort);
    if (model.resolvedReasoningEffortControlEnabled &&
        _usesClaudeOutputEffort(model) &&
        effort != null &&
        !_looksLikeNumericBudget(effort)) {
      return const <String, Object?>{'type': 'adaptive'};
    }
    final budget = requestedBudget.clamp(_claudeMinimumBudget, ceiling).toInt();
    if (budget >= maxTokens) {
      return null;
    }
    return <String, Object?>{'type': 'enabled', 'budget_tokens': budget};
  }

  static Map<String, Object?>? claudeOutputConfigFor(AiModelConfig model) {
    if (!shouldApply(model) || !model.resolvedReasoningEffortControlEnabled) {
      return null;
    }
    if (!_usesClaudeOutputEffort(model)) return null;
    final effort = _normalizeReasoningEffort(model.resolvedReasoningEffort);
    if (effort == null || _looksLikeNumericBudget(effort)) return null;
    return <String, Object?>{'effort': effort};
  }

  static void applyGeminiGenerationConfig(
    Map<String, Object?> generationConfig,
    AiModelConfig model,
  ) {
    if (!shouldApply(model)) return;
    final enabled = model.resolvedThinkingEnabled;
    final effort = model.resolvedReasoningEffortControlEnabled
        ? _normalizeReasoningEffort(model.resolvedReasoningEffort)
        : null;
    if (_usesGeminiThinkingLevel(model)) {
      final id = lowercaseStringFromValue(model.modelId);
      final disabledLevel =
          id.contains('gemini-3.5') || id.contains('gemini-3.6')
          ? 'minimal'
          : 'low';
      generationConfig[_thinkingConfigField] = <String, Object?>{
        _thinkingLevelField: _geminiThinkingLevel(
          enabled ? effort ?? 'medium' : disabledLevel,
        ),
        if (enabled) 'includeThoughts': true,
      };
      return;
    }
    generationConfig[_thinkingConfigField] = <String, Object?>{
      _thinkingBudgetField: enabled
          ? _thinkingBudget(model, fallback: _defaultThinkingBudget)
          : 0,
      if (enabled) 'includeThoughts': true,
    };
  }

  static bool requestHasMarker({required Map<String, Object?> body}) {
    return _containsThinkingMarker(body);
  }

  static Map<String, Object?> withoutRequestMarkers(Map<String, Object?> body) {
    return _stripThinkingMarkers(body);
  }

  static bool shouldRetryWithoutMarkers({
    required int statusCode,
    required String errorBody,
    required Map<String, Object?> requestBody,
  }) {
    if (statusCode < 400 || statusCode >= 500) return false;
    if (!requestHasMarker(body: requestBody)) return false;
    final normalized = errorBody.toLowerCase();
    final mentionsThinkingField =
        _topLevelMarkerFields.any((field) => normalized.contains(field)) ||
        normalized.contains('thinkingconfig') ||
        normalized.contains('thinking_config') ||
        normalized.contains('thinkingbudget') ||
        normalized.contains('thinking_budget') ||
        normalized.contains('thinkinglevel') ||
        normalized.contains('thinking_level') ||
        normalized.contains(_outputConfigField);
    if (mentionsThinkingField) {
      return _looksLikeUnsupportedParameterError(normalized);
    }
    if (statusCode != 400 && statusCode != 422) return false;
    return _looksLikeUnsupportedParameterError(normalized);
  }

  static Set<String> _supportedParameterSet(AiModelConfig model) {
    final profile = model.profileFor(model.modelId);
    final result = profile.supportedParameters
        .map(_normalizeParameterName)
        .where((item) => item.isNotEmpty)
        .toSet();
    _collectParameterKeys(profile.defaultParameters, result);
    return result;
  }

  static String _normalizeParameterName(String value) {
    return lowercaseStringFromValue(
      value,
    ).replaceAll('-', '_').replaceAll('.', '_');
  }

  static int _thinkingBudget(AiModelConfig model, {required int fallback}) {
    final effort = model.resolvedReasoningEffortControlEnabled
        ? _normalizeReasoningEffort(model.resolvedReasoningEffort)
        : null;
    final effortBudget = _budgetFromReasoningEffort(model, effort, fallback);
    if (effortBudget != null) return effortBudget;
    final profile = model.profileFor(model.modelId);
    final value = profile.maxThinkingLength;
    if (value == null || value <= 0) return fallback;
    return value;
  }

  static void _collectParameterKeys(Object? value, Set<String> output) {
    if (value is! Map) return;
    for (final entry in value.entries) {
      output.add(_normalizeParameterName('${entry.key}'));
      _collectParameterKeys(entry.value, output);
    }
  }

  static void _setEnableThinking(Map<String, Object?> body, bool enabled) {
    body[_enableThinkingField] = enabled;
    final rawTemplateKwargs = body[_chatTemplateKwargsField];
    if (rawTemplateKwargs is Map) {
      body[_chatTemplateKwargsField] = <String, Object?>{
        ...stringKeyedMapFromValue(rawTemplateKwargs),
        _enableThinkingField: enabled,
      };
    }
  }

  static void _setThinkingBudget(Map<String, Object?> body, String? effort) {
    final budget = _positiveIntFromText(effort);
    if (budget == null) return;
    body['thinking_budget'] = budget;
    final rawTemplateKwargs = body[_chatTemplateKwargsField];
    if (rawTemplateKwargs is Map) {
      body[_chatTemplateKwargsField] = <String, Object?>{
        ...stringKeyedMapFromValue(rawTemplateKwargs),
        'thinking_budget': budget,
      };
    }
  }

  static void _setReasoningObject(
    Map<String, Object?> body,
    bool enabled,
    String? effort,
  ) {
    body[_reasoningField] = <String, Object?>{
      'enabled': enabled,
      if (effort != null) 'effort': effort,
    };
  }

  static Map<String, Object?> _thinkingObject({
    required bool enabled,
    String? effort,
  }) {
    return <String, Object?>{
      'type': enabled ? 'enabled' : 'disabled',
      if (effort != null && !_looksLikeNumericBudget(effort)) 'effort': effort,
      if (effort != null && _looksLikeNumericBudget(effort))
        'budget_tokens': _positiveIntFromText(effort),
    };
  }

  static bool _prefersEnableThinking(AiProtocolType protocolType) {
    return switch (protocolType) {
      AiProtocolType.dots ||
      AiProtocolType.qwen ||
      AiProtocolType.wenxin ||
      AiProtocolType.vllm ||
      AiProtocolType.sglang => true,
      _ => false,
    };
  }

  static bool _prefersReasoningEffort(
    AiProtocolType protocolType,
    String normalizedModelId,
  ) {
    return switch (protocolType) {
      AiProtocolType.openai ||
      AiProtocolType.dots ||
      AiProtocolType.grok ||
      AiProtocolType.deepseek ||
      AiProtocolType.glm ||
      AiProtocolType.stepfun => true,
      AiProtocolType.kimi when normalizedModelId.contains('kimi-k2') => true,
      _ => false,
    };
  }

  static bool _prefersThinkingObject(
    AiProtocolType protocolType,
    String normalizedModelId,
  ) {
    return switch (protocolType) {
      AiProtocolType.deepseek ||
      AiProtocolType.glm ||
      AiProtocolType.seed ||
      AiProtocolType.stepfun ||
      AiProtocolType.longcat ||
      AiProtocolType.hunyuan ||
      AiProtocolType.mimo => true,
      AiProtocolType.kimi when !normalizedModelId.contains('kimi-k2') => true,
      _ => false,
    };
  }

  static bool _looksLikeOpenRouterRoute(AiModelConfig model) {
    final baseUrl = lowercaseStringFromValue(model.baseUrl);
    return baseUrl.contains('openrouter') || model.modelId.contains('/');
  }

  static bool _looksLikeUnsupportedParameterError(String normalizedError) {
    return normalizedError.contains('unknown') ||
        normalizedError.contains('unrecognized') ||
        normalizedError.contains('unsupported') ||
        normalizedError.contains('unexpected') ||
        normalizedError.contains('not allowed') ||
        normalizedError.contains('additional') ||
        normalizedError.contains('invalid') ||
        normalizedError.contains('schema') ||
        normalizedError.contains('parameter') ||
        normalizedError.contains('field') ||
        normalizedError.contains('body') ||
        normalizedError.contains('request') ||
        normalizedError.contains('bad request');
  }

  static bool _containsThinkingMarker(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = _normalizeParameterName('${entry.key}');
        if (_topLevelMarkerFields.contains(key) ||
            key == 'thinking_config' ||
            key == 'thinkingconfig' ||
            key == 'thinking_budget' ||
            key == 'thinkingbudget' ||
            key == 'thinking_level' ||
            key == 'thinkinglevel') {
          return true;
        }
        if (_containsThinkingMarker(entry.value)) return true;
      }
    }
    if (value is List) {
      return value.any(_containsThinkingMarker);
    }
    return false;
  }

  static Map<String, Object?> _stripThinkingMarkers(Map<String, Object?> map) {
    final result = <String, Object?>{};
    for (final entry in map.entries) {
      final key = _normalizeParameterName(entry.key);
      if (_topLevelMarkerFields.contains(key) ||
          key == 'thinking_config' ||
          key == 'thinkingconfig' ||
          key == 'thinking_budget' ||
          key == 'thinkingbudget' ||
          key == 'thinking_level' ||
          key == 'thinkinglevel') {
        continue;
      }
      result[entry.key] = _stripThinkingValue(entry.value);
    }
    return result;
  }

  static Object? _stripThinkingValue(Object? value) {
    if (value is Map<String, Object?>) {
      return _stripThinkingMarkers(value);
    }
    if (value is Map) {
      return _stripThinkingMarkers(stringKeyedMapFromValue(value));
    }
    if (value is List) {
      return value.map(_stripThinkingValue).toList(growable: false);
    }
    return value;
  }

  static String? _normalizeReasoningEffort(String? value) {
    final trimmed = nullIfBlank(value);
    return trimmed?.toLowerCase();
  }

  static bool _looksLikeNumericBudget(String value) {
    return _positiveIntFromText(value) != null;
  }

  static int? _positiveIntFromText(String? value) {
    final trimmed = nullIfBlank(value);
    if (trimmed == null) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static int? _budgetFromReasoningEffort(
    AiModelConfig model,
    String? effort,
    int fallback,
  ) {
    if (effort == null) return null;
    final numeric = _positiveIntFromText(effort);
    if (numeric != null) return numeric;
    final profile = model.profileFor(model.modelId);
    final maximum = profile.maxThinkingLength;
    final high = maximum != null && maximum > 0
        ? maximum
        : math.max(fallback, _defaultThinkingBudget);
    return switch (effort) {
      'minimal' => _claudeMinimumBudget,
      'low' => math.max(_claudeMinimumBudget, fallback ~/ 2),
      'medium' => fallback,
      'high' => high,
      _ => null,
    };
  }

  static bool _usesGeminiThinkingLevel(AiModelConfig model) {
    final id = lowercaseStringFromValue(model.modelId);
    return id.startsWith('gemini-3') || id.contains('gemini-3');
  }

  static String _geminiThinkingLevel(String effort) {
    return switch (effort) {
      'minimal' => 'MINIMAL',
      'low' => 'LOW',
      'medium' => 'MEDIUM',
      'high' => 'HIGH',
      _ => effort,
    };
  }

  static bool _usesClaudeOutputEffort(AiModelConfig model) {
    if (model.protocolType == AiProtocolType.dots) return true;
    if (model.protocolType != AiProtocolType.claude &&
        !lowercaseStringFromValue(model.modelId).contains('claude')) {
      return false;
    }
    final id = lowercaseStringFromValue(model.modelId)
        .replaceAll(_modelIdSeparatorPattern, '-')
        .replaceAll(_modelIdRepeatedDashPattern, '-')
        .replaceAll(_modelIdEdgeDashPattern, '');
    return id.contains('opus-5') ||
        id.contains('5-opus') ||
        id.contains('sonnet-5') ||
        id.contains('5-sonnet') ||
        id.contains('fable-5') ||
        id.contains('5-fable') ||
        id.contains('mythos-5') ||
        id.contains('5-mythos') ||
        id.contains('mythos-preview') ||
        id.contains('opus-4-8') ||
        id.contains('4-8-opus') ||
        id.contains('opus-4-7') ||
        id.contains('4-7-opus') ||
        id.contains('opus-4-6') ||
        id.contains('4-6-opus') ||
        id.contains('opus-4-5') ||
        id.contains('4-5-opus') ||
        id.contains('sonnet-4-6') ||
        id.contains('4-6-sonnet');
  }

  static bool _usesAlwaysOnClaudeAdaptiveThinking(AiModelConfig model) {
    if (model.protocolType == AiProtocolType.dots) return false;
    if (model.protocolType != AiProtocolType.claude &&
        !lowercaseStringFromValue(model.modelId).contains('claude')) {
      return false;
    }
    final id = lowercaseStringFromValue(model.modelId)
        .replaceAll(_modelIdSeparatorPattern, '-')
        .replaceAll(_modelIdRepeatedDashPattern, '-')
        .replaceAll(_modelIdEdgeDashPattern, '');
    return id.contains('fable-5') ||
        id.contains('5-fable') ||
        id.contains('mythos-5') ||
        id.contains('5-mythos') ||
        id.contains('mythos-preview');
  }
}

enum AiChatRole { system, user, assistant, tool }

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;

  Map<String, Object?> toOpenAiJson() {
    return <String, Object?>{
      'id': id,
      'type': 'function',
      'function': <String, Object?>{'name': name, 'arguments': arguments},
    };
  }
}

class AiToolDefinition {
  const AiToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.strict,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
  final bool? strict;

  Map<String, Object?> toOpenAiJson() {
    return <String, Object?>{
      'type': 'function',
      'function': <String, Object?>{
        'name': name,
        'description': description,
        'parameters': parameters,
        if (strict != null) 'strict': strict,
      },
    };
  }

  /// Claude/Anthropic 工具格式，`input_schema` 等同于 OpenAI 的 `parameters`。
  Map<String, Object?> toClaudeJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'input_schema': parameters,
    };
  }
}

enum AiChatContentPartKind { text, imageFile, videoFile, audioFile }

class AiChatContentPart {
  const AiChatContentPart._({
    required this.kind,
    this.text,
    this.filePath,
    this.mimeType,
  });

  const AiChatContentPart.text(String value)
    : this._(kind: AiChatContentPartKind.text, text: value);

  const AiChatContentPart.imageFile({
    required String filePath,
    required String mimeType,
  }) : this._(
         kind: AiChatContentPartKind.imageFile,
         filePath: filePath,
         mimeType: mimeType,
       );

  const AiChatContentPart.videoFile({
    required String filePath,
    required String mimeType,
  }) : this._(
         kind: AiChatContentPartKind.videoFile,
         filePath: filePath,
         mimeType: mimeType,
       );

  const AiChatContentPart.audioFile({
    required String filePath,
    required String mimeType,
  }) : this._(
         kind: AiChatContentPartKind.audioFile,
         filePath: filePath,
         mimeType: mimeType,
       );

  final AiChatContentPartKind kind;
  final String? text;
  final String? filePath;
  final String? mimeType;
}

class AiChatTurn {
  const AiChatTurn({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls = const <AiToolCall>[],
    this.parts = const <AiChatContentPart>[],
    this.reasoningContent,
  });

  final AiChatRole role;
  final String content;
  final String? toolCallId;
  final List<AiToolCall> toolCalls;
  final List<AiChatContentPart> parts;

  /// 上一轮思考内容。部分思考模型要求后续请求原样回传，仅对助手消息有效。
  final String? reasoningContent;

  AiChatTurn copyWith({String? reasoningContent}) {
    return AiChatTurn(
      role: role,
      content: content,
      toolCallId: toolCallId,
      toolCalls: toolCalls,
      parts: parts,
      reasoningContent: reasoningContent ?? this.reasoningContent,
    );
  }

  String get roleName {
    return switch (role) {
      AiChatRole.system => 'system',
      AiChatRole.user => 'user',
      AiChatRole.assistant => 'assistant',
      AiChatRole.tool => 'tool',
    };
  }

  List<AiChatContentPart> get effectiveParts {
    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      return parts;
    }
    return <AiChatContentPart>[AiChatContentPart.text(content), ...parts];
  }

  int get promptCharacterCount {
    var total = content.length;
    for (final part in parts) {
      total += switch (part.kind) {
        AiChatContentPartKind.text => part.text?.length ?? 0,
        AiChatContentPartKind.imageFile => 64,
        AiChatContentPartKind.videoFile => 256,
        AiChatContentPartKind.audioFile => 128,
      };
    }
    return total;
  }
}

class AiRequestBlueprint {
  const AiRequestBlueprint({
    required this.url,
    required this.headers,
    required this.body,
  });

  final String url;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  AiRequestBlueprint copyWith({
    String? url,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) {
    return AiRequestBlueprint(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      body: body ?? this.body,
    );
  }
}

class _ProtocolSystemPartition {
  const _ProtocolSystemPartition({
    required this.leadingSystemContent,
    required this.conversationTurns,
  });

  final String leadingSystemContent;
  final List<AiChatTurn> conversationTurns;
}

enum AiPromptCacheAffinityKind {
  none('none'),
  grokConversationHeader('grok_conversation_header'),
  openRouterSession('openrouter_session'),
  openAiPromptCacheKey('openai_prompt_cache_key'),
  openAiCompatibleGateway('openai_compatible_gateway'),
  grokCompatibleGateway('grok_compatible_gateway');

  const AiPromptCacheAffinityKind(this.storageValue);

  final String storageValue;
}

class AiPromptCacheAffinity {
  const AiPromptCacheAffinity._({
    required this.kind,
    required this.id,
    required this.promptCacheKey,
  });

  static const AiPromptCacheAffinity none = AiPromptCacheAffinity._(
    kind: AiPromptCacheAffinityKind.none,
    id: '',
    promptCacheKey: '',
  );
  static const String grokConversationHeader = 'x-grok-conv-id';
  static const String standardSessionAffinityHeader = 'x-session-id';
  static const String openRouterSessionBodyField = 'session_id';
  static const String openAiPromptCacheKeyBodyField = 'prompt_cache_key';
  static const String messagesBodyField = 'messages';
  static const int _maxIdLength = 128;
  static const Set<String> _bodyMarkerFields = <String>{
    openRouterSessionBodyField,
    openAiPromptCacheKeyBodyField,
  };
  static const Set<String> _headerMarkerNames = <String>{
    grokConversationHeader,
    standardSessionAffinityHeader,
  };

  final AiPromptCacheAffinityKind kind;
  final String id;
  final String promptCacheKey;

  bool get applies {
    if (kind == AiPromptCacheAffinityKind.none) {
      return false;
    }
    return switch (kind) {
      AiPromptCacheAffinityKind.openAiPromptCacheKey =>
        _bodyPromptCacheKey.isNotEmpty,
      AiPromptCacheAffinityKind.openAiCompatibleGateway ||
      AiPromptCacheAffinityKind.grokCompatibleGateway =>
        id.isNotEmpty || _bodyPromptCacheKey.isNotEmpty,
      AiPromptCacheAffinityKind.openRouterSession ||
      AiPromptCacheAffinityKind.grokConversationHeader => id.isNotEmpty,
      AiPromptCacheAffinityKind.none => false,
    };
  }

  String get _bodyPromptCacheKey =>
      promptCacheKey.isNotEmpty ? promptCacheKey : id;

  static AiPromptCacheAffinity resolve({
    required AiModelConfig model,
    required AiInputCacheRuntimeConfig? inputCacheConfig,
  }) {
    final kind = kindForModel(model);
    if (kind == AiPromptCacheAffinityKind.none ||
        inputCacheConfig == null ||
        !inputCacheConfig.isEffectivelyEnabled) {
      return none;
    }
    final id = _normalizeId(inputCacheConfig.cacheAffinityId);
    final promptCacheKey = _normalizeId(inputCacheConfig.promptCacheKey);
    if (id.isEmpty && promptCacheKey.isEmpty) return none;
    return AiPromptCacheAffinity._(
      kind: kind,
      id: id,
      promptCacheKey: promptCacheKey,
    );
  }

  static AiPromptCacheAffinityKind kindForModel(AiModelConfig model) {
    if (model.apiDialect != AiApiDialect.openAiCompat) {
      return AiPromptCacheAffinityKind.none;
    }
    if (_isOpenRouterEndpoint(model.baseUrl)) {
      return AiPromptCacheAffinityKind.openRouterSession;
    }
    if (model.protocolType == AiProtocolType.grok ||
        _isXaiEndpoint(model.baseUrl)) {
      return AiPromptCacheAffinityKind.grokConversationHeader;
    }
    if (_modelIdLooksLikeGrok(model.modelId)) {
      return AiPromptCacheAffinityKind.grokCompatibleGateway;
    }
    if (_isOpenAiEndpoint(model.baseUrl)) {
      return AiPromptCacheAffinityKind.openAiPromptCacheKey;
    }
    if (model.providerKind == AiProviderKind.openai) {
      return AiPromptCacheAffinityKind.openAiCompatibleGateway;
    }
    if (_usesRemoteOpenAiCompatibleChatProtocol(model.protocolType)) {
      return AiPromptCacheAffinityKind.openAiCompatibleGateway;
    }
    return AiPromptCacheAffinityKind.none;
  }

  void applyToHeaders(Map<String, String> headers) {
    if (!applies) return;
    switch (kind) {
      case AiPromptCacheAffinityKind.grokConversationHeader:
        if (id.isNotEmpty) {
          _putHeaderIfAbsent(headers, grokConversationHeader, id);
        }
      case AiPromptCacheAffinityKind.grokCompatibleGateway:
        if (id.isNotEmpty) {
          // 同时设置 xAI 路由提示和标准会话头，避免轮询凭据破坏提示词缓存。
          _putHeaderIfAbsent(headers, grokConversationHeader, id);
          _putHeaderIfAbsent(headers, standardSessionAffinityHeader, id);
        }
      case AiPromptCacheAffinityKind.openAiCompatibleGateway:
        if (id.isNotEmpty) {
          // 固定第三方网关路由和上游缓存分区。
          _putHeaderIfAbsent(headers, standardSessionAffinityHeader, id);
        }
      case AiPromptCacheAffinityKind.openRouterSession:
        if (id.isNotEmpty) {
          _putHeaderIfAbsent(headers, standardSessionAffinityHeader, id);
        }
      case AiPromptCacheAffinityKind.openAiPromptCacheKey:
      case AiPromptCacheAffinityKind.none:
        break;
    }
  }

  Map<String, Object?> applyToBody(Map<String, Object?> body) {
    if (!applies) {
      return body;
    }
    switch (kind) {
      case AiPromptCacheAffinityKind.openRouterSession:
        if (id.isEmpty) return body;
        return putBodyFieldBeforeConversationInput(
          body,
          openRouterSessionBodyField,
          id,
        );
      case AiPromptCacheAffinityKind.openAiPromptCacheKey:
      case AiPromptCacheAffinityKind.openAiCompatibleGateway:
      case AiPromptCacheAffinityKind.grokCompatibleGateway:
        final bodyKey = _bodyPromptCacheKey;
        if (bodyKey.isEmpty) return body;
        return putBodyFieldBeforeConversationInput(
          body,
          openAiPromptCacheKeyBodyField,
          bodyKey,
        );
      case AiPromptCacheAffinityKind.grokConversationHeader:
      case AiPromptCacheAffinityKind.none:
        return body;
    }
  }

  static bool kindUsesBodyAffinityMarker(AiPromptCacheAffinityKind kind) {
    return switch (kind) {
      AiPromptCacheAffinityKind.openRouterSession ||
      AiPromptCacheAffinityKind.openAiPromptCacheKey ||
      AiPromptCacheAffinityKind.openAiCompatibleGateway ||
      AiPromptCacheAffinityKind.grokCompatibleGateway => true,
      AiPromptCacheAffinityKind.grokConversationHeader ||
      AiPromptCacheAffinityKind.none => false,
    };
  }

  static bool kindRequiresGatewayForwarding(AiPromptCacheAffinityKind kind) {
    return switch (kind) {
      AiPromptCacheAffinityKind.grokCompatibleGateway ||
      AiPromptCacheAffinityKind.openAiCompatibleGateway => true,
      AiPromptCacheAffinityKind.none ||
      AiPromptCacheAffinityKind.grokConversationHeader ||
      AiPromptCacheAffinityKind.openRouterSession ||
      AiPromptCacheAffinityKind.openAiPromptCacheKey => false,
    };
  }

  static bool requiresGatewayForwardingForModel(AiModelConfig model) {
    return kindRequiresGatewayForwarding(kindForModel(model));
  }

  static bool requestHasMarker({
    required Map<String, Object?> body,
    required Map<String, String>? headers,
  }) {
    return bodyHasMarker(body) || headersHaveMarker(headers);
  }

  static bool shouldRetryWithoutMarkers({
    required int statusCode,
    required String errorBody,
    required Map<String, Object?> requestBody,
    required Map<String, String>? requestHeaders,
  }) {
    if (statusCode < 400 || statusCode >= 500) {
      return false;
    }
    if (!requestHasMarker(body: requestBody, headers: requestHeaders)) {
      return false;
    }
    final normalized = errorBody.toLowerCase();
    final mentionsAffinityField =
        normalized.contains(openAiPromptCacheKeyBodyField) ||
        normalized.contains(openRouterSessionBodyField) ||
        normalized.contains(standardSessionAffinityHeader) ||
        normalized.contains(grokConversationHeader);
    if (mentionsAffinityField) {
      return normalized.contains('unknown') ||
          normalized.contains('unrecognized') ||
          normalized.contains('unsupported') ||
          normalized.contains('unexpected') ||
          normalized.contains('not allowed') ||
          normalized.contains('additional') ||
          normalized.contains('invalid');
    }
    if (statusCode != 400 && statusCode != 422) {
      return false;
    }
    return normalized.contains('invalid') ||
        normalized.contains('schema') ||
        normalized.contains('parameter') ||
        normalized.contains('field') ||
        normalized.contains('body') ||
        normalized.contains('request') ||
        normalized.contains('bad request') ||
        normalized.contains('unrecognized') ||
        normalized.contains('unsupported') ||
        normalized.contains('unexpected') ||
        normalized.contains('additional');
  }

  static bool bodyHasMarker(Map<String, Object?> body) {
    for (final field in _bodyMarkerFields) {
      if (body.containsKey(field)) {
        return true;
      }
    }
    return false;
  }

  static bool headersHaveMarker(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return false;
    }
    final markerNames = _headerMarkerNames
        .map((item) => item.toLowerCase())
        .toSet();
    return headers.keys.any((key) => markerNames.contains(key.toLowerCase()));
  }

  static Map<String, Object?> withoutBodyMarkers(Map<String, Object?> body) {
    if (!bodyHasMarker(body)) {
      return body;
    }
    final updated = <String, Object?>{};
    for (final entry in body.entries) {
      if (_bodyMarkerFields.contains(entry.key)) {
        continue;
      }
      updated[entry.key] = entry.value;
    }
    return updated;
  }

  static Map<String, String> withoutHeaderMarkers(Map<String, String> headers) {
    if (!headersHaveMarker(headers)) {
      return headers;
    }
    final markerNames = _headerMarkerNames
        .map((item) => item.toLowerCase())
        .toSet();
    final updated = <String, String>{};
    for (final entry in headers.entries) {
      if (markerNames.contains(entry.key.toLowerCase())) {
        continue;
      }
      updated[entry.key] = entry.value;
    }
    return updated;
  }

  static Map<String, Object?> withConversationInputLast(
    Map<String, Object?> body,
  ) {
    final field = body.containsKey(messagesBodyField)
        ? messagesBodyField
        : body.containsKey('input')
        ? 'input'
        : null;
    if (field == null) return body;
    final conversationInput = body[field];
    final updated = <String, Object?>{};
    for (final entry in body.entries) {
      if (entry.key == field) continue;
      updated[entry.key] = entry.value;
    }
    updated[field] = conversationInput;
    return updated;
  }

  static Map<String, Object?> putBodyFieldBeforeConversationInput(
    Map<String, Object?> body,
    String field,
    String value,
  ) {
    if (body.containsKey(field)) {
      return body;
    }
    final updated = <String, Object?>{};
    var inserted = false;
    for (final entry in body.entries) {
      if (!inserted &&
          (entry.key == messagesBodyField || entry.key == 'input')) {
        updated[field] = value;
        inserted = true;
      }
      updated[entry.key] = entry.value;
    }
    if (!inserted) {
      updated[field] = value;
    }
    return updated;
  }

  static void _putHeaderIfAbsent(
    Map<String, String> headers,
    String name,
    String value,
  ) {
    final lowerName = lowercaseStringFromValue(name);
    final hasExisting = headers.keys.any(
      (key) => lowercaseStringFromValue(key) == lowerName,
    );
    if (!hasExisting) {
      headers[name] = value;
    }
  }

  static String _endpointHost(String baseUrl) {
    final normalizedBaseUrl = nullIfBlank(baseUrl);
    if (normalizedBaseUrl == null) return '';
    return lowercaseStringFromValue(Uri.tryParse(normalizedBaseUrl)?.host);
  }

  static bool _isOpenRouterEndpoint(String baseUrl) {
    final host = _endpointHost(baseUrl);
    return host == 'openrouter.ai' || host.endsWith('.openrouter.ai');
  }

  static bool _isXaiEndpoint(String baseUrl) {
    final host = _endpointHost(baseUrl);
    return host == 'api.x.ai' || host.endsWith('.x.ai');
  }

  static bool _isOpenAiEndpoint(String baseUrl) {
    final host = _endpointHost(baseUrl);
    return host == 'api.openai.com' ||
        host.endsWith('.openai.com') ||
        host.endsWith('.openai.azure.com');
  }

  static bool _modelIdLooksLikeGrok(String modelId) {
    final normalized = lowercaseStringFromValue(modelId);
    return normalized == 'grok' ||
        normalized.startsWith('grok-') ||
        normalized.startsWith('x-ai/grok-') ||
        normalized.contains('/grok-');
  }

  static bool _usesRemoteOpenAiCompatibleChatProtocol(
    AiProtocolType protocolType,
  ) {
    return switch (protocolType) {
      AiProtocolType.openai ||
      AiProtocolType.dots ||
      AiProtocolType.deepseek ||
      AiProtocolType.qwen ||
      AiProtocolType.kimi ||
      AiProtocolType.glm ||
      AiProtocolType.seed ||
      AiProtocolType.stepfun ||
      AiProtocolType.minimax ||
      AiProtocolType.longcat ||
      AiProtocolType.agnes ||
      AiProtocolType.joycode ||
      AiProtocolType.wenxin ||
      AiProtocolType.meta ||
      AiProtocolType.mimo ||
      AiProtocolType.hunyuan => true,
      AiProtocolType.claude ||
      AiProtocolType.gemini ||
      AiProtocolType.grok ||
      AiProtocolType.ollama ||
      AiProtocolType.vllm ||
      AiProtocolType.sglang => false,
    };
  }

  static String _normalizeId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final buffer = StringBuffer();
    for (final codeUnit in trimmed.codeUnits) {
      final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
      final isUpper = codeUnit >= 0x41 && codeUnit <= 0x5A;
      final isLower = codeUnit >= 0x61 && codeUnit <= 0x7A;
      final isSafeSeparator =
          codeUnit == 0x2D ||
          codeUnit == 0x2E ||
          codeUnit == 0x3A ||
          codeUnit == 0x5F;
      if (isDigit || isUpper || isLower || isSafeSeparator) {
        buffer.writeCharCode(codeUnit);
      } else if (buffer.isNotEmpty && !buffer.toString().endsWith('-')) {
        buffer.write('-');
      }
      if (buffer.length >= _maxIdLength) {
        break;
      }
    }
    return buffer.toString().replaceAll(_markdownSeparatorTailPattern, '');
  }
}

/// OpenAI-compatible 缓存保留提示。策略只按协议能力统一启用，不读取线程
/// 模板、模型名称或用户问题；不创建显式缓存断点。
abstract final class AiPromptCacheRetentionPolicy {
  static const String bodyField = 'prompt_cache_retention';
  static const String extendedRetention = '24h';
  static const Duration rejectionCacheTtl = Duration(hours: 1);
  static const int rejectionCacheLimit = 64;
  static final Map<String, DateTime> _rejectedRequests = <String, DateTime>{};

  static Map<String, Object?> applyToBody({
    required AiModelConfig model,
    required AiInputCacheRuntimeConfig? inputCacheConfig,
    required Map<String, Object?> body,
  }) {
    final affinityKind = AiPromptCacheAffinity.kindForModel(model);
    if (model.apiDialect != AiApiDialect.openAiCompat ||
        !AiPromptCacheAffinity.kindUsesBodyAffinityMarker(affinityKind) ||
        inputCacheConfig == null ||
        !inputCacheConfig.isEffectivelyEnabled ||
        body.containsKey(bodyField)) {
      return body;
    }
    return AiPromptCacheAffinity.putBodyFieldBeforeConversationInput(
      body,
      bodyField,
      extendedRetention,
    );
  }

  static bool shouldRetryWithoutMarker({
    required int statusCode,
    required String errorBody,
    required Map<String, Object?> requestBody,
  }) {
    if ((statusCode != 400 && statusCode != 422) ||
        !requestBody.containsKey(bodyField)) {
      return false;
    }
    final normalized = errorBody.toLowerCase();
    if (!normalized.contains(bodyField) &&
        !normalized.contains('prompt cache retention')) {
      return false;
    }
    return normalized.contains('unknown') ||
        normalized.contains('unrecognized') ||
        normalized.contains('unsupported') ||
        normalized.contains('unexpected') ||
        normalized.contains('not allowed') ||
        normalized.contains('additional') ||
        normalized.contains('invalid');
  }

  static Map<String, Object?> withoutMarker(Map<String, Object?> body) {
    if (!body.containsKey(bodyField)) return body;
    return Map<String, Object?>.from(body)..remove(bodyField);
  }

  static bool wasRecentlyRejected({
    required String requestUrl,
    required Map<String, Object?> requestBody,
  }) {
    final key = _rejectionKey(requestUrl, requestBody);
    if (key.isEmpty) return false;
    final now = DateTime.now().toUtc();
    final expiresAt = _rejectedRequests[key];
    if (expiresAt == null) return false;
    if (expiresAt.isAfter(now)) return true;
    _rejectedRequests.remove(key);
    return false;
  }

  static void rememberRejection({
    required String requestUrl,
    required Map<String, Object?> requestBody,
  }) {
    final key = _rejectionKey(requestUrl, requestBody);
    if (key.isEmpty) return;
    final now = DateTime.now().toUtc();
    _rejectedRequests.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
    while (_rejectedRequests.length >= rejectionCacheLimit) {
      _rejectedRequests.remove(_rejectedRequests.keys.first);
    }
    _rejectedRequests[key] = now.add(rejectionCacheTtl);
  }

  static String _rejectionKey(
    String requestUrl,
    Map<String, Object?> requestBody,
  ) {
    final uri = Uri.tryParse(requestUrl);
    final modelId = '${requestBody['model'] ?? ''}'.trim().toLowerCase();
    if (uri == null || uri.host.isEmpty || modelId.isEmpty) return '';
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
        ':${uri.port}${uri.path}|$modelId';
  }
}

abstract class AiProtocolAdapter {
  const AiProtocolAdapter();

  static const String _runtimeContextEnvelopeStart =
      '<openhand_runtime_context>';
  static const String _runtimeContextEnvelopeEnd =
      '</openhand_runtime_context>';
  static const String _runtimeContextEnvelopeIntro =
      'OpenHand runtime context for this turn; follow it unless higher-priority instructions conflict.';

  static const AiEndpointRouter _endpointRouter = AiEndpointRouter();

  AiProtocolType get protocolType;

  String get endpointPath;

  String get streamEndpointPath => endpointPath;

  AiApiFamily get operationFamily => AiApiFamily.chatCompletions;

  bool get supportsServerStreaming => false;

  bool get supportsToolCalls => false;

  String describe(AiModelConfig model) {
    return '${protocolType.storageValue.toUpperCase()} · ${model.modelId}';
  }

  Future<AiRequestBlueprint> buildChatRequest({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final family = operationFamily;
    final endpoint = _endpointRouter.resolve(
      model,
      family,
      fallbackPath: stream ? streamEndpointPath : endpointPath,
      method: model.requestMethod,
    );
    final body = await buildBody(
      model,
      messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: stream,
      inputCacheConfig: inputCacheConfig,
    );
    final headers = buildHeaders(model, endpointHeaders: endpoint.headers);
    final cacheAffinity = AiPromptCacheAffinity.resolve(
      model: model,
      inputCacheConfig: inputCacheConfig,
    );
    cacheAffinity.applyToHeaders(headers);
    final bodyWithExtras = AiOperationHttp.mergeBodyExtras(model, family, body);
    final cacheAwareBody = AiPromptCacheAffinity.withConversationInputLast(
      AiPromptCacheRetentionPolicy.applyToBody(
        model: model,
        inputCacheConfig: inputCacheConfig,
        body: cacheAffinity.applyToBody(bodyWithExtras),
      ),
    );
    return AiRequestBlueprint(
      url: AiOperationHttp.uriWithExtraQuery(
        endpoint.url,
        model,
        family,
      ).toString(),
      headers: headers,
      body: cacheAwareBody,
    );
  }

  Map<String, String> buildHeaders(
    AiModelConfig model, {
    Map<String, String> endpointHeaders = const <String, String>{},
  }) {
    return AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpointHeaders,
      family: operationFamily,
    );
  }

  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  });

  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profileOverride = _profileInlineImageSupport(model);
    if (profileOverride != null) return profileOverride;
    return false;
  }

  _ProtocolSystemPartition _partitionLeadingSystemTurns(
    List<AiChatTurn> messages, {
    bool preserveToolExchangeSystemReminders = false,
  }) {
    final leadingSystemContent = <String>[];
    final conversationTurns = <AiChatTurn>[];
    var sawConversationTurn = false;
    for (var index = 0; index < messages.length; index += 1) {
      final turn = messages[index];
      if (!sawConversationTurn && turn.role == AiChatRole.system) {
        final content = nullIfBlank(turn.content);
        if (content != null) {
          leadingSystemContent.add(content);
        }
        continue;
      }
      if (turn.role == AiChatRole.system) {
        final content = nullIfBlank(turn.content);
        if (content != null) {
          if (preserveToolExchangeSystemReminders &&
              _isToolExchangeSystemReminder(
                messages,
                conversationTurns,
                index,
              )) {
            conversationTurns.add(turn);
          } else {
            conversationTurns.add(_runtimeSystemTurnAsUserContext(content));
          }
        }
        continue;
      }
      sawConversationTurn = true;
      conversationTurns.add(turn);
    }
    return _ProtocolSystemPartition(
      leadingSystemContent: leadingSystemContent.join('\n\n'),
      conversationTurns: conversationTurns,
    );
  }

  bool _isToolExchangeSystemReminder(
    List<AiChatTurn> messages,
    List<AiChatTurn> emittedTurns,
    int systemTurnIndex,
  ) {
    if (emittedTurns.isEmpty) return false;
    final previous = emittedTurns.last;
    if (previous.role != AiChatRole.assistant || previous.toolCalls.isEmpty) {
      return false;
    }
    final content = nullIfBlank(messages[systemTurnIndex].content) ?? '';
    if (!content.startsWith('# System Reminder')) {
      return false;
    }
    for (var index = systemTurnIndex + 1; index < messages.length; index += 1) {
      final next = messages[index];
      if (next.role == AiChatRole.system && nullIfBlank(next.content) == null) {
        continue;
      }
      return next.role == AiChatRole.tool;
    }
    return false;
  }

  AiChatTurn _runtimeSystemTurnAsUserContext(String content) {
    return AiChatTurn(
      role: AiChatRole.user,
      content:
          '$_runtimeContextEnvelopeStart\n$_runtimeContextEnvelopeIntro\n\n$content\n$_runtimeContextEnvelopeEnd',
    );
  }

  AiTokenUsage? parseUsage(String rawResponse) {
    return null;
  }

  List<AiToolCall> parseToolCalls(String rawResponse) {
    return const <AiToolCall>[];
  }

  /// 媒体附件的统一前置校验：路径或 MIME 缺失即视为无效附件，交由调用方跳过。
  ({String filePath, String mimeType})? _inlineMediaSource(
    AiChatContentPart part,
  ) {
    final filePath = (part.filePath ?? '').trim();
    final mimeType = (part.mimeType ?? '').trim();
    if (filePath.isEmpty || mimeType.isEmpty) return null;
    return (filePath: filePath, mimeType: mimeType);
  }

  Future<String> encodeFileAsDataUrl({
    required String filePath,
    required String mimeType,
    int maxBytes = aiMessageAttachmentMaxFileBytes,
  }) async {
    return 'data:$mimeType;base64,${await encodeFileAsBase64(filePath, maxBytes: maxBytes)}';
  }

  Future<String> encodeFileAsBase64(
    String filePath, {
    int maxBytes = aiMessageAttachmentMaxFileBytes,
  }) async {
    final bytes = await readBoundedFileBytes(
      File(filePath),
      maxBytes: maxBytes,
      idleTimeout: _inlineImageReadIdleTimeout,
      totalTimeout: _inlineImageReadTotalTimeout,
    );
    return base64Encode(bytes);
  }

  Future<String> parseAssistantMessage(String rawResponse);

  String extractErrorMessage(String rawResponse) {
    return extractApiErrorMessage(rawResponse, emptyFallback: '');
  }
}

bool? _profileInlineImageSupport(AiModelConfig model) {
  final profile = model.profileFor(model.modelId);
  if (profile.isMultimodal != null) {
    return profile.isMultimodal;
  }
  if (profile.supportedModalities.contains(AiModelModality.image)) {
    return true;
  }
  return null;
}

List<AiToolDefinition> stableToolDefinitionsForAiRequest(
  List<AiToolDefinition> tools,
) {
  // 保留工具目录的能力优先级，让专用工具排在通用命令工具之前。
  return tools.map(stableToolDefinitionForAiRequest).toList(growable: false);
}

int compareToolNamesForAiRequest(String left, String right) {
  final byName = normalizeAsciiLookupKey(
    left,
  ).compareTo(normalizeAsciiLookupKey(right));
  if (byName != 0) return byName;
  return left.compareTo(right);
}

AiToolDefinition stableToolDefinitionForAiRequest(AiToolDefinition tool) {
  return AiToolDefinition(
    name: tool.name,
    description: tool.description,
    parameters: stableJsonObjectForAiRequest(
      objectRootToolSchemaForAiRequest(tool.parameters),
    ),
    strict: tool.strict,
  );
}

/// 规范函数参数的对象约束，兼容会独立校验 anyOf/oneOf 分支的服务商。
Map<String, Object?> objectRootToolSchemaForAiRequest(
  Map<String, Object?> schema,
) {
  final normalized = Map<String, Object?>.from(schema)..['type'] = 'object';
  for (final keyword in const <String>['anyOf', 'oneOf']) {
    final rawBranches = normalized[keyword];
    if (rawBranches is! List) continue;

    final objectBranches = <Map<String, Object?>>[];
    for (final rawBranch in rawBranches) {
      if (rawBranch == false) continue;
      final branch = rawBranch is Map
          ? stringKeyedMapFromValue(rawBranch)
          : <String, Object?>{};
      final declaredType = branch['type'];
      final allowsObject =
          declaredType == null ||
          declaredType == 'object' ||
          (declaredType is List && declaredType.contains('object'));
      if (!allowsObject) continue;
      objectBranches.add(<String, Object?>{...branch, 'type': 'object'});
    }

    if (objectBranches.isEmpty) {
      normalized.remove(keyword);
    } else {
      normalized[keyword] = objectBranches;
    }
  }
  return normalized;
}

Map<String, Object?> stableJsonObjectForAiRequest(Map<String, Object?> value) {
  return Map<String, Object?>.unmodifiable(
    _stableJsonValue(value) as Map<String, Object?>,
  );
}

Object? _stableJsonValue(Object? value, {String? key}) {
  if (value is Map) {
    final entries = <MapEntry<String, Object?>>[];
    for (final entry in value.entries) {
      entries.add(
        MapEntry<String, Object?>(
          '${entry.key}',
          _stableJsonValue(entry.value, key: '${entry.key}'),
        ),
      );
    }
    entries.sort((left, right) => left.key.compareTo(right.key));
    return Map<String, Object?>.fromEntries(entries);
  }
  if (value is List) {
    if (key == 'required' && value.every((item) => item is String)) {
      final requiredNames = value.cast<String>().toList(growable: false)
        ..sort();
      return List<String>.unmodifiable(requiredNames);
    }
    return value.map((item) => _stableJsonValue(item)).toList(growable: false);
  }
  return value;
}

class OpenAiProtocolAdapter extends AiProtocolAdapter {
  const OpenAiProtocolAdapter(
    this.protocolType, {
    this.visionModelPatterns = const <String>[],
  });

  static const int _toolSequenceRepairSummaryMaxChars = 4000;
  static const int _messageMappingConcurrency = 4;
  static const String _systemReminderHeader = '# System Reminder';
  static const String _systemReminderTag = '[system_reminder]';
  static const String _toolExchangeRepairedTag = '[tool_exchange_repaired]';
  static const String _toolExchangeRepairTruncatedTag =
      '[tool_exchange_repair_truncated]';
  static const String _orphanToolResultTag = '[orphan_tool_result]';

  @override
  final AiProtocolType protocolType;

  /// 用于判断模型是否支持内联图片的模型标识子串。
  final List<String> visionModelPatterns;

  @override
  String get endpointPath => 'v1/chat/completions';

  @override
  bool get supportsServerStreaming => true;

  @override
  bool get supportsToolCalls => true;

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final stableTools = stableToolDefinitionsForAiRequest(tools);
    final systemPartition = _partitionLeadingSystemTurns(
      messages,
      preserveToolExchangeSystemReminders: true,
    );
    final normalizedTurns = <AiChatTurn>[
      if (systemPartition.leadingSystemContent.isNotEmpty)
        AiChatTurn(
          role: AiChatRole.system,
          content: systemPartition.leadingSystemContent,
        ),
      ...systemPartition.conversationTurns,
    ];
    final requestMessages =
        await runOrderedWithConcurrencyLimit<Map<String, Object?>>(
          itemCount: normalizedTurns.length,
          maxConcurrency: _messageMappingConcurrency,
          task: (index) => _mapOpenAiMessage(normalizedTurns[index]),
        );
    // 多数兼容端点仅接受开头的一条系统消息，运行时状态转为用户侧上下文。
    final mergedMessages = _repairOpenAiToolMessageSequence(
      _mergeConsecutiveSystemMessages(requestMessages),
    );
    final body = <String, Object?>{
      'model': model.resolveOperationModelId(operationFamily),
      if (model.maxTokens != null) 'max_tokens': model.maxTokens,
      if (model.temperature != null) 'temperature': model.temperature,
      if (stream) 'stream': true,
      // 显式请求流式 usage，确保缓存命中和写入统计完整。
      if (stream)
        'stream_options': const <String, Object?>{'include_usage': true},
      if (stableTools.isNotEmpty)
        'tools': stableTools
            .map((item) => item.toOpenAiJson())
            .toList(growable: false),
      if (stableTools.isNotEmpty) 'tool_choice': 'auto',
      'messages': mergedMessages,
    };
    AiThinkingRequestPolicy.applyOpenAiCompatible(body, model);
    return body;
  }

  @override
  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profileOverride = _profileInlineImageSupport(model);
    if (profileOverride != null) return profileOverride;
    return _containsAny(model.modelId, visionModelPatterns);
  }

  Future<Map<String, Object?>> _mapOpenAiMessage(AiChatTurn item) async {
    final payload = <String, Object?>{'role': item.roleName};
    if (item.role == AiChatRole.tool) {
      payload[aiSessionMessageToolCallIdMetadataKey] = item.toolCallId ?? '';
      payload['content'] = item.content;
      return payload;
    }
    final contentParts = item.effectiveParts;
    if (contentParts.isNotEmpty &&
        contentParts.any((part) => part.kind != AiChatContentPartKind.text)) {
      payload['content'] = await _mapOpenAiContentParts(contentParts);
    } else {
      payload['content'] = contentParts.isEmpty
          ? item.content
          : contentParts.map((part) => part.text ?? '').join('\n\n').trim();
    }
    if (item.role == AiChatRole.assistant && item.toolCalls.isNotEmpty) {
      payload['tool_calls'] = item.toolCalls
          .map((toolCall) => toolCall.toOpenAiJson())
          .toList(growable: false);
    }
    if (item.role == AiChatRole.assistant) {
      final reasoning = item.reasoningContent;
      if (reasoning != null && reasoning.isNotEmpty) {
        // 部分思考模型要求后续请求回传上一轮 reasoning_content。
        payload['reasoning_content'] = reasoning;
      }
    }
    return payload;
  }

  Future<List<Map<String, Object?>>> _mapOpenAiContentParts(
    List<AiChatContentPart> parts,
  ) async {
    final payload = <Map<String, Object?>>[];
    final inlineMaxBytes = protocolType == AiProtocolType.mimo
        ? aiMimoUnderstandingMaxRawBytes
        : aiMessageAttachmentMaxFileBytes;
    for (final part in parts) {
      switch (part.kind) {
        case AiChatContentPartKind.text:
          final text = (part.text ?? '').trim();
          if (text.isEmpty) {
            continue;
          }
          payload.add(<String, Object?>{'type': 'text', 'text': text});
        case AiChatContentPartKind.imageFile:
        case AiChatContentPartKind.videoFile:
          final media = _inlineMediaSource(part);
          if (media == null) {
            continue;
          }
          final urlKey = part.kind == AiChatContentPartKind.videoFile
              ? 'video_url'
              : 'image_url';
          payload.add(<String, Object?>{
            'type': urlKey,
            urlKey: <String, Object?>{
              'url': await encodeFileAsDataUrl(
                filePath: media.filePath,
                mimeType: media.mimeType,
                maxBytes: inlineMaxBytes,
              ),
              'detail': protocolType == AiProtocolType.minimax
                  ? 'default'
                  : 'auto',
            },
          });
        case AiChatContentPartKind.audioFile:
          final media = _inlineMediaSource(part);
          if (media == null) {
            continue;
          }
          if (protocolType == AiProtocolType.dots) {
            payload.add(<String, Object?>{
              'type': 'audio_url',
              'audio_url': <String, Object?>{
                'url': await encodeFileAsDataUrl(
                  filePath: media.filePath,
                  mimeType: media.mimeType,
                  maxBytes: inlineMaxBytes,
                ),
              },
            });
          } else {
            payload.add(<String, Object?>{
              'type': 'input_audio',
              'input_audio': <String, Object?>{
                if (protocolType == AiProtocolType.mimo)
                  'data': await encodeFileAsDataUrl(
                    filePath: media.filePath,
                    mimeType: media.mimeType,
                    maxBytes: inlineMaxBytes,
                  )
                else ...<String, Object?>{
                  'data': await encodeFileAsBase64(media.filePath),
                  'format': _audioFormatForMimeType(media.mimeType),
                },
              },
            });
          }
      }
    }
    return payload;
  }

  static List<Map<String, Object?>> _repairOpenAiToolMessageSequence(
    List<Map<String, Object?>> messages,
  ) {
    if (messages.length <= 1) return messages;
    final repaired = <Map<String, Object?>>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      if (_isAssistantToolCallMessage(message)) {
        final assistantMessages = <Map<String, Object?>>[];
        final groupedToolCalls = <Map<String, Object?>>[];
        final groupedToolCallIds = <String>[];
        final seenToolCallIds = <String>{};
        while (index < messages.length &&
            _isAssistantToolCallMessage(messages[index])) {
          final assistantMessage = messages[index];
          assistantMessages.add(assistantMessage);
          for (final toolCall in _openAiToolCalls(assistantMessage)) {
            final toolCallId = _openAiToolCallId(toolCall);
            if (toolCallId.isEmpty || !seenToolCallIds.add(toolCallId)) {
              continue;
            }
            groupedToolCalls.add(toolCall);
            groupedToolCallIds.add(toolCallId);
          }
          index += 1;
        }
        if (groupedToolCalls.isEmpty) {
          repaired.add(
            _assistantSummaryForIncompleteToolExchange(
              assistantMessages: assistantMessages,
              toolCalls: const <Map<String, Object?>>[],
              missingToolCallIds: const <String>[],
              toolMessages: const <Map<String, Object?>>[],
              systemReminders: const <String>[],
            ),
          );
          continue;
        }

        final toolMessagesById = <String, Map<String, Object?>>{};
        final orphanToolMessages = <Map<String, Object?>>[];
        final systemReminders = <String>[];
        final expectedToolCallIds = groupedToolCallIds.toSet();
        while (index < messages.length) {
          final next = messages[index];
          if (_isSystemReminderMessage(next)) {
            systemReminders.add(_systemReminderText(next));
            index += 1;
            continue;
          }
          if (_messageRole(next) != 'tool') {
            break;
          }
          final toolCallId =
              '${next[aiSessionMessageToolCallIdMetadataKey] ?? ''}'.trim();
          if (expectedToolCallIds.contains(toolCallId) &&
              !toolMessagesById.containsKey(toolCallId)) {
            toolMessagesById[toolCallId] = next;
          } else {
            orphanToolMessages.add(next);
          }
          index += 1;
        }

        final missingToolCallIds = groupedToolCallIds
            .where((toolCallId) => !toolMessagesById.containsKey(toolCallId))
            .toList(growable: false);
        if (missingToolCallIds.isNotEmpty) {
          repaired.add(
            _assistantSummaryForIncompleteToolExchange(
              assistantMessages: assistantMessages,
              toolCalls: groupedToolCalls,
              missingToolCallIds: missingToolCallIds,
              toolMessages: <Map<String, Object?>>[
                ...toolMessagesById.values,
                ...orphanToolMessages,
              ],
              systemReminders: systemReminders,
            ),
          );
          continue;
        }

        repaired.add(
          _mergedAssistantToolCallMessage(assistantMessages, groupedToolCalls),
        );
        var remindersAttached = false;
        for (final toolCallId in groupedToolCallIds) {
          var toolMessage = Map<String, Object?>.from(
            toolMessagesById[toolCallId]!,
          );
          if (!remindersAttached && systemReminders.isNotEmpty) {
            toolMessage = _appendSystemRemindersToToolMessage(
              toolMessage,
              systemReminders,
            );
            remindersAttached = true;
          }
          repaired.add(toolMessage);
        }
        for (final orphan in orphanToolMessages) {
          repaired.add(_assistantSummaryForOrphanToolMessage(orphan));
        }
        continue;
      }

      if (_messageRole(message) == 'tool') {
        repaired.add(_assistantSummaryForOrphanToolMessage(message));
        index += 1;
        continue;
      }
      repaired.add(message);
      index += 1;
    }
    return repaired;
  }

  static bool _isAssistantToolCallMessage(Map<String, Object?> message) {
    return _messageRole(message) == 'assistant' &&
        _openAiToolCalls(message).isNotEmpty;
  }

  static String _messageRole(Map<String, Object?> message) {
    return _trimmedField(message, 'role');
  }

  static List<Map<String, Object?>> _openAiToolCalls(
    Map<String, Object?> message,
  ) {
    return _mapListFromObject(message['tool_calls']);
  }

  static String _openAiToolCallId(Map<String, Object?> toolCall) {
    return _trimmedField(toolCall, 'id');
  }

  static bool _isSystemReminderMessage(Map<String, Object?> message) {
    return _messageRole(message) == 'system' &&
        _trimmedField(message, 'content').startsWith(_systemReminderHeader);
  }

  static String _systemReminderText(Map<String, Object?> message) {
    final content = _trimmedField(message, 'content');
    final body = content.startsWith(_systemReminderHeader)
        ? content.substring(_systemReminderHeader.length).trim()
        : content;
    return body.isEmpty ? _systemReminderTag : '$_systemReminderTag $body';
  }

  static Map<String, Object?> _mergedAssistantToolCallMessage(
    List<Map<String, Object?>> assistantMessages,
    List<Map<String, Object?>> toolCalls,
  ) {
    final merged = Map<String, Object?>.from(assistantMessages.first);
    final content = assistantMessages
        .map((message) => _trimmedField(message, 'content'))
        .where((item) => item.isNotEmpty)
        .join('\n\n');
    merged['content'] = content;
    merged['tool_calls'] = toolCalls;
    final reasoning = _mergedAssistantReasoningContent(assistantMessages);
    if (reasoning != null) {
      merged['reasoning_content'] = reasoning;
    } else {
      merged.remove('reasoning_content');
    }
    return merged;
  }

  static Map<String, Object?> _appendSystemRemindersToToolMessage(
    Map<String, Object?> toolMessage,
    List<String> systemReminders,
  ) {
    final content = _trimmedField(toolMessage, 'content');
    toolMessage['content'] = <String>[
      if (content.isNotEmpty) content,
      ...systemReminders.where((item) => nullIfBlank(item) != null),
    ].join('\n\n');
    return toolMessage;
  }

  static Map<String, Object?> _assistantSummaryForIncompleteToolExchange({
    required List<Map<String, Object?>> assistantMessages,
    required List<Map<String, Object?>> toolCalls,
    required List<String> missingToolCallIds,
    required List<Map<String, Object?>> toolMessages,
    required List<String> systemReminders,
  }) {
    final lines = <String>[
      _toolExchangeRepairedTag,
      if (missingToolCallIds.isNotEmpty)
        'missing_tool_call_ids: ${missingToolCallIds.join(', ')}',
      for (final message in assistantMessages)
        if (_trimmedField(message, 'content').isNotEmpty)
          _trimmedField(message, 'content'),
      for (final toolCall in toolCalls)
        'Tool call: ${_openAiToolCallName(toolCall)} (${_openAiToolCallId(toolCall)})',
      ...systemReminders,
      for (final toolMessage in toolMessages)
        _orphanToolMessageText(toolMessage),
    ];
    return _assistantTextMessage(
      lines.join('\n'),
      reasoningContent: _mergedAssistantReasoningContent(assistantMessages),
    );
  }

  static Map<String, Object?> _assistantSummaryForOrphanToolMessage(
    Map<String, Object?> toolMessage,
  ) {
    return _assistantTextMessage(_orphanToolMessageText(toolMessage));
  }

  static String _openAiToolCallName(Map<String, Object?> toolCall) {
    final function = optionalStringKeyedMapFromValue(toolCall['function']);
    if (function == null) return 'tool';
    final name = _trimmedField(function, 'name');
    return name.isEmpty ? 'tool' : name;
  }

  static String _orphanToolMessageText(Map<String, Object?> toolMessage) {
    final toolCallId = _trimmedField(
      toolMessage,
      aiSessionMessageToolCallIdMetadataKey,
    );
    final content = _trimmedField(toolMessage, 'content');
    return <String>[
      _orphanToolResultTag,
      if (toolCallId.isNotEmpty) 'tool_call_id: $toolCallId',
      if (content.isNotEmpty) content,
    ].join('\n');
  }

  static Map<String, Object?> _assistantTextMessage(
    String content, {
    String? reasoningContent,
  }) {
    final message = <String, Object?>{
      'role': 'assistant',
      'content': _boundedRepairSummary(content),
    };
    final reasoning = reasoningContent?.trim();
    if (reasoning != null && reasoning.isNotEmpty) {
      message['reasoning_content'] = reasoning;
    }
    return message;
  }

  static String? _mergedAssistantReasoningContent(
    List<Map<String, Object?>> assistantMessages,
  ) {
    final seen = <String>{};
    final parts = <String>[];
    for (final message in assistantMessages) {
      final reasoning = _trimmedField(message, 'reasoning_content');
      if (reasoning.isEmpty || !seen.add(reasoning)) {
        continue;
      }
      parts.add(reasoning);
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join('\n\n');
  }

  static String _boundedRepairSummary(String value) {
    final trimmed = nullIfBlank(value) ?? '';
    if (trimmed.length <= _toolSequenceRepairSummaryMaxChars) return trimmed;
    return clipTextByCodeUnits(
      trimmed,
      _toolSequenceRepairSummaryMaxChars,
      suffix: '\n$_toolExchangeRepairTruncatedTag',
    );
  }

  static String _trimmedField(Map<String, Object?> map, String key) {
    return stringFromValue(map[key]);
  }

  static List<Map<String, Object?>> _mapListFromObject(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    final maps = <Map<String, Object?>>[];
    for (final item in value) {
      final map = optionalStringKeyedMapFromValue(item);
      if (map != null) maps.add(map);
    }
    return maps;
  }

  /// 合并连续系统消息，兼容仅接受单条系统消息的端点。
  static List<Map<String, Object?>> _mergeConsecutiveSystemMessages(
    List<Map<String, Object?>> messages,
  ) {
    if (messages.length <= 1) return messages;
    final result = <Map<String, Object?>>[];
    StringBuffer? pendingSystem;
    for (final msg in messages) {
      if (msg['role'] == 'system' && msg['content'] is String) {
        pendingSystem ??= StringBuffer();
        if (pendingSystem.isNotEmpty) pendingSystem.write('\n\n');
        pendingSystem.write(msg['content'] as String);
      } else {
        if (pendingSystem != null) {
          result.add(<String, Object?>{
            'role': 'system',
            'content': pendingSystem.toString(),
          });
          pendingSystem = null;
        }
        result.add(msg);
      }
    }
    if (pendingSystem != null) {
      result.add(<String, Object?>{
        'role': 'system',
        'content': pendingSystem.toString(),
      });
    }
    return result;
  }

  @override
  AiTokenUsage? parseUsage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final usage = decoded['usage'];
    if (usage is! Map && usage is! Map<String, Object?>) {
      return null;
    }
    final usageMap = usage is Map<String, Object?>
        ? usage
        : stringKeyedMapFromValue(usage);
    return AiTokenUsageParser.parseOpenAi(usageMap);
  }

  @override
  Future<String> parseAssistantMessage(String rawResponse) async {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Unexpected response payload.');
    }
    try {
      AiOperationHttp.throwIfProviderFailed(
        decoded,
        contextHint: 'chat/completions',
      );
    } catch (error) {
      throw FormatException('$error'.replaceFirst('Exception: ', ''));
    }
    final choices = decoded['choices'];
    if (choices is! List<dynamic> || choices.isEmpty) {
      throw const FormatException('Missing response choices.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, Object?>) {
      throw const FormatException('Unexpected choice payload.');
    }
    final message = firstChoice['message'];
    if (message is! Map<String, Object?>) {
      throw const FormatException('Missing response message.');
    }

    final content = message['content'];
    final contentText = await _extractOpenAiContentWithMediaSafe(content);
    if (contentText.isNotEmpty) {
      return contentText;
    }

    // 部分推理模型会把 DSML 工具调用放入 reasoning_content。
    final reasoningContent = message['reasoning_content'];
    if (reasoningContent != null) {
      final reasoningText = await _extractOpenAiContentWithMediaSafe(
        reasoningContent,
      );
      if (reasoningText.isNotEmpty) {
        return reasoningText;
      }
    }

    // 原生工具调用存在时允许文本为空。
    final toolCalls = message['tool_calls'];
    if (toolCalls is List && toolCalls.isNotEmpty) {
      return '';
    }

    throw const FormatException('Empty assistant response text.');
  }

  @override
  List<AiToolCall> parseToolCalls(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return const <AiToolCall>[];
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      return const <AiToolCall>[];
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      return const <AiToolCall>[];
    }
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List) {
      return const <AiToolCall>[];
    }
    return toolCalls
        .map((item) {
          if (item is! Map) {
            return null;
          }
          final toolCallMap = stringKeyedMapFromValue(item);
          final function = toolCallMap['function'];
          if (function is! Map) {
            return null;
          }
          final functionMap = stringKeyedMapFromValue(function);
          final id = optionalStringFromValue(toolCallMap['id']);
          final name = optionalStringFromValue(functionMap['name']);
          if (id == null || name == null) {
            return null;
          }
          // 部分兼容服务直接返回 Map/List；统一编码为 JSON，避免 Dart 调试文本
          // 进入后续工具参数解析。
          final argsValue = functionMap['arguments'];
          final String arguments;
          if (argsValue is String) {
            arguments = argsValue;
          } else if (argsValue == null) {
            arguments = '';
          } else if (argsValue is Map || argsValue is List) {
            arguments = jsonEncode(argsValue);
          } else {
            arguments = '$argsValue';
          }
          return AiToolCall(id: id, name: name, arguments: arguments);
        })
        .whereType<AiToolCall>()
        .toList(growable: false);
  }
}

/// 小米 MiMo 仅接受 OpenAI 字段的严格子集，因此单独规范请求。
void _validateMimoModelId(AiModelConfig model) {
  if (!lowercaseStringFromValue(model.modelId).contains('mimo-v2.5')) {
    throw ArgumentError.value(
      model.modelId,
      'modelId',
      'MiMo official API only supports the V2.5 model family.',
    );
  }
}

const Set<String> _mimoImageMimeTypes = <String>{
  kImageJpegMimeType,
  kImagePngMimeType,
  kImageGifMimeType,
  kImageWebpMimeType,
  kImageBmpMimeType,
};
const Set<String> _mimoAudioExtensions = <String>{
  '.mp3',
  '.wav',
  '.flac',
  '.m4a',
  '.ogg',
};
const Set<String> _mimoAsrExtensions = <String>{'.mp3', '.wav'};
const int _mimoAsrMaxBase64Bytes = 10 * kBytesPerMiB;
const int aiMimoUnderstandingMaxBase64Bytes = 50 * kBytesPerMiB;
const int aiMimoUnderstandingMaxRawBytes =
    (aiMimoUnderstandingMaxBase64Bytes ~/ 4) * 3;
const Duration _mimoMediaValidationIdleTimeout = Duration(seconds: 3);
const Duration _mimoMediaValidationTotalTimeout = Duration(seconds: 10);
const Set<String> _mimoVideoExtensions = <String>{
  '.mp4',
  '.mov',
  '.avi',
  '.wmv',
};

enum AiMimoMediaSurface { chat, anthropic, responses }

Future<void> validateMimoContentParts(
  AiModelConfig model,
  List<AiChatTurn> messages, {
  AiMimoMediaSurface surface = AiMimoMediaSurface.chat,
}) async {
  final asrModel = lowercaseStringFromValue(model.modelId) == 'mimo-v2.5-asr';
  final imagesOnly = surface != AiMimoMediaSurface.chat;
  final asrAudioInput = asrModel && !imagesOnly;
  final supportsAttachments =
      model.profileFor(model.modelId).supportsAttachments != false;
  final deadline = MonotonicDeadline(
    _mimoMediaValidationTotalTimeout,
    timeoutMessage: 'MiMo 媒体校验超过总时限。',
  );
  Duration nextOperationTimeout() =>
      deadline.limit(_mimoMediaValidationIdleTimeout);

  for (final part in messages.expand((message) => message.effectiveParts)) {
    if (part.kind == AiChatContentPartKind.text) continue;
    if (!supportsAttachments && surface != AiMimoMediaSurface.responses) {
      throw ArgumentError.value(
        model.modelId,
        'modelId',
        'This MiMo model does not support media input.',
      );
    }
    final mimeType = lowercaseStringFromValue(part.mimeType);
    final extension = p.extension(part.filePath ?? '').toLowerCase();
    final supported = surface == AiMimoMediaSurface.responses
        ? supportsAttachments &&
              part.kind == AiChatContentPartKind.imageFile &&
              _mimoImageMimeTypes.contains(mimeType)
        : asrAudioInput
        ? part.kind == AiChatContentPartKind.audioFile &&
              _mimoAsrExtensions.contains(extension)
        : switch (part.kind) {
            AiChatContentPartKind.imageFile => _mimoImageMimeTypes.contains(
              mimeType,
            ),
            AiChatContentPartKind.audioFile =>
              !imagesOnly && _mimoAudioExtensions.contains(extension),
            AiChatContentPartKind.videoFile =>
              !imagesOnly && _mimoVideoExtensions.contains(extension),
            AiChatContentPartKind.text => true,
          };
    if (!supported) {
      throw ArgumentError.value(part.filePath, 'filePath', switch (surface) {
        AiMimoMediaSurface.anthropic =>
          'MiMo Anthropic API only supports JPEG, PNG, GIF, WebP, and BMP images.',
        AiMimoMediaSurface.responses =>
          'MiMo Responses API only supports JPEG, PNG, GIF, WebP, and BMP image input.',
        AiMimoMediaSurface.chat => 'Unsupported MiMo media format.',
      });
    }
    final filePath = nullIfBlank(part.filePath);
    if (filePath != null) {
      final file = File(filePath);
      final type = await FileSystemEntity.type(
        filePath,
        followLinks: false,
      ).timeout(nextOperationTimeout());
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file) {
        throw ArgumentError.value(
          filePath,
          'filePath',
          'MiMo media input must be a regular file.',
        );
      }
      final stat = await file.stat().timeout(nextOperationTimeout());
      if (!isRegularFileStat(stat)) {
        throw ArgumentError.value(
          filePath,
          'filePath',
          'MiMo media input must be a regular file.',
        );
      }
      final rawBytes = stat.size;
      if (rawBytes <= 0) {
        throw ArgumentError.value(
          filePath,
          'filePath',
          surface == AiMimoMediaSurface.responses
              ? 'MiMo image input cannot be empty.'
              : 'MiMo media input cannot be empty.',
        );
      }
      final maxBase64Bytes = asrAudioInput
          ? _mimoAsrMaxBase64Bytes
          : aiMimoUnderstandingMaxBase64Bytes;
      final encodedBytes = ((rawBytes + 2) ~/ 3) * 4;
      if (encodedBytes > maxBase64Bytes) {
        throw ArgumentError.value(
          filePath,
          'filePath',
          surface == AiMimoMediaSurface.responses
              ? 'MiMo image Base64 payload exceeds 50 MB.'
              : asrAudioInput
              ? 'MiMo ASR Base64 payload exceeds 10 MB.'
              : 'MiMo multimodal Base64 payload exceeds 50 MB.',
        );
      }
    }
  }
  deadline.stop();
}

class MimoOpenAiProtocolAdapter extends OpenAiProtocolAdapter {
  const MimoOpenAiProtocolAdapter()
    : super(
        AiProtocolType.mimo,
        visionModelPatterns: const <String>['mimo-v2.5'],
      );

  static const String _webSearchExtraKey = 'mimo_web_search';
  static const String _videoExtraKey = 'mimo_video';

  static bool _isAsrModel(AiModelConfig model) =>
      lowercaseStringFromValue(model.modelId) == 'mimo-v2.5-asr';

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    _validateMimoModelId(model);
    final requestMessages = _isAsrModel(model)
        ? _asrMessages(messages)
        : messages;
    await validateMimoContentParts(model, requestMessages);
    final body = await super.buildBody(
      model,
      requestMessages,
      tools: tools,
      responseModalities: responseModalities,
      stream: stream,
      inputCacheConfig: inputCacheConfig,
    );
    _normalizeBody(body, model);
    return body;
  }

  @override
  Future<AiRequestBlueprint> buildChatRequest({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final request = await super.buildChatRequest(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: stream,
      inputCacheConfig: inputCacheConfig,
    );
    final body = Map<String, Object?>.from(request.body);
    final videoOptions = _videoOptions(body.remove(_videoExtraKey));
    _normalizeBody(
      body,
      model,
      videoFps: videoOptions.$1,
      videoResolution: videoOptions.$2,
    );
    final searchConfig = body.remove(_webSearchExtraKey);
    final webSearch = _webSearchTool(searchConfig);
    if (webSearch != null) {
      final existingTools = body['tools'] is List
          ? List<Object?>.from(body['tools']! as List)
          : <Object?>[];
      existingTools.add(webSearch);
      body['tools'] = existingTools;
      body['tool_choice'] = 'auto';
    }
    return request.copyWith(body: body);
  }

  static void _normalizeBody(
    Map<String, Object?> body,
    AiModelConfig model, {
    double videoFps = 2,
    String videoResolution = 'default',
  }) {
    if (_isAsrModel(model)) {
      final asrOptions = body['asr_options'] is Map
          ? stringKeyedMapFromValue(body['asr_options'])
          : <String, Object?>{'language': 'auto'};
      final language = lowercaseStringFromValue(
        asrOptions['language'],
        fallback: 'auto',
      );
      if (language != 'auto' && language != 'zh' && language != 'en') {
        throw ArgumentError.value(
          language,
          'asr_options.language',
          'MiMo ASR language must be auto, zh, or en.',
        );
      }
      body
        ..removeWhere(
          (key, _) =>
              key != 'model' &&
              key != 'messages' &&
              key != 'stream' &&
              key != 'asr_options',
        )
        ..['asr_options'] = <String, Object?>{'language': language};
      return;
    }
    final maxTokens = body.remove('max_tokens');
    if (maxTokens != null && body['max_completion_tokens'] == null) {
      body['max_completion_tokens'] = maxTokens;
    }
    body.remove('stream_options');
    body.remove('reasoning_effort');
    AiThinkingRequestPolicy.applyMimoThinking(body, model);
    _normalizeResponseFormat(body);
    if (body['tools'] is List && (body['tools']! as List).isNotEmpty) {
      body['tool_choice'] = 'auto';
    } else {
      body.remove('tool_choice');
    }
    _normalizeVideoParts(
      body['messages'],
      fps: videoFps,
      mediaResolution: videoResolution,
    );
  }

  static void _normalizeResponseFormat(Map<String, Object?> body) {
    final raw = body['response_format'];
    if (raw == null) return;
    if (raw is! Map) {
      throw ArgumentError.value(
        raw,
        'response_format',
        'MiMo response_format must be an object.',
      );
    }
    final type = lowercaseStringFromValue(raw['type']);
    if (type == 'json_schema') {
      body['response_format'] = const <String, Object?>{'type': 'json_object'};
      return;
    }
    if (type != 'text' && type != 'json_object') {
      throw ArgumentError.value(
        raw['type'],
        'response_format.type',
        'MiMo only supports text and json_object response formats.',
      );
    }
    body['response_format'] = <String, Object?>{'type': type};
  }

  static List<AiChatTurn> _asrMessages(List<AiChatTurn> messages) {
    final audioParts = messages
        .where((message) => message.role == AiChatRole.user)
        .expand((message) => message.effectiveParts)
        .where((part) => part.kind == AiChatContentPartKind.audioFile)
        .toList(growable: false);
    if (audioParts.length != 1) {
      throw ArgumentError.value(
        audioParts.length,
        'messages',
        'MiMo ASR requires exactly one MP3 or WAV audio input.',
      );
    }
    return <AiChatTurn>[
      AiChatTurn(role: AiChatRole.user, content: '', parts: audioParts),
    ];
  }

  static (double, String) _videoOptions(Object? raw) {
    if (raw == null) return (2, 'default');
    if (raw is! Map) {
      throw ArgumentError.value(raw, _videoExtraKey, 'Expected an object.');
    }
    final config = stringKeyedMapFromValue(raw);
    final fps = optionalDoubleFromValue(config['fps']) ?? 2;
    final mediaResolution = lowercaseStringFromValue(
      config['media_resolution'],
      fallback: 'default',
    );
    if (!fps.isFinite || fps < 0.1 || fps > 10) {
      throw ArgumentError.value(fps, 'fps', 'MiMo video fps must be 0.1–10.');
    }
    if (mediaResolution != 'default' && mediaResolution != 'max') {
      throw ArgumentError.value(
        mediaResolution,
        'media_resolution',
        'MiMo video resolution must be default or max.',
      );
    }
    return (fps, mediaResolution);
  }

  @override
  Future<String> parseAssistantMessage(String rawResponse) async {
    final text = await super.parseAssistantMessage(rawResponse);
    final citations = _mimoCitations(rawResponse);
    final warning = _mimoWebSearchWarning(rawResponse);
    return trimmedNonEmptyStrings(<String?>[
      text,
      if (warning != null) '> 联网搜索提示：$warning',
      if (citations.isNotEmpty)
        <String>['### Sources', ...citations].join('\n'),
    ]).join('\n\n');
  }

  static void _normalizeVideoParts(
    Object? rawMessages, {
    required double fps,
    required String mediaResolution,
  }) {
    if (rawMessages is! List) return;
    for (final rawMessage in rawMessages) {
      if (rawMessage is! Map) continue;
      final content = rawMessage['content'];
      if (content is! List) continue;
      for (final rawPart in content) {
        if (rawPart is! Map) continue;
        if (rawPart['type'] == 'image_url') {
          final image = rawPart['image_url'];
          if (image is Map) image.remove('detail');
          continue;
        }
        if (rawPart['type'] == 'video_url') {
          final video = rawPart['video_url'];
          if (video is Map) video.remove('detail');
          rawPart['fps'] = fps;
          rawPart['media_resolution'] = mediaResolution;
        }
      }
    }
  }

  static Map<String, Object?>? _webSearchTool(Object? raw) {
    if (raw == true) return const <String, Object?>{'type': 'web_search'};
    if (raw is! Map) return null;
    final config = stringKeyedMapFromValue(raw);
    if (optionalBoolFromValue(config['enabled']) == false) return null;
    int? boundedInt(String key) {
      final value = config[key];
      if (value == null) return null;
      final parsed = optionalPositiveIntFromValue(value);
      if (parsed == null || parsed > 50) {
        throw ArgumentError.value(
          value,
          key,
          'MiMo Web Search $key must be an integer from 1 to 50.',
        );
      }
      return parsed;
    }

    final maxKeyword = boundedInt('max_keyword');
    final limit = boundedInt('limit');
    final forceSearch = config['force_search'];
    if (forceSearch != null && forceSearch is! bool) {
      throw ArgumentError.value(
        forceSearch,
        'force_search',
        'MiMo Web Search force_search must be boolean.',
      );
    }
    final location = _webSearchLocation(config['user_location']);
    return <String, Object?>{
      'type': 'web_search',
      if (maxKeyword != null) 'max_keyword': maxKeyword,
      if (forceSearch is bool) 'force_search': forceSearch,
      if (limit != null) 'limit': limit,
      if (location.isNotEmpty) 'user_location': location,
    };
  }

  static Map<String, Object?> _webSearchLocation(Object? raw) {
    if (raw == null) return const <String, Object?>{};
    if (raw is! Map) {
      throw ArgumentError.value(
        raw,
        'user_location',
        'MiMo Web Search user_location must be an object.',
      );
    }
    final source = stringKeyedMapFromValue(raw);
    final type = lowercaseStringFromValue(
      source['type'],
      fallback: 'approximate',
    );
    if (type != 'approximate') {
      throw ArgumentError.value(
        type,
        'user_location.type',
        'MiMo Web Search only supports approximate locations.',
      );
    }
    double? coordinate(String key, double min, double max) {
      final value = source[key];
      if (value == null) return null;
      final parsed = optionalDoubleFromValue(value);
      if (parsed == null || !parsed.isFinite || parsed < min || parsed > max) {
        throw ArgumentError.value(
          value,
          'user_location.$key',
          'MiMo Web Search $key must be from $min to $max.',
        );
      }
      return parsed;
    }

    final country = optionalStringFromValue(source['country']);
    final region = optionalStringFromValue(source['region']);
    final city = optionalStringFromValue(source['city']);
    final district = optionalStringFromValue(source['district']);
    final longitude = coordinate('longitude', -180, 180);
    final latitude = coordinate('latitude', -90, 90);
    return <String, Object?>{
      'type': 'approximate',
      if (country != null) 'country': country,
      if (region != null) 'region': region,
      if (city != null) 'city': city,
      if (district != null) 'district': district,
      if (longitude != null) 'longitude': longitude,
      if (latitude != null) 'latitude': latitude,
    };
  }

  static List<String> _mimoCitations(String rawResponse) {
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map) return const <String>[];
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        return const <String>[];
      }
      final message = (choices.first as Map)['message'];
      if (message is! Map || message['annotations'] is! List) {
        return const <String>[];
      }
      final seen = <String>{};
      final citations = <String>[];
      for (final raw in message['annotations'] as List) {
        if (raw is! Map) continue;
        final citation = raw['url_citation'] is Map
            ? stringKeyedMapFromValue(raw['url_citation'])
            : stringKeyedMapFromValue(raw);
        final url = optionalStringFromValue(citation['url']);
        if (url == null || !seen.add(url)) continue;
        final title =
            optionalStringFromValue(citation['title']) ??
            optionalStringFromValue(citation['site_name']) ??
            url;
        citations.add('- [$title]($url)');
      }
      return citations;
    } catch (_) {
      return const <String>[];
    }
  }

  static String? _mimoWebSearchWarning(String rawResponse) {
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map) return null;
      return firstErrorMessageFromPayloads(<Object?>[
        if (decoded['choices'] is List &&
            (decoded['choices'] as List).isNotEmpty &&
            (decoded['choices'] as List).first is Map)
          ((decoded['choices'] as List).first as Map)['message'],
        decoded['web_search'],
        decoded['webSearch'],
      ]);
    } catch (_) {
      return null;
    }
  }
}

/// 从若干候选载荷里取出第一条错误文案。
///
/// 同一份告警在流式与非流式两条路径上各写了一遍这三种键名的兜底：少认一种
/// 拼法就会静默丢掉服务端的报错，用户只看到一条空回复。
String? firstErrorMessageFromPayloads(Iterable<Object?> candidates) {
  for (final candidate in candidates) {
    if (candidate is! Map) continue;
    final values = stringKeyedMapFromValue(candidate);
    final message =
        optionalStringFromValue(values['error_message']) ??
        optionalStringFromValue(values['errorMessage']) ??
        optionalStringFromValue(values['message']);
    if (message != null) return message;
  }
  return null;
}

class ClaudeProtocolAdapter extends AiProtocolAdapter {
  const ClaudeProtocolAdapter();

  @override
  AiProtocolType get protocolType => AiProtocolType.claude;

  @override
  String get endpointPath => 'v1/messages';

  @override
  bool get supportsServerStreaming => true;

  @override
  bool get supportsToolCalls => true;

  @override
  Map<String, String> buildHeaders(
    AiModelConfig model, {
    Map<String, String> endpointHeaders = const <String, String>{},
  }) {
    final headers = super.buildHeaders(model, endpointHeaders: endpointHeaders);
    headers.putIfAbsent('anthropic-version', () => '2023-06-01');
    return headers;
  }

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    // 仅开头连续系统消息进入 Claude 顶层 system，避免运行时状态改写缓存前缀。
    final systemPartition = _partitionLeadingSystemTurns(messages);
    final stableSystemContent = systemPartition.leadingSystemContent;
    final requestMessages = await _mapClaudeMessages(
      systemPartition.conversationTurns,
    );
    final effectiveMaxTokens = AiThinkingRequestPolicy.effectiveClaudeMaxTokens(
      model,
      model.maxTokens ?? 1024,
    );
    final thinkingPayload = AiThinkingRequestPolicy.claudeThinkingFor(
      model: model,
      maxTokens: effectiveMaxTokens,
    );
    final outputConfigPayload = AiThinkingRequestPolicy.claudeOutputConfigFor(
      model,
    );
    final claudeTemperature = model.temperature;
    final sendTemperature =
        claudeTemperature != null &&
        (thinkingPayload == null ||
            thinkingPayload['type'] != 'enabled' ||
            claudeTemperature == 1.0);
    final cacheEnabled = inputCacheConfig?.isEffectivelyEnabled ?? false;
    // Claude 按 tools → system → messages 组成缓存前缀。system 末尾断点
    // 已覆盖工具目录，因此不再重复占用工具断点，把预算留给消息连续锚点。
    int remainingBreakpoints = cacheEnabled
        ? inputCacheConfig!.breakpointCount.clamp(1, 4)
        : 0;

    Object? systemPayload;
    if (stableSystemContent.isNotEmpty) {
      final blocks = <Map<String, Object?>>[];
      if (cacheEnabled && remainingBreakpoints > 0) {
        blocks.add(<String, Object?>{
          'type': 'text',
          'text': stableSystemContent,
          'cache_control': <String, Object?>{'type': 'ephemeral'},
        });
        remainingBreakpoints -= 1;
      } else {
        blocks.add(<String, Object?>{
          'type': 'text',
          'text': stableSystemContent,
        });
      }
      systemPayload = blocks.length == 1 && !cacheEnabled
          ? blocks.first['text'] as String
          : blocks;
    }

    Object? toolsPayload;
    if (tools.isNotEmpty) {
      final toolJson = stableToolDefinitionsForAiRequest(
        tools,
      ).map((item) => item.toClaudeJson()).toList(growable: false);
      if (cacheEnabled &&
          stableSystemContent.isEmpty &&
          remainingBreakpoints > 0 &&
          toolJson.isNotEmpty) {
        // 没有 system 时，工具末尾作为稳定前缀锚点。
        final mutableTools = toolJson
            .map((e) => Map<String, Object?>.of(stringKeyedMapFromValue(e)))
            .toList(growable: false);
        mutableTools.last['cache_control'] = <String, Object?>{
          'type': 'ephemeral',
        };
        toolsPayload = mutableTools;
        remainingBreakpoints -= 1;
      } else {
        toolsPayload = toolJson;
      }
    }

    if (cacheEnabled &&
        remainingBreakpoints > 0 &&
        requestMessages.isNotEmpty) {
      _injectMessageCacheBreakpoints(
        requestMessages,
        budget: remainingBreakpoints,
        config: inputCacheConfig!,
      );
    }

    return <String, Object?>{
      'model': model.resolveOperationModelId(operationFamily),
      if (systemPayload != null) 'system': systemPayload,
      'max_tokens': effectiveMaxTokens,
      if (thinkingPayload != null) 'thinking': thinkingPayload,
      if (outputConfigPayload != null) 'output_config': outputConfigPayload,
      if (sendTemperature) 'temperature': claudeTemperature,
      if (stream) 'stream': true,
      if (toolsPayload != null) 'tools': toolsPayload,
      if (tools.isNotEmpty) 'tool_choice': <String, Object?>{'type': 'auto'},
      'messages': requestMessages,
    };
  }

  /// 在 [requestMessages] 上按 mode/interval 注入剩余 cache_control breakpoint。
  /// 命中点位于命中消息的最后一个 content 块上。
  void _injectMessageCacheBreakpoints(
    List<Map<String, Object?>> requestMessages, {
    required int budget,
    required AiInputCacheRuntimeConfig config,
  }) {
    if (budget <= 0 || requestMessages.isEmpty) return;
    final lastIndex = requestMessages.length - 1;
    // 当前尾点负责写入最新前缀；上一请求尾点必须原位保留，否则部分兼容网关
    // 只会退回 system/tools 缓存，长工具轮会产生大量重复输入费用。
    final selected = <int>{lastIndex};
    if (selected.length < budget) {
      final previousTailIndex = _previousRequestTailIndex(requestMessages);
      if (previousTailIndex != null) selected.add(previousTailIndex);
    }

    final candidates = <int>[];
    final positions = config.breakpointPositions;
    if (positions.isNotEmpty &&
        positions.length == config.breakpointCount - 1) {
      for (final position in positions.reversed) {
        final ratio = finiteUnitInterval(position, fallback: 1.0);
        candidates.add((ratio * lastIndex).round().clamp(0, lastIndex));
      }
    } else {
      final interval = config.updateInterval <= 0 ? 1 : config.updateInterval;
      switch (config.mode) {
        case 'userMessages':
          var seenUsers = 0;
          for (var i = lastIndex; i >= 0; i--) {
            if (requestMessages[i]['role'] == 'user') {
              if (seenUsers % interval == 0) candidates.add(i);
              seenUsers++;
            }
          }
        case 'tokens':
          // 以累计字符数近似 token 数，达到间隔后放置候选点。
          var charAcc = 0;
          for (var i = lastIndex; i >= 0; i--) {
            charAcc += _estimateMessageChars(requestMessages[i]);
            if (charAcc >= interval || i == lastIndex) {
              candidates.add(i);
              charAcc = 0;
            }
          }
        case 'allMessages':
        default:
          for (var i = lastIndex; i >= 0; i -= interval) {
            candidates.add(i);
          }
      }
    }
    for (final index in candidates) {
      if (selected.length >= budget) break;
      selected.add(index);
    }
    for (var index = 0; index < requestMessages.length; index++) {
      if (selected.length >= budget) break;
      if (_estimateMessageChars(requestMessages[index]) > 0) {
        selected.add(index);
      }
    }
    final ordered = selected.toList()..sort();
    for (final index in ordered.take(budget)) {
      _attachCacheControlToMessageTail(requestMessages[index]);
    }
  }

  int? _previousRequestTailIndex(List<Map<String, Object?>> requestMessages) {
    for (var index = requestMessages.length - 2; index >= 0; index--) {
      final message = requestMessages[index];
      if (message['role'] != 'user' || _estimateMessageChars(message) <= 0) {
        continue;
      }
      return index;
    }
    return null;
  }

  int _estimateMessageChars(Map<String, Object?> message) {
    final content = message['content'];
    if (content is String) return content.length;
    if (content is List) {
      var total = 0;
      for (final block in content) {
        if (block is Map) {
          final t = block['text'];
          if (t is String) total += t.length;
          final c = block['content'];
          if (c is String) total += c.length;
        }
      }
      return total;
    }
    return 0;
  }

  void _attachCacheControlToMessageTail(Map<String, Object?> message) {
    final content = message['content'];
    if (content is String) {
      message['content'] = <Map<String, Object?>>[
        <String, Object?>{
          'type': 'text',
          'text': content,
          'cache_control': <String, Object?>{'type': 'ephemeral'},
        },
      ];
      return;
    }
    if (content is List<Map<String, Object?>>) {
      if (content.isEmpty) return;
      content.last['cache_control'] = <String, Object?>{'type': 'ephemeral'};
      return;
    }
    if (content is List) {
      // List<dynamic> 场景下复制并替换最后一个 Map，避免类型转换失败。
      if (content.isEmpty) return;
      final last = content.last;
      if (last is Map<String, Object?>) {
        last['cache_control'] = <String, Object?>{'type': 'ephemeral'};
      } else if (last is Map) {
        final m = Map<String, Object?>.from(last);
        m['cache_control'] = <String, Object?>{'type': 'ephemeral'};
        content[content.length - 1] = m;
      }
    }
  }

  @override
  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profileOverride = _profileInlineImageSupport(model);
    if (profileOverride != null) return profileOverride;
    return _containsAny(model.modelId, const <String>[
      'claude-3',
      'claude-4',
      'claude-sonnet',
      'claude-opus',
      'claude-haiku',
    ]);
  }

  /// 将消息转换为 Claude 格式，并合并连续同角色消息。
  Future<List<Map<String, Object?>>> _mapClaudeMessages(
    List<AiChatTurn> turns,
  ) async {
    final result = <Map<String, Object?>>[];

    for (final turn in turns) {
      if (turn.role == AiChatRole.assistant && turn.toolCalls.isNotEmpty) {
        // 助手工具调用转换为 tool_use 内容块。
        final contentBlocks = <Map<String, Object?>>[];
        final reasoning = nullIfBlank(turn.reasoningContent);
        if (reasoning != null) {
          contentBlocks.add(<String, Object?>{
            'type': 'thinking',
            'thinking': reasoning,
          });
        }
        final text = turn.content.trim();
        if (text.isNotEmpty) {
          contentBlocks.add(<String, Object?>{'type': 'text', 'text': text});
        }
        for (final tc in turn.toolCalls) {
          Object? parsedArgs;
          try {
            parsedArgs = jsonDecode(tc.arguments);
          } catch (_) {
            parsedArgs = <String, Object?>{};
          }
          contentBlocks.add(<String, Object?>{
            'type': 'tool_use',
            'id': tc.id,
            'name': tc.name,
            'input': parsedArgs,
          });
        }
        _appendClaudeMessage(result, <String, Object?>{
          'role': 'assistant',
          'content': contentBlocks,
        });
      } else if (turn.role == AiChatRole.tool) {
        // 工具结果以用户消息的 tool_result 内容块发送。
        final toolResultBlock = <String, Object?>{
          'type': 'tool_result',
          'tool_use_id': turn.toolCallId ?? '',
          'content': turn.content,
        };
        // 合并连续用户消息。
        if (result.isNotEmpty && result.last['role'] == 'user') {
          final prevContent = result.last['content'];
          if (prevContent is List<Map<String, Object?>>) {
            prevContent.add(toolResultBlock);
          } else if (prevContent is String && prevContent.isNotEmpty) {
            // 合并工具结果时保留已有文本。
            result.last['content'] = <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': prevContent},
              toolResultBlock,
            ];
          } else {
            result.last['content'] = <Map<String, Object?>>[toolResultBlock];
          }
        } else {
          _appendClaudeMessage(result, <String, Object?>{
            'role': 'user',
            'content': <Map<String, Object?>>[toolResultBlock],
          });
        }
      } else {
        // 普通用户或助手文本消息。
        final mapped = await _mapClaudeMessage(turn);
        _appendClaudeMessage(result, mapped);
      }
    }

    return result;
  }

  void _appendClaudeMessage(
    List<Map<String, Object?>> result,
    Map<String, Object?> message,
  ) {
    if (result.isEmpty || result.last['role'] != message['role']) {
      result.add(message);
      return;
    }
    result.last['content'] = _mergeClaudeMessageContent(
      result.last['content'],
      message['content'],
    );
  }

  Object? _mergeClaudeMessageContent(Object? current, Object? next) {
    if (current is String && next is String) {
      final currentText = current.trim();
      final nextText = next.trim();
      if (currentText.isEmpty) return nextText;
      if (nextText.isEmpty) return currentText;
      return '$currentText\n\n$nextText';
    }
    final blocks = <Map<String, Object?>>[];
    void addContent(Object? value) {
      if (value is String) {
        final text = value.trim();
        if (text.isNotEmpty) {
          blocks.add(<String, Object?>{'type': 'text', 'text': text});
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            blocks.add(stringKeyedMapFromValue(item));
          }
        }
      }
    }

    addContent(current);
    addContent(next);
    return blocks;
  }

  Future<Map<String, Object?>> _mapClaudeMessage(AiChatTurn item) async {
    final contentParts = item.effectiveParts;
    final reasoning = item.role == AiChatRole.assistant
        ? nullIfBlank(item.reasoningContent)
        : null;
    if (contentParts.isEmpty ||
        contentParts.every((part) => part.kind == AiChatContentPartKind.text)) {
      final textContent = contentParts.isEmpty
          ? item.content
          : contentParts.map((part) => part.text ?? '').join('\n\n').trim();
      if (reasoning != null) {
        return <String, Object?>{
          'role': item.role == AiChatRole.user ? 'user' : 'assistant',
          'content': <Map<String, Object?>>[
            <String, Object?>{'type': 'thinking', 'thinking': reasoning},
            if (textContent.isNotEmpty)
              <String, Object?>{'type': 'text', 'text': textContent},
          ],
        };
      }
      return <String, Object?>{
        'role': item.role == AiChatRole.user ? 'user' : 'assistant',
        'content': textContent,
      };
    }
    final mappedParts = await _mapClaudeContentParts(contentParts);
    if (reasoning != null) {
      mappedParts.insert(0, <String, Object?>{
        'type': 'thinking',
        'thinking': reasoning,
      });
    }
    return <String, Object?>{
      'role': item.role == AiChatRole.user ? 'user' : 'assistant',
      'content': mappedParts,
    };
  }

  Future<List<Map<String, Object?>>> _mapClaudeContentParts(
    List<AiChatContentPart> parts,
  ) async {
    final payload = <Map<String, Object?>>[];
    for (final part in parts) {
      switch (part.kind) {
        case AiChatContentPartKind.text:
          final text = (part.text ?? '').trim();
          if (text.isEmpty) {
            continue;
          }
          payload.add(<String, Object?>{'type': 'text', 'text': text});
        case AiChatContentPartKind.imageFile:
        case AiChatContentPartKind.videoFile:
        case AiChatContentPartKind.audioFile:
          final media = _inlineMediaSource(part);
          if (media == null) {
            continue;
          }
          payload.add(<String, Object?>{
            'type': switch (part.kind) {
              AiChatContentPartKind.videoFile => 'video',
              AiChatContentPartKind.audioFile => 'input_audio',
              _ => 'image',
            },
            'source': <String, Object?>{
              'type': 'base64',
              'media_type': media.mimeType,
              'data': await encodeFileAsBase64(media.filePath),
            },
          });
      }
    }
    return payload;
  }

  @override
  AiTokenUsage? parseUsage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final usage = decoded['usage'];
    if (usage is! Map && usage is! Map<String, Object?>) {
      return null;
    }
    final usageMap = usage is Map<String, Object?>
        ? usage
        : stringKeyedMapFromValue(usage);
    return AiTokenUsageParser.parseClaude(usageMap);
  }

  @override
  Future<String> parseAssistantMessage(String rawResponse) async {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Unexpected response payload.');
    }
    try {
      AiOperationHttp.throwIfProviderFailed(decoded, contextHint: 'messages');
    } catch (error) {
      throw FormatException('$error'.replaceFirst('Exception: ', ''));
    }
    final content = decoded['content'];
    if (content is! List<dynamic> || content.isEmpty) {
      throw const FormatException('Missing response content.');
    }
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final type = '${item['type'] ?? ''}'.trim();
      // 文本块。
      if (type == 'text' || type.isEmpty) {
        final text = '${item['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(text);
        continue;
      }
      // 图片块。
      if (type == 'image') {
        final source = item['source'];
        if (source is Map<String, Object?>) {
          final sourceType = '${source['type'] ?? ''}'.trim();
          final mediaType = '${source['media_type'] ?? ''}'.trim();
          final data = '${source['data'] ?? ''}'.trim();
          if (sourceType == 'base64' &&
              mediaType.isNotEmpty &&
              data.isNotEmpty) {
            final md = await saveInlineMediaToMarkdown(
              AiInlineMedia(mimeType: mediaType, base64Data: data),
            );
            if (md.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.writeln();
              buffer.writeln();
              buffer.write(md);
            }
          }
        }
        continue;
      }
    }
    final output = buffer.toString().trim();
    if (output.isEmpty) {
      // 仅包含工具调用时允许文本为空。
      return '';
    }
    return output;
  }

  @override
  List<AiToolCall> parseToolCalls(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final content = decoded['content'];
    if (content is! List) {
      return const <AiToolCall>[];
    }
    final calls = <AiToolCall>[];
    for (final item in content) {
      if (item is! Map<String, Object?>) continue;
      final type = '${item['type'] ?? ''}'.trim();
      if (type != 'tool_use') continue;
      final id = '${item['id'] ?? ''}'.trim();
      final name = '${item['name'] ?? ''}'.trim();
      if (id.isEmpty || name.isEmpty) continue;
      final input = item['input'];
      final arguments = input is Map ? jsonEncode(input) : '{}';
      calls.add(AiToolCall(id: id, name: name, arguments: arguments));
    }
    return calls;
  }
}

/// MiniMax 复用 Claude 消息格式，但端点位于 `/anthropic/v1/messages`。
class MiniMaxAnthropicProtocolAdapter extends ClaudeProtocolAdapter {
  const MiniMaxAnthropicProtocolAdapter();

  @override
  AiProtocolType get protocolType => AiProtocolType.minimax;

  @override
  String get endpointPath => 'anthropic/v1/messages';
}

/// MiMo 的 Anthropic 兼容端点位于 `/anthropic`，thinking 不需要预算字段。
class MimoAnthropicProtocolAdapter extends ClaudeProtocolAdapter {
  const MimoAnthropicProtocolAdapter();

  @override
  AiProtocolType get protocolType => AiProtocolType.mimo;

  @override
  String get endpointPath => 'anthropic/v1/messages';

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    _validateMimoModelId(model);
    await validateMimoContentParts(
      model,
      messages,
      surface: AiMimoMediaSurface.anthropic,
    );
    final body = await super.buildBody(
      model,
      messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: stream,
      inputCacheConfig: inputCacheConfig,
    );
    _normalizeBody(body, model);
    return body;
  }

  @override
  Future<AiRequestBlueprint> buildChatRequest({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final request = await super.buildChatRequest(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: stream,
      inputCacheConfig: inputCacheConfig,
    );
    final body = Map<String, Object?>.from(request.body);
    _normalizeBody(body, model);
    return request.copyWith(body: body);
  }

  static void _normalizeBody(Map<String, Object?> body, AiModelConfig model) {
    AiThinkingRequestPolicy.applyMimoThinking(body, model);
    body.remove('output_config');
  }

  @override
  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profile = model.profileFor(model.modelId);
    return profile.supportsAttachments != false &&
        profile.supportedModalities.contains(AiModelModality.image);
  }
}

class GeminiProtocolAdapter extends AiProtocolAdapter {
  const GeminiProtocolAdapter();

  @override
  AiProtocolType get protocolType => AiProtocolType.gemini;

  @override
  String get endpointPath => 'v1beta/models/{model_id}:generateContent';

  @override
  String get streamEndpointPath =>
      'v1beta/models/{model_id}:streamGenerateContent?alt=sse';

  @override
  bool get supportsServerStreaming => true;

  @override
  bool get supportsToolCalls => true;

  @override
  Map<String, String> buildHeaders(
    AiModelConfig model, {
    Map<String, String> endpointHeaders = const <String, String>{},
  }) {
    final headers = super.buildHeaders(model, endpointHeaders: endpointHeaders);
    headers.remove(kAuthorizationHeaderName);
    headers.remove('x-api-key');
    final token = nullIfBlank(model.token);
    if (token != null && model.authScheme == AiAuthScheme.apiKey) {
      headers['x-goog-api-key'] = token;
    }
    return headers;
  }

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final systemPartition = _partitionLeadingSystemTurns(messages);
    final systemContent = systemPartition.leadingSystemContent;
    final requestContents = await _mapGeminiMessages(
      systemPartition.conversationTurns,
    );

    // 优先使用调用方指定的响应模态，否则根据模型名称判断。
    final effectiveModalities = responseModalities.isNotEmpty
        ? responseModalities
        : model.modelId.toLowerCase().contains('image')
        ? const <String>['Text', 'Image']
        : const <String>[];

    final generationConfig = <String, Object?>{
      'maxOutputTokens': model.maxTokens ?? 8192,
      if (model.temperature != null) 'temperature': model.temperature,
      if (effectiveModalities.isNotEmpty)
        'responseModalities': effectiveModalities,
    };
    AiThinkingRequestPolicy.applyGeminiGenerationConfig(
      generationConfig,
      model,
    );

    return <String, Object?>{
      if (systemContent.isNotEmpty)
        'systemInstruction': <String, Object?>{
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': systemContent},
          ],
        },
      'contents': requestContents,
      'generationConfig': generationConfig,
      if (tools.isNotEmpty)
        'tools': <Map<String, Object?>>[
          <String, Object?>{
            'functionDeclarations': stableToolDefinitionsForAiRequest(tools)
                .map(
                  (item) => <String, Object?>{
                    'name': item.name,
                    'description': item.description,
                    'parameters': item.parameters,
                  },
                )
                .toList(growable: false),
          },
        ],
    };
  }

  @override
  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profileOverride = _profileInlineImageSupport(model);
    if (profileOverride != null) return profileOverride;
    return _containsAny(model.modelId, const <String>[
      'gemini-1.5',
      'gemini-2.0',
      'gemini-2.5',
      'gemini',
    ]);
  }

  /// 将消息转换为 Gemini 格式，包括 functionCall 和 functionResponse。
  Future<List<Map<String, Object?>>> _mapGeminiMessages(
    List<AiChatTurn> turns,
  ) async {
    final result = <Map<String, Object?>>[];
    // 记录工具调用标识到函数名称的映射。
    final toolCallIdToName = <String, String>{};

    for (final turn in turns) {
      if (turn.role == AiChatRole.assistant && turn.toolCalls.isNotEmpty) {
        // 模型函数调用消息。
        final parts = <Map<String, Object?>>[];
        final text = turn.content.trim();
        if (text.isNotEmpty) {
          parts.add(<String, Object?>{'text': text});
        }
        for (final tc in turn.toolCalls) {
          toolCallIdToName[tc.id] = tc.name;
          Object? parsedArgs;
          try {
            parsedArgs = jsonDecode(tc.arguments);
          } catch (_) {
            parsedArgs = <String, Object?>{};
          }
          parts.add(<String, Object?>{
            'functionCall': <String, Object?>{
              'name': tc.name,
              'args': parsedArgs,
            },
          });
        }
        _appendGeminiContent(result, <String, Object?>{
          'role': 'model',
          'parts': parts,
        });
      } else if (turn.role == AiChatRole.tool) {
        // Gemini 工具结果需要函数名称而非调用标识。
        final callId = turn.toolCallId ?? '';
        final functionName = toolCallIdToName[callId] ?? callId;
        Object? parsedContent;
        try {
          parsedContent = jsonDecode(turn.content);
        } catch (_) {
          parsedContent = <String, Object?>{'result': turn.content};
        }
        final responseBlock = <String, Object?>{
          'functionResponse': <String, Object?>{
            'name': functionName,
            'response': parsedContent,
          },
        };
        // 合并连续用户消息。
        if (result.isNotEmpty && result.last['role'] == 'user') {
          final prevParts = result.last['parts'];
          if (prevParts is List<Map<String, Object?>>) {
            prevParts.add(responseBlock);
          } else {
            result.last['parts'] = <Map<String, Object?>>[responseBlock];
          }
        } else {
          _appendGeminiContent(result, <String, Object?>{
            'role': 'user',
            'parts': <Map<String, Object?>>[responseBlock],
          });
        }
      } else {
        _appendGeminiContent(result, await _mapGeminiMessage(turn));
      }
    }

    return result;
  }

  void _appendGeminiContent(
    List<Map<String, Object?>> result,
    Map<String, Object?> content,
  ) {
    if (result.isEmpty || result.last['role'] != content['role']) {
      result.add(content);
      return;
    }
    final previousParts = result.last['parts'];
    final nextParts = content['parts'];
    if (previousParts is List && nextParts is List) {
      previousParts.addAll(nextParts);
      return;
    }
    result.add(content);
  }

  Future<Map<String, Object?>> _mapGeminiMessage(AiChatTurn item) async {
    final parts = await _mapGeminiContentParts(item.effectiveParts);
    // Gemini 不接受 parts 为空的消息。
    if (parts.isEmpty) {
      parts.add(<String, Object?>{'text': ' '});
    }
    return <String, Object?>{
      'role': item.role == AiChatRole.assistant ? 'model' : 'user',
      'parts': parts,
    };
  }

  Future<List<Map<String, Object?>>> _mapGeminiContentParts(
    List<AiChatContentPart> parts,
  ) async {
    final payload = <Map<String, Object?>>[];
    for (final part in parts) {
      switch (part.kind) {
        case AiChatContentPartKind.text:
          final text = (part.text ?? '').trim();
          if (text.isEmpty) {
            continue;
          }
          payload.add(<String, Object?>{'text': text});
        case AiChatContentPartKind.imageFile:
        case AiChatContentPartKind.videoFile:
        case AiChatContentPartKind.audioFile:
          final media = _inlineMediaSource(part);
          if (media == null) {
            continue;
          }
          payload.add(<String, Object?>{
            'inline_data': <String, Object?>{
              'mime_type': media.mimeType,
              'data': await encodeFileAsBase64(media.filePath),
            },
          });
      }
    }
    return payload;
  }

  @override
  AiTokenUsage? parseUsage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final usage = decoded['usageMetadata'];
    if (usage is! Map && usage is! Map<String, Object?>) {
      return null;
    }
    final usageMap = usage is Map<String, Object?>
        ? usage
        : stringKeyedMapFromValue(usage);
    return AiTokenUsageParser.parseGemini(usageMap);
  }

  @override
  Future<String> parseAssistantMessage(String rawResponse) async {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Unexpected response payload.');
    }
    final candidates = decoded['candidates'];
    if (candidates is! List<dynamic> || candidates.isEmpty) {
      throw const FormatException('Missing response candidates.');
    }
    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, Object?>) {
      throw const FormatException('Unexpected candidate payload.');
    }
    final content = firstCandidate['content'];
    if (content is! Map<String, Object?>) {
      throw const FormatException('Missing candidate content.');
    }
    final parts = content['parts'];
    if (parts is! List<dynamic> || parts.isEmpty) {
      throw const FormatException('Missing Gemini response parts.');
    }
    final buffer = StringBuffer();
    for (final item in parts) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      // 文本部分。
      final text = '${item['text'] ?? ''}'.trim();
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(text);
        continue;
      }
      // 内联图片、音频或视频。
      final inlineData = item['inline_data'] ?? item['inlineData'];
      if (inlineData is Map<String, Object?>) {
        final mimeType =
            '${inlineData['mime_type'] ?? inlineData['mimeType'] ?? ''}'.trim();
        final data = '${inlineData['data'] ?? ''}'.trim();
        if (mimeType.isNotEmpty && data.isNotEmpty) {
          final md = await saveInlineMediaToMarkdown(
            AiInlineMedia(mimeType: mimeType, base64Data: data),
          );
          if (md.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln();
            buffer.write(md);
          }
        }
        continue;
      }
      // 文件 URI。
      final fileData = item['file_data'] ?? item['fileData'];
      if (fileData is Map<String, Object?>) {
        final mimeType =
            '${fileData['mime_type'] ?? fileData['mimeType'] ?? ''}'.trim();
        final fileUri = '${fileData['file_uri'] ?? fileData['fileUri'] ?? ''}'
            .trim();
        if (fileUri.isNotEmpty) {
          final label = isImageMimeType(mimeType)
              ? 'AI Generated Image'
              : isVideoMimeType(mimeType)
              ? 'AI Generated Video'
              : isAudioMimeType(mimeType)
              ? 'AI Generated Audio'
              : 'AI Generated File';
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          if (isImageMimeType(mimeType)) {
            buffer.write('![$label]($fileUri)');
          } else if (isVideoMimeType(mimeType) || isAudioMimeType(mimeType)) {
            buffer.write('[$label]($fileUri)');
          } else {
            buffer.write('[$label]($fileUri)');
          }
        }
        continue;
      }
    }
    final output = buffer.toString().trim();
    if (output.isEmpty) {
      // 仅包含函数调用时允许文本为空。
      return '';
    }
    return output;
  }

  @override
  List<AiToolCall> parseToolCalls(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return const <AiToolCall>[];
    }
    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final content = firstCandidate['content'];
    if (content is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final parts = content['parts'];
    if (parts is! List) {
      return const <AiToolCall>[];
    }
    final calls = <AiToolCall>[];
    var index = 0;
    for (final part in parts) {
      if (part is! Map<String, Object?>) continue;
      final functionCall = part['functionCall'];
      if (functionCall is! Map<String, Object?>) continue;
      final name = '${functionCall['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final args = functionCall['args'];
      final arguments = args is Map ? jsonEncode(args) : '{}';
      calls.add(
        AiToolCall(id: 'gemini-tc-$index', name: name, arguments: arguments),
      );
      index++;
    }
    return calls;
  }
}

/// Ollama 的 OpenAI 兼容适配器，兼容其认证、流选项及用量字段差异。
class OllamaProtocolAdapter extends OpenAiProtocolAdapter {
  const OllamaProtocolAdapter({super.visionModelPatterns})
    : super(AiProtocolType.ollama);

  @override
  Map<String, String> buildHeaders(
    AiModelConfig model, {
    Map<String, String> endpointHeaders = const <String, String>{},
  }) {
    // 本地 Ollama 未配置令牌时不发送空认证头。
    return super.buildHeaders(model, endpointHeaders: endpointHeaders);
  }

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final body = await super.buildBody(
      model,
      messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: stream,
      inputCacheConfig: inputCacheConfig,
    );
    // 旧版 Ollama 不支持 stream_options。
    body.remove('stream_options');
    return body;
  }

  @override
  AiTokenUsage? parseUsage(String rawResponse) {
    // 优先解析标准 OpenAI 用量字段。
    final standardUsage = super.parseUsage(rawResponse);
    if (standardUsage != null && !standardUsage.isEmpty) {
      return standardUsage;
    }
    // 兼容 Ollama 原生用量字段。
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map<String, Object?>) return null;
      final promptEval = optionalNonNegativeIntegralIntFromValue(
        decoded['prompt_eval_count'],
      );
      final evalCount = optionalNonNegativeIntegralIntFromValue(
        decoded['eval_count'],
      );
      if (promptEval == null && evalCount == null) return null;
      return AiTokenUsage(
        promptTokens: promptEval,
        completionTokens: evalCount,
        totalTokens: (promptEval ?? 0) + (evalCount ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  // 共享错误提取器已覆盖 Ollama 的文本和 JSON 错误。
}

abstract final class AiProtocolRegistry {
  // 各服务商视觉模型标识，匹配时忽略大小写。

  static const _openaiVisionPatterns = <String>[
    'gpt-4o',
    'gpt-4.1',
    'gpt-4.5',
    'gpt-5',
    'o1',
    'o3',
    'o4',
    'vision',
    'omni',
    'claude-3',
    'claude-4',
    'claude-sonnet',
    'claude-opus',
    'claude-haiku',
    'gemini',
    'llava',
    'pixtral',
    'internvl',
    'minicpm-v',
    'cogvlm',
    'moondream',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'multimodal',
    'multi-modal',
  ];

  static const _deepseekVisionPatterns = <String>[
    'vision',
    'vl',
    'janus',
    'multimodal',
    'multi-modal',
  ];

  static const _qwenVisionPatterns = <String>['vl', 'omni', 'vision', 'doc'];

  static const _kimiVisionPatterns = <String>[
    'vision',
    'vl',
    'moonshot-v',
    'k1.5-vision',
    'k2-vision',
    'k2.5-vision',
  ];

  static const _glmVisionPatterns = <String>[
    'glm-4v',
    'glm-4.5v',
    '4v',
    'vision',
    'vl',
    'vlm',
  ];

  static const _grokVisionPatterns = <String>[
    'vision',
    'grok-2-vision',
    'grok-vision',
  ];

  static const _ollamaVisionPatterns = <String>[
    'llava',
    'llama3.2-vision',
    'moondream',
    'bakllava',
    'minicpm-v',
    'cogvlm',
    'internvl',
    'vision',
  ];

  static const _vllmVisionPatterns = <String>[
    'llava',
    'pixtral',
    'internvl',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'minicpm-v',
    'cogvlm',
    'vision',
  ];

  static const _sglangVisionPatterns = <String>[
    'llava',
    'pixtral',
    'internvl',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'vision',
  ];

  static const _seedVisionPatterns = <String>[
    'vision',
    'vl',
    'doubao-vision',
    'doubao-1.5-vision',
  ];

  static const _stepfunVisionPatterns = <String>[
    'step-3.7',
    'step-3-7',
    'step-2v',
    'step-1.5v',
    'step-1v',
    'vision',
    'vl',
  ];

  static const _minimaxVisionPatterns = <String>[
    'minimax-m3',
    'minimax_m3',
    'vision',
    'vl',
    'm2-vl',
  ];

  static const _longCatVisionPatterns = <String>['vision', 'vl'];
  static const _agnesVisionPatterns = <String>[
    'agnes-1.5-flash',
    'agnes-2.0-flash',
  ];
  static const _joyCodeVisionPatterns = <String>['vision', 'vl'];

  static const _wenxinVisionPatterns = <String>[
    'ernie-vl',
    'ernie-4.5-vl',
    'vision',
    'vl',
  ];

  static const _metaVisionPatterns = <String>[
    'llama-4',
    'llama3.2-vision',
    'llama-3.2-vision',
    'vision',
    'vl',
  ];

  static const _hunyuanVisionPatterns = <String>[
    'hunyuan-vision',
    'hunyuan-turbos-vision',
    'vision',
    'vl',
  ];

  static const _dotsVisionPatterns = <String>['dots3', 'dots-3'];

  static final Map<AiProtocolType, AiProtocolAdapter> _adapters =
      <AiProtocolType, AiProtocolAdapter>{
        AiProtocolType.openai: const OpenAiProtocolAdapter(
          AiProtocolType.openai,
          visionModelPatterns: _openaiVisionPatterns,
        ),
        AiProtocolType.dots: const OpenAiProtocolAdapter(
          AiProtocolType.dots,
          visionModelPatterns: _dotsVisionPatterns,
        ),
        AiProtocolType.deepseek: const OpenAiProtocolAdapter(
          AiProtocolType.deepseek,
          visionModelPatterns: _deepseekVisionPatterns,
        ),
        AiProtocolType.qwen: const OpenAiProtocolAdapter(
          AiProtocolType.qwen,
          visionModelPatterns: _qwenVisionPatterns,
        ),
        AiProtocolType.kimi: const OpenAiProtocolAdapter(
          AiProtocolType.kimi,
          visionModelPatterns: _kimiVisionPatterns,
        ),
        AiProtocolType.glm: const OpenAiProtocolAdapter(
          AiProtocolType.glm,
          visionModelPatterns: _glmVisionPatterns,
        ),
        AiProtocolType.grok: const OpenAiProtocolAdapter(
          AiProtocolType.grok,
          visionModelPatterns: _grokVisionPatterns,
        ),
        AiProtocolType.ollama: const OllamaProtocolAdapter(
          visionModelPatterns: _ollamaVisionPatterns,
        ),
        AiProtocolType.vllm: const OpenAiProtocolAdapter(
          AiProtocolType.vllm,
          visionModelPatterns: _vllmVisionPatterns,
        ),
        AiProtocolType.sglang: const OpenAiProtocolAdapter(
          AiProtocolType.sglang,
          visionModelPatterns: _sglangVisionPatterns,
        ),
        AiProtocolType.seed: const OpenAiProtocolAdapter(
          AiProtocolType.seed,
          visionModelPatterns: _seedVisionPatterns,
        ),
        AiProtocolType.stepfun: const OpenAiProtocolAdapter(
          AiProtocolType.stepfun,
          visionModelPatterns: _stepfunVisionPatterns,
        ),
        AiProtocolType.minimax: const OpenAiProtocolAdapter(
          AiProtocolType.minimax,
          visionModelPatterns: _minimaxVisionPatterns,
        ),
        AiProtocolType.longcat: const OpenAiProtocolAdapter(
          AiProtocolType.longcat,
          visionModelPatterns: _longCatVisionPatterns,
        ),
        AiProtocolType.agnes: const OpenAiProtocolAdapter(
          AiProtocolType.agnes,
          visionModelPatterns: _agnesVisionPatterns,
        ),
        AiProtocolType.joycode: const OpenAiProtocolAdapter(
          AiProtocolType.joycode,
          visionModelPatterns: _joyCodeVisionPatterns,
        ),
        AiProtocolType.wenxin: const OpenAiProtocolAdapter(
          AiProtocolType.wenxin,
          visionModelPatterns: _wenxinVisionPatterns,
        ),
        AiProtocolType.meta: const OpenAiProtocolAdapter(
          AiProtocolType.meta,
          visionModelPatterns: _metaVisionPatterns,
        ),
        AiProtocolType.mimo: const MimoOpenAiProtocolAdapter(),
        AiProtocolType.hunyuan: const OpenAiProtocolAdapter(
          AiProtocolType.hunyuan,
          visionModelPatterns: _hunyuanVisionPatterns,
        ),
        AiProtocolType.claude: const ClaudeProtocolAdapter(),
        AiProtocolType.gemini: const GeminiProtocolAdapter(),
      };

  static AiProtocolAdapter adapterFor(AiProtocolType protocolType) {
    return _adapters[protocolType] ?? _adapters[AiProtocolType.openai]!;
  }

  static AiProtocolAdapter adapterForModel(AiModelConfig model) {
    return switch (model.apiDialect) {
      AiApiDialect.anthropicNative
          when model.protocolType == AiProtocolType.minimax =>
        const MiniMaxAnthropicProtocolAdapter(),
      AiApiDialect.anthropicNative
          when model.protocolType == AiProtocolType.mimo =>
        const MimoAnthropicProtocolAdapter(),
      AiApiDialect.anthropicNative => const ClaudeProtocolAdapter(),
      AiApiDialect.geminiNative => const GeminiProtocolAdapter(),
      AiApiDialect.openAiCompat => adapterFor(model.protocolType),
    };
  }

  /// 判断模型是否支持消息正文中的内联图片。
  static bool supportsInlineImages(AiModelConfig model) {
    return adapterForModel(model).supportsAttachmentsForModel(model);
  }
}

/// 从 OpenAI 兼容响应中提取文本、图像和音频内容；格式异常时返回空字符串。
Future<String> _extractOpenAiContentWithMediaSafe(Object? rawContent) async {
  try {
    return await _extractOpenAiContentWithMedia(rawContent);
  } on FormatException {
    return '';
  }
}

/// 从 OpenAI 兼容响应中提取文本、图像和音频内容。
Future<String> _extractOpenAiContentWithMedia(Object? rawContent) async {
  if (rawContent is String) {
    final text = nullIfBlank(rawContent);
    if (text != null) return text;
  }
  if (rawContent is List<dynamic>) {
    final buffer = StringBuffer();
    for (final item in rawContent) {
      final itemText = item is String ? nullIfBlank(item) : null;
      if (itemText != null) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(itemText);
        continue;
      }
      if (item is! Map<String, Object?>) continue;
      final type = stringFromValue(item['type']);
      // 文本块。
      if (type == 'text' || type.isEmpty) {
        final text =
            optionalStringFromValue(item['text']) ??
            optionalStringFromValue(item['content']);
        if (text != null) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.write(text);
        }
        continue;
      }
      // Base64 数据 URI 或远程图片地址。
      if (type == 'image_url') {
        final imageUrl = item['image_url'];
        if (imageUrl is Map<String, Object?>) {
          final url = optionalStringFromValue(imageUrl['url']);
          if (url == null) {
            continue;
          }
          if (url.startsWith('data:')) {
            final commaIndex = url.indexOf(',');
            if (commaIndex > 0) {
              final header = url.substring(0, commaIndex);
              final mimeMatch = _dataUriMimePattern.firstMatch(header);
              final mimeType = mimeMatch?.group(1) ?? kImagePngMimeType;
              final base64Data = url.substring(commaIndex + 1);
              final md = await saveInlineMediaToMarkdown(
                AiInlineMedia(mimeType: mimeType, base64Data: base64Data),
              );
              if (md.isNotEmpty) {
                if (buffer.isNotEmpty) buffer.writeln();
                buffer.writeln();
                buffer.write(md);
              }
            }
          } else {
            // 远程地址直接渲染为 Markdown 图片。
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln();
            buffer.write('![AI Generated Image]($url)');
          }
        }
        continue;
      }
      // 视频块。
      if (type == 'video' || type == 'video_url') {
        final videoPayload = item['video'] ?? item['video_url'];
        final md = await _markdownFromOpenAiMediaPayload(
          videoPayload,
          fallbackMimeType: kVideoMp4MimeType,
          fallbackLabel: 'AI Generated Video',
        );
        if (md.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          buffer.write(md);
        }
        continue;
      }
      // 音频块。
      if (type == 'audio') {
        final audioData = item['audio'];
        if (audioData is Map<String, Object?>) {
          final data = optionalStringFromValue(audioData['data']);
          if (data != null) {
            final md = await saveInlineMediaToMarkdown(
              AiInlineMedia(mimeType: kAudioMp3AliasMimeType, base64Data: data),
              label:
                  optionalStringFromValue(audioData['transcript']) ??
                  'AI Audio Response',
            );
            if (md.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.writeln();
              buffer.writeln();
              buffer.write(md);
            }
          }
          final url =
              optionalStringFromValue(audioData['url']) ??
              optionalStringFromValue(audioData['audio_url']);
          if (url != null) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln();
            buffer.write('[AI Audio Response]($url)');
          }
          // 存在转写文本时一并返回。
          final transcript = optionalStringFromValue(audioData['transcript']);
          if (transcript != null) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.write(transcript);
          }
        }
        continue;
      }
    }
    final output = buffer.toString().trim();
    if (output.isNotEmpty) {
      return output;
    }
  }
  throw const FormatException('Empty assistant response text.');
}

Future<String> _markdownFromOpenAiMediaPayload(
  Object? payload, {
  required String fallbackMimeType,
  required String fallbackLabel,
}) async {
  if (payload is String) {
    final trimmed = nullIfBlank(payload);
    if (trimmed == null) return '';
    if (trimmed.startsWith('data:')) {
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex > 0) {
        final header = trimmed.substring(0, commaIndex);
        final mimeMatch = _dataUriMimePattern.firstMatch(header);
        final mimeType = mimeMatch?.group(1) ?? fallbackMimeType;
        final base64Data = trimmed.substring(commaIndex + 1);
        return saveInlineMediaToMarkdown(
          AiInlineMedia(mimeType: mimeType, base64Data: base64Data),
          label: fallbackLabel,
        );
      }
    }
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('file:')) {
      return '[$fallbackLabel]($trimmed)';
    }
    return '';
  }
  if (payload is! Map<String, Object?>) return '';
  final data =
      optionalStringFromValue(payload['data']) ??
      optionalStringFromValue(payload['base64']);
  final mimeType =
      optionalStringFromValue(payload['mime_type']) ??
      optionalStringFromValue(payload['mimeType']) ??
      fallbackMimeType;
  final label =
      optionalStringFromValue(payload['transcript']) ??
      optionalStringFromValue(payload['title']) ??
      fallbackLabel;
  if (data != null) {
    return saveInlineMediaToMarkdown(
      AiInlineMedia(
        mimeType: nullIfBlank(mimeType) ?? fallbackMimeType,
        base64Data: data,
      ),
      label: nullIfBlank(label) ?? fallbackLabel,
    );
  }
  final url =
      optionalStringFromValue(payload['url']) ??
      optionalStringFromValue(payload['video_url']) ??
      optionalStringFromValue(payload['audio_url']);
  if (url != null) {
    return '[${sanitizeMarkdownAltText(nullIfBlank(label) ?? fallbackLabel)}]($url)';
  }
  return '';
}

String _audioFormatForMimeType(String mimeType) {
  return switch (lowercaseStringFromValue(mimeType)) {
    kAudioMpegMimeType || kAudioMp3AliasMimeType => 'mp3',
    kAudioWavMimeType ||
    kAudioWaveAliasMimeType ||
    kAudioXWavAliasMimeType => 'wav',
    kAudioFlacMimeType || 'audio/x-flac' => 'flac',
    kAudioMp4MimeType || 'audio/m4a' || 'audio/x-m4a' => 'm4a',
    kAudioOggMimeType || 'audio/opus' => 'ogg',
    _ => 'wav',
  };
}

bool _containsAny(String value, List<String> candidates) {
  final normalized = optionalLowercaseStringFromValue(value);
  if (normalized == null) return false;
  for (final candidate in candidates) {
    if (normalized.contains(candidate.toLowerCase())) {
      return true;
    }
  }
  return false;
}

// 内联媒体提取工具。

/// 从 AI 响应解码出的内联媒体块。
class AiInlineMedia {
  const AiInlineMedia({required this.mimeType, required this.base64Data});

  final String mimeType;
  final String base64Data;

  /// 简短的媒体类型名称。
  String get mediaKind {
    if (isImageMimeType(mimeType)) return 'image';
    if (isAudioMimeType(mimeType)) return 'audio';
    if (isVideoMimeType(mimeType)) return 'video';
    return 'file';
  }

  /// 根据 MIME 类型推断文件扩展名。
  String get fileExtension {
    return switch (mimeType) {
      kImagePngMimeType => '.png',
      kImageJpegMimeType || 'image/jpg' => '.jpg',
      kImageGifMimeType => '.gif',
      kImageWebpMimeType => '.webp',
      kImageSvgXmlMimeType => '.svg',
      kAudioMp3AliasMimeType || kAudioMpegMimeType => '.mp3',
      kAudioWavMimeType || kAudioXWavAliasMimeType => '.wav',
      kAudioOggMimeType => '.ogg',
      kAudioAacMimeType => '.aac',
      kVideoMp4MimeType => '.mp4',
      kVideoWebmMimeType => '.webm',
      _ => '',
    };
  }
}

/// 内联媒体产物共享目录。复用单个目录可批量清理过期文件，避免每个媒体资源泄漏
/// 一个独立临时目录。
Directory? _inlineMediaDir;
int _inlineMediaFileSequence = 0;
final OpenHandSingleFlight<void> _inlineMediaCleanupFlight =
    OpenHandSingleFlight<void>();
Future<Directory> _ensureInlineMediaDir() async {
  final dir =
      _inlineMediaDir ??
      Directory(p.join(Directory.systemTemp.path, 'openhand_media'));
  await createDirectoryBounded(dir, timeout: _inlineMediaCacheIdleTimeout);
  _inlineMediaDir = dir;
  return dir;
}

/// 尽力删除过期或超出容量上限的内联媒体文件；并发调用复用同一任务。
Future<void> pruneInlineMediaCache() {
  return _inlineMediaCleanupFlight.run(_pruneInlineMediaCache);
}

Future<void> _pruneInlineMediaCache() async {
  final deadline = MonotonicDeadline(
    _inlineMediaCacheCleanupTimeout,
    timeoutMessage: '内联媒体缓存清理超时。',
  );

  try {
    final dir = Directory(p.join(Directory.systemTemp.path, 'openhand_media'));
    if (!await dir.exists().timeout(
      deadline.limit(_inlineMediaCacheIdleTimeout),
    )) {
      return;
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final remainingTime = deadline.remaining();
    final listing = await listDirectoryBounded(
      dir,
      maxEntries: _inlineMediaCacheScanLimit,
      idleTimeout: deadline.limit(_inlineMediaCacheIdleTimeout),
      totalTimeout: remainingTime,
    );
    final files = <({File file, int bytes, DateTime modified})>[];
    var totalBytes = 0;
    for (final entity in listing.entries) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat().timeout(
          deadline.limit(_inlineMediaCacheIdleTimeout),
        );
        if (stat.type != FileSystemEntityType.file) continue;
        files.add((file: entity, bytes: stat.size, modified: stat.modified));
        totalBytes += stat.size;
      } on FileSystemException {
        // 跳过无法读取元数据的文件。
      }
    }
    files.sort((left, right) => left.modified.compareTo(right.modified));
    var deleted = 0;
    var remainingFiles = files.length;
    for (final entry in files) {
      if (deleted >= _inlineMediaCacheDeleteLimit) break;
      final expired = entry.modified.isBefore(cutoff);
      final overCapacity =
          listing.truncated ||
          remainingFiles > _inlineMediaCacheMaxFiles ||
          totalBytes > _inlineMediaCacheMaxBytes;
      if (!expired && !overCapacity) break;
      try {
        await entry.file.delete().timeout(
          deadline.limit(_inlineMediaCacheIdleTimeout),
        );
        deleted += 1;
        remainingFiles -= 1;
        totalBytes -= entry.bytes;
      } on FileSystemException {
        // 跳过无法删除的文件。
      }
    }
  } on TimeoutException {
    // 清理仅尽力执行，并受严格时限约束。
  } on FileSystemException {
    // 缓存清理失败不影响主流程。
  } finally {
    deadline.stop();
  }
}

Future<File> createInlineMediaOutputFile({required String mimeType}) async {
  final media = AiInlineMedia(mimeType: mimeType, base64Data: '');
  final tempDir = await _ensureInlineMediaDir();
  final id =
      '${DateTime.now().microsecondsSinceEpoch}_'
      '${_inlineMediaFileSequence++}';
  return File(
    p.join(tempDir.path, '${media.mediaKind}_$id${media.fileExtension}'),
  );
}

String inlineMediaFileMarkdown({
  required String filePath,
  required String mimeType,
  String? label,
}) {
  final media = AiInlineMedia(mimeType: mimeType, base64Data: '');
  _scheduleInlineMediaCachePrune(filePath);
  final displayLabel = sanitizeMarkdownAltText(
    label ?? 'AI Generated ${media.mediaKind}',
  );
  if (isImageMimeType(mimeType)) {
    return '![$displayLabel]($filePath)';
  }
  if (isAudioMimeType(mimeType)) {
    return '[🔊 $displayLabel]($filePath)';
  }
  if (isVideoMimeType(mimeType)) {
    return '[🎬 $displayLabel]($filePath)';
  }
  return '[📎 $displayLabel]($filePath)';
}

void _scheduleInlineMediaCachePrune(String filePath) {
  final cachePath = p.absolute(
    p.join(Directory.systemTemp.path, 'openhand_media'),
  );
  final absoluteFilePath = p.absolute(filePath);
  if (!p.isWithin(cachePath, absoluteFilePath)) return;
  unawaited(
    pruneInlineMediaCache().catchError((Object error, StackTrace stack) {
      silentLog('ai_protocol_adapter', '清理内联媒体缓存', error, stack);
    }),
  );
}

/// 把内联媒体安全写入临时文件，并返回对应的 Markdown 引用。
Future<String> saveInlineMediaToMarkdown(
  AiInlineMedia media, {
  String? label,
}) async {
  if (media.base64Data.isEmpty) return '';
  try {
    final bytes = decodeBase64Bounded(
      media.base64Data,
      maxDecodedBytes: _inlineMediaMaxDecodedBytes,
    );
    if (bytes.isEmpty) return '';
    final file = await createInlineMediaOutputFile(mimeType: media.mimeType);
    await writeTemporaryFileBytesBounded(
      file,
      bytes,
      timeout: _inlineMediaWriteTimeout,
      onSecondaryError: (error, stack) =>
          silentLog('ai_protocol_adapter', '清理内联媒体临时文件', error, stack),
    );
    return inlineMediaFileMarkdown(
      filePath: file.path,
      mimeType: media.mimeType,
      label: label,
    );
  } catch (error, stack) {
    silentLog('ai_protocol_adapter', '保存内联媒体并生成 Markdown', error, stack);
    return '';
  }
}

/// 清理 Markdown 图片或链接替代文本，并限制长度。
String sanitizeMarkdownAltText(String text) {
  var sanitized = text
      .replaceAll('[', '')
      .replaceAll(']', '')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .trim();
  if (sanitized.length > 120) {
    sanitized = clipTextByCodeUnits(sanitized, 120);
  }
  return sanitized;
}
