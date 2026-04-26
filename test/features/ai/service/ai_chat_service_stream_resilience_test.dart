import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

/// Resilience tests for [AiChatService]'s SSE pipeline:
///
/// 1. A misbehaving server that streams > 4 MiB without a `\n\n` event
///    delimiter must not OOM the process. The chat service caps the line
///    buffer at 4 MiB and drops pending bytes; the result future must still
///    resolve cleanly when the server eventually closes.
/// 2. Calling [AiChatStreamingResponse.cancel] mid-stream must complete
///    without throwing `Bad state: Cannot add new events after close()`.
void main() {
  group('AiChatService SSE pipeline resilience', () {
    const model = AiModelConfig(
      id: 'test-model',
      baseUrl: 'https://mock.invalid/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'mock-token',
      modelId: 'mock-model',
      protocolType: AiProtocolType.openai,
    );

    test(
      'drops oversized SSE buffer instead of OOM-ing when no \\n\\n delimiter arrives',
      () async {
        // 5 MiB of garbage with no `\n\n` separator — exceeds the 4 MiB cap.
        final oversize = Uint8List(5 * 1024 * 1024)
          ..fillRange(0, 5 * 1024 * 1024, 0x41); // 'A'
        final mockClient = MockClient.streaming((request, body) async {
          // Single chunk, then close. No SSE delimiter is ever emitted.
          final stream = Stream<List<int>>.value(oversize);
          return http.StreamedResponse(
            stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });

        final service = AiChatService(client: mockClient);
        final response = await service.sendMessageStream(
          model: model,
          messages: const [AiChatTurn(role: AiChatRole.user, content: 'hello')],
        );

        // Drain events without crashing; we don't assert on count because the
        // overflow guard intentionally drops bytes (no parseable SSE blocks).
        final events = <Object>[];
        final sub = response.events.listen(events.add);
        final result = await response.result;
        await sub.cancel();

        // The stream must terminate via the natural close path, not via an
        // exception — the cap is a graceful drop, not an error.
        expect(result, isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'cancel() mid-stream completes cleanly without "add after close" race',
      () async {
        final controller = StreamController<List<int>>();
        final mockClient = MockClient.streaming((request, body) async {
          return http.StreamedResponse(
            controller.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });

        final service = AiChatService(client: mockClient);
        final response = await service.sendMessageStream(
          model: model,
          messages: const [AiChatTurn(role: AiChatRole.user, content: 'hi')],
        );

        // Push a partial heartbeat that does not complete an SSE block.
        controller.add(': heartbeat\n'.codeUnits);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Cancel while the upstream is still open. Must not throw.
        await response.cancel?.call();

        // Now close upstream and ensure no late delivery resurrects the
        // closed event controller.
        await controller.close();
        final result = await response.result;
        expect(result, isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'splits two index-less tool_calls into separate entries instead of '
      'concatenating their arguments (regression for `}{` JSON corruption)',
      () async {
        // Some non-strict OpenAI-compatible providers ship multiple tool_calls
        // in a single chunk WITHOUT the `index` field. Both would otherwise
        // bucket into index=0 and the second's `arguments` would be appended
        // to the first's, producing un-decodable JSON like `{...}{...}`.
        const sse =
            'data: {"choices":[{"delta":{"tool_calls":['
            '{"id":"call_a","function":{"name":"bash","arguments":"{\\"cwd\\":\\"/repo\\"}"}},'
            '{"id":"call_b","function":{"name":"bash","arguments":"{\\"cmd\\":\\"ls\\"}"}}'
            ']},"finish_reason":null}]}\n\n'
            'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n'
            'data: [DONE]\n\n';

        final mockClient = MockClient.streaming((request, body) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(sse.codeUnits),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });

        final service = AiChatService(client: mockClient);
        final response = await service.sendMessageStream(
          model: model,
          messages: const [AiChatTurn(role: AiChatRole.user, content: 'hi')],
        );
        final result = await response.result;
        expect(result, isNotNull);
        expect(
          result.toolCalls.length,
          2,
          reason:
              'must produce two distinct tool calls, not one with merged arguments',
        );
        expect(result.toolCalls[0].id, 'call_a');
        expect(result.toolCalls[1].id, 'call_b');
        // Each `arguments` must be standalone, decodable JSON.
        expect(result.toolCalls[0].arguments, '{"cwd":"/repo"}');
        expect(result.toolCalls[1].arguments, '{"cmd":"ls"}');
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'surfaces generated media URLs from provider-specific SSE payloads',
      () async {
        const mediaUrl =
            'https://assets.grok.com/users/abc/generated_video.mp4';
        const sse =
            'data: {"status":"processing","result":{"status_url":"https://api.x.ai/tasks/123"}}\n\n'
            'data: {"result":{"video_url":"$mediaUrl"}}\n\n'
            'data: {"result":{"video_url":"$mediaUrl"}}\n\n'
            'data: [DONE]\n\n';

        final mockClient = MockClient.streaming((request, body) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(sse.codeUnits),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });

        final service = AiChatService(client: mockClient);
        final response = await service.sendMessageStream(
          model: model,
          messages: const [
            AiChatTurn(role: AiChatRole.user, content: 'make a video'),
          ],
        );
        final deltas = <String>[];
        final subscription = response.events.listen((event) {
          if (event.textDelta != null) {
            deltas.add(event.textDelta!);
          }
        });

        final result = await response.result;
        await subscription.cancel();

        expect(result.reply, contains('[AI Generated Video]($mediaUrl)'));
        expect(deltas.join(), contains('[AI Generated Video]($mediaUrl)'));
        expect(
          result.reply.indexOf(mediaUrl),
          result.reply.lastIndexOf(mediaUrl),
        );
        expect(result.reply, isNot(contains('status_url')));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'surfaces generated audio URLs from provider-specific SSE payloads',
      () async {
        const mediaUrl = 'https://cdn.example.invalid/speech/final_audio.mp3';
        const sse =
            'data: {"output":{"progress":0.8,"status_url":"https://api.example.invalid/tasks/audio-1"}}\n\n'
            'data: {"output":{"audio_url":"$mediaUrl"}}\n\n'
            'data: [DONE]\n\n';

        final mockClient = MockClient.streaming((request, body) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(sse.codeUnits),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });

        final service = AiChatService(client: mockClient);
        final response = await service.sendMessageStream(
          model: model,
          messages: const [
            AiChatTurn(role: AiChatRole.user, content: 'make audio'),
          ],
        );
        final deltas = <String>[];
        final subscription = response.events.listen((event) {
          if (event.textDelta != null) {
            deltas.add(event.textDelta!);
          }
        });

        final result = await response.result;
        await subscription.cancel();

        expect(result.reply, contains('[AI Generated Audio]($mediaUrl)'));
        expect(deltas.join(), contains('[AI Generated Audio]($mediaUrl)'));
        expect(result.reply, isNot(contains('status_url')));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'ignores local file URLs and typed task URLs in media SSE payloads',
      () async {
        const sse =
            'data: {"type":"video","url":"https://api.example.invalid/tasks/video-123"}\n\n'
            'data: {"result":{"video_url":"file:///tmp/generated_video.mp4"}}\n\n'
            'data: [DONE]\n\n';

        final mockClient = MockClient.streaming((request, body) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(sse.codeUnits),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });

        final service = AiChatService(client: mockClient);
        final response = await service.sendMessageStream(
          model: model,
          messages: const [
            AiChatTurn(role: AiChatRole.user, content: 'make a video'),
          ],
        );
        final deltas = <String>[];
        final subscription = response.events.listen((event) {
          if (event.textDelta != null) {
            deltas.add(event.textDelta!);
          }
        });

        final result = await response.result;
        await subscription.cancel();

        expect(result.reply, isEmpty);
        expect(deltas, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
