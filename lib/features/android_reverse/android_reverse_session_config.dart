import '../../shared/util/input_value_parsing.dart';

const int _kAndroidPackageNameMaxLength = 220;

/// Android 包名形态校验（如 com.example.app）：至少两段、每段以字母开头。
/// 预编译正则供高频 ADB 路径复用。
final RegExp _androidPackageNamePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
);

/// 是否形如合法 Android 包名；null / 空白 / 超长(>220) 一律视为非法。
bool looksLikeAndroidPackageName(String? value) {
  final packageName = nullIfBlank(value);
  if (packageName == null ||
      packageName.length > _kAndroidPackageNameMaxLength) {
    return false;
  }
  return _androidPackageNamePattern.hasMatch(packageName);
}

/// Android 逆向会话的运行时配置，序列化进 session metadata。
class AndroidReverseSessionConfig {
  const AndroidReverseSessionConfig({
    required this.objective,
    this.packageName,
    this.apkPath,
    this.deviceSerial,
    this.authorizationScope,
    this.analysisMode = AndroidReverseAnalysisMode.balanced,
    this.adbMcpEnabled = false,
    this.fridaMcpEnabled = false,
    this.keywords = const <String>[],
    this.notes,
  });

  final String objective;

  /// 目标 APP 包名，如 com.example.app。
  final String? packageName;

  /// 本地 APK 文件路径（可选，不上传设备）。
  final String? apkPath;

  /// ADB 设备序列号，null 表示自动选择唯一在线设备。
  final String? deviceSerial;

  /// 用户确认的授权范围，避免动态动作越过学习/研究/自有应用边界。
  final String? authorizationScope;

  /// 分析策略：静态优先、均衡、动态验证优先。
  final AndroidReverseAnalysisMode analysisMode;

  /// 是否在会话启动时启用 ADB MCP。
  final bool adbMcpEnabled;

  /// 是否在会话启动时启用 Frida MCP。
  final bool fridaMcpEnabled;

  /// 辅助关键字，用于引导模型在静态分析中优先搜索。
  final List<String> keywords;

  /// 用户备注（如登录账号 / 抓包网关 / 证书路径）。
  final String? notes;

  AndroidReverseSessionConfig copyWith({
    String? objective,
    String? packageName,
    String? apkPath,
    String? deviceSerial,
    String? authorizationScope,
    AndroidReverseAnalysisMode? analysisMode,
    bool? adbMcpEnabled,
    bool? fridaMcpEnabled,
    List<String>? keywords,
    String? notes,
  }) {
    return AndroidReverseSessionConfig(
      objective: objective ?? this.objective,
      packageName: packageName ?? this.packageName,
      apkPath: apkPath ?? this.apkPath,
      deviceSerial: deviceSerial ?? this.deviceSerial,
      authorizationScope: authorizationScope ?? this.authorizationScope,
      analysisMode: analysisMode ?? this.analysisMode,
      adbMcpEnabled: adbMcpEnabled ?? this.adbMcpEnabled,
      fridaMcpEnabled: fridaMcpEnabled ?? this.fridaMcpEnabled,
      keywords: keywords ?? this.keywords,
      notes: notes ?? this.notes,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'objective': objective,
    if (packageName != null) 'package_name': packageName,
    if (apkPath != null) 'apk_path': apkPath,
    if (deviceSerial != null) 'device_serial': deviceSerial,
    if (authorizationScope != null) 'authorization_scope': authorizationScope,
    'analysis_mode': analysisMode.storageValue,
    'adb_mcp_enabled': adbMcpEnabled,
    'frida_mcp_enabled': fridaMcpEnabled,
    if (keywords.isNotEmpty) 'keywords': keywords,
    if (notes != null) 'notes': notes,
  };

  static AndroidReverseSessionConfig? fromJson(Object? raw) {
    final map = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (map == null) return null;
    final objective = stringFromValue(map['objective']);
    if (objective.isEmpty) return null;
    return AndroidReverseSessionConfig(
      objective: objective,
      packageName: optionalStringFromValue(map['package_name']),
      apkPath: optionalStringFromValue(map['apk_path']),
      deviceSerial: optionalStringFromValue(map['device_serial']),
      authorizationScope: optionalStringFromValue(map['authorization_scope']),
      analysisMode: AndroidReverseAnalysisMode.fromStorage(
        stringFromValue(map['analysis_mode']),
      ),
      adbMcpEnabled: boolFromValue(map['adb_mcp_enabled']),
      fridaMcpEnabled: boolFromValue(map['frida_mcp_enabled']),
      keywords: stringListFromValueOrJsonText(map['keywords']),
      notes: optionalStringFromValue(map['notes']),
    );
  }

  /// 生成会话首条 prompt 内容块，模型据此进入 Android 逆向工作流。
  String toRequestTemplate() {
    final buf = StringBuffer()
      ..writeln('Android 逆向请求：')
      ..writeln('- 逆向目标：【$objective】');
    if (packageName != null && packageName!.isNotEmpty) {
      buf.writeln('- 目标包名：【$packageName】');
    }
    if (apkPath != null && apkPath!.isNotEmpty) {
      buf.writeln('- APK 路径：【$apkPath】');
    }
    if (deviceSerial != null && deviceSerial!.isNotEmpty) {
      buf.writeln('- 设备序列号：【$deviceSerial】');
    } else {
      buf.writeln('- 设备：【自动选择在线设备】');
    }
    buf.writeln('- 分析模式：【${analysisMode.labelZh}】');
    if (authorizationScope != null && authorizationScope!.isNotEmpty) {
      buf.writeln('- 授权范围：【${authorizationScope!.trim()}】');
    } else {
      buf.writeln('- 授权范围：【未填写；仅允许非破坏性静态分析，动态动作需再次确认】');
    }
    buf
      ..writeln('- ADB MCP：【${adbMcpEnabled ? '已启用' : '未启用；优先用 Bash/ADB 兜底'}】')
      ..writeln(
        '- Frida MCP：【${fridaMcpEnabled ? '已启用' : '未启用；优先用 Bash/Frida CLI 兜底'}】',
      );
    if (keywords.isNotEmpty) {
      buf.writeln('- 关键字：【${keywords.join(', ')}】');
    }
    if (notes != null && notes!.isNotEmpty) {
      buf.writeln('- 备注：【${notes!.trim()}】');
    }
    buf
      ..writeln(
        '- 取证纪律：【先 adb devices 确认设备；域名/URL定位优先静态扫描APK；静态证据已闭环时先交付结论；动态验证需用户批准；同一错误连续≥2轮停下报告】',
      )
      ..write('- 验收标准：【结论有证据路径；若生成脚本/命令，需可在无 IDE 环境下独立运行】');
    return buf.toString();
  }
}

enum AndroidReverseAnalysisMode {
  staticFirst('static_first', '静态优先'),
  balanced('balanced', '均衡分析'),
  dynamicFirst('dynamic_first', '动态验证优先');

  const AndroidReverseAnalysisMode(this.storageValue, this.labelZh);

  final String storageValue;
  final String labelZh;

  static AndroidReverseAnalysisMode fromStorage(String raw) {
    return enumByStorageValue(
          values,
          raw,
          (mode) => mode.storageValue,
          normalize: (value) => value.toLowerCase(),
        ) ??
        enumByStorageValueOr(
          values,
          raw,
          (mode) => mode.name.toLowerCase(),
          fallback: AndroidReverseAnalysisMode.balanced,
          normalize: (value) => value.toLowerCase(),
        );
  }
}
