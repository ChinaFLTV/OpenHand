import 'dart:io';

import '../../../app/support/url_validation.dart';
import '../model/mcp_server.dart';
import '../model/mcp_server_ops.dart';

/// OpenHand 内置 MCP 运维服务器（Streamable HTTP）入口的地址计算与「自引用」
/// 识别工具集合。UI 展示、连通性自检、以及「禁止把本机 MCP 运维入口添加回
/// MCP 列表」的甄别逻辑都复用这里，避免 host 归一化规则散落各处漂移。
///
/// 纯函数、无 Flutter 依赖：可被 controller / widget / runtime 共同引用。

/// 运维入口实际生效的端口：优先取已绑定端口，未启动时回落到配置端口。
int mcpOpsEffectivePort(McpOpsRuntimeSnapshot snapshot, McpOpsConfig config) {
  return snapshot.boundPort ?? config.listenPort;
}

/// 运维入口的「原始」监听 host（可能是 0.0.0.0 / :: 等通配地址）。
String mcpOpsRawEndpointHost(
  McpOpsRuntimeSnapshot snapshot,
  McpOpsConfig config,
) {
  final host = snapshot.boundHost?.trim().isNotEmpty == true
      ? snapshot.boundHost!.trim()
      : config.listenHost.trim();
  return host.isEmpty ? mcpOpsDefaultListenHost : host;
}

/// 把通配监听地址（0.0.0.0 / ::）映射为客户端可直接拨号的回环地址。
String mcpOpsClientHost(String host) {
  final normalized = host.trim();
  if (normalized.isEmpty ||
      normalized == '0.0.0.0' ||
      normalized == '::' ||
      normalized == '[::]') {
    return mcpOpsDefaultListenHost;
  }
  return normalized;
}

/// 组装 `host:port` authority，IPv6 字面量自动补方括号。
String mcpOpsAuthority(String host, int port) {
  final cleanHost = host.trim();
  final formattedHost =
      cleanHost.contains(':') &&
          !cleanHost.startsWith('[') &&
          !cleanHost.endsWith(']')
      ? '[$cleanHost]'
      : cleanHost;
  return '${formattedHost.isEmpty ? mcpOpsDefaultListenHost : formattedHost}:$port';
}

/// 客户端可直接访问的 authority（通配地址归一化为回环）。
String mcpOpsClientAuthority(
  McpOpsRuntimeSnapshot snapshot,
  McpOpsConfig config,
) {
  return mcpOpsAuthority(
    mcpOpsClientHost(mcpOpsRawEndpointHost(snapshot, config)),
    mcpOpsEffectivePort(snapshot, config),
  );
}

/// 服务器真实监听的 authority（保留通配地址，仅用于展示「监听于」）。
String mcpOpsBindAuthority(
  McpOpsRuntimeSnapshot snapshot,
  McpOpsConfig config,
) {
  return mcpOpsAuthority(
    mcpOpsRawEndpointHost(snapshot, config),
    mcpOpsEffectivePort(snapshot, config),
  );
}

/// 判断一个待保存的 MCP server 是否指向 OpenHand 自身的 MCP 运维入口。
///
/// 命中即为「自引用」：把内置运维入口再添加回 MCP 列表会造成引用循环
/// （运维入口的 mcp_servers 面会把桥接工具反向再曝露）与工具无限膨胀，
/// 故一律拒绝。仅 HTTP / SSE 传输可能命中；stdio 走本地进程不涉及。
bool mcpOpsServerTargetsSelfEndpoint({
  required McpServer server,
  required McpOpsRuntimeSnapshot snapshot,
  required McpOpsConfig config,
}) {
  if (server.type == McpServerType.stdio) {
    return false;
  }
  final uri = tryParseValidHttpUrl(server.url);
  if (uri == null) {
    return false;
  }
  final urlPort = uri.hasPort ? uri.port : _defaultPortForScheme(uri.scheme);
  if (urlPort != mcpOpsEffectivePort(snapshot, config)) {
    return false;
  }
  return _hostReachesLocalOps(
    urlHost: uri.host,
    opsHost: mcpOpsRawEndpointHost(snapshot, config),
  );
}

int _defaultPortForScheme(String scheme) {
  return scheme.toLowerCase() == 'https' ? 443 : 80;
}

/// URL host 是否指向本机运维监听：回环 / localhost / 通配地址，或与运维配置
/// host 归一化后相等。对无法判定为本机的远端地址保持保守（不误伤外部服务）。
bool _hostReachesLocalOps({required String urlHost, required String opsHost}) {
  final normalizedUrlHost = urlHost.trim().toLowerCase();
  if (normalizedUrlHost.isEmpty) {
    return false;
  }
  if (normalizedUrlHost == 'localhost' ||
      normalizedUrlHost.endsWith('.localhost')) {
    return true;
  }
  final urlAddress = InternetAddress.tryParse(_stripIpv6Brackets(urlHost));
  if (urlAddress != null &&
      (urlAddress.isLoopback || _isUnspecifiedAddress(urlAddress))) {
    return true;
  }

  final normalizedOpsHost = mcpOpsClientHost(opsHost).trim().toLowerCase();
  if (normalizedUrlHost == normalizedOpsHost) {
    return true;
  }
  final opsAddress = InternetAddress.tryParse(
    _stripIpv6Brackets(normalizedOpsHost),
  );
  if (urlAddress != null &&
      opsAddress != null &&
      urlAddress.address == opsAddress.address) {
    return true;
  }
  return false;
}

bool _isUnspecifiedAddress(InternetAddress address) {
  return address.rawAddress.every((byte) => byte == 0);
}

String _stripIpv6Brackets(String host) {
  final trimmed = host.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}
