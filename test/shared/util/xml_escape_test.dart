import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/xml_escape.dart';

void main() {
  group('XML escaping', () {
    test('escapes text nodes without over-escaping quotes', () {
      expect(
        escapeXmlText('Tom & "Jerry" <tag>'),
        'Tom &amp; "Jerry" &lt;tag&gt;',
      );
    });

    test('escapes attribute values for both quote styles', () {
      expect(
        escapeXmlAttribute('Tom & "Jerry" <tag> \'x\''),
        'Tom &amp; &quot;Jerry&quot; &lt;tag&gt; &apos;x&apos;',
      );
    });
  });
}
