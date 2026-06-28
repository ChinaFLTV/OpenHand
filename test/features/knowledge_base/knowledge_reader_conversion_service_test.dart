import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_reader_conversion_service.dart';

void main() {
  test('reader conversion uses chat model and cleans fenced output', () async {
    final chatClient = _FakeChatClient(
      reply: '```markdown\n# Title\n\nConverted text.\n```',
    );
    final service = KnowledgeReaderConversionService(chatClient: chatClient);

    final result = await service.convert(
      KnowledgeReaderConversionRequest(
        model: _readerModel(),
        sourceType: 'htm',
        targetType: 'markdown',
        content: '<html><h1>Title</h1><p>Converted text.</p></html>',
        sourceTitle: 'doc.html',
      ),
    );

    expect(result.text, '# Title\n\nConverted text.');
    expect(result.metadata['reader_source_type'], 'html');
    expect(result.metadata['reader_target_type'], 'markdown');
    expect(chatClient.messages.single.last.content, contains('源类型: html'));
    expect(chatClient.messages.single.last.content, contains('目标类型: markdown'));
  });

  test('reader conversion rejects unsupported target type before request', () {
    final chatClient = _FakeChatClient(reply: 'unused');
    final service = KnowledgeReaderConversionService(chatClient: chatClient);

    expect(
      service.convert(
        KnowledgeReaderConversionRequest(
          model: _readerModel(),
          sourceType: 'html',
          targetType: 'text',
          content: '<p>x</p>',
          sourceTitle: 'doc.html',
        ),
      ),
      throwsStateError,
    );
    expect(chatClient.messages, isEmpty);
  });
}

AiModelConfig _readerModel() {
  return const AiModelConfig(
    id: 'reader-provider',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'token',
    modelId: 'reader-model',
    protocolType: AiProtocolType.openai,
    modelProfiles: <String, AiModelProfile>{
      'reader-model': AiModelProfile(
        capabilities: <AiModelCapability>{AiModelCapability.readerConversion},
        readerSourceTypes: <String>['html'],
        readerTargetTypes: <String>['markdown', 'json'],
      ),
    },
  );
}

class _FakeChatClient implements AiChatClient {
  _FakeChatClient({required this.reply});

  final String reply;
  final List<List<AiChatTurn>> messages = <List<AiChatTurn>>[];

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    this.messages.add(messages);
    return AiChatCompletion(reply: reply);
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Duration streamIdleTimeout = const Duration(seconds: 120),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
