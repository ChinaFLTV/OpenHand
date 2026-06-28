import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_har_replay_server.dart';

void main() {
  test('HAR replay server normalizes dirty entries', () async {
    final server = await WebReverseHarReplayServer.start(
      harBytes: utf8.encode(
        jsonEncode(<String, Object?>{
          'log': <String, Object?>{
            'entries': <Object?>[
              <String, Object?>{
                'request': <String, Object?>{
                  'method': ' get ',
                  'url': ' https://example.test/api?b=2&a=1 ',
                },
                'response': <String, Object?>{
                  'status': '201',
                  'headers': <Object?>[
                    <Object?, Object?>{'name': ' x-test ', 'value': ' ok '},
                    <String, Object?>{'name': ' ', 'value': 'skip'},
                    <String, Object?>{'name': 'content-length', 'value': '999'},
                  ],
                  'content': <String, Object?>{
                    'mimeType': 'text/plain',
                    'text': ' hello ',
                  },
                },
              },
              'noise',
              <String, Object?>{
                'request': <String, Object?>{
                  'method': 'GET',
                  'url': 'https://example.test/bad-status',
                },
                'response': <String, Object?>{
                  'status': 'bad',
                  'content': <String, Object?>{'text': 'fallback'},
                },
              },
              <String, Object?>{
                'request': <String, Object?>{
                  'method': 'POST',
                  'url': 'https://example.test/ignored',
                },
                'response': <String, Object?>{'status': 204},
              },
            ],
          },
        }),
      ),
    );
    expect(server, isNotNull);
    addTearDown(() async {
      await server?.close();
    });

    final first = await _get(server!.port, '/api?a=1&b=2');
    expect(first.statusCode, 201);
    expect(first.body, ' hello ');
    expect(first.headers.value('x-test'), 'ok');
    expect(first.headers.value('content-length'), isNull);

    final fallback = await _get(server.port, '/bad-status');
    expect(fallback.statusCode, 200);
    expect(fallback.body, 'fallback');
  });

  test('HAR replay server rejects non-object HAR roots', () async {
    final server = await WebReverseHarReplayServer.start(
      harBytes: utf8.encode('[]'),
    );

    expect(server, isNull);
  });
}

Future<_HttpTextResponse> _get(int port, String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _HttpTextResponse(response.statusCode, response.headers, body);
  } finally {
    client.close(force: true);
  }
}

class _HttpTextResponse {
  const _HttpTextResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final HttpHeaders headers;
  final String body;
}
