import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/net/http_response_utils.dart';
import 'package:openhand/shared/net/network_limits.dart';
import 'package:openhand/shared/util/byte_size_format.dart';

void main() {
  group('受限字节流', () {
    test('流式写入接受大于内存缓冲上限的配置', () async {
      final chunks = <List<int>>[
        <int>[1, 2],
        <int>[3, 4, 5],
      ];
      final writtenChunks = <List<int>>[];

      final written = await writeBoundedByteStream(
        Stream<List<int>>.fromIterable(chunks),
        writeChunk: (chunk) async => writtenChunks.add(chunk),
        maxBytes: 2 * kBytesPerGiB,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 2),
      );

      expect(written, 5);
      expect(writtenChunks, chunks);
    });

    test('内存读取仍拒绝超过缓冲安全上限的配置', () {
      expect(
        () => readBoundedByteStream(
          const Stream<List<int>>.empty(),
          maxBytes: kOpenHandMaxNetworkPayloadBytes + 1,
          idleTimeout: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
    });

    test('流式传输拒绝超过流式安全上限的配置', () {
      expect(
        () => limitByteStream(
          const Stream<List<int>>.empty(),
          maxBytes: kOpenHandMaxNetworkStreamBytes + 1,
        ),
        throwsArgumentError,
      );
    });

    test('流式累计字节超过调用方上限时终止', () async {
      final stream = limitByteStream(
        Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ]),
        maxBytes: 3,
      );

      await expectLater(
        stream.toList(),
        throwsA(
          isA<ByteStreamSizeLimitException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            3,
          ),
        ),
      );
    });

    test('前缀读取允许使用完整内存缓冲上限', () async {
      final result = await readBoundedByteStreamPrefix(
        Stream<List<int>>.value(<int>[1, 2, 3]),
        maxBytes: kOpenHandMaxNetworkPayloadBytes,
        idleTimeout: const Duration(seconds: 1),
      );

      expect(result.bytes, <int>[1, 2, 3]);
      expect(result.truncated, isFalse);
    });
  });
}
