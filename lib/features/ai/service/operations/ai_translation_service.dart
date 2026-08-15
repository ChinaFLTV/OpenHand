import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/stable_hash.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_translation_settings.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../runtime/ai_transport_client.dart';
import '../usage/ai_usage_tracker.dart';

final RegExp _aiTranslationFencePattern = RegExp(
  r'^```(?:[a-zA-Z0-9_-]+)?\s*([\s\S]*?)\s*```$',
);
final RegExp _translationErrorPrefixPattern = RegExp(r'^[^:]+:\s*');

class AiTranslationResult {
  const AiTranslationResult({
    required this.text,
    required this.provider,
    this.modelConfigId,
    this.modelId,
  });

  final String text;
  final AiTranslationProvider provider;
  final String? modelConfigId;
  final String? modelId;
}

class AiTranslationException implements Exception {
  const AiTranslationException(this.message, {this.provider});

  final String message;
  final AiTranslationProvider? provider;

  @override
  String toString() => message;
}

class AiTranslationService {
  AiTranslationService({http.Client? client, AiChatClient? chatClient})
    : _transport = AiTransportClient(client: client),
      _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null;

  static const String _aiPromptAsset =
      'assets/prompts/common/ai_translation_system_prompt.md';
  static const int _networkPreviewLength = 180;
  static const int _doubaoSuccessCode = 20000000;
  static const int _maxTranslationResponseBytes = kBytesPerMiB;
  static const String _doubaoDefaultResourceId = 'volc.speech.mt';
  static const int _translationCacheMaxEntries = 512;
  static const int _translationCacheMaxCharacters = 8 * kBytesPerMiB;
  static final LifecycleLruCache<AiTranslationResult> _translationCache =
      LifecycleLruCache<AiTranslationResult>(
        maxEntries: _translationCacheMaxEntries,
        maxCost: _translationCacheMaxCharacters,
        costOf: (result) =>
            result.text.length +
            (result.modelConfigId?.length ?? 0) +
            (result.modelId?.length ?? 0),
      );
  final OpenHandKeyedSingleFlight<String, AiTranslationResult>
  _translationFlights =
      OpenHandKeyedSingleFlight<String, AiTranslationResult>();

  final AiTransportClient _transport;
  final AiChatClient _chatClient;
  final bool _ownsChatClient;
  final Set<Completer<void>> _activeAiCancellations = <Completer<void>>{};
  bool _disposed = false;
  late final OpenHandRetryableAsyncCache<String> _aiPromptCache =
      OpenHandRetryableAsyncCache<String>(
        () => rootBundle.loadString(_aiPromptAsset, cache: false),
      );

  Future<AiTranslationResult> translate({
    required String text,
    required AiTranslationSettings settings,
    required List<AiModelConfig> availableModels,
    AiModelConfig? fallbackModel,
  }) async {
    _throwIfDisposed();
    final normalizedSettings = settings.normalized();
    final normalizedText = nullIfBlank(text);
    if (!normalizedSettings.enabled) {
      throw const AiTranslationException('文本翻译未开启。');
    }
    if (normalizedText == null) {
      throw const AiTranslationException('没有可翻译的文本。');
    }
    final boundedText = _truncateText(
      normalizedText,
      normalizedSettings.maxTextCharacters,
    );
    final timeout = Duration(seconds: normalizedSettings.timeoutSeconds);
    final deadline = MonotonicDeadline(timeout, timeoutMessage: '翻译超过总时限。');
    AiTranslationException? firstFailure;
    var triedAny = false;

    for (final provider in normalizedSettings.providerPriority) {
      _throwIfDisposed();
      final providerSettings = normalizedSettings
          .provider(provider)
          .normalized();
      if (!providerSettings.enabled) continue;
      triedAny = true;
      final remaining = deadline.remainingOrNull();
      if (remaining == null) {
        firstFailure ??= const AiTranslationException('翻译超过总时限。');
        break;
      }
      try {
        final result =
            await _translateWithCache(
              provider: provider,
              text: boundedText,
              settings: normalizedSettings,
              providerSettings: providerSettings,
              availableModels: availableModels,
              fallbackModel: fallbackModel,
              timeout: remaining,
            ).timeout(
              remaining,
              onTimeout: () => throw deadline.timeoutException(),
            );
        _throwIfDisposed();
        return result;
      } on AiTranslationException catch (error) {
        _throwIfDisposed();
        firstFailure ??= error;
      } on TimeoutException {
        _throwIfDisposed();
        firstFailure ??= AiTranslationException(
          '${provider.storageKey} 翻译超时。',
          provider: provider,
        );
        if (deadline.isExpired) break;
      } catch (error) {
        _throwIfDisposed();
        firstFailure ??= AiTranslationException(
          _friendlyTranslationError(error),
          provider: provider,
        );
      }
    }

    if (!triedAny) {
      throw const AiTranslationException('没有启用可用的翻译服务。');
    }
    throw firstFailure ?? const AiTranslationException('翻译失败。');
  }

  Future<AiTranslationResult> _translateWithCache({
    required AiTranslationProvider provider,
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
    required Duration timeout,
  }) async {
    final cacheKey = _translationCacheKey(
      provider: provider,
      text: text,
      settings: settings,
      providerSettings: providerSettings,
      availableModels: availableModels,
      fallbackModel: fallbackModel,
    );
    final cached = _translationCache.get(cacheKey);
    if (cached != null) return cached;

    return _translationFlights.run(cacheKey, () async {
      final result = await _translateProvider(
        provider: provider,
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        availableModels: availableModels,
        fallbackModel: fallbackModel,
        timeout: timeout,
      );
      if (!_disposed) _translationCache.put(cacheKey, result);
      return result;
    });
  }

  Future<AiTranslationResult> _translateProvider({
    required AiTranslationProvider provider,
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
    required Duration timeout,
  }) async {
    final translated = switch (provider) {
      AiTranslationProvider.ai => await _translateWithAi(
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        availableModels: availableModels,
        fallbackModel: fallbackModel,
        timeout: timeout,
      ),
      AiTranslationProvider.youdao => await _translateWithYoudao(
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        timeout: timeout,
      ),
      AiTranslationProvider.google => await _translateWithGoogle(
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        timeout: timeout,
      ),
      AiTranslationProvider.bing => await _translateWithBing(
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        timeout: timeout,
      ),
      AiTranslationProvider.apple => await _translateWithAppleBridge(
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        timeout: timeout,
      ),
      AiTranslationProvider.baidu => await _translateWithBaidu(
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        timeout: timeout,
      ),
      AiTranslationProvider.doubao => await _translateWithDoubao(
        text: text,
        settings: settings,
        providerSettings: providerSettings,
        timeout: timeout,
      ),
    };
    final cleanText = nullIfBlank(translated);
    if (cleanText == null) {
      throw AiTranslationException(
        '${provider.storageKey} 未返回翻译文本。',
        provider: provider,
      );
    }
    return AiTranslationResult(
      text: cleanText,
      provider: provider,
      modelConfigId: providerSettings.modelConfigId.isEmpty
          ? null
          : providerSettings.modelConfigId,
      modelId: providerSettings.modelId.isEmpty
          ? null
          : providerSettings.modelId,
    );
  }

  Future<String> _translateWithAi({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
    required Duration timeout,
  }) async {
    final model = _resolveAiModel(
      providerSettings: providerSettings,
      availableModels: availableModels,
      fallbackModel: fallbackModel,
    );
    if (model == null) {
      throw const AiTranslationException(
        'AI 翻译需要先选择一个可用模型。',
        provider: AiTranslationProvider.ai,
      );
    }
    final systemPrompt = await _aiPromptCache.load();
    final translationModel = model.protocolType == AiProtocolType.mimo
        ? model.copyWith(
            modelProfiles: <String, AiModelProfile>{
              ...model.modelProfiles,
              model.modelId: model
                  .profileFor(model.modelId)
                  .copyWith(
                    thinkingEnabled: false,
                    reasoningEffortControlEnabled: false,
                  ),
            },
          )
        : model;
    final cancellation = Completer<void>();
    _activeAiCancellations.add(cancellation);
    if (_disposed) cancellation.complete();
    try {
      _throwIfDisposed();
      final completion = await AiUsageTraceContext.runDerived(
        source: AiUsageSource.translation,
        operation: 'text_translation',
        body: () => _chatClient.sendMessage(
          model: translationModel,
          messages: <AiChatTurn>[
            AiChatTurn(role: AiChatRole.system, content: systemPrompt),
            AiChatTurn(
              role: AiChatRole.user,
              content: _buildAiUserPrompt(
                text: text,
                sourceLanguage: settings.sourceLanguage,
                targetLanguage: settings.targetLanguage,
              ),
            ),
          ],
          creationRequest: AiCreationRequest.none,
          timeout: timeout,
          cancelSignal: cancellation.future,
        ),
      );
      return _cleanAiTranslationOutput(completion.reply);
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      _activeAiCancellations.remove(cancellation);
    }
  }

  Future<String> _translateWithYoudao({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required Duration timeout,
  }) async {
    _requireFields(
      providerSettings,
      provider: AiTranslationProvider.youdao,
      fields: <String, String>{
        'API Key': providerSettings.apiKey,
        'API Secret': providerSettings.apiSecret,
      },
    );
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    final curtime = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signText =
        providerSettings.apiKey +
        _youdaoInput(text) +
        salt +
        curtime +
        providerSettings.apiSecret;
    final response = await _transport.sendForm(
      uri: Uri.parse(_endpointOrDefault(providerSettings)),
      method: 'POST',
      headers: const <String, String>{
        kContentTypeHeaderName: kFormUrlEncodedMimeType,
      },
      body: <String, String>{
        'q': text,
        'from': _youdaoLanguage(settings.sourceLanguage),
        'to': _youdaoLanguage(settings.targetLanguage),
        'appKey': providerSettings.apiKey,
        'salt': salt,
        'sign': sha256.convert(utf8.encode(signText)).toString(),
        'signType': 'v3',
        'curtime': curtime,
      },
      timeout: timeout,
      maxResponseBytes: _maxTranslationResponseBytes,
    );
    final json = _decodeObject(response, AiTranslationProvider.youdao);
    final errorCode = '${json['errorCode'] ?? ''}';
    if (errorCode.isNotEmpty && errorCode != '0') {
      throw AiTranslationException(
        '有道翻译失败：$errorCode',
        provider: AiTranslationProvider.youdao,
      );
    }
    final translation = json['translation'];
    if (translation is List && translation.isNotEmpty) {
      return '${translation.first}';
    }
    return _readTranslatedText(json);
  }

  Future<String> _translateWithGoogle({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required Duration timeout,
  }) async {
    _requireFields(
      providerSettings,
      provider: AiTranslationProvider.google,
      fields: <String, String>{'API Key': providerSettings.apiKey},
    );
    final uri = _withQuery(
      Uri.parse(_endpointOrDefault(providerSettings)),
      <String, String>{'key': providerSettings.apiKey},
    );
    final body = <String, Object?>{
      'q': text,
      'target': _googleLanguage(settings.targetLanguage),
      'format': 'text',
      if (settings.sourceLanguage != 'auto')
        'source': _googleLanguage(settings.sourceLanguage),
    };
    final response = await _transport.sendJson(
      uri: uri,
      method: 'POST',
      headers: const <String, String>{
        kContentTypeHeaderName: kApplicationJsonUtf8ContentType,
      },
      body: body,
      timeout: timeout,
      maxResponseBytes: _maxTranslationResponseBytes,
    );
    final json = _decodeObject(response, AiTranslationProvider.google);
    final data = json['data'];
    if (data is Map) {
      final translations = data['translations'];
      if (translations is List && translations.isNotEmpty) {
        final first = translations.first;
        if (first is Map && first['translatedText'] != null) {
          return '${first['translatedText']}';
        }
      }
    }
    return _readTranslatedText(json);
  }

  Future<String> _translateWithBing({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required Duration timeout,
  }) async {
    _requireFields(
      providerSettings,
      provider: AiTranslationProvider.bing,
      fields: <String, String>{'Subscription Key': providerSettings.apiKey},
    );
    final query = <String, String>{
      'api-version': '3.0',
      'to': _bingLanguage(settings.targetLanguage),
      if (settings.sourceLanguage != 'auto')
        'from': _bingLanguage(settings.sourceLanguage),
    };
    final response = await _transport.sendJson(
      uri: _withQuery(Uri.parse(_endpointOrDefault(providerSettings)), query),
      method: 'POST',
      headers: <String, String>{
        kContentTypeHeaderName: kApplicationJsonUtf8ContentType,
        'Ocp-Apim-Subscription-Key': providerSettings.apiKey,
        if (nullIfBlank(providerSettings.region) case final region?)
          'Ocp-Apim-Subscription-Region': region,
      },
      body: <Map<String, String>>[
        <String, String>{'Text': text},
      ],
      timeout: timeout,
      maxResponseBytes: _maxTranslationResponseBytes,
    );
    final decoded = _decodeJson(response, AiTranslationProvider.bing);
    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map) {
        final translations = first['translations'];
        if (translations is List && translations.isNotEmpty) {
          final candidate = translations.first;
          if (candidate is Map && candidate['text'] != null) {
            return '${candidate['text']}';
          }
        }
      }
    }
    if (decoded is Map<String, Object?>) {
      return _readTranslatedText(decoded);
    }
    throw const AiTranslationException(
      'Bing 翻译响应格式无效。',
      provider: AiTranslationProvider.bing,
    );
  }

  Future<String> _translateWithAppleBridge({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required Duration timeout,
  }) async {
    final endpoint = nullIfBlank(providerSettings.endpoint);
    if (endpoint == null) {
      throw const AiTranslationException(
        'Apple 翻译需要填写本机或私有桥接服务地址。',
        provider: AiTranslationProvider.apple,
      );
    }
    final headers = <String, String>{
      kContentTypeHeaderName: kApplicationJsonUtf8ContentType,
      if (nullIfBlank(providerSettings.apiKey) case final apiKey?)
        'x-api-key': apiKey,
      if (nullIfBlank(providerSettings.accessToken) case final accessToken?)
        kAuthorizationHeaderName: 'Bearer $accessToken',
    };
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint),
      method: 'POST',
      headers: headers,
      body: <String, Object?>{
        'text': text,
        'source_language': settings.sourceLanguage,
        'target_language': settings.targetLanguage,
      },
      timeout: timeout,
      maxResponseBytes: _maxTranslationResponseBytes,
    );
    final json = _decodeObject(response, AiTranslationProvider.apple);
    return _readTranslatedText(json);
  }

  Future<String> _translateWithBaidu({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required Duration timeout,
  }) async {
    _requireFields(
      providerSettings,
      provider: AiTranslationProvider.baidu,
      fields: <String, String>{
        'App ID': providerSettings.appId,
        'Secret Key': providerSettings.apiSecret,
      },
    );
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    final signText =
        providerSettings.appId + text + salt + providerSettings.apiSecret;
    final response = await _transport.sendForm(
      uri: Uri.parse(_endpointOrDefault(providerSettings)),
      method: 'POST',
      headers: const <String, String>{
        kContentTypeHeaderName: kFormUrlEncodedMimeType,
      },
      body: <String, String>{
        'q': text,
        'from': _baiduLanguage(settings.sourceLanguage),
        'to': _baiduLanguage(settings.targetLanguage),
        'appid': providerSettings.appId,
        'salt': salt,
        'sign': md5.convert(utf8.encode(signText)).toString(),
      },
      timeout: timeout,
      maxResponseBytes: _maxTranslationResponseBytes,
    );
    final json = _decodeObject(response, AiTranslationProvider.baidu);
    if (json['error_code'] != null) {
      throw AiTranslationException(
        '百度翻译失败：${json['error_code']} ${json['error_msg'] ?? ''}',
        provider: AiTranslationProvider.baidu,
      );
    }
    final result = json['trans_result'];
    if (result is List && result.isNotEmpty) {
      final first = result.first;
      if (first is Map && first['dst'] != null) return '${first['dst']}';
    }
    return _readTranslatedText(json);
  }

  Future<String> _translateWithDoubao({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required Duration timeout,
  }) async {
    final apiKey = nullIfBlank(providerSettings.apiKey);
    final appId = nullIfBlank(providerSettings.appId);
    final accessKey = nullIfBlank(providerSettings.apiSecret);
    if (apiKey == null && (appId == null || accessKey == null)) {
      throw const AiTranslationException(
        '豆包翻译需要 API Key，或 App ID 与 Access Key。',
        provider: AiTranslationProvider.doubao,
      );
    }
    final resourceId = _extraString(
      providerSettings,
      'resource_id',
      fallback: _doubaoDefaultResourceId,
    );
    final configuredRequestId = _extraString(providerSettings, 'request_id');
    final requestId = configuredRequestId.isEmpty
        ? const Uuid().v4()
        : configuredRequestId;
    final body = <String, Object?>{
      'target_language': _doubaoLanguage(settings.targetLanguage),
      'text_list': <String>[text],
    };
    if (settings.sourceLanguage != 'auto') {
      body['source_language'] = _doubaoLanguage(settings.sourceLanguage);
    }
    final corpus = _doubaoCorpus(providerSettings);
    if (corpus != null) body['corpus'] = corpus;

    final headers = <String, String>{
      kContentTypeHeaderName: kApplicationJsonUtf8ContentType,
      'X-Api-Resource-Id': resourceId,
      'X-Api-Request-Id': requestId,
      if (apiKey != null) 'X-Api-Key': apiKey,
      if (apiKey == null && appId != null) 'X-Api-App-Key': appId,
      if (apiKey == null && accessKey != null) 'X-Api-Access-Key': accessKey,
    };
    final response = await _transport.sendJson(
      uri: Uri.parse(_endpointOrDefault(providerSettings)),
      method: 'POST',
      headers: headers,
      body: body,
      timeout: timeout,
      maxResponseBytes: _maxTranslationResponseBytes,
    );
    final json = _decodeObject(response, AiTranslationProvider.doubao);
    final code = optionalIntFromValue(json['code']);
    if (code != null && code != _doubaoSuccessCode) {
      throw AiTranslationException(
        '豆包翻译失败：$code ${json['message'] ?? ''}',
        provider: AiTranslationProvider.doubao,
      );
    }
    final data = json['data'];
    if (data is Map) {
      final translations = data['translation_list'];
      if (translations is List && translations.isNotEmpty) {
        final first = translations.first;
        if (first is Map && first['translation'] != null) {
          return '${first['translation']}';
        }
      }
    }
    return _readTranslatedText(json);
  }

  AiModelConfig? _resolveAiModel({
    required AiTranslationProviderSettings providerSettings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) {
    final configId = nullIfBlank(providerSettings.modelConfigId);
    final modelId = nullIfBlank(providerSettings.modelId);
    if (configId != null && modelId != null) {
      for (final config in availableModels) {
        if (config.id == configId && config.allModelIds.contains(modelId)) {
          return config.copyWith(modelId: modelId);
        }
      }
    }
    return fallbackModel;
  }

  String _translationCacheKey({
    required AiTranslationProvider provider,
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) {
    final resolvedModel = provider == AiTranslationProvider.ai
        ? _resolveAiModel(
            providerSettings: providerSettings,
            availableModels: availableModels,
            fallbackModel: fallbackModel,
          )
        : null;
    return 'ai_translation:${provider.storageKey}:${stableJsonSha256(<String, Object?>{
      'version': 1,
      'text_sha256': stableJsonSha256(text),
      'provider': provider.storageKey,
      'settings': settings.toJson(),
      'provider_settings': providerSettings.toJson(),
      'effective_endpoint': _endpointOrDefault(providerSettings),
      if (provider == AiTranslationProvider.ai) ...<String, Object?>{'prompt_asset': _aiPromptAsset, 'model': resolvedModel?.toJson()},
    })}';
  }

  String _buildAiUserPrompt({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return [
      'Source language: ${sourceLanguage == 'auto' ? 'auto-detect' : sourceLanguage}',
      'Target language: $targetLanguage',
      '',
      '<text_to_translate>',
      text,
      '</text_to_translate>',
    ].join('\n');
  }

  void _requireFields(
    AiTranslationProviderSettings settings, {
    required AiTranslationProvider provider,
    required Map<String, String> fields,
  }) {
    final missing = <String>[];
    for (final entry in fields.entries) {
      if (nullIfBlank(entry.value) == null) missing.add(entry.key);
    }
    if (missing.isNotEmpty) {
      throw AiTranslationException(
        '${provider.storageKey} 翻译缺少配置：${missing.join('、')}。',
        provider: provider,
      );
    }
  }

  Object? _decodeJson(http.Response response, AiTranslationProvider provider) {
    if (isHttpFailureStatus(response.statusCode)) {
      throw AiTranslationException(
        '${provider.storageKey} 翻译请求失败（HTTP ${response.statusCode}）：${_preview(response.body)}',
        provider: provider,
      );
    }
    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw AiTranslationException(
        '${provider.storageKey} 翻译返回无效 JSON：${error.message}',
        provider: provider,
      );
    }
  }

  Map<String, Object?> _decodeObject(
    http.Response response,
    AiTranslationProvider provider,
  ) {
    final decoded = _decodeJson(response, provider);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return stringKeyedMapFromValue(decoded);
    throw AiTranslationException(
      '${provider.storageKey} 翻译响应格式无效。',
      provider: provider,
    );
  }

  Uri _withQuery(Uri base, Map<String, String> query) {
    final merged = <String, String>{...base.queryParameters, ...query};
    return base.replace(queryParameters: merged);
  }

  String _endpointOrDefault(AiTranslationProviderSettings settings) {
    return nullIfBlank(settings.endpoint) ??
        AiTranslationProviderSettings.defaults(settings.provider).endpoint;
  }

  String _truncateText(String text, int maxCharacters) {
    if (text.characters.length <= maxCharacters) return text;
    return text.characters.take(maxCharacters).toString();
  }

  String _youdaoInput(String input) {
    if (input.length <= 20) return input;
    final headEnd = safeUtf16PrefixCodeUnits(input, 10);
    final tailStart = safeUtf16SuffixStart(input, input.length - 10);
    return input.substring(0, headEnd) +
        input.length.toString() +
        input.substring(tailStart);
  }

  String _readTranslatedText(Map<String, Object?> json) {
    for (final key in const <String>[
      'translated_text',
      'translatedText',
      'translation',
      'text',
      'result',
    ]) {
      final value = json[key];
      if (value is String && nullIfBlank(value) != null) return value;
      if (value is List && value.isNotEmpty) return '${value.first}';
    }
    throw const AiTranslationException('翻译响应中没有可用文本。');
  }

  String _cleanAiTranslationOutput(String value) {
    var text = value.trim();
    final fenced = _aiTranslationFencePattern.firstMatch(text);
    if (fenced != null) {
      text = fenced.group(1)?.trim() ?? text;
    }
    return text;
  }

  String _preview(String value) {
    final compact = collapseInlineWhitespace(value);
    return clipText(compact, _networkPreviewLength);
  }

  String _friendlyTranslationError(Object error) {
    final text = error.toString().replaceFirst(
      _translationErrorPrefixPattern,
      '',
    );
    final normalized = collapseInlineWhitespace(text);
    if (normalized.isEmpty) return '翻译失败。';
    return clipText(normalized, _networkPreviewLength);
  }

  String _googleLanguage(String value) {
    return switch (value) {
      'zh-CN' => 'zh-CN',
      'zh-TW' => 'zh-TW',
      'ja' => 'ja',
      'ko' => 'ko',
      _ => value,
    };
  }

  String _bingLanguage(String value) {
    return switch (value) {
      'zh-CN' => 'zh-Hans',
      'zh-TW' => 'zh-Hant',
      'ja' => 'ja',
      'ko' => 'ko',
      _ => value,
    };
  }

  String _youdaoLanguage(String value) {
    return switch (value) {
      'zh-CN' => 'zh-CHS',
      'zh-TW' => 'zh-CHT',
      'ja' => 'ja',
      'ko' => 'ko',
      _ => value,
    };
  }

  String _baiduLanguage(String value) {
    return switch (value) {
      'zh-CN' => 'zh',
      'zh-TW' => 'cht',
      'ja' => 'jp',
      'ko' => 'kor',
      'fr' => 'fra',
      'es' => 'spa',
      'vi' => 'vie',
      'ar' => 'ara',
      _ => value,
    };
  }

  String _doubaoLanguage(String value) {
    return switch (value) {
      'zh-CN' => 'zh',
      'zh-TW' => 'zh-Hant',
      _ => value,
    };
  }

  String _extraString(
    AiTranslationProviderSettings settings,
    String key, {
    String fallback = '',
  }) {
    final value = settings.extra[key];
    if (value is String) {
      return nullIfBlank(value) ?? fallback;
    }
    return fallback;
  }

  Object? _doubaoCorpus(AiTranslationProviderSettings settings) {
    final rawObject = settings.extra['corpus'];
    if (rawObject is Map) return stringKeyedMapFromValue(rawObject);
    final rawJson = _extraString(settings, 'corpus_json');
    if (rawJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) return stringKeyedMapFromValue(decoded);
    } on FormatException catch (error) {
      throw AiTranslationException(
        '豆包语料库 JSON 无效：${error.message}',
        provider: AiTranslationProvider.doubao,
      );
    }
    throw const AiTranslationException(
      '豆包语料库 JSON 必须是对象。',
      provider: AiTranslationProvider.doubao,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final cancellation in _activeAiCancellations.toList(growable: false)) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _activeAiCancellations.clear();
    _transport.dispose();
    if (_ownsChatClient) {
      _chatClient.dispose();
    }
  }

  void _throwIfDisposed() {
    if (_disposed) throw const AiTranslationException('翻译服务已释放。');
  }
}
