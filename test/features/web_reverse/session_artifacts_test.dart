import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_artifacts.dart';

void main() {
  late Directory directory;
  late WebReverseSessionArtifacts artifacts;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('openhand-artifacts-');
    artifacts = WebReverseSessionArtifacts(rootDir: directory.path);
  });

  tearDown(() async {
    await artifacts.close();
    await directory.delete(recursive: true);
  });

  test('并发初始化共享结果，重复关闭仅收尾一次并保留待写事件', () async {
    final initialization = artifacts.init();
    expect(identical(initialization, artifacts.init()), isTrue);
    await initialization;
    artifacts.appendNetwork(<String, Object?>{'kind': '请求'});
    artifacts.appendConsole(<String, Object?>{'text': '中文日志'});
    final closing = artifacts.close();
    expect(identical(closing, artifacts.close()), isTrue);
    await closing;
    expect(
      await File('${directory.path}/network.jsonl').readAsString(),
      contains('请求'),
    );
    expect(
      await File('${directory.path}/console.jsonl').readAsString(),
      contains('中文日志'),
    );
    artifacts.appendConsole(<String, Object?>{'text': '不应写入'});
    await artifacts.init();
    expect(
      await File('${directory.path}/console.jsonl').readAsString(),
      isNot(contains('不应写入')),
    );
  });

  test('初始化期间关闭不会留下打开的输出文件', () async {
    final initialization = artifacts.init();
    await artifacts.close();
    await initialization;
    expect(await artifacts.exportHar(), isNull);
    // Windows 上仍被持有的文件句柄会阻止目录删除。
    await directory.delete(recursive: true);
    await directory.create();
  });

  test('HAR 请求体使用 UTF-8 字节数，结束时间提前时归零', () async {
    await artifacts.init();
    final started = DateTime.utc(2026, 9, 14);
    artifacts.recordHarRequest(
      requestId: '请求',
      url: 'https://example.com/check',
      method: 'POST',
      headers: const <String, Object?>{},
      postData: '中文🚀',
      startedAt: started,
    );
    artifacts.recordHarFinished(
      '请求',
      started.subtract(const Duration(seconds: 1)),
    );
    final entries = await _readHarEntries(artifacts);
    final entry = entries.single as Map<String, dynamic>;
    expect(entry['request']['bodySize'], utf8.encode('中文🚀').length);
    expect(entry['time'], 0);
  });

  test('HAR 总预算淘汰旧草稿，避免大量大请求累积占用内存', () async {
    await artifacts.init();
    final body = 'x' * (256 * 1024);
    for (var index = 0; index < 70; index++) {
      artifacts.recordHarRequest(
        requestId: '$index',
        url: 'https://example.com/$index',
        method: 'POST',
        headers: const <String, Object?>{},
        postData: body,
        startedAt: DateTime.utc(2026, 9, 14).add(Duration(milliseconds: index)),
      );
    }
    final entries = await _readHarEntries(artifacts);
    expect(entries.length, inInclusiveRange(1, 63));
    expect(
      (entries.last as Map<String, dynamic>)['request']['url'],
      'https://example.com/69',
    );
  });
}

Future<List<dynamic>> _readHarEntries(
  WebReverseSessionArtifacts artifacts,
) async {
  final path = await artifacts.exportHar();
  expect(path, isNotNull);
  final har =
      jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
  return har['log']['entries'] as List<dynamic>;
}
