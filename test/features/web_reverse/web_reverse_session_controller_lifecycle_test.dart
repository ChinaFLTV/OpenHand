import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_browser_kind.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_config.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

import '../../support/test_directory.dart';

void main() {
  test('session config rejects oversized target URLs', () {
    final config = WebReverseSessionConfig.fromJson(<String, Object?>{
      'target_url':
          'x' * (WebReverseSessionController.maxPageTargetUrlChars + 1),
      'objective': 'test',
      'cdp_port': 9222,
      'user_data_dir': '/tmp/openhand-profile',
      'browser_kind': WebReverseBrowserKind.chromium.id,
    });

    expect(config, isNull);
  });

  test('source map reports retained character cost for bounded caching', () {
    final info = WebReverseSourceMapInfo(
      scriptUrl: 'script.js',
      mapUrl: 'script.js.map',
      sources: const <String>['one.ts', 'two.ts'],
      sourcesContent: const <String?>['const one = 1;', null],
      names: const <String>['one'],
      sourceRoot: '/src/',
      mappings: 'AAAA',
    );

    expect(
      info.estimatedRetainedChars,
      'script.js'.length +
          'script.js.map'.length +
          'one.ts'.length +
          'two.ts'.length +
          'const one = 1;'.length +
          'one'.length +
          '/src/'.length +
          'AAAA'.length,
    );
  });

  test('shutdown is idempotent and rejects browser restart', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand-web-reverse-lifecycle-',
    );
    final controller = WebReverseSessionController(
      config: WebReverseSessionConfig(
        targetUrl: 'https://example.com',
        objective: 'test',
        cdpPort: 9222,
        userDataDir: '${tempDir.path}/profile',
        browserKind: WebReverseBrowserKind.chromium,
      ),
      executablePath: '/missing-browser',
      artifactsRootDir: '${tempDir.path}/artifacts',
    );

    await Future.wait<void>(<Future<void>>[
      controller.shutdown(),
      controller.shutdown(),
    ]);
    controller.dispose();

    await expectLater(controller.restartBrowser(), throwsStateError);
    await expectLater(controller.start(), throwsStateError);
    expect(controller.dispose, returnsNormally);
    await deleteTestDirectory(tempDir);
  });

  test('user-managed local collections enforce deterministic limits', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand-web-reverse-collections-',
    );
    final controller = WebReverseSessionController(
      config: WebReverseSessionConfig(
        targetUrl: 'https://example.com',
        objective: 'test',
        cdpPort: 9222,
        userDataDir: '${tempDir.path}/profile',
        browserKind: WebReverseBrowserKind.chromium,
      ),
      executablePath: '/missing-browser',
      artifactsRootDir: '${tempDir.path}/artifacts',
    );

    await controller.blockUrl('  https://example.com/blocked  ');
    for (
      var i = 1;
      i <= WebReverseSessionController.maxBlockedUrlPatterns;
      i++
    ) {
      await controller.blockUrl('https://example.com/blocked/$i');
    }
    expect(
      controller.blockedUrls,
      hasLength(WebReverseSessionController.maxBlockedUrlPatterns),
    );
    expect(controller.blockedUrls, contains('https://example.com/blocked'));

    for (var i = 0; i < WebReverseSessionController.maxWatchExpressions; i++) {
      expect(controller.addWatchExpression('value_$i'), isTrue);
    }
    expect(controller.addWatchExpression('overflow'), isFalse);
    expect(
      controller.addWatchExpression(
        'x' * (WebReverseSessionController.maxDebuggerExpressionChars + 1),
      ),
      isFalse,
    );
    expect(
      controller.watchExpressions,
      hasLength(WebReverseSessionController.maxWatchExpressions),
    );

    controller.setAccountSnapshots(<WebReverseAccountSnapshot>[
      for (
        var i = 0;
        i < WebReverseSessionController.maxAccountSnapshots + 2;
        i++
      )
        WebReverseAccountSnapshot(
          id: '$i',
          name: 'snapshot $i',
          origin: 'https://example.com',
          capturedAt: DateTime.fromMillisecondsSinceEpoch(i),
          cookies: const <Map<String, Object?>>[],
          localStorage: const <String, String>{},
          sessionStorage: const <String, String>{},
        ),
    ]);
    expect(
      controller.accountSnapshots,
      hasLength(WebReverseSessionController.maxAccountSnapshots),
    );
    expect(controller.accountSnapshots.first.id, '2');

    controller.setInterceptRules(<WebReverseInterceptRule>[
      WebReverseInterceptRule(
        urlPattern:
            '*' * (WebReverseSessionController.maxBreakpointTextChars + 1),
        replaceUrl:
            'r' * (WebReverseSessionController.maxBreakpointTextChars + 1),
        headerOverrides: <String, String>{
          'invalid\nheader': 'value',
          for (
            var i = 0;
            i < WebReverseSessionController.maxRuleHeaderEntries + 1;
            i++
          )
            'header-$i':
                'v' * (WebReverseSessionController.maxRuleHeaderValueChars + 1),
        },
      ),
    ]);
    final interceptRule = controller.interceptRules.single;
    expect(interceptRule.urlPattern, '*');
    expect(
      interceptRule.replaceUrl,
      hasLength(WebReverseSessionController.maxBreakpointTextChars),
    );
    expect(
      interceptRule.headerOverrides.length,
      lessThanOrEqualTo(WebReverseSessionController.maxRuleHeaderEntries),
    );
    expect(interceptRule.headerOverrides, isNot(contains('invalid\nheader')));

    controller.setMockRules(<WebReverseMockRule>[
      WebReverseMockRule(
        id: 'duplicate',
        name: ' n ' * WebReverseSessionController.maxRuleNameChars,
        urlPattern: 'https://example.com/***',
        body: 'b' * (WebReverseSessionController.maxMockBodyChars + 1),
      ),
      const WebReverseMockRule(
        id: 'duplicate',
        name: 'second',
        urlPattern: 'https://example.com/*',
      ),
    ]);
    expect(controller.mockRules, hasLength(2));
    expect(controller.mockRules.first.urlPattern, 'https://example.com/*');
    expect(
      controller.mockRules.first.body,
      hasLength(WebReverseSessionController.maxMockBodyChars),
    );
    expect(controller.mockRules[1].id, isNot(controller.mockRules.first.id));

    controller.setRequestBreakpoints(<WebReverseRequestBreakpoint>[
      WebReverseRequestBreakpoint(
        id: 'request',
        name: ' request ',
        enabled: true,
        methodFilter: ' post ',
        urlContains:
            'u' * (WebReverseSessionController.maxBreakpointTextChars + 1),
        bodyContains:
            'b' * (WebReverseSessionController.maxDebuggerExpressionChars + 1),
        evalExpression:
            'e' * (WebReverseSessionController.maxDebuggerExpressionChars + 1),
      ),
    ]);
    final requestBreakpoint = controller.requestBreakpoints.single;
    expect(requestBreakpoint.methodFilter, 'POST');
    expect(
      requestBreakpoint.urlContains,
      hasLength(WebReverseSessionController.maxBreakpointTextChars),
    );
    expect(
      requestBreakpoint.evalExpression,
      hasLength(WebReverseSessionController.maxDebuggerExpressionChars),
    );

    controller.setAccountSnapshots(<WebReverseAccountSnapshot>[
      WebReverseAccountSnapshot(
        id: 'bounded',
        name: 'account',
        origin: 'https://example.com',
        capturedAt: DateTime.fromMillisecondsSinceEpoch(1),
        cookies: <Map<String, Object?>>[
          for (
            var i = 0;
            i < WebReverseSessionController.maxAccountSnapshotCookies + 1;
            i++
          )
            <String, Object?>{
              'name': 'cookie-$i',
              'value': i == 0
                  ? 'v' *
                        (WebReverseSessionController
                                .maxAccountSnapshotValueChars +
                            1)
                  : 'value',
              'unexpected': <String, String>{'nested': 'value'},
            },
        ],
        localStorage: <String, String>{
          for (
            var i = 0;
            i <
                WebReverseSessionController.maxAccountSnapshotStorageEntries +
                    1;
            i++
          )
            'key-$i': 'value-$i',
        },
        sessionStorage: const <String, String>{},
      ),
    ]);
    final snapshot = controller.accountSnapshots.single;
    expect(
      snapshot.cookies,
      hasLength(WebReverseSessionController.maxAccountSnapshotCookies),
    );
    expect(
      snapshot.cookies.first['value'],
      isA<String>().having(
        (value) => value.length,
        'length',
        WebReverseSessionController.maxAccountSnapshotValueChars,
      ),
    );
    expect(snapshot.cookies.first, isNot(contains('unexpected')));
    expect(
      snapshot.localStorage.length,
      lessThanOrEqualTo(
        WebReverseSessionController.maxAccountSnapshotStorageEntries,
      ),
    );

    controller.setRecorderSteps(<Map<String, Object?>>[
      for (var i = 0; i < WebReverseSessionController.maxRecorderSteps + 2; i++)
        <String, Object?>{
          'type': 'navigate',
          'url': 'https://example.com/$i',
          'ts': i,
          'untrusted': <String, Object?>{'nested': true},
        },
    ]);
    expect(
      controller.recorderSteps,
      hasLength(WebReverseSessionController.maxRecorderSteps),
    );
    expect(controller.recorderSteps.first['url'], 'https://example.com/2');
    expect(controller.recorderSteps.first, isNot(contains('untrusted')));

    controller.setRecorderSteps(<Map<String, Object?>>[
      <String, Object?>{
        'type': 'input',
        'selector':
            's' * (WebReverseSessionController.maxBreakpointTextChars + 1),
        'value':
            'v' * (WebReverseSessionController.maxRecorderStepTextChars + 1),
      },
      const <String, Object?>{'type': 'unknown', 'selector': '#ignored'},
    ]);
    final recorderStep = controller.recorderSteps.single;
    expect(
      recorderStep['selector'],
      isA<String>().having(
        (value) => value.length,
        'length',
        WebReverseSessionController.maxBreakpointTextChars,
      ),
    );
    expect(
      recorderStep['value'],
      isA<String>().having(
        (value) => value.length,
        'length',
        WebReverseSessionController.maxRecorderStepTextChars,
      ),
    );

    controller.replacePageTargets(<CdpPageTargetSnapshot>[
      CdpPageTargetSnapshot(
        id: 'x' * (WebReverseSessionController.maxPageTargetIdChars + 1),
        url: 'https://invalid.example',
        title: 'Invalid ID',
      ),
      for (var i = 0; i < WebReverseSessionController.maxPageTargets + 2; i++)
        CdpPageTargetSnapshot(
          id: 'target-$i',
          url: i == 0
              ? 'u' * (WebReverseSessionController.maxPageTargetUrlChars + 1)
              : 'https://example.com/$i',
          title: i == 0
              ? 't' * (WebReverseSessionController.maxPageTargetTitleChars + 1)
              : 'Page $i',
        ),
    ]);
    expect(
      controller.pageTargets,
      hasLength(WebReverseSessionController.maxPageTargets),
    );
    expect(
      controller.pageTargets.first.url,
      hasLength(WebReverseSessionController.maxPageTargetUrlChars),
    );
    expect(
      controller.pageTargets.first.title,
      hasLength(WebReverseSessionController.maxPageTargetTitleChars),
    );
    controller.applyPageTargetOrder(const <Object?>['target-2', 'target-0']);
    expect(controller.pageTargetOrder.take(4), <String>[
      'target-2',
      'target-0',
      'target-1',
      'target-3',
    ]);

    await controller.shutdown();
    controller.dispose();
    await deleteTestDirectory(tempDir);
  });
}
