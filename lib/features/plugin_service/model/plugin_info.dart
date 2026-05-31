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

class PluginInfo {
  const PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    this.enabled = true,
    this.installedVersion,
    this.latestVersion,
    this.installPath,
    this.dependencies = const [],
    this.dependents = const [],
    this.errorMessage,
  });

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

  /// 安装路径
  final String? installPath;

  /// 依赖的其他插件 id 列表（安装本插件前需先安装这些）
  final List<String> dependencies;

  /// 依赖本插件的其他插件 id 列表（卸载本插件前需先卸载这些）
  final List<String> dependents;

  /// 错误信息
  final String? errorMessage;

  bool get isInstalled => status == PluginStatus.installed;
  bool get isBusy =>
      status == PluginStatus.installing ||
      status == PluginStatus.updating ||
      status == PluginStatus.uninstalling;
  bool get hasUpdate =>
      isInstalled &&
      latestVersion != null &&
      installedVersion != null &&
      _compareVersions(latestVersion!, installedVersion!) > 0;

  static int _compareVersions(String a, String b) {
    final normalizedA = _normalizeVersion(a);
    final normalizedB = _normalizeVersion(b);
    if (normalizedA == null || normalizedB == null) {
      return a.compareTo(b);
    }
    final maxLength = normalizedA.length > normalizedB.length
        ? normalizedA.length
        : normalizedB.length;
    for (int index = 0; index < maxLength; index++) {
      final av = index < normalizedA.length ? normalizedA[index] : 0;
      final bv = index < normalizedB.length ? normalizedB[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int>? _normalizeVersion(String value) {
    final match = RegExp(r'\d+(?:\.\d+)+').firstMatch(value);
    final raw = match?.group(0);
    if (raw == null) return null;
    return raw.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  }

  PluginInfo copyWith({
    String? id,
    String? name,
    String? description,
    PluginStatus? status,
    bool? enabled,
    String? installedVersion,
    String? latestVersion,
    String? installPath,
    List<String>? dependencies,
    List<String>? dependents,
    String? errorMessage,
  }) {
    return PluginInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      installedVersion: installedVersion ?? this.installedVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      installPath: installPath ?? this.installPath,
      dependencies: dependencies ?? this.dependencies,
      dependents: dependents ?? this.dependents,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
