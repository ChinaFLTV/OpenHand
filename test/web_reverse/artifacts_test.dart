// WebReverseSessionArtifacts 行为：
//   - jsonl 真的把 append 落盘
//   - HAR exportHar 合成有效的 1.2 文档（包含 log / entries）
//   - close 后 jsonl 文件正确收尾。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_artifacts.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('oh_artifacts_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('init 后 network/console.jsonl 真的可写，flush 后内容对得上', () async {
    final a = WebReverseSessionArtifacts(
      rootDir: tmp.path,
      flushInterval: const Duration(milliseconds: 50),
    );
    await a.init();
    a.appendNetwork(<String, Object?>{'kind': 'request', 'url': 'https://x'});
    a.appendConsole(<String, Object?>{'level': 'log', 'text': 'hi'});
    // 等一次 flush。
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await a.close();
    final net =
        await File('${tmp.path}/network.jsonl').readAsString();
    expect(net.trim(), isNotEmpty);
    final firstLine = const LineSplitter().convert(net).first;
    final decoded = jsonDecode(firstLine) as Map<String, Object?>;
    expect(decoded['kind'], 'request');
    expect(decoded['url'], 'https://x');
    final con = await File('${tmp.path}/console.jsonl').readAsString();
    expect(con, contains('"level":"log"'));
  });

  test('exportHar 生成 HAR 1.2 带 entries', () async {
    final a = WebReverseSessionArtifacts(
      rootDir: tmp.path,
      flushInterval: const Duration(milliseconds: 50),
    );
    await a.init();
    final start = DateTime.now();
    a
      ..recordHarRequest(
        requestId: 'r1',
        url: 'https://example.com/api',
        method: 'POST',
        headers: <String, Object?>{'Content-Type': 'application/json'},
        postData: '{"q":1}',
        startedAt: start,
      )
      ..recordHarResponse(
        requestId: 'r1',
        status: 200,
        statusText: 'OK',
        mimeType: 'application/json',
        headers: <String, Object?>{'Server': 'cloudflare'},
        bodySize: 42,
      )
      ..recordHarFinished('r1', start.add(const Duration(milliseconds: 120)));
    final path = await a.exportHar();
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    final har = jsonDecode(await File(path).readAsString()) as Map;
    final log = har['log'] as Map;
    expect(log['version'], '1.2');
    expect(log['creator'], isA<Map>());
    final entries = log['entries'] as List;
    expect(entries.length, 1);
    final e = entries.first as Map;
    expect(e['request'], isA<Map>());
    expect((e['request'] as Map)['method'], 'POST');
    expect((e['response'] as Map)['status'], 200);
    expect(e['time'], greaterThanOrEqualTo(0));
    await a.close();
  });

  test('init 失败时 append 不抛', () async {
    // 用一个不可写的根（不存在父目录的 readonly），让 init 失败。
    final a = WebReverseSessionArtifacts(rootDir: '/proc/should-not-exist');
    await a.init(); // 内部 silentLog 吞错
    a.appendNetwork(<String, Object?>{'k': 1});
    a.appendConsole(<String, Object?>{'k': 2});
    await a.close();
  });
}
