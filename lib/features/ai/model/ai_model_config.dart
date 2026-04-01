import '../../../l10n/app_localizations.dart';

enum AiAuthScheme {
  none('none'),
  bearer('bearer'),
  token('token'),
  apiKey('api_key');

  const AiAuthScheme(this.storageValue);

  final String storageValue;

  static bool isValidStorageValue(String? value) {
    return AiAuthScheme.values.any((item) => item.storageValue == value);
  }

  static AiAuthScheme fromStorage(String? value) {
    return AiAuthScheme.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiAuthScheme.bearer,
    );
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      AiAuthScheme.none => l10n.aiAuthNone,
      AiAuthScheme.bearer => l10n.aiAuthBearer,
      AiAuthScheme.token => l10n.aiAuthToken,
      AiAuthScheme.apiKey => l10n.aiAuthApiKey,
    };
  }

  String apply(String rawToken) {
    return switch (this) {
      AiAuthScheme.none => '',
      AiAuthScheme.bearer => 'Bearer $rawToken',
      AiAuthScheme.token => 'Token $rawToken',
      AiAuthScheme.apiKey => rawToken,
    };
  }
}

enum AiProtocolType {
  openai('openai'),
  claude('claude'),
  gemini('gemini'),
  deepseek('deepseek'),
  qwen('qwen'),
  kimi('kimi'),
  glm('glm'),
  grok('grok');

  const AiProtocolType(this.storageValue);

  final String storageValue;

  static bool isValidStorageValue(String? value) {
    return AiProtocolType.values.any((item) => item.storageValue == value);
  }

  static AiProtocolType fromStorage(String? value) {
    return AiProtocolType.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiProtocolType.openai,
    );
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      AiProtocolType.openai => l10n.aiProtocolOpenAi,
      AiProtocolType.claude => l10n.aiProtocolClaude,
      AiProtocolType.gemini => l10n.aiProtocolGemini,
      AiProtocolType.deepseek => l10n.aiProtocolDeepSeek,
      AiProtocolType.qwen => 'Qwen',
      AiProtocolType.kimi => l10n.aiProtocolKimi,
      AiProtocolType.glm => l10n.aiProtocolGlm,
      AiProtocolType.grok => l10n.aiProtocolGrok,
    };
  }
}

class AiModelConfig {

  factory AiModelConfig.fromJson(Map<String, Object?> json) {
    return AiModelConfig(
      id: '${json['id'] ?? ''}'.trim(),
      baseUrl: _normalizeBaseUrl('${json['base_url'] ?? ''}'),
      authScheme: AiAuthScheme.fromStorage('${json['auth_scheme'] ?? ''}'),
      token: '${json['token'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}'.trim(),
      protocolType: AiProtocolType.fromStorage(
        '${json['protocol_type'] ?? ''}',
      ),
      maxContextTokens: _readNullablePositiveInt(json['max_context_tokens']),
    );
  }
  const AiModelConfig({
    required this.id,
    required this.baseUrl,
    required this.authScheme,
    required this.token,
    required this.modelId,
    required this.protocolType,
    this.maxContextTokens,
  });

  final String id;
  final String baseUrl;
  final AiAuthScheme authScheme;
  final String token;
  final String modelId;
  final AiProtocolType protocolType;
  final int? maxContextTokens;

  String get normalizedBaseUrl => _normalizeBaseUrl(baseUrl);

  String get displayName {
    final trimmedModelId = modelId.trim();
    if (trimmedModelId.isNotEmpty) {
      return trimmedModelId;
    }
    return protocolType.storageValue.toUpperCase();
  }

  String get maskedToken {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      return '';
    }
    if (trimmedToken.length <= 8) {
      return '*' * trimmedToken.length;
    }
    final visibleSuffix = trimmedToken.substring(trimmedToken.length - 4);
    return '${'*' * (trimmedToken.length - 4)}$visibleSuffix';
  }

  AiModelConfig copyWith({
    String? id,
    String? baseUrl,
    AiAuthScheme? authScheme,
    String? token,
    String? modelId,
    AiProtocolType? protocolType,
    int? maxContextTokens,
    bool clearMaxContextTokens = false,
  }) {
    return AiModelConfig(
      id: id ?? this.id,
      baseUrl: _normalizeBaseUrl(baseUrl ?? this.baseUrl),
      authScheme: authScheme ?? this.authScheme,
      token: token ?? this.token,
      modelId: modelId ?? this.modelId,
      protocolType: protocolType ?? this.protocolType,
      maxContextTokens: clearMaxContextTokens
          ? null
          : maxContextTokens ?? this.maxContextTokens,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'base_url': normalizedBaseUrl,
      'auth_scheme': authScheme.storageValue,
      'token': token,
      'model_id': modelId.trim(),
      'protocol_type': protocolType.storageValue,
      'max_context_tokens': maxContextTokens,
    };
  }

  static String _normalizeBaseUrl(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return '';
    }
    return trimmedValue.endsWith('/')
        ? trimmedValue.substring(0, trimmedValue.length - 1)
        : trimmedValue;
  }

  static int? _readNullablePositiveInt(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is num) {
      final normalized = value.toInt();
      return normalized > 0 ? normalized : null;
    }
    final parsed = int.tryParse('${value ?? ''}'.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }
}
