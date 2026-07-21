import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/reader_file_type.dart';

void main() {
  group('ReaderFileType.isTextLikeExtension', () {
    test('兼容点号、大小写及各功能原有文本扩展名', () {
      for (final extension in <String>[
        '.md',
        'TSX',
        '.env',
        '.swift',
        '.cs',
        '.php',
        '.less',
      ]) {
        expect(
          ReaderFileType.isTextLikeExtension(extension),
          isTrue,
          reason: extension,
        );
      }
    });

    test('拒绝空值、逻辑类型及非文本扩展名', () {
      for (final extension in <String>['', 'code', '.pdf', '.rtf', '.tex']) {
        expect(
          ReaderFileType.isTextLikeExtension(extension),
          isFalse,
          reason: extension,
        );
      }
    });
  });
}
