part of 'web_message_platform_service.dart';

/// Web 端登录后保存在内存中的会话凭据。
///
/// - `token`：随机 32 字节 base64url 字符串；当 `authEnabled=false` 时使用
///   常量 `'anonymous'` 直连。
/// - `toMetadata()` 输出 Web 端来源信息，最终由请求元数据构建器写入
///   `AiSession.metadata`。
/// - `source/deviceId` 在跨请求授权时用于二次校验：匿名模式下 token 共享，
///   `_authCanAccessAllSessions` 才会决定是否要求 device 一致。
class _WebGatewayAuthSession {
  const _WebGatewayAuthSession({
    required this.token,
    required this.source,
    required this.deviceId,
    required this.deviceMacAddress,
    required this.deviceName,
    required this.devicePlatform,
    required this.osName,
    required this.osVersion,
    required this.browserName,
    required this.browserVersion,
    required this.webClientVersion,
    required this.locale,
    required this.timezone,
    required this.screenClass,
    required this.loginAt,
    required this.issuedAt,
    required this.remoteAddress,
    required this.userAgent,
  });

  final String token;
  final WebGatewayLoginSource source;
  final String deviceId;
  final String deviceMacAddress;
  final String deviceName;
  final String devicePlatform;
  final String osName;
  final String osVersion;
  final String browserName;
  final String browserVersion;
  final String webClientVersion;
  final String locale;
  final String timezone;
  final String screenClass;
  final DateTime loginAt;
  final Duration issuedAt;
  final String remoteAddress;
  final String userAgent;

  Map<String, Object?> toMetadata() {
    return <String, Object?>{
      'login_source': source.storageValue,
      'source': source.storageValue,
      'device_id': deviceId,
      'device_mac_address': deviceMacAddress,
      'device_name': deviceName,
      'device_platform': devicePlatform,
      'os_name': osName,
      'os_version': osVersion,
      'browser_name': browserName,
      'browser_version': browserVersion,
      'web_client_version': webClientVersion,
      'app_version': webClientVersion,
      'locale': locale,
      'timezone': timezone,
      'screen_class': screenClass,
      'login_at': loginAt.toUtc().toIso8601String(),
      'login_os': devicePlatform,
      'login_address': remoteAddress,
      'remote_ip': remoteAddress,
      'user_agent': userAgent,
      'entrypoint': 'web_message_platform',
    };
  }
}
