import 'web_message_platform_config.dart';

/// 强类型 Web 端登录上下文。
///
/// OpenHand 端用户在 APP/Web 创建会话时，会把这一组结构化字段写入
/// `AiSession.metadata[webGatewayMetadataKey]`，作为后续按 设备指纹/登录途径
/// 过滤会话列表的来源。在此之前是裸 `Map`，键容易写错且类型易错位。
///
/// 兼容性约定：
/// - 序列化键名与现网已写入的 metadata 键 (`webGatewayLoginSourceKey` 等)
///   保持一致，避免老会话读不出来。
/// - `fromJson` 容忍缺失字段——老数据没写过的字段返回 null。
class WebGatewaySessionMetadata {
  const WebGatewaySessionMetadata({
    required this.loginSource,
    this.deviceId,
    this.deviceMac,
    this.ipAddress,
    this.userAgent,
    this.osName,
    this.osVersion,
    this.locale,
    this.timezone,
    this.loginAt,
    this.username,
    this.appVersion,
    this.extra = const <String, Object?>{},
  });

  factory WebGatewaySessionMetadata.fromJson(Map<String, Object?> json) {
    final extras = <String, Object?>{};
    final reserved = <String>{
      webGatewayLoginSourceKey,
      webGatewayDeviceIdKey,
      webGatewayDeviceMacKey,
      'ip_address',
      'user_agent',
      'os_name',
      'os_version',
      'locale',
      'timezone',
      'login_at',
      'username',
      'app_version',
    };
    json.forEach((key, value) {
      if (!reserved.contains(key)) extras[key] = value;
    });
    final loginAtRaw = json['login_at'];
    DateTime? loginAt;
    if (loginAtRaw is String && loginAtRaw.isNotEmpty) {
      loginAt = DateTime.tryParse(loginAtRaw);
    }
    return WebGatewaySessionMetadata(
      loginSource: WebGatewayLoginSource.fromStorage(
        json[webGatewayLoginSourceKey]?.toString(),
      ),
      deviceId: _opt(json[webGatewayDeviceIdKey]),
      deviceMac: _opt(json[webGatewayDeviceMacKey]),
      ipAddress: _opt(json['ip_address']),
      userAgent: _opt(json['user_agent']),
      osName: _opt(json['os_name']),
      osVersion: _opt(json['os_version']),
      locale: _opt(json['locale']),
      timezone: _opt(json['timezone']),
      loginAt: loginAt,
      username: _opt(json['username']),
      appVersion: _opt(json['app_version']),
      extra: extras,
    );
  }

  final WebGatewayLoginSource loginSource;
  final String? deviceId;
  final String? deviceMac;
  final String? ipAddress;
  final String? userAgent;
  final String? osName;
  final String? osVersion;
  final String? locale;
  final String? timezone;
  final DateTime? loginAt;
  final String? username;
  final String? appVersion;
  final Map<String, Object?> extra;

  /// 复合设备指纹——先 MAC，其次 deviceId。
  /// 用于 Web 列表 API 的过滤条件。
  String? get fingerprint {
    final mac = deviceMac?.trim();
    if (mac != null && mac.isNotEmpty) return mac.toLowerCase();
    final id = deviceId?.trim();
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  WebGatewaySessionMetadata copyWith({
    WebGatewayLoginSource? loginSource,
    String? deviceId,
    String? deviceMac,
    String? ipAddress,
    String? userAgent,
    String? osName,
    String? osVersion,
    String? locale,
    String? timezone,
    DateTime? loginAt,
    String? username,
    String? appVersion,
    Map<String, Object?>? extra,
  }) {
    return WebGatewaySessionMetadata(
      loginSource: loginSource ?? this.loginSource,
      deviceId: deviceId ?? this.deviceId,
      deviceMac: deviceMac ?? this.deviceMac,
      ipAddress: ipAddress ?? this.ipAddress,
      userAgent: userAgent ?? this.userAgent,
      osName: osName ?? this.osName,
      osVersion: osVersion ?? this.osVersion,
      locale: locale ?? this.locale,
      timezone: timezone ?? this.timezone,
      loginAt: loginAt ?? this.loginAt,
      username: username ?? this.username,
      appVersion: appVersion ?? this.appVersion,
      extra: extra ?? this.extra,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      webGatewayLoginSourceKey: loginSource.storageValue,
      if (deviceId != null && deviceId!.isNotEmpty)
        webGatewayDeviceIdKey: deviceId,
      if (deviceMac != null && deviceMac!.isNotEmpty)
        webGatewayDeviceMacKey: deviceMac,
      if (ipAddress != null && ipAddress!.isNotEmpty) 'ip_address': ipAddress,
      if (userAgent != null && userAgent!.isNotEmpty) 'user_agent': userAgent,
      if (osName != null && osName!.isNotEmpty) 'os_name': osName,
      if (osVersion != null && osVersion!.isNotEmpty) 'os_version': osVersion,
      if (locale != null && locale!.isNotEmpty) 'locale': locale,
      if (timezone != null && timezone!.isNotEmpty) 'timezone': timezone,
      if (loginAt != null) 'login_at': loginAt!.toUtc().toIso8601String(),
      if (username != null && username!.isNotEmpty) 'username': username,
      if (appVersion != null && appVersion!.isNotEmpty)
        'app_version': appVersion,
      ...extra,
    };
  }

  /// 把强类型元数据写入 `AiSession.metadata` 顶层 map 的统一入口。
  /// 旧代码会用这个 key 直接 `metadata[webGatewayMetadataKey]` 读出来。
  Map<String, Object?> wrapForSession() {
    return <String, Object?>{webGatewayMetadataKey: toJson()};
  }

  static WebGatewaySessionMetadata? readFromSession(
    Map<String, Object?> sessionMetadata,
  ) {
    final raw = sessionMetadata[webGatewayMetadataKey];
    if (raw is Map) {
      return WebGatewaySessionMetadata.fromJson(
        Map<String, Object?>.from(raw),
      );
    }
    return null;
  }
}

String? _opt(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
