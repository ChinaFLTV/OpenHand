import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/media/ai_image_generation_service.dart';
import 'package:openhand/features/ai/service/model_registry/ai_model_scanner.dart';
import 'package:openhand/features/ai/service/operations/ai_audio_io_service.dart';
import 'package:openhand/features/ai/service/operations/ai_completions_service.dart';
import 'package:openhand/features/ai/service/operations/ai_embeddings_service.dart';
import 'package:openhand/features/ai/service/operations/ai_files_service.dart';
import 'package:openhand/features/ai/service/operations/ai_fine_tunes_service.dart';
import 'package:openhand/features/ai/service/operations/ai_image_edit_service.dart';
import 'package:openhand/features/ai/service/operations/ai_models_service.dart';
import 'package:openhand/features/ai/service/operations/ai_moderations_service.dart';
import 'package:openhand/features/ai/service/operations/ai_realtime_service.dart';
import 'package:openhand/features/ai/service/operations/ai_rerank_service.dart';
import 'package:openhand/features/ai/service/operations/ai_responses_service.dart';
import 'package:openhand/features/ai/service/operations/ai_stepfun_operations_service.dart';
import 'package:openhand/features/ai/service/operations/ai_video_generation_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';
import 'package:openhand/features/skills/data/skill_market_client.dart';

void main() {
  test('services do not close an injected HTTP client', () {
    final client = _RecordingHttpClient();

    AiTransportClient(client: client).dispose();
    AiModelScanner(httpClient: client).dispose();
    AiImageGenerationService(client: client).dispose();
    SkillMarketClient(httpClient: client).close();
    DefaultMcpToolDiscoveryService(client: client).dispose();
    AiChatService(client: client).dispose();

    expect(client.closeCount, 0);
    client.close();
    expect(client.closeCount, 1);
  });

  test('operation services do not dispose an injected transport', () {
    final transport = _RecordingTransport();
    final disposers = <void Function()>[
      AiAudioIoService(transport: transport).dispose,
      AiCompletionsService(transport: transport).dispose,
      AiEmbeddingsService(transport: transport).dispose,
      AiFilesService(transport: transport).dispose,
      AiFineTunesService(transport: transport).dispose,
      AiImageEditService(transport: transport).dispose,
      AiModelsService(transport: transport).dispose,
      AiModerationsService(transport: transport).dispose,
      AiRealtimeService(transport: transport).dispose,
      AiRerankService(transport: transport).dispose,
      AiResponsesService(transport: transport).dispose,
      AiStepFunOperationsService(transport: transport).dispose,
      AiVideoGenerationService(transport: transport).dispose,
    ];

    for (final dispose in disposers) {
      dispose();
    }

    expect(transport.disposeCount, 0);
  });
}

class _RecordingHttpClient extends http.BaseClient {
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('No request expected in ownership tests.');
  }

  @override
  void close() {
    closeCount += 1;
  }
}

class _RecordingTransport extends AiTransportClient {
  _RecordingTransport() : super(client: _RecordingHttpClient());

  int disposeCount = 0;

  @override
  void dispose() {
    disposeCount += 1;
  }
}
