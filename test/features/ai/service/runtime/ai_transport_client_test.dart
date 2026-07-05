import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/service/runtime/ai_transport_client.dart';

void main() {
  group('AiTransportClient', () {
    test('sendJson uppercases method and encodes body once', () async {
      final transport = AiTransportClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url, Uri.parse('https://example.com/v1/test'));
          expect(request.headers['authorization'], 'Bearer token');
          expect(jsonDecode(request.body), <String, Object?>{'ok': true});
          return http.Response('done', 201);
        }),
      );

      final response = await transport.sendJson(
        uri: Uri.parse('https://example.com/v1/test'),
        method: 'post',
        headers: const <String, String>{'authorization': 'Bearer token'},
        body: const <String, Object?>{'ok': true},
        timeout: const Duration(seconds: 1),
      );

      expect(response.statusCode, 201);
      expect(response.body, 'done');
    });

    test(
      'sendMultipart strips caller content type and serializes fields',
      () async {
        final transport = AiTransportClient(
          client: MockClient((request) async {
            expect(request.method, 'PATCH');
            expect(request.headers['x-test'], 'yes');
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data; boundary='),
            );
            expect(request.body, contains('name="plain"'));
            expect(request.body, contains('value'));
            expect(request.body, contains('name="count"'));
            expect(request.body, contains('3'));
            expect(request.body, contains('name="meta"'));
            expect(request.body, contains('{"flag":true}'));
            return http.Response('uploaded', 200);
          }),
        );

        final response = await transport.sendMultipart(
          uri: Uri.parse('https://example.com/v1/upload'),
          method: 'patch',
          headers: const <String, String>{
            'content-type': 'application/json',
            'x-test': 'yes',
          },
          body: const <String, Object?>{
            'plain': 'value',
            'count': 3,
            'meta': <String, Object?>{'flag': true},
          },
          timeout: const Duration(seconds: 1),
        );

        expect(response.body, 'uploaded');
      },
    );

    test('downloadBytes rejects non-success responses', () async {
      final transport = AiTransportClient(
        client: MockClient(
          (_) async => http.Response.bytes(const <int>[1, 2, 3], 404),
        ),
      );

      await expectLater(
        transport.downloadBytes(
          uri: Uri.parse('https://example.com/missing.bin'),
          headers: const <String, String>{},
          timeout: const Duration(seconds: 1),
        ),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            'HTTP 404',
          ),
        ),
      );
    });
  });
}
