import 'dart:convert';

import '../../../app/support/silent_log.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_web_fetch_settings.dart';
import 'ai_web_search_settings.dart';

export '../service/runtime/ai_tool_runtime_service.dart' show AiBuiltinToolKind;
export 'ai_web_fetch_settings.dart';
export 'ai_web_search_settings.dart';

enum AiAgentBuiltinToolGroup {
  discovery,
  taskLifecycle,
  governance,
  operations,
  cluster,
}

class AiAgentBuiltinToolMetadata {
  const AiAgentBuiltinToolMetadata({
    required this.canonicalName,
    required this.group,
    required this.labelZh,
    required this.labelEn,
    required this.summaryZh,
    required this.summaryEn,
    this.isCore = false,
    this.isMutation = false,
  });

  final String canonicalName;
  final AiAgentBuiltinToolGroup group;
  final String labelZh;
  final String labelEn;
  final String summaryZh;
  final String summaryEn;
  final bool isCore;
  final bool isMutation;
}

/// 只读内建工具：不改动工作区、不发起写操作，可安全交给并行子代理。
///
/// Task 子代理与数字员工 worker 此前各写了一份同样的十项名单；新增只读工具
/// 时漏改一处，就会出现「同一个工具在 Task 子代理里可用、在员工里不可用」
/// 这种说不通的差异。
const Set<AiBuiltinToolKind> kAiReadOnlyBuiltinToolKinds = <AiBuiltinToolKind>{
  AiBuiltinToolKind.glob,
  AiBuiltinToolKind.grep,
  AiBuiltinToolKind.ls,
  AiBuiltinToolKind.read,
  AiBuiltinToolKind.webFetch,
  AiBuiltinToolKind.webSearch,
  AiBuiltinToolKind.lsp,
  AiBuiltinToolKind.codebaseSearch,
  AiBuiltinToolKind.git,
  AiBuiltinToolKind.readLints,
};

const List<AiBuiltinToolKind> aiAgentBuiltinToolKinds = <AiBuiltinToolKind>[
  AiBuiltinToolKind.agentList,
  AiBuiltinToolKind.agentDetail,
  AiBuiltinToolKind.agentActivityLog,
  AiBuiltinToolKind.agentAuditReport,
  AiBuiltinToolKind.agentAuditRecord,
  AiBuiltinToolKind.agentApprovalRequest,
  AiBuiltinToolKind.agentKpiUpsert,
  AiBuiltinToolKind.agentResourceUpdate,
  AiBuiltinToolKind.agentClusterConfigure,
  AiBuiltinToolKind.agentClusterStatus,
  AiBuiltinToolKind.agentTaskList,
  AiBuiltinToolKind.agentTaskPublish,
  AiBuiltinToolKind.agentTaskTrack,
  AiBuiltinToolKind.agentTaskProgress,
  AiBuiltinToolKind.agentTaskCancel,
  AiBuiltinToolKind.agentTaskPause,
  AiBuiltinToolKind.agentTaskTerminate,
  AiBuiltinToolKind.agentTaskResume,
  AiBuiltinToolKind.agentTaskComplete,
  AiBuiltinToolKind.agentTaskResult,
];

const Map<AiBuiltinToolKind, AiAgentBuiltinToolMetadata>
aiAgentBuiltinToolMetadataByKind =
    <AiBuiltinToolKind, AiAgentBuiltinToolMetadata>{
      AiBuiltinToolKind.agentList: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentList',
        group: AiAgentBuiltinToolGroup.discovery,
        labelZh: '智能体列表',
        labelEn: 'Agent list',
        summaryZh: '发现可用智能体',
        summaryEn: 'Discover available agents',
        isCore: true,
      ),
      AiBuiltinToolKind.agentDetail: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentDetail',
        group: AiAgentBuiltinToolGroup.discovery,
        labelZh: '智能体详情',
        labelEn: 'Agent detail',
        summaryZh: '读取职责与绑定能力',
        summaryEn: 'Read profile and bindings',
      ),
      AiBuiltinToolKind.agentActivityLog: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentActivityLog',
        group: AiAgentBuiltinToolGroup.governance,
        labelZh: '活动记录',
        labelEn: 'Activity log',
        summaryZh: '查看工作循环输出',
        summaryEn: 'Read work-loop output',
      ),
      AiBuiltinToolKind.agentAuditReport: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentAuditReport',
        group: AiAgentBuiltinToolGroup.governance,
        labelZh: '审计报表',
        labelEn: 'Audit report',
        summaryZh: '汇总能力与任务审计',
        summaryEn: 'Summarize audit metrics',
      ),
      AiBuiltinToolKind.agentAuditRecord: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentAuditRecord',
        group: AiAgentBuiltinToolGroup.governance,
        labelZh: '写入审计',
        labelEn: 'Audit record',
        summaryZh: '记录能力调用审计',
        summaryEn: 'Write capability audit',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentApprovalRequest: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentApprovalRequest',
        group: AiAgentBuiltinToolGroup.governance,
        labelZh: '审批请求',
        labelEn: 'Approval request',
        summaryZh: '提交 mentor 审批',
        summaryEn: 'Request mentor approval',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentKpiUpsert: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentKpiUpsert',
        group: AiAgentBuiltinToolGroup.operations,
        labelZh: 'KPI 维护',
        labelEn: 'KPI upsert',
        summaryZh: '创建或更新 KPI',
        summaryEn: 'Create or update KPI',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentResourceUpdate: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentResourceUpdate',
        group: AiAgentBuiltinToolGroup.operations,
        labelZh: '资源更新',
        labelEn: 'Resource update',
        summaryZh: '登记资源占用',
        summaryEn: 'Record resource usage',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentClusterConfigure: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentClusterConfigure',
        group: AiAgentBuiltinToolGroup.cluster,
        labelZh: '集群配置',
        labelEn: 'Cluster configure',
        summaryZh: '调整 worker 池策略',
        summaryEn: 'Tune worker pool policy',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentClusterStatus: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentClusterStatus',
        group: AiAgentBuiltinToolGroup.cluster,
        labelZh: '集群状态',
        labelEn: 'Cluster status',
        summaryZh: '读取 worker 状态',
        summaryEn: 'Read worker status',
      ),
      AiBuiltinToolKind.agentTaskList: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskList',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务列表',
        labelEn: 'Task list',
        summaryZh: '筛选任务台任务',
        summaryEn: 'Filter task desk',
      ),
      AiBuiltinToolKind.agentTaskPublish: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskPublish',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务发布',
        labelEn: 'Task publish',
        summaryZh: '向匹配智能体派发任务',
        summaryEn: 'Delegate matched work',
        isCore: true,
        isMutation: true,
      ),
      AiBuiltinToolKind.agentTaskTrack: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskTrack',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务追踪',
        labelEn: 'Task track',
        summaryZh: '读取完整任务状态',
        summaryEn: 'Read full task state',
        isCore: true,
      ),
      AiBuiltinToolKind.agentTaskProgress: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskProgress',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务进度',
        labelEn: 'Task progress',
        summaryZh: '轮询进度与下一步',
        summaryEn: 'Poll progress and next step',
      ),
      AiBuiltinToolKind.agentTaskCancel: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskCancel',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务取消',
        labelEn: 'Task cancel',
        summaryZh: '撤销队列或运行任务',
        summaryEn: 'Cancel queued or active task',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentTaskPause: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskPause',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务暂停',
        labelEn: 'Task pause',
        summaryZh: '暂停任务等待介入',
        summaryEn: 'Pause for intervention',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentTaskTerminate: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskTerminate',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务终止',
        labelEn: 'Task terminate',
        summaryZh: '异常终止并标记失败',
        summaryEn: 'Abort and mark failed',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentTaskResume: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskResume',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务恢复',
        labelEn: 'Task resume',
        summaryZh: '恢复暂停任务',
        summaryEn: 'Resume paused task',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentTaskComplete: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskComplete',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务完成',
        labelEn: 'Task complete',
        summaryZh: '回写任务结果',
        summaryEn: 'Write task result',
        isMutation: true,
      ),
      AiBuiltinToolKind.agentTaskResult: AiAgentBuiltinToolMetadata(
        canonicalName: 'AgentTaskResult',
        group: AiAgentBuiltinToolGroup.taskLifecycle,
        labelZh: '任务结果',
        labelEn: 'Task result',
        summaryZh: '读取终态结果',
        summaryEn: 'Read terminal result',
        isCore: true,
      ),
    };

AiAgentBuiltinToolMetadata? agentBuiltinToolMetadata(AiBuiltinToolKind kind) {
  return aiAgentBuiltinToolMetadataByKind[kind];
}

String agentBuiltinToolCanonicalName(AiBuiltinToolKind kind) {
  final metadata = agentBuiltinToolMetadata(kind);
  if (metadata != null) return metadata.canonicalName;
  final name = kind.name;
  if (name.isEmpty) return '';
  return '${name[0].toUpperCase()}${name.substring(1)}';
}

const String aiAgentToolAccessEnabledMetadataKey = 'agent_tools_enabled';
const String aiAgentToolAllowedAgentIdsMetadataKey = 'allowed_agent_ids';
const String aiAgentToolAccessSourceMetadataKey = 'agent_tool_access_source';

extension AiBuiltinToolKindMachineTerminalMetadata on AiBuiltinToolKind {
  bool get isMachineTerminalTool {
    return switch (this) {
      AiBuiltinToolKind.machineTerminalRead ||
      AiBuiltinToolKind.machineTerminalWrite ||
      AiBuiltinToolKind.machineTerminalExec ||
      AiBuiltinToolKind.machineTerminalControl => true,
      _ => false,
    };
  }

  bool get isMachineTerminalMutationTool {
    return switch (this) {
      AiBuiltinToolKind.machineTerminalWrite ||
      AiBuiltinToolKind.machineTerminalExec ||
      AiBuiltinToolKind.machineTerminalControl => true,
      _ => false,
    };
  }
}

extension AiBuiltinToolKindAgentMetadata on AiBuiltinToolKind {
  bool get isAgentCoordinationTool {
    return agentBuiltinToolMetadata(this) != null;
  }

  bool get isAgentCoreCoordinationTool {
    return agentBuiltinToolMetadata(this)?.isCore ?? false;
  }

  AiAgentBuiltinToolGroup? get agentToolGroup {
    return agentBuiltinToolMetadata(this)?.group;
  }

  bool get isAgentMutationTool {
    return agentBuiltinToolMetadata(this)?.isMutation ?? false;
  }
}

/// 内建工具的加载策略。
enum AiBuiltinToolLoadStrategy {
  /// 立即加载（默认）：工具在目录解析时立即可用。
  eager,

  /// 懒加载：工具仅在首次被模型调用时才初始化完整上下文。
  lazy,

  /// 缓加载：工具延迟到系统空闲时再初始化，降低启动耗时。
  deferred,
}

/// 内建工具 schema 懒加载模式。
enum AiBuiltinToolLazyLoadingMode {
  /// 始终直接携带全部已启用内建工具 schema。
  disabled('disabled'),

  /// 内建工具 schema 总体积超过阈值时才启用懒加载。
  auto('auto'),

  /// 始终启用懒加载，但强制加载/立即加载工具仍直接携带。
  enabled('enabled');

  const AiBuiltinToolLazyLoadingMode(this.storageValue);

  final String storageValue;

  static AiBuiltinToolLazyLoadingMode fromStorage(String? raw) {
    return enumByStorageValueOr(
      values,
      raw,
      (mode) => mode.storageValue,
      fallback: AiBuiltinToolLazyLoadingMode.auto,
      normalize: (value) => value.toLowerCase(),
    );
  }
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
    this.forceLoad = false,
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

  /// 单次工具调用未在用户层面显式覆盖时使用的默认超时秒数。
  /// 统一默认值可避免调用方遗漏边界而长时间挂起。
  static const int defaultTimeoutSeconds = 20;

  /// 单次工具调用可配置超时下限。
  static const int minTimeoutSeconds = 1;

  /// 单次工具调用可配置超时上限，避免极端配置造成近似无限等待。
  static const int maxTimeoutSeconds = 600;

  /// 失败/超时重试的硬上限。即便用户把 [maxRetries] 设得很大，
  /// 也不会超过此值，避免错误指数级放大。
  static const int maxRetriesUpperBound = 5;

  /// 重试间隔（毫秒）的默认值——首轮重试等待 200ms，后续按指数退避。
  static const int defaultRetryBackoffMs = 200;

  /// 重试间隔（毫秒）的硬上限：单次等待最多 30s，避免任意大数把流程卡死。
  static const int maxRetryBackoffMs = 30000;
  static const IntValueRange _maxRetriesRange = IntValueRange(
    fallback: 0,
    min: 0,
    max: maxRetriesUpperBound,
  );
  static const IntValueRange _retryBackoffMsRange = IntValueRange(
    fallback: defaultRetryBackoffMs,
    min: 0,
    max: maxRetryBackoffMs,
  );

  static int maxRetriesFromValue(Object? value) {
    return _maxRetriesRange.fromValue(value);
  }

  static int normalizeMaxRetries(int value) {
    return _maxRetriesRange.normalize(value);
  }

  static int retryBackoffMsFromValue(Object? value) {
    return _retryBackoffMsRange.fromValue(value);
  }

  static int normalizeRetryBackoffMs(int value) {
    return _retryBackoffMsRange.normalize(value);
  }

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

  /// 即使全局内建工具懒加载处于自动/开启，也强制直接携带该工具 schema。
  final bool forceLoad;

  /// 用户标签（分类、筛选用）。
  final List<String> tags;

  /// 单次调用输出上限（字符数）。null 表示使用全局默认。
  final int? maxOutputChars;

  /// 单次调用外层运行时超时（秒）。null 表示使用全局默认。
  /// 仅作为无副作用工具的兜底护栏；Task / Bash / 写工具使用各自可控边界。
  final int? timeoutSeconds;

  /// 是否需要用户手动确认后才执行。null 表示使用工具自身默认行为。
  final bool? requireConfirmation;

  /// 失败或超时后是否自动重试。默认 false。
  /// 仅用于无副作用工具的瞬时失败；Task、写文件、Bash、后台进程、
  /// 技能管理、Memory 写入等可能产生副作用的调用会由运行时禁止自动重放。
  /// invalid_arguments / 已确认拒绝执行等状态不会重试。
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
    if (raw > maxTimeoutSeconds) return maxTimeoutSeconds;
    return raw;
  }

  /// 实际生效的重试次数（已 clamp 到上限）。
  int get effectiveMaxRetries {
    if (!retryOnFailure) return 0;
    return normalizeMaxRetries(maxRetries);
  }

  /// 实际生效的退避基线（毫秒），已 clamp 到 [0, [maxRetryBackoffMs]]。
  int get effectiveRetryBackoffMs => normalizeRetryBackoffMs(retryBackoffMs);

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
    final customName = nullIfBlank(customToolName);
    if (isCustom && customName != null) {
      return customName;
    }
    return nullIfBlank(displayName) ?? kind.name;
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
    bool? forceLoad,
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
      forceLoad: forceLoad ?? this.forceLoad,
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
      maxRetries: normalizeMaxRetries(maxRetries ?? this.maxRetries),
      retryBackoffMs: normalizeRetryBackoffMs(
        retryBackoffMs ?? this.retryBackoffMs,
      ),
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
      'force_load': forceLoad,
      if (tags.isNotEmpty) 'tags': tags,
      if (maxOutputChars != null) 'max_output_chars': maxOutputChars,
      if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
      if (requireConfirmation != null)
        'require_confirmation': requireConfirmation,
      'retry_on_failure': retryOnFailure,
      'max_retries': normalizeMaxRetries(maxRetries),
      'retry_backoff_ms': normalizeRetryBackoffMs(retryBackoffMs),
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

  static AiBuiltinToolConfig fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) {
      throw const FormatException('Expected AiBuiltinToolConfig object');
    }
    final kindStr = stringFromValue(json['kind']);
    final kind = enumByName(AiBuiltinToolKind.values, kindStr);
    if (kind == null) {
      throw FormatException('Unknown AiBuiltinToolKind: $kindStr');
    }
    Map<String, Object?>? schemaOverride;
    final rawSchema = json['schema_override'];
    if (rawSchema is String && rawSchema.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSchema);
        if (decoded is Map) {
          schemaOverride = stringKeyedMapFromValue(decoded);
        }
      } catch (error, stack) {
        silentLog(
          'ai_builtin_tool_config',
          '解码 schema_override JSON 字符串',
          error,
          stack,
        );
      }
    } else if (rawSchema is Map) {
      schemaOverride = stringKeyedMapFromValue(rawSchema);
    }

    final rawLoadStrategy = stringFromValue(json['load_strategy']);
    final loadStrategy = enumByNameOr(
      AiBuiltinToolLoadStrategy.values,
      rawLoadStrategy,
      fallback: AiBuiltinToolLoadStrategy.eager,
    );

    final tags = stringListFromValueOrJsonText(json['tags']);

    return AiBuiltinToolConfig(
      kind: kind,
      enabled: boolFromValue(json['enabled'], defaultValue: true),
      displayName: optionalStringFromValue(json['display_name']),
      summary: optionalStringFromValue(json['summary']),
      promptOverride: optionalStringFromValue(json['prompt_override']),
      schemaOverride: schemaOverride,
      priority: intFromValue(json['priority'], fallback: 100),
      sortOrder: intFromValue(json['sort_order'], fallback: kind.index),
      loadStrategy: loadStrategy,
      forceLoad: boolFromValue(
        json['force_load'],
        defaultValue: defaultForceLoadForKind(kind),
      ),
      tags: tags,
      maxOutputChars: optionalIntFromValue(json['max_output_chars']),
      timeoutSeconds: optionalIntFromValue(json['timeout_seconds']),
      requireConfirmation: optionalBoolFromValue(json['require_confirmation']),
      retryOnFailure: boolFromValue(json['retry_on_failure']),
      maxRetries: maxRetriesFromValue(json['max_retries']),
      retryBackoffMs: retryBackoffMsFromValue(json['retry_backoff_ms']),
      isCustom: boolFromValue(json['is_custom']),
      customToolName: optionalStringFromValue(json['custom_tool_name']),
      customDescription: optionalStringFromValue(json['custom_description']),
      customParameters: optionalStringFromValue(json['custom_parameters']),
      webSearchSettings: AiWebSearchSettings.fromJson(
        json['web_search_settings'],
      ),
      webFetchSettings: AiWebFetchSettings.fromJson(json['web_fetch_settings']),
    );
  }

  /// 返回内建工具在默认配置中是否强制直接加载。
  static bool defaultForceLoadForKind(AiBuiltinToolKind kind) {
    return defaultLoadStrategyForKind(kind) == AiBuiltinToolLoadStrategy.eager;
  }

  /// 返回内建工具在默认配置中的视觉/Prompt 优先级。数值越小越优先。
  static int defaultPriorityForKind(AiBuiltinToolKind kind) {
    if (kind.isAgentCoreCoordinationTool) return 80;
    if (kind.isAgentCoordinationTool) return 110;
    return switch (kind) {
      AiBuiltinToolKind.machineTerminalRead ||
      AiBuiltinToolKind.machineTerminalWrite ||
      AiBuiltinToolKind.machineTerminalExec ||
      AiBuiltinToolKind.machineTerminalControl => 10,
      AiBuiltinToolKind.task ||
      AiBuiltinToolKind.todoWrite ||
      AiBuiltinToolKind.toolSearch ||
      AiBuiltinToolKind.exitPlanMode => 20,
      AiBuiltinToolKind.glob ||
      AiBuiltinToolKind.grep ||
      AiBuiltinToolKind.ls ||
      AiBuiltinToolKind.read ||
      AiBuiltinToolKind.lsp ||
      AiBuiltinToolKind.codebaseSearch ||
      AiBuiltinToolKind.git ||
      AiBuiltinToolKind.readLints => 30,
      AiBuiltinToolKind.edit ||
      AiBuiltinToolKind.multiEdit ||
      AiBuiltinToolKind.applyFileDiffs ||
      AiBuiltinToolKind.write ||
      AiBuiltinToolKind.notebookEdit ||
      AiBuiltinToolKind.deleteFile => 40,
      AiBuiltinToolKind.webSearch || AiBuiltinToolKind.webFetch => 60,
      AiBuiltinToolKind.knowledgeSearch ||
      AiBuiltinToolKind.knowledgeRead => 65,
      AiBuiltinToolKind.skillManager || AiBuiltinToolKind.memory => 70,
      AiBuiltinToolKind.taskOutput || AiBuiltinToolKind.taskStop => 85,
      AiBuiltinToolKind.bash => 90,
      AiBuiltinToolKind.bashBackground => 95,
      AiBuiltinToolKind.dingTalkToolSearch => 13,
      AiBuiltinToolKind.dingtalkDws => 100,
      AiBuiltinToolKind.dingtalkImageGeneration ||
      AiBuiltinToolKind.dingtalkVideoGeneration ||
      AiBuiltinToolKind.dingtalkAudioGeneration => 100,
      _ => 100,
    };
  }

  /// 返回内建工具在默认配置中的展示顺序。
  static int defaultSortOrderForKind(AiBuiltinToolKind kind) {
    return switch (kind) {
      AiBuiltinToolKind.machineTerminalRead => 0,
      AiBuiltinToolKind.machineTerminalWrite => 1,
      AiBuiltinToolKind.machineTerminalExec => 2,
      AiBuiltinToolKind.machineTerminalControl => 3,
      AiBuiltinToolKind.task => 10,
      AiBuiltinToolKind.todoWrite => 11,
      AiBuiltinToolKind.toolSearch => 12,
      AiBuiltinToolKind.dingTalkToolSearch => 13,
      AiBuiltinToolKind.glob => 20,
      AiBuiltinToolKind.grep => 21,
      AiBuiltinToolKind.ls => 22,
      AiBuiltinToolKind.read => 23,
      AiBuiltinToolKind.lsp => 24,
      AiBuiltinToolKind.codebaseSearch => 25,
      AiBuiltinToolKind.readLints => 26,
      AiBuiltinToolKind.git => 27,
      AiBuiltinToolKind.edit => 40,
      AiBuiltinToolKind.multiEdit => 41,
      AiBuiltinToolKind.applyFileDiffs => 42,
      AiBuiltinToolKind.write => 43,
      AiBuiltinToolKind.notebookEdit => 44,
      AiBuiltinToolKind.deleteFile => 45,
      AiBuiltinToolKind.exitPlanMode => 50,
      AiBuiltinToolKind.askUserChoice => 51,
      AiBuiltinToolKind.webSearch => 60,
      AiBuiltinToolKind.webFetch => 61,
      AiBuiltinToolKind.knowledgeSearch => 70,
      AiBuiltinToolKind.knowledgeRead => 71,
      AiBuiltinToolKind.skillManager => 72,
      AiBuiltinToolKind.memory => 73,
      AiBuiltinToolKind.taskOutput => 80,
      AiBuiltinToolKind.taskStop => 81,
      AiBuiltinToolKind.bash => 90,
      AiBuiltinToolKind.bashBackground => 91,
      AiBuiltinToolKind.dingtalkDws => 100,
      AiBuiltinToolKind.dingtalkImageGeneration => 101,
      AiBuiltinToolKind.dingtalkVideoGeneration => 102,
      AiBuiltinToolKind.dingtalkAudioGeneration => 103,
      AiBuiltinToolKind.agentList => 200,
      AiBuiltinToolKind.agentDetail => 201,
      AiBuiltinToolKind.agentActivityLog => 202,
      AiBuiltinToolKind.agentAuditReport => 203,
      AiBuiltinToolKind.agentAuditRecord => 204,
      AiBuiltinToolKind.agentApprovalRequest => 205,
      AiBuiltinToolKind.agentKpiUpsert => 206,
      AiBuiltinToolKind.agentResourceUpdate => 207,
      AiBuiltinToolKind.agentClusterConfigure => 208,
      AiBuiltinToolKind.agentClusterStatus => 209,
      AiBuiltinToolKind.agentTaskList => 210,
      AiBuiltinToolKind.agentTaskPublish => 211,
      AiBuiltinToolKind.agentTaskTrack => 212,
      AiBuiltinToolKind.agentTaskProgress => 213,
      AiBuiltinToolKind.agentTaskCancel => 214,
      AiBuiltinToolKind.agentTaskPause => 215,
      AiBuiltinToolKind.agentTaskTerminate => 216,
      AiBuiltinToolKind.agentTaskResume => 217,
      AiBuiltinToolKind.agentTaskComplete => 218,
      AiBuiltinToolKind.agentTaskResult => 219,
    };
  }

  /// 返回内建工具在默认配置中的加载策略。
  static AiBuiltinToolLoadStrategy defaultLoadStrategyForKind(
    AiBuiltinToolKind kind,
  ) {
    if (kind.isAgentCoreCoordinationTool) {
      return AiBuiltinToolLoadStrategy.eager;
    }
    if (kind.isAgentCoordinationTool) {
      return AiBuiltinToolLoadStrategy.lazy;
    }
    switch (kind) {
      case AiBuiltinToolKind.task:
      case AiBuiltinToolKind.bash:
      case AiBuiltinToolKind.glob:
      case AiBuiltinToolKind.grep:
      case AiBuiltinToolKind.ls:
      case AiBuiltinToolKind.exitPlanMode:
      case AiBuiltinToolKind.read:
      case AiBuiltinToolKind.edit:
      case AiBuiltinToolKind.todoWrite:
      case AiBuiltinToolKind.toolSearch:
      case AiBuiltinToolKind.dingTalkToolSearch:
      case AiBuiltinToolKind.dingtalkDws:
      case AiBuiltinToolKind.dingtalkImageGeneration:
      case AiBuiltinToolKind.dingtalkVideoGeneration:
      case AiBuiltinToolKind.dingtalkAudioGeneration:
      case AiBuiltinToolKind.knowledgeSearch:
      case AiBuiltinToolKind.knowledgeRead:
      case AiBuiltinToolKind.machineTerminalRead:
      case AiBuiltinToolKind.machineTerminalWrite:
      case AiBuiltinToolKind.machineTerminalExec:
      case AiBuiltinToolKind.machineTerminalControl:
        return AiBuiltinToolLoadStrategy.eager;
      case AiBuiltinToolKind.bashBackground:
      case AiBuiltinToolKind.taskOutput:
      case AiBuiltinToolKind.taskStop:
      case AiBuiltinToolKind.multiEdit:
      case AiBuiltinToolKind.applyFileDiffs:
      case AiBuiltinToolKind.write:
      case AiBuiltinToolKind.notebookEdit:
      case AiBuiltinToolKind.webFetch:
      case AiBuiltinToolKind.webSearch:
      case AiBuiltinToolKind.lsp:
      case AiBuiltinToolKind.codebaseSearch:
      case AiBuiltinToolKind.git:
      case AiBuiltinToolKind.deleteFile:
      case AiBuiltinToolKind.readLints:
      case AiBuiltinToolKind.askUserChoice:
      case AiBuiltinToolKind.skillManager:
      case AiBuiltinToolKind.memory:
      default:
        return AiBuiltinToolLoadStrategy.lazy;
    }
  }

  static bool looksLikeLegacyEagerDefaults(List<AiBuiltinToolConfig> configs) {
    return _looksLikeLegacyDefaults(configs, _looksLikeLegacyEagerDefault);
  }

  static bool looksLikeLegacyBuiltinOrderingDefaults(
    List<AiBuiltinToolConfig> configs,
  ) {
    return _looksLikeLegacyDefaults(
      configs,
      _looksLikeLegacyBuiltinOrderingDefault,
    );
  }

  static bool _looksLikeLegacyDefaults(
    List<AiBuiltinToolConfig> configs,
    bool Function(AiBuiltinToolConfig config) matches,
  ) {
    if (configs.length != AiBuiltinToolKind.values.length) return false;
    final byKind = <AiBuiltinToolKind, AiBuiltinToolConfig>{};
    for (final config in configs) {
      if (byKind.containsKey(config.kind)) return false;
      byKind[config.kind] = config;
    }
    for (final kind in AiBuiltinToolKind.values) {
      final config = byKind[kind];
      if (config == null || !matches(config)) {
        return false;
      }
    }
    return true;
  }

  static bool _looksLikeLegacyEagerDefault(AiBuiltinToolConfig config) {
    return _looksLikeLegacyDefaultConfig(
      config,
      loadStrategy: AiBuiltinToolLoadStrategy.eager,
    );
  }

  static bool _looksLikeLegacyBuiltinOrderingDefault(
    AiBuiltinToolConfig config,
  ) {
    return _looksLikeLegacyDefaultConfig(
      config,
      loadStrategy: defaultLoadStrategyForKind(config.kind),
      forceLoad: defaultForceLoadForKind(config.kind),
    );
  }

  static bool _looksLikeLegacyDefaultConfig(
    AiBuiltinToolConfig config, {
    required AiBuiltinToolLoadStrategy loadStrategy,
    bool? forceLoad,
  }) {
    if (!config.enabled ||
        config.displayName != null ||
        config.summary != null ||
        config.promptOverride != null ||
        config.schemaOverride != null ||
        config.priority != 100 ||
        config.sortOrder != config.kind.index ||
        config.loadStrategy != loadStrategy ||
        (forceLoad != null && config.forceLoad != forceLoad) ||
        config.tags.isNotEmpty ||
        config.maxOutputChars != null ||
        config.timeoutSeconds != null ||
        config.requireConfirmation != null ||
        config.retryOnFailure ||
        config.maxRetries != 0 ||
        config.retryBackoffMs != defaultRetryBackoffMs ||
        config.isCustom ||
        config.customToolName != null ||
        config.customDescription != null ||
        config.customParameters != null) {
      return false;
    }
    return _defaultProviderSettingsEquivalent(config);
  }

  static bool _defaultProviderSettingsEquivalent(AiBuiltinToolConfig config) {
    final expectedWebSearch = config.kind == AiBuiltinToolKind.webSearch
        ? AiWebSearchSettings.defaults()
        : null;
    final expectedWebFetch = config.kind == AiBuiltinToolKind.webFetch
        ? AiWebFetchSettings.defaults()
        : null;
    return _jsonEquivalent(
          config.webSearchSettings?.toJson(),
          expectedWebSearch?.toJson(),
        ) &&
        _jsonEquivalent(
          config.webFetchSettings?.toJson(),
          expectedWebFetch?.toJson(),
        );
  }

  static bool _jsonEquivalent(Object? left, Object? right) {
    if (left == null || right == null) return left == right;
    return stableJsonEquals(left, right);
  }

  /// 为所有内建工具类型生成默认配置列表。
  static List<AiBuiltinToolConfig> defaults() {
    final configs = AiBuiltinToolKind.values
        .map(
          (kind) => AiBuiltinToolConfig(
            kind: kind,
            priority: defaultPriorityForKind(kind),
            sortOrder: defaultSortOrderForKind(kind),
            loadStrategy: defaultLoadStrategyForKind(kind),
            forceLoad: defaultForceLoadForKind(kind),
            webSearchSettings: kind == AiBuiltinToolKind.webSearch
                ? AiWebSearchSettings.defaults()
                : null,
            webFetchSettings: kind == AiBuiltinToolKind.webFetch
                ? AiWebFetchSettings.defaults()
                : null,
          ),
        )
        .toList();
    configs.sort((a, b) {
      final sortOrderCompare = a.sortOrder.compareTo(b.sortOrder);
      if (sortOrderCompare != 0) return sortOrderCompare;
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.kind.index.compareTo(b.kind.index);
    });
    return configs;
  }
}
