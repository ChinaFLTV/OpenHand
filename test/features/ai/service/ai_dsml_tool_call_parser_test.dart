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
  });
}
