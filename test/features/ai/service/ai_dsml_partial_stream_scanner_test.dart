import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_dsml_partial_stream_scanner.dart';
import 'package:openhand/features/ai/service/ai_dsml_tool_call_parser.dart';

void main() {
  group('scanPartialDsmlInvokes', () {
    test('decodes typed parameters and unquoted attributes like extractor', () {
      final partials = scanPartialDsmlInvokes('''
<DSML:function_calls>
  <DSML:invoke name=TodoWrite>
    <DSML:parameter name=todos string=false>[{"id":"1","content":"Audit"}]</DSML:parameter>
    <DSML:parameter name=note><![CDATA[
keep whitespace
]]></DSML:parameter>
''');

      expect(partials, hasLength(1));
      expect(partials.single.name, 'TodoWrite');
      expect(partials.single.isComplete, isFalse);
      final args = jsonDecode(partials.single.argumentsJson) as Map;
      expect(args['todos'], isA<List>());
      expect((args['todos'] as List).single, isA<Map>());
      expect(args['note'], '\nkeep whitespace\n');
    });

    test('detects bracket JSON envelopes during streaming preview', () {
      final partials = scanPartialDsmlInvokes(r'''
[TOOL_CALL]
{"name":"TodoWrite","input":{"todos":[{"id":"1","status":"pending"}],"replace":true}}
[/TOOL_CALL]
''');

      expect(partials, hasLength(1));
      expect(partials.single.id, 'dsml-tool-call-1');
      expect(partials.single.isComplete, isTrue);
      final args = jsonDecode(partials.single.argumentsJson) as Map;
      expect(args['todos'], isA<List>());
      expect(args['replace'], isTrue);
    });

    test('lower-case DSML tags produce matching preview and final calls', () {
      const text = '''
<dsml:function_calls>
  <dsml:invoke name="Write">
    <dsml:parameter name="content"><![CDATA[
hello
]]></dsml:parameter>
  </dsml:invoke>
</dsml:function_calls>
''';

      final partials = scanPartialDsmlInvokes(text);
      final finalCalls = extractDsmlToolCalls(text).toolCalls;

      expect(partials, hasLength(1));
      expect(finalCalls, hasLength(1));
      expect(partials.single.id, finalCalls.single.id);
      expect(partials.single.name, finalCalls.single.name);
      expect(partials.single.argumentsJson, finalCalls.single.arguments);
    });
  });
}
