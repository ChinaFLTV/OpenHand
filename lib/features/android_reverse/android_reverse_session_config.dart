/// Android 逆向会话的运行时配置，序列化进 session metadata。
class AndroidReverseSessionConfig {
  const AndroidReverseSessionConfig({
    required this.objective,
    this.packageName,
    this.apkPath,
    this.deviceSerial,
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
    'adb_mcp_enabled': adbMcpEnabled,
    'frida_mcp_enabled': fridaMcpEnabled,
    if (keywords.isNotEmpty) 'keywords': keywords,
    if (notes != null) 'notes': notes,
  };

  static AndroidReverseSessionConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final objective = '${map['objective'] ?? ''}'.trim();
    if (objective.isEmpty) return null;
    return AndroidReverseSessionConfig(
      objective: objective,
      packageName: map['package_name'] as String?,
      apkPath: map['apk_path'] as String?,
      deviceSerial: map['device_serial'] as String?,
      adbMcpEnabled: _boolFromJson(map['adb_mcp_enabled']),
      fridaMcpEnabled: _boolFromJson(map['frida_mcp_enabled']),
      keywords: (map['keywords'] as List?)?.cast<String>() ?? const <String>[],
      notes: map['notes'] as String?,
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
    buf
      ..writeln(
        '- ADB MCP：【${adbMcpEnabled ? '已启用' : '未启用；如需 ADB MCP，请在调试面板手动开启'}】',
      )
      ..writeln(
        '- Frida MCP：【${fridaMcpEnabled ? '已启用' : '未启用；如需 Frida MCP，请在调试面板手动开启'}】',
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

  static bool _boolFromJson(Object? raw) {
    if (raw is bool) return raw;
    final value = '${raw ?? ''}'.trim().toLowerCase();
    return value == 'true' || value == '1' || value == 'yes';
  }
}
