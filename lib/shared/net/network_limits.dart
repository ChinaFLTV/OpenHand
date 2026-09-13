import '../util/byte_size_format.dart';

const Duration kOpenHandMaxNetworkOperationTimeout = Duration(hours: 24);

/// 单次网络响应允许缓冲的最大字节数，避免异常配置造成不可控内存分配。
const int kOpenHandMaxNetworkPayloadBytes = 512 * kBytesPerMiB;

/// 单次网络流式传输的最大字节数；仅用于保持背压且不完整驻留内存的消费路径。
const int kOpenHandMaxNetworkStreamBytes = 4 * kBytesPerGiB;

/// 单次网络流最多接收的数据块数，避免异常碎片流长期占用事件循环。
const int kOpenHandMaxNetworkStreamChunks = 1024 * 1024;
