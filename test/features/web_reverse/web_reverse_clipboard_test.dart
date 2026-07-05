import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_clipboard.dart';

void main() {
  group('prepareWebReverseClipboardText', () {
    test('keeps text unchanged when it fits the limit', () {
      final prepared = prepareWebReverseClipboardText(
        'short text',
        maxChars: 20,
      );

      expect(prepared.text, 'short text');
      expect(prepared.clipped, isFalse);
    });

    test('clips long text without exceeding the limit', () {
      final prepared = prepareWebReverseClipboardText(
        'abcdefghijklmnopqrstuvwxyz' * 4,
        maxChars: 80,
      );

      expect(prepared.clipped, isTrue);
      expect(prepared.text.length, lessThanOrEqualTo(80));
      expect(prepared.text, contains('OpenHand clipped clipboard text'));
    });

    test('handles tiny and invalid limits without overflowing', () {
      final tiny = prepareWebReverseClipboardText('abcdef', maxChars: 4);
      final zero = prepareWebReverseClipboardText('abcdef', maxChars: 0);
      final negative = prepareWebReverseClipboardText('abcdef', maxChars: -5);

      expect(tiny.clipped, isTrue);
      expect(tiny.text.length, lessThanOrEqualTo(4));
      expect(zero, (text: '', clipped: true));
      expect(negative, (text: '', clipped: true));
    });
  });
}
