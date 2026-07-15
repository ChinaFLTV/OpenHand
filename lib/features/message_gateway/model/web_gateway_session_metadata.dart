import 'web_message_platform_config.dart';

/// Builds the stable session metadata shape shared by Web requests and the
/// gateway history UI. Empty device fields remain present for compatibility
/// with sessions created by earlier OpenHand versions.
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
