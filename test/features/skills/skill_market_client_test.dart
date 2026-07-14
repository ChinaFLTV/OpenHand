import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/skills/data/skill_market_client.dart';

void main() {
  test('file content cache evicts its least recently used entry', () async {
    final requestCounts = <String, int>{};
    final httpClient = MockClient((request) async {
      final path = request.url.queryParameters['path'] ?? '';
      requestCounts[path] = (requestCounts[path] ?? 0) + 1;
      return http.Response('content:$path', 200);
    });
    final client = SkillMarketClient(httpClient: httpClient);
    addTearDown(client.close);
    addTearDown(httpClient.close);

    for (var index = 0; index <= 128; index += 1) {
      await client.fetchSkillFileContent(
        slug: 'bounded-cache',
        path: 'file-$index.txt',
        version: '1.0.0',
      );
    }
    await client.fetchSkillFileContent(
      slug: 'bounded-cache',
      path: 'file-0.txt',
      version: '1.0.0',
    );

    expect(requestCounts['file-0.txt'], 2);
    expect(requestCounts['file-128.txt'], 1);
  });

  test('file content rejects a response above its byte limit', () async {
    final httpClient = _OversizedSkillFileClient();
    final client = SkillMarketClient(httpClient: httpClient);
    addTearDown(client.close);
    addTearDown(httpClient.close);

    await expectLater(
      client.fetchSkillFileContent(
        slug: 'oversized-file',
        path: 'SKILL.md',
        version: '1.0.0',
      ),
      throwsA(
        isA<SkillMarketException>().having(
          (error) => error.message,
          'message',
          contains('too large'),
        ),
      ),
    );
  });
}

class _OversizedSkillFileClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final chunk = Uint8List(1024 * 1024);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(List<List<int>>.filled(5, chunk)),
      200,
      request: request,
    );
  }
}
