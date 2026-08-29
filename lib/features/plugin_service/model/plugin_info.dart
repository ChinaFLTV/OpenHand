import '../../../shared/util/version_compare.dart';

/// 插件基本信息模型。
///
/// 每个可选插件（NodeJS / PlayWright 等）对应一个 [PluginInfo] 实例，
/// 描述其名称、版本、安装状态、依赖关系等元数据。
enum PluginStatus {
  /// 未安装
  notInstalled,

  /// 已安装且可用
  installed,

  /// 正在安装中
  installing,

  /// 正在更新中
  updating,

  /// 正在卸载中
  uninstalling,

  /// 安装/更新/卸载失败
  error,
}

class PluginCatalogIds {
  const PluginCatalogIds._();

  static const String nodejs = 'nodejs';
  static const String playwright = 'playwright';
  static const String python = 'python';
  static const String pip = 'pip';
  static const String java = 'java';
  static const String frida = 'frida';
  static const String mitmproxy = 'mitmproxy';
  static const String apktool = 'apktool';
  static const String jadx = 'jadx';
  static const String radare2 = 'radare2';
  static const String blutter = 'blutter';
  static const String doldrums = 'doldrums';
  static const String anythingAnalyzer = 'anything_analyzer';
  static const String docker = 'docker';
  static const String qdrant = 'qdrant';
  static const String postgresql = 'postgresql';
  static const String redis = 'redis';
  static const String aiJungler = 'ai_jungler';
  static const String dingtalkWorkspaceCli = 'dingtalk_workspace_cli';
  static const String googleChrome = 'google_chrome';

  static const List<String> displayOrder = <String>[
    nodejs,
    playwright,
    python,
    pip,
    java,
    frida,
    mitmproxy,
    apktool,
    jadx,
    radare2,
    blutter,
    doldrums,
    anythingAnalyzer,
    docker,
    qdrant,
    postgresql,
    redis,
    aiJungler,
    dingtalkWorkspaceCli,
    googleChrome,
  ];
}

class PluginInfo {
  const PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    this.enabled = true,
    this.installedVersion,
    this.latestVersion,
    this.updateAvailable,
    this.installPath,
    this.dependencies = const [],
    this.dependents = const [],
    this.supportsUninstall = true,
    this.supportsInstall = true,
    bool? supportsUpdateCheck,
    this.metadata = const <String, Object?>{},
    this.errorMessage,
  }) : supportsUpdateCheck = supportsUpdateCheck ?? supportsInstall;

  /// 唯一标识符，如 'nodejs', 'playwright'
  final String id;

  /// 显示名称
  final String name;

  /// 简短描述
  final String description;

  /// 当前状态
  final PluginStatus status;

  /// 是否启用（已安装时有效）
  final bool enabled;

  /// 已安装版本（未安装时为 null）
  final String? installedVersion;

  /// 可用最新版本
  final String? latestVersion;

  /// 显式更新判定。容器镜像等可变标签无法仅凭版本文本比较。
  final bool? updateAvailable;

  /// 安装路径
  final String? installPath;

  /// 依赖的其他插件 id 列表（安装本插件前需先安装这些）
  final List<String> dependencies;

  /// 依赖本插件的其他插件 id 列表（卸载本插件前需先卸载这些）
  final List<String> dependents;

  /// 是否支持卸载
  final bool supportsUninstall;

  /// 是否由 OpenHand 提供安装入口。外部数据库服务仅扫描状态，不提供接管操作。
  final bool supportsInstall;

  /// 是否支持查询上游最新版本。外部安装的运行时可独立支持此能力。
  final bool supportsUpdateCheck;

  /// 插件专属的结构化诊断信息。
  final Map<String, Object?> metadata;

  /// 错误信息
  final String? errorMessage;

  bool get isInstalled => status == PluginStatus.installed;
  bool get isBusy =>
      status == PluginStatus.installing ||
      status == PluginStatus.updating ||
      status == PluginStatus.uninstalling;
  bool get hasUpdate =>
      isInstalled &&
      (updateAvailable ??
          (latestVersion != null &&
              installedVersion != null &&
              compareSemanticVersions(latestVersion!, installedVersion!) > 0));

  PluginInfo copyWith({
    String? id,
    String? name,
    String? description,
    PluginStatus? status,
    bool? enabled,
    String? installedVersion,
    String? latestVersion,
    bool? updateAvailable,
    String? installPath,
    List<String>? dependencies,
    List<String>? dependents,
    bool? supportsUninstall,
    bool? supportsInstall,
    bool? supportsUpdateCheck,
    Map<String, Object?>? metadata,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return PluginInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      installedVersion: installedVersion ?? this.installedVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      installPath: installPath ?? this.installPath,
      dependencies: dependencies ?? this.dependencies,
      dependents: dependents ?? this.dependents,
      supportsUninstall: supportsUninstall ?? this.supportsUninstall,
      supportsInstall: supportsInstall ?? this.supportsInstall,
      supportsUpdateCheck: supportsUpdateCheck ?? this.supportsUpdateCheck,
      metadata: metadata ?? this.metadata,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}
