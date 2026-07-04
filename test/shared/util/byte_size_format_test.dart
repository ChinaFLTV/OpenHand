import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/byte_size_format.dart';

void main() {
  group('formatByteSize', () {
    test('formats non-positive and byte values directly', () {
      expect(formatByteSize(-1), '0 B');
      expect(formatByteSize(0), '0 B');
      expect(formatByteSize(42), '42 B');
    });

    test('trims unnecessary fractional zeros', () {
      expect(formatByteSize(kBytesPerKiB), '1 KB');
      expect(formatByteSize(kBytesPerMiB), '1 MB');
      expect(formatByteSize(10 * kBytesPerMiB), '10 MB');
      expect(formatByteSize(100 * kBytesPerMiB), '100 MB');
    });

    test('keeps meaningful fractional precision', () {
      expect(formatByteSize(1536), '1.5 KB');
      expect(formatByteSize(15 * kBytesPerMiB + kBytesPerMiB ~/ 2), '15.5 MB');
      expect(formatByteSize(kBytesPerMiB + kBytesPerMiB ~/ 4), '1.25 MB');
    });
  });

  group('megabytesTextToBytes', () {
    test('clamps parsed megabytes into configured bounds', () {
      expect(
        megabytesTextToBytes(
          '999',
          fallbackBytes: kBytesPerMiB,
          minBytes: kBytesPerMiB,
          maxBytes: 4 * kBytesPerMiB,
        ),
        4 * kBytesPerMiB,
      );
      expect(
        megabytesTextToBytes(
          '-1',
          fallbackBytes: kBytesPerMiB,
          minBytes: kBytesPerMiB,
          maxBytes: 4 * kBytesPerMiB,
        ),
        kBytesPerMiB,
      );
    });
  });
}
