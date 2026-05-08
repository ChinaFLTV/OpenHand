import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_dsml_tool_call_parser.dart';

void main() {
  group('extractDsmlToolCalls', () {
    test('decodes non-string parameters marked string=false', () {
      final result = extractDsmlToolCalls('''
<DSML:function_calls>
  <DSML:invoke name="TodoWrite">
    <DSML:parameter name="todos" string="false">[{"id":"1","content":"Audit","status":"in_progress"}]</DSML:parameter>
  </DSML:invoke>
</DSML:function_calls>
''');

      expect(result.toolCalls, hasLength(1));
      final args = jsonDecode(result.toolCalls.single.arguments) as Map;
      expect(args['todos'], isA<List>());
      expect((args['todos'] as List).single, isA<Map>());
      expect(((args['todos'] as List).single as Map)['id'], '1');
    });

    test('keeps default parameters as strings even when content is JSON', () {
      final result = extractDsmlToolCalls('''
<DSML:function_calls>
  <DSML:invoke name="Write">
    <DSML:parameter name="file_path">/tmp/config.json</DSML:parameter>
    <DSML:parameter name="content">{"name":"OpenHand","enabled":true}</DSML:parameter>
  </DSML:invoke>
</DSML:function_calls>
''');

      final args = jsonDecode(result.toolCalls.single.arguments) as Map;
      expect(args['content'], isA<String>());
      expect(args['content'], '{"name":"OpenHand","enabled":true}');
    });

    test('preserves CDATA string payload exactly for content parameters', () {
      final result = extractDsmlToolCalls('''
<DSML:function_calls>
  <DSML:invoke name="Write">
    <DSML:parameter name="content"><![CDATA[
line 1
  line 2
]]]]><![CDATA[> marker
]]></DSML:parameter>
  </DSML:invoke>
</DSML:function_calls>
''');

      final args = jsonDecode(result.toolCalls.single.arguments) as Map;
      expect(args['content'], '\nline 1\n  line 2\n]]> marker\n');
    });

    test(
      'converts JSON envelopes with non-string parameters as typed values',
      () {
        final result = extractDsmlToolCalls(r'''
[TOOL_CALL]
{
  "name": "TodoWrite",
  "input": {
    "todos": [{"id":"1","content":"Audit <DSML:parameter>","status":"pending"}],
    "replace": true,
    "limit": 2
  }
}
[/TOOL_CALL]
''');

        expect(result.toolCalls, hasLength(1));
        final args = jsonDecode(result.toolCalls.single.arguments) as Map;
        expect(args['todos'], isA<List>());
        expect((args['todos'] as List).single, isA<Map>());
        expect(
          ((args['todos'] as List).single as Map)['content'],
          'Audit <DSML:parameter>',
        );
        expect(args['replace'], isTrue);
        expect(args['limit'], 2);
      },
    );
  });
}
