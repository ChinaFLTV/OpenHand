import '../../../shared/util/input_value_parsing.dart';
import 'ai_lsp_backend_catalog.dart';

class AiLspLanguageSettings {
  const AiLspLanguageSettings({
    this.backendId = '',
    this.rootPath = '',
    this.sdkPath = '',
    this.version = '',
  });

  final String backendId;
  final String rootPath;
  final String sdkPath;
  final String version;

  bool get isEmpty =>
      nullIfBlank(backendId) == null &&
      nullIfBlank(rootPath) == null &&
      nullIfBlank(sdkPath) == null &&
      nullIfBlank(version) == null;

  String get normalizedVersion => nullIfBlank(version) ?? 'latest';

  AiLspLanguageSettings copyWith({
    String? backendId,
    String? rootPath,
    String? sdkPath,
    String? version,
    bool clearBackendId = false,
    bool clearRootPath = false,
    bool clearSdkPath = false,
    bool clearVersion = false,
  }) {
    return AiLspLanguageSettings(
      backendId: clearBackendId ? '' : (backendId ?? this.backendId),
      rootPath: clearRootPath ? '' : (rootPath ?? this.rootPath),
      sdkPath: clearSdkPath ? '' : (sdkPath ?? this.sdkPath),
      version: clearVersion ? '' : (version ?? this.version),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backend_id': nullIfBlank(backendId) ?? '',
      'root_path': nullIfBlank(rootPath) ?? '',
      'sdk_path': nullIfBlank(sdkPath) ?? '',
      'version': nullIfBlank(version) ?? '',
    };
  }

  static AiLspLanguageSettings fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiLspLanguageSettings(
      backendId: stringFromValue(json['backend_id']),
      rootPath: stringFromValue(json['root_path']),
      sdkPath: stringFromValue(json['sdk_path']),
      version: stringFromValue(json['version']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AiLspLanguageSettings &&
        other.backendId == backendId &&
        other.rootPath == rootPath &&
        other.sdkPath == sdkPath &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(backendId, rootPath, sdkPath, version);
}

Map<String, AiLspLanguageSettings> normalizeAiLspLanguageSettingsMap(
  Map<String, AiLspLanguageSettings> value,
) {
  final normalized = <String, AiLspLanguageSettings>{};
  for (final entry in value.entries) {
    final language = normalizeAiLspLanguage(entry.key);
    if (language == 'plaintext' || entry.value.isEmpty) {
      continue;
    }
    normalized[language] = entry.value;
  }
  return Map<String, AiLspLanguageSettings>.unmodifiable(normalized);
}
