import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/mcp_bridge/mcp_loaded_tools_tracker.dart';
import 'package:openhand/shared/net/http_response_utils.dart';
import 'package:openhand/shared/util/bounded_file_io.dart';
import 'package:openhand/shared/util/bounded_log_buffer.dart';
import 'package:openhand/shared/util/html_webview_mount_limiter.dart';

void main() {
  test('轻量统计响应不序列化缓存趋势点', () {
    final statistics = const AiSessionStatistics.initial().copyWith(
      totalPromptTokens: 200,
      cacheReadTokens: 120,
      cacheHitTrendPoints: const <AiSessionCacheHitTrendPoint>[
        AiSessionCacheHitTrendPoint(
          turnIndex: 1,
          hitRatio: 0.6,
          promptTokens: 200,
          cacheReadTokens: 120,
          cacheWriteTokens: 0,
          starterOrigin: 'explicit_user',
        ),
      ],
    );

    final lightweight = statistics.toJson(includeCacheHitTrendPoints: false);
    final complete = statistics.toJson();

    expect(lightweight, isNot(contains('cache_hit_trend_points')));
    expect(complete['cache_hit_trend_points'], hasLength(1));
  });

  test('HTML 平台视图许可保持并发上限并延迟授予回调', () {
    final scheduled = <void Function()>[];
    final limiter = HtmlWebViewMountLimiter(
      maxMounted: 1,
      scheduleGranted: scheduled.add,
    );
    var revoked = 0;
    var granted = 0;
    final first = limiter.request(() {}, onRevoked: () => revoked += 1);
    final second = limiter.request(() => granted += 1);

    expect(first.granted, isTrue);
    expect(second.granted, isFalse);

    limiter.revokeOldest();

    expect(revoked, 1);
    expect(second.granted, isTrue);
    expect(granted, 0);
    expect(scheduled, hasLength(1));

    scheduled.single();
    expect(granted, 1);
    second.release();
  });

  test('日志缓冲同时限制行数与字符数并保留最新内容', () {
    final buffer = BoundedLogBuffer(maxLines: 2, maxCharacters: 6);

    buffer
      ..add('1234')
      ..add('56')
      ..add('abcdefghi');

    expect(buffer.snapshot(), <String>['defghi']);
    expect(buffer.characterCount, 6);
  });

  test('ToolSearch 跟踪限制会话、工具名和历史容量', () {
    final tracker = McpLoadedToolsTracker(
      maxTrackedSessions: 2,
      maxNamesPerSession: 3,
      maxHistoryPerSession: 2,
      maxNameCharacters: 3,
      maxQueryCharacters: 4,
    );
    addTearDown(tracker.dispose);

    tracker
      ..absorb(sessionId: 's1', loadedNamesRaw: <String>['toolong', 'a'])
      ..absorb(sessionId: 's1', loadedNamesRaw: <String>['b'])
      ..absorb(
        sessionId: 's1',
        loadedNamesRaw: <String>['c'],
        queryRaw: '12345',
      )
      ..absorb(sessionId: 's1', loadedNamesRaw: <String>['d']);
    expect(tracker.namesForSession('s1'), <String>['a', 'b', 'c']);
    expect(tracker.historyForSession('s1'), hasLength(2));
    expect(tracker.historyForSession('s1').last.query, '1234');

    tracker
      ..absorb(sessionId: 's2', loadedNamesRaw: <String>['d'])
      ..absorb(sessionId: 's3', loadedNamesRaw: <String>['e']);

    expect(tracker.namesForSession('s1'), isEmpty);
    expect(tracker.namesForSession('s2'), <String>['d']);
    expect(tracker.namesForSession('s3'), <String>['e']);
  });

  test('Claude Hook 限制单次执行命令数量', () async {
    final root = await Directory.systemTemp.createTemp('openhand_hook_guard_');
    addTearDown(() => root.delete(recursive: true));
    final home = Directory('${root.path}/home');
    final configDirectory = Directory('${home.path}/.claude');
    await configDirectory.create(recursive: true);
    await File('${configDirectory.path}/settings.json').writeAsString(
      jsonEncode(<String, Object?>{
        'hooks': <String, Object?>{
          'GuardTest': <Object?>[
            <String, Object?>{
              'hooks': <Object?>[
                <String, Object?>{'type': 'command', 'command': 'echo 第一项'},
                <String, Object?>{'type': 'command', 'command': 'echo 第二项'},
                <String, Object?>{'type': 'command', 'command': 'echo 第三项'},
              ],
            },
          ],
        },
      }),
    );
    final service = AiClaudeHookService(
      applicationDirectoryPath: () => root.path,
      homeDirectoryPath: () => home.path,
      commandTimeout: const Duration(seconds: 2),
      invocationTimeout: const Duration(seconds: 5),
      maxCommandsPerInvocation: 2,
      configPresenceCacheTtl: Duration.zero,
    );

    final result = await service.runHooks(
      eventName: 'GuardTest',
      sessionId: 'session',
      payload: const <String, Object?>{},
      cwd: root.path,
    );

    expect(result.executedHookCount, 2);
    expect(result.executedCommands, <String>['echo 第一项', 'echo 第二项']);
  });

  test('字节流前缀读取严格限制容量并返回截断状态', () async {
    final exact = await readBoundedByteStreamPrefix(
      Stream<List<int>>.fromIterable(<List<int>>[
        <int>[1, 2],
        <int>[3],
      ]),
      maxBytes: 3,
      idleTimeout: const Duration(seconds: 1),
    );
    expect(exact.bytes, orderedEquals(<int>[1, 2, 3]));
    expect(exact.truncated, isFalse);

    final truncated = await readBoundedByteStreamPrefix(
      Stream<List<int>>.fromIterable(<List<int>>[
        <int>[1, 2],
        <int>[3, 4, 5],
      ]),
      maxBytes: 3,
      idleTimeout: const Duration(seconds: 1),
    );
    expect(truncated.bytes, orderedEquals(<int>[1, 2, 3]));
    expect(truncated.truncated, isTrue);
  });

  test('有界文件租约串行写入并执行自定义释放', () async {
    final root = await Directory.systemTemp.createTemp('openhand_file_guard_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/output.bin');
    var released = false;
    final lease = await openBoundedRandomAccessFileLease(
      file,
      mode: FileMode.write,
      timeout: const Duration(seconds: 1),
      release: (output) async {
        await output.close();
        released = true;
      },
    );

    await lease.run(
      (output) => output.writeFrom(<int>[1, 2, 3]),
      timeout: const Duration(seconds: 1),
    );
    await lease.close(timeout: const Duration(seconds: 1));

    expect(released, isTrue);
    expect(await file.readAsBytes(), orderedEquals(<int>[1, 2, 3]));
  });
}
