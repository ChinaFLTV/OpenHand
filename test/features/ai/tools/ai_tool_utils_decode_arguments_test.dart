import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';

void main() {
  group('AiToolUtils.decodeArguments', () {
    test('keeps JSON-looking string values as strings for string schema', () {
      final args = AiToolUtils.decodeArguments(
        jsonEncode(<String, Object?>{
          'file_path': '/tmp/config.json',
          'content': '{"name":"OpenHand","enabled":true}',
        }),
        parameters: _writeSchema,
      );

      expect(args['content'], isA<String>());
      expect(args['content'], '{"name":"OpenHand","enabled":true}');
    });

    test('decodes JSON-shaped strings for array schema values', () {
      final args = AiToolUtils.decodeArguments(
        jsonEncode(<String, Object?>{
          'todos': '[{"id":"1","content":"Audit","status":"in_progress"}]',
        }),
        parameters: _todoWriteSchema,
      );

      final todos = args['todos'];
      expect(todos, isA<List>());
      expect((todos as List).single, isA<Map>());
      expect((todos.single as Map)['content'], 'Audit');
    });

    test('unwraps same-key object wrappers using the target schema', () {
      final args = AiToolUtils.decodeArguments(
        jsonEncode(<String, Object?>{
          'todos':
              '{"todos":[{"id":"1","content":"Audit","status":"pending"}]}',
        }),
        parameters: _todoWriteSchema,
      );

      final todos = args['todos'];
      expect(todos, isA<List>());
      expect((todos as List).single, isA<Map>());
      expect((todos.single as Map)['status'], 'pending');
    });
  });
}

const Map<String, Object?> _writeSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'file_path': <String, Object?>{'type': 'string'},
    'content': <String, Object?>{'type': 'string'},
  },
  'required': <String>['file_path', 'content'],
};

const Map<String, Object?> _todoWriteSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'todos': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'string'},
          'content': <String, Object?>{'type': 'string'},
          'status': <String, Object?>{'type': 'string'},
        },
      },
    },
  },
  'required': <String>['todos'],
};
