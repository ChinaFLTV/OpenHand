import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/xml_escape.dart';

void main() {
  group('escapeXmlText', () {
    test('escapes text node control characters', () {
      expect(escapeXmlText('Tom & Jerry <tag>'), 'Tom &amp; Jerry &lt;tag&gt;');
    });

    test('leaves quotes unchanged for text nodes', () {
      expect(
        escapeXmlText('"quoted" and \'single\''),
        '"quoted" and \'single\'',
      );
    });

    test('returns unchanged text when no escaping is needed', () {
      const value = 'OpenHand 中文 text';
      expect(identical(escapeXmlText(value), value), isTrue);
    });
  });

  group('escapeXmlAttribute', () {
    test('escapes text and quote characters for attributes', () {
      expect(
        escapeXmlAttribute('name="A&B" path=\'<root>\''),
        'name=&quot;A&amp;B&quot; path=&apos;&lt;root&gt;&apos;',
      );
    });

    test('preserves non-ASCII content while escaping XML syntax', () {
      expect(
        escapeXmlAttribute('提示 <完成> & "OK"'),
        '提示 &lt;完成&gt; &amp; &quot;OK&quot;',
      );
    });
  });
}
