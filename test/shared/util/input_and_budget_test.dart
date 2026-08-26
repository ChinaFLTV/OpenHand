import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/bounded_line_budget.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('输入文本归一化', () {
    test('按键读取时跳过空值和字面量 null', () {
      final value = firstNonBlankTextForKeys(
        <String, Object?>{'empty': '  ', 'legacy': 'null', 'count': 12},
        const <String>['empty', 'legacy', 'count'],
      );

      expect(value, '12');
    });

    test('字面量 null 的兼容开关不改变默认语义', () {
      expect(optionalStringFromValue('null'), 'null');
      expect(optionalStringFromValue('null', ignoreLiteralNull: true), isNull);
    });
  });

  group('有界行渲染', () {
    test('非法预算直接拒绝', () {
      expect(
        () => renderLinesWithinBudget<int>(
          items: const <int>[1],
          maxItems: -1,
          maxCharacters: 10,
          lineBuilder: (item) => '$item',
          omissionMarkerBuilder: (count) => '省略 $count 项',
        ),
        throwsArgumentError,
      );
    });

    test('保留预算内条目并生成省略标记', () {
      final result = renderLinesWithinBudget<String>(
        items: const <String>['甲', '乙', '丙'],
        maxItems: 2,
        maxCharacters: 9,
        lineBuilder: (item) => item,
        omissionMarkerBuilder: (count) => '省略$count项',
      );

      expect(result.includedItemCount, 2);
      expect(result.text, '甲\n乙\n省略1项');
    });
  });
}
