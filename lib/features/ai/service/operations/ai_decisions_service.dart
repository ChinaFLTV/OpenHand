import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/util/decision_payload.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/localized_text.dart';
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
      orElse: () => throw FormatException(
        openHandAmbientText(
          zh: '请输入待评估内容。',
          zhHant: '請輸入待評估內容。',
          en: 'Enter the content to evaluate.',
          fr: 'Saisissez le contenu à évaluer.',
          de: 'Geben Sie den zu bewertenden Inhalt ein.',
          ja: '評価対象を入力してください。',
        ),
      ),
    );
    if (turn.parts.any((part) => part.kind != AiChatContentPartKind.text)) {
      throw FormatException(
        openHandAmbientText(
          zh: 'Jev 仅接收文本，请先将附件转成文本。',
          zhHant: 'Jev 僅接收文字，請先將附件轉成文字。',
          en: 'Jev accepts text only. Convert attachments to text first.',
          fr: 'Jev n’accepte que du texte. Convertissez d’abord les pièces jointes.',
          de: 'Jev akzeptiert nur Text. Wandeln Sie Anhänge zuerst in Text um.',
          ja: 'Jev はテキストのみ受け付けます。先に添付をテキストへ変換してください。',
        ),
      );
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
          '${openHandAmbientText(zh: '决策接口请求失败', zhHant: '決策介面請求失敗', en: 'Decision API request failed', fr: 'Échec de la requête API de décision', de: 'Anfrage an die Entscheidungs-API fehlgeschlagen', ja: '意思決定 API のリクエストに失敗しました')}（${response.statusCode}）：${AiOperationHttp.extractErrorMessage(raw)}',
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
      if (decoded is! Map) {
        throw FormatException(
          openHandAmbientText(
            zh: '决策接口响应必须是 JSON 对象。',
            zhHant: '決策介面回應必須是 JSON 物件。',
            en: 'The decision API response must be a JSON object.',
            fr: 'La réponse de l’API de décision doit être un objet JSON.',
            de: 'Die Antwort der Entscheidungs-API muss ein JSON-Objekt sein.',
            ja: '意思決定 API の応答は JSON オブジェクトである必要があります。',
          ),
        );
      }
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
