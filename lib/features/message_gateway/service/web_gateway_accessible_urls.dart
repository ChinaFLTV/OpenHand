/// Web 通用消息平台「当前可访问 URL 列表」的纯函数推导逻辑。
///
/// 抽出独立模块的目的：使 `WebMessagePlatformService.accessibleUrls`
/// 可在不构造完整 service（避免拉起 6 个 controller + AppInfo）的前提下
/// 被单元测试覆盖。逻辑须与 service.accessibleUrls 文档块保持一一对应：
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
  final normalized = listenHost.trim();
  final isWildcard =
      normalized.isEmpty ||
      normalized == '0.0.0.0' ||
      normalized == '::' ||
      normalized == '::0';
  if (!isWildcard) {
    return List<String>.unmodifiable(<String>['http://$normalized:$port']);
  }
  final urls = <String>{'http://localhost:$port', 'http://127.0.0.1:$port'};
  for (final addr in localIPv4Addresses) {
    if (addr.isEmpty) continue;
    urls.add('http://$addr:$port');
  }
  return List<String>.unmodifiable(urls);
}
