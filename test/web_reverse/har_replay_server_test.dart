// HAR 重放 mock server：构造极简 HAR → 启动 server → HTTP GET 验证 status/body。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_har_replay_server.dart';

void main() {
  test('启动后能按 URL 全等命中并回放 status / body', () async {
    final har = jsonEncode({
      'log': {
        'version': '1.2',
        'creator': {'name': 'oh-test', 'version': '1'},
        'entries': [
          {
            'startedDateTime': DateTime.now().toUtc().toIso8601String(),
            'time': 12,
            'request': {
              'method': 'GET',
              'url': 'https://example.com/api/foo?x=1&y=2',
              'headers': [],
              'queryString': [],
            },
            'response': {
              'status': 200,
              'statusText': 'OK',
              'headers': [
                {'name': 'X-Mock', 'value': 'yes'},
              ],
              'content': {
                'mimeType': 'application/json',
                'text': '{"hello":"world"}',
              },
            },
            'cache': {},
            'timings': {'send': 0, 'wait': 0, 'receive': 0},
          },
        ],
      },
    });
    final server =
        await WebReverseHarReplayServer.start(harBytes: utf8.encode(har));
    expect(server, isNotNull);
    // entryCount 包括 full URL + path-only 两份索引，因此是 2。
    expect(server!.entryCount, 2);
    final client = HttpClient();
    try {
      // path-only fallback 命中。
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/foo?x=1&y=2'),
      );
      final res = await req.close();
      expect(res.statusCode, 200);
      final body = await res.transform(utf8.decoder).join();
      expect(body, '{"hello":"world"}');
      expect(res.headers.value('X-Mock'), 'yes');
    } finally {
      client.close(force: true);
      await server.close();
    }
  });

  test('查询参数顺序不同也能命中（归一化排序）', () async {
    final har = jsonEncode({
      'log': {
        'version': '1.2',
        'creator': {'name': 'oh-test', 'version': '1'},
        'entries': [
          {
            'startedDateTime': DateTime.now().toUtc().toIso8601String(),
            'time': 1,
            'request': {
              'method': 'GET',
              'url': 'https://example.com/q?a=1&b=2',
              'headers': [],
              'queryString': [],
            },
            'response': {
              'status': 201,
              'headers': [],
              'content': {'mimeType': 'text/plain', 'text': 'ok'},
            },
            'cache': {},
            'timings': {'send': 0, 'wait': 0, 'receive': 0},
          },
        ],
      },
    });
    final server =
        await WebReverseHarReplayServer.start(harBytes: utf8.encode(har));
    expect(server, isNotNull);
    final client = HttpClient();
    try {
      // 顺序反转：b=2&a=1。
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server!.port}/q?b=2&a=1'),
      );
      final res = await req.close();
      expect(res.statusCode, 201);
      final body = await res.transform(utf8.decoder).join();
      expect(body, 'ok');
    } finally {
      client.close(force: true);
      await server!.close();
    }
  });

  test('不匹配的请求 → 404 + JSON 提示', () async {
    final har = jsonEncode({
      'log': {'version': '1.2', 'creator': {'name': 'x', 'version': '1'}, 'entries': []},
    });
    final server =
        await WebReverseHarReplayServer.start(harBytes: utf8.encode(har));
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server!.port}/anything'),
      );
      final res = await req.close();
      expect(res.statusCode, 404);
      final body = await res.transform(utf8.decoder).join();
      expect(body, contains('no har entry'));
    } finally {
      client.close(force: true);
      await server!.close();
    }
  });

  test('损坏 HAR → start 返回 null', () async {
    final s = await WebReverseHarReplayServer.start(
      harBytes: utf8.encode('not json'),
    );
    expect(s, isNull);
  });
}
