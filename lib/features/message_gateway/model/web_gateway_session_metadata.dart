import 'web_message_platform_config.dart';

/// 构建 Web 请求与网关历史界面共用的稳定会话元数据结构。
/// 保留空设备字段，以兼容旧版本创建的会话。
Map<String, Object?> buildWebGatewayRequestMetadata({
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
      'captured_at': (capturedAt ?? DateTime.now()).toUtc().toIso8601String(),
    },
  };
}
