import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';

void main() {
  test('tool integer parsing accepts finite integral values only', () {
    expect(AiToolUtils.readInt(12), 12);
    expect(AiToolUtils.readInt(12.0), 12);
    expect(AiToolUtils.readInt('12'), 12);
    expect(AiToolUtils.readInt('12.0'), 12);
    expect(AiToolUtils.readInt(12.5), isNull);
    expect(AiToolUtils.readInt('12.5'), isNull);
    expect(AiToolUtils.readInt(double.infinity), isNull);
    expect(AiToolUtils.readInt(double.nan), isNull);
    expect(AiToolUtils.readInt('bad'), isNull);
  });

  test('tool integer parsing clamps valid values and safe fallback', () {
    expect(AiToolUtils.readClampedInt('12', fallback: 6, min: 1, max: 20), 12);
    expect(AiToolUtils.readClampedInt(99, fallback: 6, min: 1, max: 20), 20);
    expect(AiToolUtils.readClampedInt(-5, fallback: 6, min: 1, max: 20), 1);
    expect(
      AiToolUtils.readClampedInt('bad', fallback: 99, min: 1, max: 20),
      20,
    );
    expect(AiToolUtils.readClampedInt('12', fallback: 6, min: 20, max: 1), 12);
  });

  test('tool boolean parsing accepts common finite flag forms', () {
    expect(AiToolUtils.readBool(true), isTrue);
    expect(AiToolUtils.readBool(false), isFalse);
    expect(AiToolUtils.readBool(1), isTrue);
    expect(AiToolUtils.readBool(0), isFalse);
    expect(AiToolUtils.readBool('1.0'), isTrue);
    expect(AiToolUtils.readBool('yes'), isTrue);
    expect(AiToolUtils.readBool('on'), isTrue);
    expect(AiToolUtils.readBool('enabled'), isTrue);
    expect(AiToolUtils.readBool('no'), isFalse);
    expect(AiToolUtils.readBool('off'), isFalse);
    expect(AiToolUtils.readBool('disabled'), isFalse);
    expect(AiToolUtils.readBool(2), isNull);
    expect(AiToolUtils.readBool(0.5), isNull);
    expect(AiToolUtils.readBool(double.nan), isNull);
    expect(AiToolUtils.readBool('bad'), isNull);
  });

  test('normalizes string list values from arrays and text', () {
    expect(
      AiToolUtils.normalizeStringList(<Object?>[' Example.COM ', '', 'Foo.cn']),
      <String>['example.com', 'foo.cn'],
    );
    expect(AiToolUtils.normalizeStringList(' Example.COM, Foo.cn '), <String>[
      'example.com',
      'foo.cn',
    ]);
    expect(
      AiToolUtils.normalizeStringList('["Example.COM", " Foo.cn "]'),
      <String>['example.com', 'foo.cn'],
    );
  });

  test('decode arguments coerces schema-guided JSON strings and wrappers', () {
    final decoded = AiToolUtils.decodeArguments(
      '{"limit":"12","todos":{"item":[{"content":"ship"}]}}',
      parameters: <String, Object?>{
        'properties': <Object?, Object?>{
          'limit': <Object?, Object?>{'type': 'integer'},
          'todos': <Object?, Object?>{
            'type': 'array',
            'items': <Object?, Object?>{'type': 'object'},
          },
        },
      },
    );

    expect(decoded['limit'], 12);
    final todos = decoded['todos'] as List<Object?>;
    expect(todos, hasLength(1));
    expect(todos.single, isA<Map<String, Object?>>());
    expect((todos.single as Map<String, Object?>)['content'], 'ship');
  });
}
