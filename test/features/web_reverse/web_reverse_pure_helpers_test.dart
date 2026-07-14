import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_pure_helpers.dart';

Map<String, Object?> _samplingNode(
  String functionName,
  int selfSize, {
  List<Map<String, Object?>> children = const <Map<String, Object?>>[],
}) {
  return <String, Object?>{
    'callFrame': <String, Object?>{
      'functionName': functionName,
      'url': 'https://example.com/$functionName.js',
      'lineNumber': 1,
      'columnNumber': 2,
    },
    'selfSize': selfSize,
    'children': children,
  };
}

void main() {
  test('page target normalization clips, deduplicates and retains current', () {
    final raw =
        List<Map<String, Object?>>.generate(
          6,
          (index) => <String, Object?>{
            'type': 'page',
            'targetId': 'target-$index',
            'url': 'u' * 40,
            'title': 't' * 20,
            'unused': 'discarded',
          },
        )..insert(1, <String, Object?>{
          'type': 'page',
          'targetId': 'target-0',
          'url': 'duplicate',
          'title': 'duplicate',
        });

    final targets = normalizeWebReversePageTargets(
      raw,
      preferredId: 'target-5',
      maxEntries: 2,
      maxIdChars: 32,
      maxUrlChars: 12,
      maxTitleChars: 8,
    );

    expect(targets, hasLength(2));
    expect(targets.map((target) => target.id), contains('target-5'));
    expect(targets.every((target) => target.url.length == 12), isTrue);
    expect(targets.every((target) => target.title.length == 8), isTrue);
  });

  test('service worker compaction joins scopes and keeps only UI fields', () {
    final workers = compactWebReverseServiceWorkers(
      <Object?>[
        <String, Object?>{
          'versionId': 'version-1',
          'registrationId': 'registration-1',
          'scriptURL': 'https://example.com/worker-one.js',
          'runningStatus': 'running',
          'status': 'installed',
          'largeUnusedPayload': 'x' * 10000,
        },
        <String, Object?>{
          'versionId': 'version-1',
          'registrationId': 'registration-1',
          'scriptURL': 'https://example.com/worker-two.js',
          'runningStatus': 'stopped',
          'status': 'activated',
        },
        <String, Object?>{
          'versionId': 'version-2',
          'scriptURL': 'https://example.com/worker-three.js',
        },
        <String, Object?>{
          'versionId': 'version-3',
          'scriptURL': 'https://example.com/worker-four.js',
        },
      ],
      rawRegistrations: <Object?>[
        <String, Object?>{
          'registrationId': 'registration-1',
          'scopeURL': 'https://example.com/a-very-long-scope/',
        },
      ],
      maxEntries: 2,
      maxIdChars: 32,
      maxUrlChars: 24,
      maxStatusChars: 16,
    );

    expect(workers, hasLength(2));
    expect(workers.first['status'], 'activated');
    expect(workers.first['scopeURL'], hasLength(24));
    expect(workers.first, isNot(contains('largeUnusedPayload')));
    expect(workers.map((worker) => worker['versionId']), [
      'version-1',
      'version-2',
    ]);
  });

  test('cache and persisted tab metadata normalization stay bounded', () {
    final cacheNames = normalizeWebReverseCacheStorageNames(
      <Object?>[
        <String, Object?>{'cacheName': 'cache-a'},
        <String, Object?>{'cacheName': 'cache-a'},
        <String, Object?>{'cacheName': 'cache-name-is-long'},
        <String, Object?>{'cacheName': 'cache-c'},
      ],
      maxEntries: 2,
      maxNameChars: 8,
    );
    final restoreUrls = normalizeWebReverseTabRestoreUrls(
      <Object?>['tab-a', 'tab-blank', 'tab-a', 'tab-b', 'tab-c'],
      <String, Object?>{
        'tab-a': 'https://example.com/first',
        'tab-blank': 'about:blank',
        'tab-b': 'https://example.com/second',
        'tab-c': 'https://example.com/third',
      },
      maxEntries: 2,
      maxIdChars: 16,
      maxUrlChars: 20,
    );

    expect(cacheNames, ['cache-a', 'cache-na']);
    expect(restoreUrls, ['https://example.com/', 'https://example.com/']);
  });

  test('application data compaction bounds cookies and DOM storage', () {
    final cookies = compactWebReverseCookies(
      <Object?>[
        <String, Object?>{
          'name': 'session',
          'value': 'v' * 32,
          'domain': 'example.com',
          'path': '/',
          'secure': true,
          'partitionKey': <String, Object?>{
            'topLevelSite': 'https://top.example',
            'hasCrossSiteAncestor': true,
            'unexpected': 'discarded',
          },
          'unexpected': 'discarded',
        },
        <String, Object?>{'name': 'x' * 20, 'value': 'ignored'},
      ],
      maxValueChars: 8,
      maxNameChars: 12,
      maxTotalChars: 64,
    );
    final storage = normalizeWebReverseDomStorageEntries(
      <Object?>[
        <Object?>['key', 'v' * 20],
        <Object?>['k' * 20, 'ignored'],
        <Object?>['second', 'value'],
      ],
      maxKeyChars: 8,
      maxValueChars: 8,
      maxTotalChars: 32,
    );

    expect(cookies, hasLength(1));
    expect(cookies.single['value'], 'v' * 8);
    expect(cookies.single, isNot(contains('unexpected')));
    expect(cookies.single['partitionKey'], <String, Object?>{
      'topLevelSite': 'https://top.example',
      'hasCrossSiteAncestor': true,
    });
    expect(storage, hasLength(2));
    expect(storage.first.value, 'v' * 8);
    expect(storage.last.key, 'second');
  });

  test('indexedDB compaction bounds names, remote objects and page size', () {
    final names = normalizeWebReverseIndexedDbNames(
      <Object?>[' db-a ', ' db-a ', 'n' * 20, 'db-b'],
      maxEntries: 2,
      maxNameChars: 8,
    );
    final stores = normalizeWebReverseIndexedDbStoreNames(<Object?>[
      <String, Object?>{'name': 'store-a'},
      <String, Object?>{'name': 'store-b'},
    ], maxEntries: 1);
    final entries = compactWebReverseIndexedDbEntries(
      <Object?>[
        <String, Object?>{
          'key': <String, Object?>{
            'type': 'string',
            'value': 'key',
            'objectId': 'discarded',
          },
          'value': <String, Object?>{
            'type': 'object',
            'description': 'd' * 20,
            'preview': <String, Object?>{'overflow': true},
          },
        },
        <String, Object?>{
          'key': <String, Object?>{'type': 'string', 'value': 'k' * 100},
        },
      ],
      maxEntries: 2,
      maxTextChars: 8,
    );

    expect(names, [' db-a ', 'db-b']);
    expect(stores, ['store-a']);
    expect(entries, hasLength(1));
    expect(entries.single['key'], isA<Map<String, Object?>>());
    expect(entries.single['value'], isNot(contains('preview')));
  });

  test(
    'sampling profile summary aggregates functions and preserves top stack',
    () {
      final summary = summarizeSamplingHeapProfile(
        _samplingNode(
          'root',
          3,
          children: <Map<String, Object?>>[
            _samplingNode('root', 5),
            _samplingNode('worker', 7),
          ],
        ),
      );

      expect(summary, isNotNull);
      expect(summary!.totalSize, 15);
      expect(summary.top.first.label, 'root');
      expect(summary.top.first.size, 8);
      expect(summary.top.first.stack.first, contains('root'));
    },
  );

  test(
    'sampling profile summary bounds deep traversal and retained stacks',
    () {
      var head = _samplingNode('leaf', 1);
      for (var i = 0; i < 1000; i++) {
        head = _samplingNode('frame-$i', 1, children: [head]);
      }

      final summary = summarizeSamplingHeapProfile(
        head,
        maxNodes: 128,
        maxStackDepth: 32,
        maxFunctionBuckets: 64,
        maxTopEntries: 64,
      );

      expect(summary, isNotNull);
      expect(summary!.totalSize, 128);
      expect(summary.top, hasLength(64));
      expect(summary.top.every((entry) => entry.stack.length <= 32), isTrue);
    },
  );

  test('sampling profile summary rejects invalid limits', () {
    expect(
      () => summarizeSamplingHeapProfile(_samplingNode('root', 1), maxNodes: 0),
      throwsArgumentError,
    );
  });

  test('DOM compaction bounds depth, children and arbitrary fields', () {
    final raw = <String, Object?>{
      'nodeId': 1,
      'nodeName': 'DIV',
      'nodeValue': 'x' * 100,
      'attributes': <Object?>['id', 'a', 'class', 'b', 'ignored', 'c'],
      'unused': <Object?>[for (var i = 0; i < 100; i++) i],
      'children': <Object?>[
        <String, Object?>{
          'nodeId': 2,
          'nodeName': 'SPAN',
          'children': <Object?>[
            <String, Object?>{'nodeId': 3, 'nodeName': 'B'},
          ],
        },
      ],
    };
    final compact = compactWebReverseDomNode(
      raw,
      maxDepth: 1,
      maxNodes: 2,
      maxFieldChars: 8,
      maxAttributes: 4,
    );
    expect(compact, isNotNull);
    expect(compact!['nodeValue'], 'xxxxxxxx');
    expect(compact['unused'], isNull);
    expect((compact['children'] as List).length, 1);
    expect((compact['children']!.first as Map)['children'], isNull);
    expect(compactWebReverseDomNode(raw, maxDepth: 0)!['children'], isNull);
  });

  test('performance, style, listener and runtime records stay compact', () {
    final metrics = normalizeWebReversePerformanceMetrics(<Object?>[
      <String, Object?>{'name': 'Task', 'value': 1},
      <String, Object?>{'name': 'Task', 'value': 2},
      <String, Object?>{'name': 'bad', 'value': double.nan},
    ]);
    expect(metrics, [("Task", 2.0)]);

    final styles = compactWebReverseComputedStyles(<Object?>[
      <String, Object?>{'name': 'color', 'value': 'red'},
      <String, Object?>{'name': 'color', 'value': 'blue'},
    ]);
    expect(styles, [
      <String, String>{'name': 'color', 'value': 'red'},
    ]);

    final listeners = compactWebReverseDomEventListeners(<Object?>[
      <String, Object?>{
        'type': 'click',
        'useCapture': true,
        'handler': <String, Object?>{
          'type': 'function',
          'description': 'fn',
          'preview': 'discarded',
        },
      },
    ]);
    expect(listeners.single['type'], 'click');
    expect((listeners.single['handler'] as Map)['description'], 'fn');
    expect((listeners.single['handler'] as Map)['preview'], isNull);

    final properties = compactWebReverseRuntimeProperties(<Object?>[
      <String, Object?>{
        'name': 'value',
        'value': <String, Object?>{
          'type': 'string',
          'value': 'ok',
          'preview': <String, Object?>{'overflow': true},
        },
      },
    ]);
    expect((properties.single['value'] as Map)['value'], 'ok');
    expect((properties.single['value'] as Map)['preview'], isNull);
  });

  test('long task and WebRTC drains are bounded and typed', () {
    final tasks = compactWebReverseLongTasks(<Object?>[
      <String, Object?>{
        'start': 1,
        'duration': 20,
        'attribution': <String, Object?>{
          'containerName': 'widget',
          'unused': 'discarded',
        },
      },
    ]);
    expect(tasks.single['startTime'], 1.0);
    expect(tasks.single['duration'], 20.0);
    expect((tasks.single['attribution'] as Map)['unused'], isNull);

    final events = compactWebReverseWebRtcLog(<Object?>[
      <String, Object?>{
        'kind': 'track',
        'id': 1,
        'trackKind': 'video',
        'sdp': 's' * 100000,
        'huge': 'discarded',
      },
      <String, Object?>{'kind': 'stats', 'id': 1, 'bytesSent': 2},
    ], maxEventChars: 4096);
    expect(events, hasLength(2));
    expect(events.first['kind'], 'track');
    expect((events.first['sdp'] as String).length, lessThan(4096));
    expect(events.first['huge'], isNull);
    expect(normalizeWebReverseWebRtcConnections([1, 1, 0, -1, 2]), [1, 2]);
  });
}
