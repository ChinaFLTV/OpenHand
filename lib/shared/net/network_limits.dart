import '../util/byte_size_format.dart';

const Duration kOpenHandMaxNetworkOperationTimeout = Duration(hours: 24);

/// 单次网络响应允许缓冲的最大字节数，避免异常配置造成不可控内存分配。
const int kOpenHandMaxNetworkPayloadBytes = 512 * kBytesPerMiB;
