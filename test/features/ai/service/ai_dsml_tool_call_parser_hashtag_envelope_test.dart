import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_dsml_tool_call_parser.dart';

void main() {
  group('extractDsmlToolCalls — ##TOOL_CALL## envelope', () {
    test('converts a well-formed envelope with `name`+`input` shape', () {
      const input = '我将创建文件。\n'
          '##TOOL_CALL##\n'
          '{"name": "Write", "input": {"file_path": "/tmp/a.txt", "content": "hi"}}\n'
          '##END_CALL##\n'
          '完成。';
      final result = extractDsmlToolCalls(input);
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'Write');
      final args = jsonDecode(result.toolCalls.single.arguments) as Map;
      expect(args['file_path'], '/tmp/a.txt');
      expect(args['content'], 'hi');
      expect(result.sanitizedText, isNot(contains('##TOOL_CALL##')));
      expect(result.sanitizedText, isNot(contains('##END_CALL##')));
      expect(result.sanitizedText, contains('我将创建文件。'));
      expect(result.sanitizedText, contains('完成。'));
    });

    test('accepts `tool_name`+`parameters` and `arguments` aliases', () {
      const input1 =
          '##TOOL_CALL##{"tool_name":"Bash","parameters":{"command":"ls"}}##END_CALL##';
      const input2 =
          '##TOOL_CALL##{"name":"Read","arguments":{"file_path":"/x"}}##END_CALL##';
      final r1 = extractDsmlToolCalls(input1);
      final r2 = extractDsmlToolCalls(input2);
      expect(r1.toolCalls.single.name, 'Bash');
      expect(jsonDecode(r1.toolCalls.single.arguments), {'command': 'ls'});
      expect(r2.toolCalls.single.name, 'Read');
      expect(jsonDecode(r2.toolCalls.single.arguments), {'file_path': '/x'});
    });

    test('handles multiple envelopes in a single response', () {
      const input =
          '##TOOL_CALL##{"name":"A","input":{"k":1}}##END_CALL##\n中间文本\n'
          '##TOOL_CALL##{"name":"B","input":{"k":"two"}}##END_CALL##';
      final result = extractDsmlToolCalls(input);
      expect(result.toolCalls.map((c) => c.name).toList(), ['A', 'B']);
      expect(result.sanitizedText, contains('中间文本'));
      expect(result.sanitizedText, isNot(contains('##')));
    });

    test('drops malformed JSON envelope without leaking it', () {
      const input = '前文 ##TOOL_CALL##{not json##END_CALL## 后文';
      final result = extractDsmlToolCalls(input);
      expect(result.toolCalls, isEmpty);
      expect(result.sanitizedText, isNot(contains('##TOOL_CALL##')));
      expect(result.sanitizedText, isNot(contains('not json')));
      expect(result.sanitizedText, contains('前文'));
      expect(result.sanitizedText, contains('后文'));
    });

    test('strips dangling opener with no closing marker', () {
      const input =
          '部分回答\n##TOOL_CALL##\n{"name":"Write","input":{"file_path":"/x","content":"...';
      final result = extractDsmlToolCalls(input);
      expect(result.toolCalls, isEmpty);
      expect(result.sanitizedText, isNot(contains('##TOOL_CALL##')));
      expect(result.sanitizedText, isNot(contains('"file_path"')));
      expect(result.sanitizedText.trim(), '部分回答');
      expect(result.hasTrailingIncompleteMarkup, isTrue);
    });

    test('passes through plain text untouched (no `##` substring)', () {
      const input = '普通回复。完全没有工具调用标记。';
      final result = extractDsmlToolCalls(input);
      expect(result.toolCalls, isEmpty);
      expect(result.sanitizedText, input);
      expect(result.hasTrailingIncompleteMarkup, isFalse);
    });

    test('sanitizeVisibleDsmlContent strips envelopes too', () {
      const input =
          '前 ##TOOL_CALL##{"name":"X","input":{}}##END_CALL## 后';
      final stripped = sanitizeVisibleDsmlContent(input);
      expect(stripped, isNot(contains('##')));
      expect(stripped, contains('前'));
      expect(stripped, contains('后'));
    });
  });
}
