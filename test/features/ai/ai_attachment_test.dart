import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('attachment numeric metadata ignores invalid and non-finite values', () {
    final attachment = AiMessageAttachment.fromJson(<String, Object?>{
      'id': 'att-1',
      'name': 'image.png',
      'storage_path': '/tmp/image.png',
      'kind': 'image',
      'mime_type': 'image/png',
      'size_bytes': double.infinity,
      'width': '-1',
      'height': '1080',
      'pixel_count': 'NaN',
      'compression_ratio': 'Infinity',
    });

    expect(attachment.sizeBytes, 0);
    expect(attachment.width, isNull);
    expect(attachment.height, 1080);
    expect(attachment.pixelCount, isNull);
    expect(attachment.compressionRatio, isNull);
  });

  test('attachment numeric metadata keeps valid persisted values', () {
    final attachment = AiMessageAttachment.fromJson(<String, Object?>{
      'id': 'att-2',
      'name': 'image.png',
      'storage_path': '/tmp/image.png',
      'kind': 'image',
      'mime_type': 'image/png',
      'size_bytes': '2048',
      'width': 1920.8,
      'height': 1080,
      'pixel_count': '2073600',
      'compression_ratio': '0.75',
    });

    expect(attachment.sizeBytes, 2048);
    expect(attachment.width, 1920);
    expect(attachment.height, 1080);
    expect(attachment.pixelCount, 2073600);
    expect(attachment.compressionRatio, 0.75);
  });
}
