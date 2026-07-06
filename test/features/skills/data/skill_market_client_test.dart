import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/skills/data/skill_market_client.dart';

void main() {
  group('SkillMarketClient', () {
    test('removes failed file content requests from cache', () async {
      var attempts = 0;
      final client = SkillMarketClient(
        httpClient: MockClient((request) async {
          attempts += 1;
          expect(request.url.path, '/api/v1/skills/demo/file');
          if (attempts == 1) {
            return http.Response('temporary failure', 503);
          }
          return http.Response.bytes(utf8.encode('skill body'), 200);
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.fetchSkillFileContent(
          slug: 'demo',
          path: 'SKILL.md',
          version: '1.0.0',
        ),
        throwsA(
          isA<SkillMarketException>().having(
            (error) => error.message,
            'message',
            'HTTP 503 while fetching skill file.',
          ),
        ),
      );

      final body = await client.fetchSkillFileContent(
        slug: 'demo',
        path: 'SKILL.md',
        version: '1.0.0',
      );

      expect(body, 'skill body');
      expect(attempts, 2);
    });

    test('reports download HTTP failures with shared failure handling', () {
      final client = SkillMarketClient(
        httpClient: MockClient(
          (_) async => http.Response.bytes(const <int>[1, 2, 3], 404),
        ),
      );
      addTearDown(client.close);

      expect(
        client.downloadSkillArchive('demo'),
        throwsA(
          isA<SkillMarketException>().having(
            (error) => error.message,
            'message',
            'HTTP 404 while downloading skill.',
          ),
        ),
      );
    });
  });
}
