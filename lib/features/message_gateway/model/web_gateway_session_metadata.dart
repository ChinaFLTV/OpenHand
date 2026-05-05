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
    this.browserName,
    this.browserVersion,
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
      'browser_name',
      'browser_version',
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
      browserName: _opt(json['browser_name']),
      browserVersion: _opt(json['browser_version']),
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
  final String? browserName;
  final String? browserVersion;
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
    String? browserName,
    String? browserVersion,
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
      browserName: browserName ?? this.browserName,
      browserVersion: browserVersion ?? this.browserVersion,
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
      if (browserName != null && browserName!.isNotEmpty)
        'browser_name': browserName,
      if (browserVersion != null && browserVersion!.isNotEmpty)
        'browser_version': browserVersion,
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
      return WebGatewaySessionMetadata.fromJson(Map<String, Object?>.from(raw));
    }
    return null;
  }
}

String? _opt(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// 构造与 1.0 时期 Web 端会话写入完全一致的 metadata Map。
///
/// 设计动机：
/// [WebGatewaySessionMetadata.wrapForSession] 出于强类型考量，序列化时会跳过
/// 空字符串字段、并把 `remoteAddress` 标准化为新键 `ip_address`，与现网历史
/// 会话的 metadata 字节布局存在细微差异。本函数保留旧布局——把 `auth.toMetadata()`
/// 的输出原样合并、再叠加 caller 的 extras 与 4 项请求级字段——专门服务于
/// `web_message_platform_service` 的 `_metadataForRequest` 写入路径，确保
/// `web_gateway_context` 顶层 map 的字节级 1:1 兼容。
///
/// 与 view 端读取协议（`message_gateway_view.dart`）配套：view 历史上始终读到
/// `device_id`/`device_mac_address`/`user_agent` 这些键即便其值为空，故迁移期
/// 不引入跳过空字段的语义，避免静默回归。
Map<String, Object?> buildLegacyWebGatewayRequestMetadata({
  required Map<String, Object?> authMetadata,
  required String requestMethod,
  required String requestPath,
  required int requestId,
  required Map<String, Object?> extras,
  DateTime? capturedAt,
}) {
  return <String, Object?>{
    webGatewayMetadataKey: <String, Object?>{
      ...authMetadata,
      ...extras,
      'request_id': requestId,
      'request_method': requestMethod,
      'request_path': requestPath,
      'captured_at': (capturedAt ?? DateTime.now().toUtc()).toIso8601String(),
    },
  };
}
