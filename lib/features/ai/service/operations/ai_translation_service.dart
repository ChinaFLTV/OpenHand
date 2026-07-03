import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_translation_settings.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';

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
    : _client = client ?? SystemProxyResolver.instance.createHttpClient(),
      _chatClient = chatClient ?? AiChatService();

  static const String _aiPromptAsset =
      'assets/prompts/common/ai_translation_system_prompt.md';
  static const int _networkPreviewLength = 180;
  static const int _doubaoSuccessCode = 20000000;
  static const String _doubaoDefaultResourceId = 'volc.speech.mt';
  static const int _translationCacheMaxEntries = 512;
  static final LifecycleLruCache<AiTranslationResult> _translationCache =
      LifecycleLruCache<AiTranslationResult>(
        maxEntries: _translationCacheMaxEntries,
      );
  static final Map<String, Future<AiTranslationResult>> _translationInFlight =
      <String, Future<AiTranslationResult>>{};

  final http.Client _client;
  final AiChatClient _chatClient;
  Future<String>? _aiPromptFuture;

  Future<AiTranslationResult> translate({
    required String text,
    required AiTranslationSettings settings,
    required List<AiModelConfig> availableModels,
    AiModelConfig? fallbackModel,
  }) async {
    final normalizedSettings = settings.normalized();
    final normalizedText = text.trim();
    if (!normalizedSettings.enabled) {
      throw const AiTranslationException('文本翻译未开启。');
    }
    if (normalizedText.isEmpty) {
      throw const AiTranslationException('没有可翻译的文本。');
    }
    final boundedText = _truncateText(
      normalizedText,
      normalizedSettings.maxTextCharacters,
    );
    final timeout = Duration(seconds: normalizedSettings.timeoutSeconds);
    AiTranslationException? firstFailure;
    var triedAny = false;

    for (final provider in normalizedSettings.providerPriority) {
      final providerSettings = normalizedSettings
          .provider(provider)
          .normalized();
      if (!providerSettings.enabled) continue;
      triedAny = true;
      try {
        return await _translateWithCache(
          provider: provider,
          text: boundedText,
          settings: normalizedSettings,
          providerSettings: providerSettings,
          availableModels: availableModels,
          fallbackModel: fallbackModel,
          timeout: timeout,
        );
      } on AiTranslationException catch (error) {
        firstFailure ??= error;
      } on TimeoutException {
        firstFailure ??= AiTranslationException(
          '${provider.storageKey} translation timed out.',
          provider: provider,
        );
      } catch (error) {
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

    final inFlight = _translationInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final request =
        _translateProvider(
          provider: provider,
          text: text,
          settings: settings,
          providerSettings: providerSettings,
          availableModels: availableModels,
          fallbackModel: fallbackModel,
          timeout: timeout,
        ).then((result) {
          _translationCache.put(cacheKey, result);
          return result;
        });
    _translationInFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      if (identical(_translationInFlight[cacheKey], request)) {
        _translationInFlight.remove(cacheKey);
      }
    }
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
    final cleanText = translated.trim();
    if (cleanText.isEmpty) {
      throw AiTranslationException(
        '${provider.storageKey} returned an empty translation.',
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
    final systemPrompt = await _loadAiPrompt();
    final completion = await _chatClient.sendMessage(
      model: model,
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
    );
    return _cleanAiTranslationOutput(completion.reply);
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
    final response = await _client
        .post(
          Uri.parse(_endpointOrDefault(providerSettings)),
          headers: const <String, String>{
            'content-type': 'application/x-www-form-urlencoded',
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
        )
        .timeout(timeout);
    final json = _decodeObject(response, AiTranslationProvider.youdao);
    final errorCode = '${json['errorCode'] ?? ''}';
    if (errorCode.isNotEmpty && errorCode != '0') {
      throw AiTranslationException(
        'Youdao translation failed: $errorCode',
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
    final response = await _client
        .post(
          uri,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
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
    final response = await _client
        .post(
          _withQuery(Uri.parse(_endpointOrDefault(providerSettings)), query),
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'Ocp-Apim-Subscription-Key': providerSettings.apiKey,
            if (providerSettings.region.trim().isNotEmpty)
              'Ocp-Apim-Subscription-Region': providerSettings.region.trim(),
          },
          body: jsonEncode(<Map<String, String>>[
            <String, String>{'Text': text},
          ]),
        )
        .timeout(timeout);
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
      'Bing translation response is invalid.',
      provider: AiTranslationProvider.bing,
    );
  }

  Future<String> _translateWithAppleBridge({
    required String text,
    required AiTranslationSettings settings,
    required AiTranslationProviderSettings providerSettings,
    required Duration timeout,
  }) async {
    if (providerSettings.endpoint.trim().isEmpty) {
      throw const AiTranslationException(
        'Apple 翻译需要填写本机或私有桥接服务地址。',
        provider: AiTranslationProvider.apple,
      );
    }
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      if (providerSettings.apiKey.trim().isNotEmpty)
        'x-api-key': providerSettings.apiKey.trim(),
      if (providerSettings.accessToken.trim().isNotEmpty)
        'authorization': 'Bearer ${providerSettings.accessToken.trim()}',
    };
    final response = await _client
        .post(
          Uri.parse(providerSettings.endpoint.trim()),
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'text': text,
            'source_language': settings.sourceLanguage,
            'target_language': settings.targetLanguage,
          }),
        )
        .timeout(timeout);
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
    final response = await _client
        .post(
          Uri.parse(_endpointOrDefault(providerSettings)),
          headers: const <String, String>{
            'content-type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{
            'q': text,
            'from': _baiduLanguage(settings.sourceLanguage),
            'to': _baiduLanguage(settings.targetLanguage),
            'appid': providerSettings.appId,
            'salt': salt,
            'sign': md5.convert(utf8.encode(signText)).toString(),
          },
        )
        .timeout(timeout);
    final json = _decodeObject(response, AiTranslationProvider.baidu);
    if (json['error_code'] != null) {
      throw AiTranslationException(
        'Baidu translation failed: ${json['error_code']} ${json['error_msg'] ?? ''}',
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
    final apiKey = providerSettings.apiKey.trim();
    final appId = providerSettings.appId.trim();
    final accessKey = providerSettings.apiSecret.trim();
    if (apiKey.isEmpty && (appId.isEmpty || accessKey.isEmpty)) {
      throw const AiTranslationException(
        'Doubao translation needs API Key or App ID + Access Key.',
        provider: AiTranslationProvider.doubao,
      );
    }
    final resourceId = _extraString(
      providerSettings,
      'resource_id',
      fallback: _doubaoDefaultResourceId,
    );
    final requestId = _extraString(providerSettings, 'request_id').isEmpty
        ? const Uuid().v4()
        : _extraString(providerSettings, 'request_id');
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
      'content-type': 'application/json; charset=utf-8',
      'X-Api-Resource-Id': resourceId,
      'X-Api-Request-Id': requestId,
      if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
      if (apiKey.isEmpty) 'X-Api-App-Key': appId,
      if (apiKey.isEmpty) 'X-Api-Access-Key': accessKey,
    };
    final response = await _client
        .post(
          Uri.parse(_endpointOrDefault(providerSettings)),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final json = _decodeObject(response, AiTranslationProvider.doubao);
    final code = _intValue(json['code']);
    if (code != null && code != _doubaoSuccessCode) {
      throw AiTranslationException(
        'Doubao translation failed: $code ${json['message'] ?? ''}',
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

  Future<String> _loadAiPrompt() {
    return _aiPromptFuture ??= rootBundle.loadString(_aiPromptAsset);
  }

  AiModelConfig? _resolveAiModel({
    required AiTranslationProviderSettings providerSettings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) {
    final configId = providerSettings.modelConfigId.trim();
    final modelId = providerSettings.modelId.trim();
    if (configId.isNotEmpty && modelId.isNotEmpty) {
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
      if (entry.value.trim().isEmpty) missing.add(entry.key);
    }
    if (missing.isNotEmpty) {
      throw AiTranslationException(
        '${provider.storageKey} translation is missing ${missing.join(', ')}.',
        provider: provider,
      );
    }
  }

  Object? _decodeJson(http.Response response, AiTranslationProvider provider) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiTranslationException(
        '${provider.storageKey} translation HTTP ${response.statusCode}: ${_preview(response.body)}',
        provider: provider,
      );
    }
    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw AiTranslationException(
        '${provider.storageKey} translation returned invalid JSON: ${error.message}',
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
      '${provider.storageKey} translation response is invalid.',
      provider: provider,
    );
  }

  Uri _withQuery(Uri base, Map<String, String> query) {
    final merged = <String, String>{...base.queryParameters, ...query};
    return base.replace(queryParameters: merged);
  }

  String _endpointOrDefault(AiTranslationProviderSettings settings) {
    final endpoint = settings.endpoint.trim();
    if (endpoint.isNotEmpty) return endpoint;
    return AiTranslationProviderSettings.defaults(settings.provider).endpoint;
  }

  String _truncateText(String text, int maxCharacters) {
    if (text.characters.length <= maxCharacters) return text;
    return text.characters.take(maxCharacters).toString();
  }

  String _youdaoInput(String input) {
    if (input.length <= 20) return input;
    return input.substring(0, 10) +
        input.length.toString() +
        input.substring(input.length - 10);
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
      if (value is String && value.trim().isNotEmpty) return value;
      if (value is List && value.isNotEmpty) return '${value.first}';
    }
    throw const AiTranslationException('翻译响应中没有可用文本。');
  }

  String _cleanAiTranslationOutput(String value) {
    var text = value.trim();
    final fenced = RegExp(
      r'^```(?:[a-zA-Z0-9_-]+)?\s*([\s\S]*?)\s*```$',
    ).firstMatch(text);
    if (fenced != null) {
      text = fenced.group(1)?.trim() ?? text;
    }
    return text;
  }

  String _preview(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= _networkPreviewLength) return compact;
    return '${compact.substring(0, _networkPreviewLength)}...';
  }

  String _friendlyTranslationError(Object error) {
    final text = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'translation failed';
    if (normalized.length <= _networkPreviewLength) return normalized;
    return '${normalized.substring(0, _networkPreviewLength)}...';
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
      final trimmed = value.trim();
      return trimmed.isEmpty ? fallback : trimmed;
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
        'Doubao corpus JSON is invalid: ${error.message}',
        provider: AiTranslationProvider.doubao,
      );
    }
    throw const AiTranslationException(
      'Doubao corpus JSON must be an object.',
      provider: AiTranslationProvider.doubao,
    );
  }

  int? _intValue(Object? value) {
    return optionalIntFromValue(value);
  }

  void dispose() {
    _client.close();
    _chatClient.dispose();
  }
}
