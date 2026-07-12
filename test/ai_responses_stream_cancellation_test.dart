import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_api_dialect.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';

void main() {
  const model = AiModelConfig(
    id: 'responses-test',
    baseUrl: 'https://example.test/v1',
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: 'gpt-test',
    protocolType: AiProtocolType.openai,
    providerKind: AiProviderKind.openai,
  );
  const messages = <AiChatTurn>[
    AiChatTurn(role: AiChatRole.user, content: 'hello'),
  ];

  test('explicit Responses stream cancellation completes result', () async {
    final client = _ControlledStreamingClient(immediateHeaders: true);
    final service = AiChatService(client: client);
    try {
      final response = await service.sendMessageStream(
        model: model,
        messages: messages,
      );

      await response.cancel!();
      final result = await response.result.timeout(const Duration(seconds: 1));

      expect(result.wasCancelled, isTrue);
      expect(client.streamWasCancelled, isTrue);
    } finally {
      service.dispose();
      await client.dispose();
    }
  });

  test('explicit cancellation is bounded when stream cancel stalls', () async {
    final client = _ControlledStreamingClient(
      immediateHeaders: true,
      stallCancellation: true,
    );
    final service = AiChatService(client: client);
    try {
      final response = await service.sendMessageStream(
        model: model,
        messages: messages,
        streamIdleTimeout: const Duration(milliseconds: 20),
      );

      await response.cancel!().timeout(const Duration(seconds: 1));
      final result = await response.result.timeout(const Duration(seconds: 1));

      expect(result.wasCancelled, isTrue);
      expect(client.streamWasCancelled, isTrue);
    } finally {
      client.releaseCancellation();
      service.dispose();
      await client.dispose();
    }
  });

  test('cancellation before headers closes the late response stream', () async {
    final client = _ControlledStreamingClient(immediateHeaders: false);
    final service = AiChatService(client: client);
    final cancel = Completer<void>();
    try {
      final pending = service.sendMessageStream(
        model: model,
        messages: messages,
        cancelSignal: cancel.future,
      );
      cancel.complete();

      final response = await pending;
      final result = await response.result.timeout(const Duration(seconds: 1));
      expect(result.wasCancelled, isTrue);

      client.completeHeaders();
      await client.cancelled.timeout(const Duration(seconds: 1));
      expect(client.streamWasCancelled, isTrue);
    } finally {
      service.dispose();
      await client.dispose();
    }
  });

  test('drops an oversized SSE event through its delimiter', () async {
    final client = _ControlledStreamingClient(immediateHeaders: true);
    final service = AiChatService(client: client)
      ..maxStreamLineBufferBytes = 64;
    try {
      final response = await service.sendMessageStream(
        model: model,
        messages: messages,
      );
      final events = response.events.toList();

      client.addText('data: ${'x' * 80}\n');
      client.addText(
        'data: ${jsonEncode(<String, Object?>{'type': 'response.output_text.delta', 'delta': 'discarded'})}\n\n',
      );
      client.addText(
        'data: ${jsonEncode(<String, Object?>{'type': 'response.output_text.delta', 'delta': 'kept'})}\n\n',
      );
      await client.closeStream();

      final result = await response.result.timeout(const Duration(seconds: 1));
      final emitted = await events.timeout(const Duration(seconds: 1));
      expect(result.reply, 'kept');
      expect(
        emitted.map((event) => event.textDelta).whereType<String>(),
        <String>['kept'],
      );
    } finally {
      service.dispose();
      await client.dispose();
    }
  });
}

class _ControlledStreamingClient extends http.BaseClient {
  _ControlledStreamingClient({
    required bool immediateHeaders,
    this.stallCancellation = false,
  }) {
    _streamController.onCancel = () {
      streamWasCancelled = true;
      if (!_cancelled.isCompleted) _cancelled.complete();
      if (stallCancellation) return _cancellationRelease.future;
    };
    if (immediateHeaders) completeHeaders();
  }

  final StreamController<List<int>> _streamController =
      StreamController<List<int>>();
  final Completer<http.StreamedResponse> _headers =
      Completer<http.StreamedResponse>();
  final Completer<void> _cancelled = Completer<void>();
  final Completer<void> _cancellationRelease = Completer<void>();
  final bool stallCancellation;
  bool streamWasCancelled = false;

  Future<void> get cancelled => _cancelled.future;

  void addText(String text) {
    if (!_streamController.isClosed) {
      _streamController.add(utf8.encode(text));
    }
  }

  Future<void> closeStream() => _streamController.close();

  void releaseCancellation() {
    if (!_cancellationRelease.isCompleted) {
      _cancellationRelease.complete();
    }
  }

  void completeHeaders() {
    if (_headers.isCompleted) return;
    _headers.complete(
      http.StreamedResponse(
        _streamController.stream,
        200,
        headers: const <String, String>{'content-type': 'text/event-stream'},
      ),
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _headers.future;
  }

  Future<void> dispose() async {
    releaseCancellation();
    await _streamController.close();
  }
}
