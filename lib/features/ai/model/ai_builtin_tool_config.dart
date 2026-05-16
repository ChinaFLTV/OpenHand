import 'dart:convert';

import '../../../app/support/silent_log.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_web_fetch_settings.dart';
import 'ai_web_search_settings.dart';

export '../service/runtime/ai_tool_runtime_service.dart' show AiBuiltinToolKind;
export 'ai_web_fetch_settings.dart';
export 'ai_web_search_settings.dart';

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
    this.retryOnFailure = false,
    this.maxRetries = 0,
    this.retryBackoffMs = defaultRetryBackoffMs,
    this.isCustom = false,
    this.customToolName,
    this.customDescription,
    this.customParameters,
    this.webSearchSettings,
    this.webFetchSettings,
  });

  /// 单次工具调用未在用户层面显式覆盖时使用的默认超时秒数（2026-04-29）。
  /// 之前为 null 时由调用方各自决定，现在统一为 20s 以避免内建工具长时间挂起。
  static const int defaultTimeoutSeconds = 20;

  /// 失败/超时重试的硬上限。即便用户把 [maxRetries] 设得很大，
  /// 也不会超过此值，避免错误指数级放大。
  static const int maxRetriesUpperBound = 5;

  /// 重试间隔（毫秒）的默认值——首轮重试等待 200ms，后续按指数退避。
  static const int defaultRetryBackoffMs = 200;

  /// 重试间隔（毫秒）的硬上限：单次等待最多 30s，避免任意大数把流程卡死。
  static const int maxRetryBackoffMs = 30000;

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

  /// 失败或超时后是否自动重试。默认 false。
  /// 仅在工具调用产生明确失败状态（status=failed/timed_out 或抛出异常）
  /// 时才会触发重试；invalid_arguments / 已确认拒绝执行等状态不会重试。
  final bool retryOnFailure;

  /// 最多重试次数（不含首次执行）。范围 [0, [maxRetriesUpperBound]]。
  /// 仅当 [retryOnFailure] = true 时生效。
  final int maxRetries;

  /// 重试前的基础等待间隔（毫秒）。第 N 次重试实际等待
  /// `retryBackoffMs * (1 << (N-1))` 毫秒（指数退避，封顶 [maxRetryBackoffMs]）。
  /// 设为 0 表示无等待立即重试（不推荐）。
  final int retryBackoffMs;

  /// 实际生效的超时秒数（毫秒级 Duration 由调用方包装）。
  int get effectiveTimeoutSeconds {
    final raw = timeoutSeconds ?? defaultTimeoutSeconds;
    if (raw <= 0) return defaultTimeoutSeconds;
    return raw;
  }

  /// 实际生效的重试次数（已 clamp 到上限）。
  int get effectiveMaxRetries {
    if (!retryOnFailure) return 0;
    if (maxRetries <= 0) return 0;
    if (maxRetries > maxRetriesUpperBound) return maxRetriesUpperBound;
    return maxRetries;
  }

  /// 实际生效的退避基线（毫秒），已 clamp 到 [0, [maxRetryBackoffMs]]。
  int get effectiveRetryBackoffMs {
    if (retryBackoffMs <= 0) return 0;
    if (retryBackoffMs > maxRetryBackoffMs) return maxRetryBackoffMs;
    return retryBackoffMs;
  }

  /// 计算第 [attemptIndex]（1-based: 第 1 次重试 = 1）次重试前应等待的毫秒数。
  /// 指数退避：base * 2^(attemptIndex-1)，上限 [maxRetryBackoffMs]。
  Duration retryBackoffFor(int attemptIndex) {
    if (attemptIndex <= 0) return Duration.zero;
    final base = effectiveRetryBackoffMs;
    if (base == 0) return Duration.zero;
    final shift = attemptIndex - 1;
    final raw = shift >= 30 ? maxRetryBackoffMs : base << shift;
    final capped = raw > maxRetryBackoffMs ? maxRetryBackoffMs : raw;
    return Duration(milliseconds: capped);
  }

  /// 是否为用户自定义的"新增"工具（非内建 kind 映射）。
  final bool isCustom;

  /// 仅当 [isCustom] = true 时有效的自定义工具名称。
  final String? customToolName;

  /// 仅当 [isCustom] = true 时有效的自定义工具描述。
  final String? customDescription;

  /// 仅当 [isCustom] = true 时有效的自定义工具参数 Schema JSON 字符串。
  final String? customParameters;

  /// 仅 [AiBuiltinToolKind.webSearch] 工具会读取该字段：sub-agent 调度、引擎数据源
  /// 列表、summary 控制等。其他工具的 [webSearchSettings] 应为 null。
  final AiWebSearchSettings? webSearchSettings;

  /// 仅 [AiBuiltinToolKind.webFetch] 工具会读取该字段：多数据源 fan-out
  /// 调度 / 本地缓存 / 并行参数。其他工具的 [webFetchSettings] 应为 null。
  final AiWebFetchSettings? webFetchSettings;

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
    bool? retryOnFailure,
    int? maxRetries,
    int? retryBackoffMs,
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
    AiWebSearchSettings? webSearchSettings,
    bool clearWebSearchSettings = false,
    AiWebFetchSettings? webFetchSettings,
    bool clearWebFetchSettings = false,
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
      retryOnFailure: retryOnFailure ?? this.retryOnFailure,
      maxRetries: maxRetries ?? this.maxRetries,
      retryBackoffMs: retryBackoffMs ?? this.retryBackoffMs,
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
      webSearchSettings: clearWebSearchSettings
          ? null
          : (webSearchSettings ?? this.webSearchSettings),
      webFetchSettings: clearWebFetchSettings
          ? null
          : (webFetchSettings ?? this.webFetchSettings),
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
      'retry_on_failure': retryOnFailure,
      'max_retries': maxRetries,
      'retry_backoff_ms': retryBackoffMs,
      'is_custom': isCustom,
      if (customToolName != null) 'custom_tool_name': customToolName,
      if (customDescription != null) 'custom_description': customDescription,
      if (customParameters != null) 'custom_parameters': customParameters,
      if (webSearchSettings != null)
        'web_search_settings': webSearchSettings!.toJson(),
      if (webFetchSettings != null)
        'web_fetch_settings': webFetchSettings!.toJson(),
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
      retryOnFailure: json['retry_on_failure'] is bool
          ? json['retry_on_failure'] as bool
          : false,
      maxRetries: (json['max_retries'] as num?)?.toInt() ?? 0,
      retryBackoffMs:
          (json['retry_backoff_ms'] as num?)?.toInt() ?? defaultRetryBackoffMs,
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
      webSearchSettings: AiWebSearchSettings.fromJson(
        json['web_search_settings'],
      ),
      webFetchSettings: AiWebFetchSettings.fromJson(
        json['web_fetch_settings'],
      ),
    );
  }

  /// 为所有内建工具类型生成默认配置列表。
  static List<AiBuiltinToolConfig> defaults() {
    return AiBuiltinToolKind.values
        .map(
          (kind) => AiBuiltinToolConfig(
            kind: kind,
            sortOrder: kind.index,
            webSearchSettings: kind == AiBuiltinToolKind.webSearch
                ? AiWebSearchSettings.defaults()
                : null,
            webFetchSettings: kind == AiBuiltinToolKind.webFetch
                ? AiWebFetchSettings.defaults()
                : null,
          ),
        )
        .toList();
  }
}
