import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/widgets/html_selection_bridge_clipboard.dart';

void main() {
  group('HtmlSelectionBridgeClipboard', () {
    tearDown(HtmlSelectionBridgeClipboard.clear);

    test('clears stale selection when updated with empty text', () {
      HtmlSelectionBridgeClipboard.update('hello');
      expect(HtmlSelectionBridgeClipboard.hasSelection, isTrue);

      HtmlSelectionBridgeClipboard.update('   ');

      expect(HtmlSelectionBridgeClipboard.hasSelection, isFalse);
    });

    test('normalizes nbsp and trims text', () {
      HtmlSelectionBridgeClipboard.update('  foo bar  ');
      expect(HtmlSelectionBridgeClipboard.selectedTextForTest, 'foo bar');
    });
  });
}
