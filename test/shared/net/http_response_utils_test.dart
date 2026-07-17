import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/http_response_utils.dart';

void main() {
  const timeout = Duration(seconds: 1);

  test('达到容量上限时等待源流正常结束', () async {
    final source = StreamController<List<int>>();
    var completed = false;
    final reading = readBoundedByteStream(
      source.stream,
      maxBytes: 3,
      idleTimeout: timeout,
      truncateOnOverflow: true,
    )..then((_) => completed = true);

    source.add(const <int>[1, 2, 3]);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    await source.close();
    expect(await reading, orderedEquals(const <int>[1, 2, 3]));
  });

  test('超过容量上限时返回前缀并取消源订阅', () async {
    final cancelled = Completer<void>();
    final source = StreamController<List<int>>(onCancel: cancelled.complete);
    final reading = readBoundedByteStream(
      source.stream,
      maxBytes: 3,
      idleTimeout: timeout,
      truncateOnOverflow: true,
    );

    source.add(const <int>[1, 2, 3, 4]);

    expect(await reading, orderedEquals(const <int>[1, 2, 3]));
    await cancelled.future.timeout(timeout);
    await source.close();
  });

  test('非截断读取超过容量时抛出明确异常', () async {
    await expectLater(
      readBoundedByteStream(
        Stream<List<int>>.value(const <int>[1, 2]),
        maxBytes: 1,
        idleTimeout: timeout,
      ),
      throwsA(
        isA<ByteStreamSizeLimitException>().having(
          (error) => error.maxBytes,
          '容量上限',
          1,
        ),
      ),
    );
  });

  test('统一拒绝无效容量和超时参数', () {
    expect(
      () => readBoundedByteStream(
        const Stream<List<int>>.empty(),
        maxBytes: 0,
        idleTimeout: timeout,
      ),
      throwsArgumentError,
    );
    expect(
      () => limitByteStream(
        const Stream<List<int>>.empty(),
        maxBytes: 1,
        totalTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
