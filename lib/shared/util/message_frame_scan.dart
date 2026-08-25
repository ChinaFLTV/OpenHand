/// HTTP / LSP 风格帧消息头终止符扫描。
///
/// stdio JSON-RPC（LSP、MCP）与 HTTP 代理均使用「头部 + 空行 + 载荷」的
/// 帧格式统一为单遍最早匹配。
library;

/// 定位字节缓冲中消息头的空行终止符。
///
/// 返回 `headerEnd`（头部字节长度，不含终止符）与 `bodyStart`（终止符后
/// 首字节下标）；未找到时返回 null。单遍扫描取最早出现的 `\r\n\r\n`，
/// [acceptBareLf] 为 true 时同时接受 `\n\n`（最早者优先，避免畸形输入把
/// 超长内容伪装进头部）。
///
/// [startIndex] 供增量扫描传入「上次扫描过的字节数」，内部自动回退少量
/// 字节覆盖跨数据块的终止符边界，调用方无需自行减偏移。
({int headerEnd, int bodyStart})? findMessageFrameHeaderEnd(
  List<int> bytes, {
  int startIndex = 0,
  bool acceptBareLf = true,
}) {
  const cr = 0x0D;
  const lf = 0x0A;
  for (
    var index = startIndex > 3 ? startIndex - 3 : 0;
    index < bytes.length;
    index++
  ) {
    final byte = bytes[index];
    if (byte == cr) {
      if (index + 3 < bytes.length &&
          bytes[index + 1] == lf &&
          bytes[index + 2] == cr &&
          bytes[index + 3] == lf) {
        return (headerEnd: index, bodyStart: index + 4);
      }
    } else if (acceptBareLf &&
        byte == lf &&
        index + 1 < bytes.length &&
        bytes[index + 1] == lf) {
      return (headerEnd: index, bodyStart: index + 2);
    }
  }
  return null;
}
