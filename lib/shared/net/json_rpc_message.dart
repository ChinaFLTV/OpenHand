const String kJsonRpcVersion = '2.0';
const int kJsonRpcMethodNotFound = -32601;

/// 仅识别可关联请求的响应信封，避免同编号的反向请求抢占等待结果。
bool isJsonRpcResponse(Map<Object?, Object?> message) {
  final id = message['id'];
  return message['jsonrpc'] == kJsonRpcVersion &&
      (id is String || id is num && id.isFinite) &&
      !message.containsKey('method') &&
      message.containsKey('result') != message.containsKey('error');
}
