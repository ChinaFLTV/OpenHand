import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/chat/ai_sse_data_parser.dart';

void main() {
  group('extractSseDataLines', () {
    test('extracts and trims data lines from an event block', () {
      expect(
        extractSseDataLines('event: message\ndata:  {"ok":true}  \n\n'),
        <String>['{"ok":true}'],
      );
    });

    test(
      'keeps done markers and empty data payloads for callers to decide',
      () {
        expect(extractSseDataLines('data:\ndata: [DONE]'), <String>[
          '',
          '[DONE]',
        ]);
      },
    );

    test('returns an empty list for blank or comment-only blocks', () {
      expect(extractSseDataLines('  \n  '), isEmpty);
      expect(extractSseDataLines(': keep-alive'), isEmpty);
    });
  });
}
