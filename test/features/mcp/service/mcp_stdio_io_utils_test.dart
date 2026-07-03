import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/service/mcp_stdio_io_utils.dart';

void main() {
  group('McpStdioWriteQueue', () {
    test(
      'rejects new writes without cancelling already queued writes',
      () async {
        final queue = McpStdioWriteQueue();
        final releaseFirst = Completer<void>();
        final events = <String>[];
        final closingError = StateError('closing');

        final first = queue.run(() async {
          events.add('first:start');
          await releaseFirst.future;
          events.add('first:end');
        });
        final second = queue.run(() async {
          events.add('second');
        });

        queue.rejectNewWrites(closingError);

        await expectLater(
          queue.run(() async {
            events.add('third');
          }),
          throwsA(same(closingError)),
        );

        releaseFirst.complete();
        await first;
        await second;
        await queue.drain(const Duration(milliseconds: 100));

        expect(events, <String>['first:start', 'first:end', 'second']);
        expect(queue.isClosed, isTrue);
      },
    );
  });
}
