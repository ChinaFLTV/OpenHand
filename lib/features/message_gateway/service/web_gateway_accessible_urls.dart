import '../model/web_message_platform_config.dart';

/// Web 通用消息平台「当前可访问 URL 列表」的纯函数推导逻辑。
///
/// 与 `WebMessagePlatformService.accessibleUrls` 共用以下推导规则：
///
/// - `boundPort == null`（服务未启动）→ 返回空列表
/// - 监听具体 IP（如 `192.168.1.5`）→ 仅返回 `[http://<host>:<port>]`
/// - 监听通配符（`0.0.0.0` / `::` / `::0` / 空串）→ 返回
///   `localhost` + `127.0.0.1` + 所有非环回 IPv4 地址（去重，保留稳定顺序）
///
/// 注意：返回 List 不可变，避免调用方误改缓存视图。
List<String> computeWebGatewayAccessibleUrls({
  required String listenHost,
  required int? boundPort,
  required Iterable<String> localIPv4Addresses,
}) {
  if (boundPort == null) return const <String>[];
  final port = boundPort;
  final normalized = webGatewayNormalizeListenHost(listenHost);
  final isWildcard =
      normalized.isEmpty ||
      normalized == '0.0.0.0' ||
      normalized == '::' ||
      normalized == '::0';
  if (!isWildcard) {
    return List<String>.unmodifiable(<String>[
      webGatewayHttpUrl(normalized, port),
    ]);
  }
  final urls = <String>{
    webGatewayHttpUrl('localhost', port),
    webGatewayHttpUrl('127.0.0.1', port),
  };
  for (final addr in localIPv4Addresses) {
    final normalizedAddress = addr.trim();
    if (normalizedAddress.isEmpty) continue;
    urls.add(webGatewayHttpUrl(normalizedAddress, port));
  }
  return List<String>.unmodifiable(urls);
}
