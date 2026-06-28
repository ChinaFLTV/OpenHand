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

  test('attachment metadata accepts JSON object text', () {
    final attachment = AiMessageAttachment.fromJson('''
      {
        "id": " att-3 ",
        "name": " doc.md ",
        "storage_path": " /tmp/doc.md ",
        "kind": "text",
        "mime_type": " text/markdown ",
        "size_bytes": "1024",
        "prompt_text": "  keep text spacing  ",
        "original_source_path": " /source/doc.md "
      }
    ''');

    expect(attachment.id, 'att-3');
    expect(attachment.name, 'doc.md');
    expect(attachment.storagePath, '/tmp/doc.md');
    expect(attachment.kind, AiAttachmentKind.text);
    expect(attachment.mimeType, 'text/markdown');
    expect(attachment.sizeBytes, 1024);
    expect(attachment.promptText, '  keep text spacing  ');
    expect(attachment.originalSourcePath, '/source/doc.md');
  });

  test(
    'attachment list metadata accepts JSON text and filters incomplete rows',
    () {
      final attachments = AiMessageAttachment.listFromMetadata('''
      [
        {
          "id": "att-4",
          "name": "image.png",
          "storage_path": "/tmp/image.png",
          "kind": "image",
          "size_bytes": "2048"
        },
        {
          "id": "missing-storage",
          "name": "broken.txt"
        }
      ]
    ''');

      expect(attachments, hasLength(1));
      expect(attachments.single.id, 'att-4');
      expect(attachments.single.storagePath, '/tmp/image.png');
      expect(attachments.single.sizeBytes, 2048);
    },
  );
}
