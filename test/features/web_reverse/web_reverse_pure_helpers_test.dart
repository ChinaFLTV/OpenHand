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
