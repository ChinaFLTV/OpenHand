import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/reader_file_type.dart';

void main() {
  group('ReaderFileType.normalize', () {
    test('normalizes extensions and display names', () {
      expect(ReaderFileType.normalize('.md'), ReaderFileType.markdown);
      expect(ReaderFileType.normalize(' plain text '), ReaderFileType.text);
      expect(
        ReaderFileType.normalize('tab-separated values'),
        ReaderFileType.tsv,
      );
      expect(ReaderFileType.normalize('Type Script'), ReaderFileType.code);
    });

    test('normalizes common MIME types', () {
      expect(ReaderFileType.normalize('text/plain'), ReaderFileType.text);
      expect(
        ReaderFileType.normalize('text/markdown'),
        ReaderFileType.markdown,
      );
      expect(ReaderFileType.normalize('application/json'), ReaderFileType.json);
      expect(
        ReaderFileType.normalize('application/x-ndjson'),
        ReaderFileType.jsonl,
      );
      expect(
        ReaderFileType.normalize('application/x-yaml'),
        ReaderFileType.yaml,
      );
      expect(ReaderFileType.normalize('image/svg+xml'), ReaderFileType.xml);
      expect(
        ReaderFileType.normalize('text/tab-separated-values'),
        ReaderFileType.tsv,
      );
      expect(ReaderFileType.normalize('application/pdf'), ReaderFileType.pdf);
      expect(
        ReaderFileType.normalize(
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        ReaderFileType.docx,
      );
      expect(
        ReaderFileType.normalize(
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
        ReaderFileType.xlsx,
      );
      expect(
        ReaderFileType.normalize(
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        ),
        ReaderFileType.pptx,
      );
    });

    test('keeps unknown values normalized but unclassified', () {
      expect(ReaderFileType.normalize(' Custom-Type '), 'customtype');
    });
  });

  group('ReaderFileType.normalizeList', () {
    test('deduplicates after alias normalization while preserving order', () {
      expect(
        ReaderFileType.normalizeList(<String>[
          'text/plain',
          '.txt',
          'application/json',
          'json',
          'yaml',
        ]),
        <String>[ReaderFileType.text, ReaderFileType.json, ReaderFileType.yaml],
      );
    });
  });

  group('ReaderFileType classification', () {
    test('detects text-like MIME source types', () {
      expect(ReaderFileType.isTextLikeSource('text/plain'), isTrue);
      expect(ReaderFileType.isTextLikeSource('application/json'), isTrue);
      expect(ReaderFileType.isTextLikeSource('application/pdf'), isFalse);
    });

    test('returns stable MIME types for normalized aliases', () {
      expect(ReaderFileType.mimeType('text/plain'), 'text/plain');
      expect(
        ReaderFileType.mimeType('application/x-ndjson'),
        'application/x-ndjson',
      );
      expect(ReaderFileType.mimeType('image/svg+xml'), 'application/xml');
    });
  });
}
