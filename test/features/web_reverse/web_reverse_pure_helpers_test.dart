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
}
