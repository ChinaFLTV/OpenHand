import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_http_utils.dart';
import 'package:openhand/shared/net/http_response_utils.dart';

const Duration _timeout = Duration(seconds: 1);

void main() {
  test('collects a bounded response with immutable metadata', () async {
    final uri = Uri.parse('https://example.com/search');
    final request = http.Request('GET', uri);
    final response = http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('响应正文')),
      200,
      headers: const <String, String>{'content-type': 'text/plain'},
      request: request,
    );

    final collected = await collectBoundedWebEngineResponse(
      response,
      responseTimeout: _timeout,
      maxBytes: 64,
    );

    expect(collected.statusCode, 200);
    expect(collected.body, '响应正文');
    expect(collected.requestUrl, uri);
    expect(collected.headers, const <String, String>{
      'content-type': 'text/plain',
    });
    expect(
      () => collected.headers['content-type'] = 'application/json',
      throwsUnsupportedError,
    );
  });

  test('rejects a response that exceeds the configured byte limit', () async {
    final response = http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode('1234'),
        utf8.encode('5'),
      ]),
      200,
    );

    await expectLater(
      collectBoundedWebEngineResponse(
        response,
        responseTimeout: _timeout,
        maxBytes: 4,
      ),
      throwsA(
        isA<ByteStreamSizeLimitException>().having(
          (error) => error.maxBytes,
          'maxBytes',
          4,
        ),
      ),
    );
  });

  test('clips error previews to a bounded character count', () {
    final body = '${List<String>.filled(2500, 'x').join()}tail-marker';
    final response = BoundedWebEngineHttpResponse(
      statusCode: 500,
      headers: const <String, String>{},
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      requestUrl: null,
    );

    final preview = response.errorPreview();

    expect(preview.length, 2000);
    expect(preview, endsWith('…'));
    expect(preview, isNot(contains('tail-marker')));
  });

  test('rejects a non-positive connection timeout before sending', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);

    await expectLater(
      sendBoundedWebEngineRequest(
        client: client,
        request: http.Request('GET', Uri.parse('https://example.com')),
        connectionTimeout: Duration.zero,
        responseTimeout: _timeout,
      ),
      throwsArgumentError,
    );
    expect(requestCount, 0);
  });
}
