/// 在字符预算内渲染「条目列表 + 省略计数标记」的通用算法。
///
/// Prompt 装配里反复出现同一个形状：把若干条目逐行渲染进有限的字符预算，
/// 放不下的用一行 `[xxx_omitted: N entries]` 概括；而这行标记本身也要占
/// 预算，所以必须一边回退已渲染的行、一边重算省略数，直到标记也放得下。
library;

import 'argument_guards.dart';
import 'text_clip.dart';

/// [renderLinesWithinBudget] 的结果。
///
/// [includedItemCount] 只统计真正渲染出来的条目，不含省略标记那一行——
/// 调用方据此得知「前 N 条被采用」，可以用来回填引用 id 等旁路信息。
typedef BoundedLineRender = ({String text, int includedItemCount});

/// 逐条渲染 [items]，在 [maxCharacters] 预算内尽可能多放，放不下的用
/// [omissionMarkerBuilder] 生成的单行标记概括。
///
/// - [maxItems] 为候选条数上限，先于预算生效。
/// - [lineBuilder] 负责把单个条目渲染成一行（不含换行符）。
/// - 行与行之间按 `\n` 连接，预算计算已计入分隔符。
/// - 若连一行都放不下，省略标记也会在预算内安全裁剪。
BoundedLineRender renderLinesWithinBudget<T>({
  required List<T> items,
  required int maxItems,
  required int maxCharacters,
  required String Function(T item) lineBuilder,
  required String Function(int omitted) omissionMarkerBuilder,
}) {
  requireNonNegativeInt(maxItems, 'maxItems');
  requireNonNegativeInt(maxCharacters, 'maxCharacters');
  final lines = <String>[];
  var renderedCharacters = 0;
  final candidateCount = items.length < maxItems ? items.length : maxItems;
  for (var index = 0; index < candidateCount; index++) {
    final line = lineBuilder(items[index]);
    final separatorCharacters = lines.isEmpty ? 0 : 1;
    if (renderedCharacters + separatorCharacters + line.length >
        maxCharacters) {
      break;
    }
    lines.add(line);
    renderedCharacters += separatorCharacters + line.length;
  }

  var includedItemCount = lines.length;
  while (true) {
    final omitted = items.length - includedItemCount;
    if (omitted <= 0) break;
    final marker = omissionMarkerBuilder(omitted);
    final separatorCharacters = lines.isEmpty ? 0 : 1;
    if (renderedCharacters + separatorCharacters + marker.length <=
        maxCharacters) {
      lines.add(marker);
      break;
    }
    if (lines.isEmpty) {
      return (
        text: clipTextByCodeUnits(marker, maxCharacters, suffix: ''),
        includedItemCount: 0,
      );
    }
    final removed = lines.removeLast();
    includedItemCount -= 1;
    renderedCharacters -= removed.length + (lines.isEmpty ? 0 : 1);
  }

  return (text: lines.join('\n'), includedItemCount: includedItemCount);
}
