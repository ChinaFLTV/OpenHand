import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/util/decision_payload.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import '../session_io/ai_token_usage_parser.dart';
import 'ai_operation_http.dart';

/// Jev 决策请求不携带聊天工具、思考参数或系统提示词，也不回退到聊天接口。
class AiDecisionsService {
  const AiDecisionsService(this.client);
  final http.Client client;

  Future<AiChatCompletion> evaluate({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required Duration timeout,
    Future<void>? cancelSignal,
    void Function(AiChatRequestTelemetry)? onRequestStarted,
  }) async {
    final turn = messages.lastWhere(
      (item) => item.role == AiChatRole.user,
      orElse: () => throw const FormatException('请输入待评估内容。'),
    );
    if (turn.parts.any((part) => part.kind != AiChatContentPartKind.text)) {
      throw const FormatException('Jev 仅接收文本，请先将附件转成文本。');
    }
    final request = DecisionPayload.request(
      turn.effectiveParts.map((part) => part.text ?? '').join('\n\n'),
    );
    final body = <String, Object?>{'model': model.modelId, ...request};
    final endpoint = const AiEndpointRouter().resolve(
      model,
      AiApiFamily.decisions,
    );
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
      family: AiApiFamily.decisions,
    );
    final uri = AiOperationHttp.uriWithExtraQuery(
      endpoint.url,
      model,
      AiApiFamily.decisions,
    );
    final started = DateTime.now().toUtc();
    onRequestStarted?.call(
      AiChatRequestTelemetry(
        requestUrl: uri.toString(),
        requestMethod: endpoint.method,
        requestHeaders: headers,
        requestBody: body,
        startedAt: started,
      ),
    );
    final transport = AiTransportClient(client: client);
    try {
      final response = await transport.sendJson(
        uri: uri,
        method: endpoint.method,
        headers: headers,
        body: body,
        timeout: timeout,
        cancelSignal: cancelSignal,
        maxResponseBytes: DecisionPayload.maxCharacters,
      );
      final raw = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiChatException(
          '决策接口请求失败（${response.statusCode}）：${AiOperationHttp.extractErrorMessage(raw)}',
          telemetry: AiChatRequestTelemetry(
            requestUrl: uri.toString(),
            requestMethod: endpoint.method,
            requestBody: body,
            rawResponse: raw,
            startedAt: started,
            endedAt: DateTime.now().toUtc(),
          ),
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('决策接口响应必须是 JSON 对象。');
      final result = DecisionPayload.result(
        stringKeyedMapFromValue(decoded),
        request['questions'] as Map<String, Object?>,
      );
      final ended = DateTime.now().toUtc();
      return AiChatCompletion(
        reply: DecisionPayload.encode(DecisionPayload.resultLanguage, result),
        rawResponse: raw,
        usage: AiTokenUsageParser.parseOpenAi(
          stringKeyedMapFromValue(decoded['usage']),
        ),
        requestUrl: uri.toString(),
        requestMethod: endpoint.method,
        requestHeaders: headers,
        requestBody: body,
        startedAt: started,
        endedAt: ended,
        durationMs: ended.difference(started).inMilliseconds,
      );
    } finally {
      transport.dispose();
    }
  }
}
