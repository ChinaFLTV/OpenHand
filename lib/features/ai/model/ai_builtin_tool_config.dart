import 'dart:convert';

import '../../../app/support/silent_log.dart';
import '../service/ai_tool_runtime_service.dart';

export '../service/ai_tool_runtime_service.dart' show AiBuiltinToolKind;

/// 内建工具的加载策略。
enum AiBuiltinToolLoadStrategy {
  /// 立即加载（默认）：工具在目录解析时立即可用。
  eager,

  /// 懒加载：工具仅在首次被模型调用时才初始化完整上下文。
  lazy,

  /// 缓加载：工具延迟到系统空闲时再初始化，降低启动耗时。
  deferred,
}

/// 单个内建工具的用户可定制配置。
///
/// 设计原则：
/// - 每个 [AiBuiltinToolKind] 对应一份 [AiBuiltinToolConfig]。
/// - 不存在的 kind 由 [defaults()] 兜底补全。
/// - 用户仅能覆盖名称、描述、Prompt 补充、参数 Schema、优先级等元数据，
///   工具的执行逻辑本身不受影响。
class AiBuiltinToolConfig {
  const AiBuiltinToolConfig({
    required this.kind,
    this.enabled = true,
    this.displayName,
    this.summary,
    this.promptOverride,
    this.schemaOverride,
    this.priority = 100,
    this.sortOrder = 0,
    this.loadStrategy = AiBuiltinToolLoadStrategy.eager,
    this.tags = const <String>[],
    this.maxOutputChars,
    this.timeoutSeconds,
    this.requireConfirmation,
    this.isCustom = false,
    this.customToolName,
    this.customDescription,
    this.customParameters,
  });

  /// 工具类型标识。
  final AiBuiltinToolKind kind;

  /// 是否启用该工具。禁用后不会出现在工具目录中。
  final bool enabled;

  /// 用户自定义的显示名称（覆盖默认名称）。
  final String? displayName;

  /// 用户自定义的简要说明。
  final String? summary;

  /// 附加的 Prompt 覆盖/补充（会追加到工具 description 后面）。
  final String? promptOverride;

  /// 覆盖默认 JSON Schema 参数定义。
  /// 为 null 时使用内建默认 Schema。
  final Map<String, Object?>? schemaOverride;

  /// 优先级数值。数值越小优先级越高。默认 100。
  /// 影响工具在目录中的呈现顺序。
  final int priority;

  /// 显示排序序号。数值越小越靠前。
  final int sortOrder;

  /// 加载策略。
  final AiBuiltinToolLoadStrategy loadStrategy;

  /// 用户标签（分类、筛选用）。
  final List<String> tags;

  /// 单次调用输出上限（字符数）。null 表示使用全局默认。
  final int? maxOutputChars;

  /// 单次调用超时（秒）。null 表示使用全局默认。
  final int? timeoutSeconds;

  /// 是否需要用户手动确认后才执行。null 表示使用工具自身默认行为。
  final bool? requireConfirmation;

  /// 是否为用户自定义的"新增"工具（非内建 kind 映射）。
  final bool isCustom;

  /// 仅当 [isCustom] = true 时有效的自定义工具名称。
  final String? customToolName;

  /// 仅当 [isCustom] = true 时有效的自定义工具描述。
  final String? customDescription;

  /// 仅当 [isCustom] = true 时有效的自定义工具参数 Schema JSON 字符串。
  final String? customParameters;

  /// 生效的工具名称。
  String get effectiveName {
    if (isCustom &&
        customToolName != null &&
        customToolName!.trim().isNotEmpty) {
      return customToolName!.trim();
    }
    return displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : kind.name;
  }

  /// 生效的描述。
  String get effectiveDescription {
    final base = isCustom ? (customDescription ?? '') : '';
    final prompt = promptOverride?.trim() ?? '';
    if (base.isNotEmpty && prompt.isNotEmpty) {
      return '$base\n\n$prompt';
    }
    return base.isNotEmpty ? base : prompt;
  }

  AiBuiltinToolConfig copyWith({
    AiBuiltinToolKind? kind,
    bool? enabled,
    String? displayName,
    String? summary,
    String? promptOverride,
    Map<String, Object?>? schemaOverride,
    int? priority,
    int? sortOrder,
    AiBuiltinToolLoadStrategy? loadStrategy,
    List<String>? tags,
    int? maxOutputChars,
    int? timeoutSeconds,
    bool? requireConfirmation,
    bool? isCustom,
    String? customToolName,
    String? customDescription,
    String? customParameters,
    bool clearDisplayName = false,
    bool clearSummary = false,
    bool clearPromptOverride = false,
    bool clearSchemaOverride = false,
    bool clearMaxOutputChars = false,
    bool clearTimeoutSeconds = false,
    bool clearRequireConfirmation = false,
    bool clearCustomToolName = false,
    bool clearCustomDescription = false,
    bool clearCustomParameters = false,
  }) {
    return AiBuiltinToolConfig(
      kind: kind ?? this.kind,
      enabled: enabled ?? this.enabled,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      summary: clearSummary ? null : (summary ?? this.summary),
      promptOverride: clearPromptOverride
          ? null
          : (promptOverride ?? this.promptOverride),
      schemaOverride: clearSchemaOverride
          ? null
          : (schemaOverride ?? this.schemaOverride),
      priority: priority ?? this.priority,
      sortOrder: sortOrder ?? this.sortOrder,
      loadStrategy: loadStrategy ?? this.loadStrategy,
      tags: tags ?? this.tags,
      maxOutputChars: clearMaxOutputChars
          ? null
          : (maxOutputChars ?? this.maxOutputChars),
      timeoutSeconds: clearTimeoutSeconds
          ? null
          : (timeoutSeconds ?? this.timeoutSeconds),
      requireConfirmation: clearRequireConfirmation
          ? null
          : (requireConfirmation ?? this.requireConfirmation),
      isCustom: isCustom ?? this.isCustom,
      customToolName: clearCustomToolName
          ? null
          : (customToolName ?? this.customToolName),
      customDescription: clearCustomDescription
          ? null
          : (customDescription ?? this.customDescription),
      customParameters: clearCustomParameters
          ? null
          : (customParameters ?? this.customParameters),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'enabled': enabled,
      if (displayName != null) 'display_name': displayName,
      if (summary != null) 'summary': summary,
      if (promptOverride != null) 'prompt_override': promptOverride,
      if (schemaOverride != null) 'schema_override': jsonEncode(schemaOverride),
      'priority': priority,
      'sort_order': sortOrder,
      'load_strategy': loadStrategy.name,
      if (tags.isNotEmpty) 'tags': tags,
      if (maxOutputChars != null) 'max_output_chars': maxOutputChars,
      if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
      if (requireConfirmation != null)
        'require_confirmation': requireConfirmation,
      'is_custom': isCustom,
      if (customToolName != null) 'custom_tool_name': customToolName,
      if (customDescription != null) 'custom_description': customDescription,
      if (customParameters != null) 'custom_parameters': customParameters,
    };
  }

  static AiBuiltinToolConfig fromJson(Map<String, Object?> json) {
    final kindStr = '${json['kind'] ?? ''}'.trim();
    final kind = AiBuiltinToolKind.values
        .where((k) => k.name == kindStr)
        .firstOrNull;
    if (kind == null) {
      throw FormatException('Unknown AiBuiltinToolKind: $kindStr');
    }
    Map<String, Object?>? schemaOverride;
    final rawSchema = json['schema_override'];
    if (rawSchema is String && rawSchema.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSchema);
        if (decoded is Map) {
          schemaOverride = Map<String, Object?>.from(decoded);
        }
      } catch (error, stack) {
        silentLog('ai_builtin_tool_config', 'decode schema_override JSON string', error, stack);
      }
    } else if (rawSchema is Map) {
      schemaOverride = Map<String, Object?>.from(rawSchema);
    }

    final rawLoadStrategy = '${json['load_strategy'] ?? ''}'.trim();
    final loadStrategy =
        AiBuiltinToolLoadStrategy.values
            .where((s) => s.name == rawLoadStrategy)
            .firstOrNull ??
        AiBuiltinToolLoadStrategy.eager;

    final rawTags = json['tags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final t in rawTags) {
        final s = '$t'.trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }

    return AiBuiltinToolConfig(
      kind: kind,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      displayName: json['display_name'] is String
          ? json['display_name'] as String
          : null,
      summary: json['summary'] is String ? json['summary'] as String : null,
      promptOverride: json['prompt_override'] is String
          ? json['prompt_override'] as String
          : null,
      schemaOverride: schemaOverride,
      priority: (json['priority'] as num?)?.toInt() ?? 100,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      loadStrategy: loadStrategy,
      tags: tags,
      maxOutputChars: (json['max_output_chars'] as num?)?.toInt(),
      timeoutSeconds: (json['timeout_seconds'] as num?)?.toInt(),
      requireConfirmation: json['require_confirmation'] is bool
          ? json['require_confirmation'] as bool
          : null,
      isCustom: json['is_custom'] is bool ? json['is_custom'] as bool : false,
      customToolName: json['custom_tool_name'] is String
          ? json['custom_tool_name'] as String
          : null,
      customDescription: json['custom_description'] is String
          ? json['custom_description'] as String
          : null,
      customParameters: json['custom_parameters'] is String
          ? json['custom_parameters'] as String
          : null,
    );
  }

  /// 为所有内建工具类型生成默认配置列表。
  static List<AiBuiltinToolConfig> defaults() {
    return AiBuiltinToolKind.values
        .map((kind) => AiBuiltinToolConfig(kind: kind, sortOrder: kind.index))
        .toList();
  }
}
