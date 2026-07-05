import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_attachment.dart';

void main() {
  group('AiMessageAttachment', () {
    test('fromJson clamps compression ratio into the unit interval', () {
      expect(_attachmentWithCompression(-0.5).compressionRatio, 0);
      expect(_attachmentWithCompression('0.25').compressionRatio, 0.25);
      expect(_attachmentWithCompression(1.5).compressionRatio, 1);
      expect(_attachmentWithCompression('bad').compressionRatio, isNull);
    });

    test('fromJson drops negative dimensions and sizes safely', () {
      final attachment = AiMessageAttachment.fromJson(<String, Object?>{
        'id': 'att-1',
        'name': 'image.png',
        'storage_path': '/tmp/image.png',
        'kind': 'image',
        'size_bytes': -10,
        'width': -100,
        'height': 200,
        'pixel_count': -20000,
      });

      expect(attachment.sizeBytes, 0);
      expect(attachment.width, isNull);
      expect(attachment.height, 200);
      expect(attachment.pixelCount, isNull);
    });
  });
}

AiMessageAttachment _attachmentWithCompression(Object? compressionRatio) {
  return AiMessageAttachment.fromJson(<String, Object?>{
    'id': 'att-1',
    'name': 'image.png',
    'storage_path': '/tmp/image.png',
    'kind': 'image',
    'compression_ratio': compressionRatio,
  });
}
