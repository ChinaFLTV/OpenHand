/// 在字符预算内渲染「条目集合 + 省略计数标记」的通用算法。
///
/// Prompt 装配里反复出现同一个形状：把若干条目渲染进有限的字符预算，
/// 放不下的用 `[xxx_omitted: N entries]` 概括；而标记本身也要占
/// 预算，所以必须一边回退已渲染的行、一边重算省略数，直到标记也放得下。
library;

import 'argument_guards.dart';
import 'text_clip.dart';

/// [renderItemsWithinBudget] 的结果。
///
/// [includedItemCount] 只统计真正渲染出来的条目，不含省略标记那一行——
/// 调用方据此得知「前 N 条被采用」，可以用来回填引用 id 等旁路信息。
typedef BoundedItemRender = ({String text, int includedItemCount});

/// 依次渲染 [items]，在 [maxCharacters] 预算内尽可能多放，放不下的用
/// [omissionMarkerBuilder] 生成的单行标记概括。
///
/// - [maxItems] 为候选条数上限，先于预算生效。
/// - [itemBuilder] 负责渲染单个条目，不应包含尾部分隔符。
/// - 条目之间按 [separator] 连接，预算计算已包含分隔符。
/// - 若连一项都放不下，省略标记也会在预算内安全裁剪。
BoundedItemRender renderItemsWithinBudget<T>({
  required List<T> items,
  required int maxItems,
  required int maxCharacters,
  required String Function(T item) itemBuilder,
  required String Function(int omitted) omissionMarkerBuilder,
  String separator = '\n',
}) {
  requireNonNegativeInt(maxItems, 'maxItems');
  requireNonNegativeInt(maxCharacters, 'maxCharacters');
  final renderedItems = <String>[];
  var renderedCharacters = 0;
  final candidateCount = items.length < maxItems ? items.length : maxItems;
  for (var index = 0; index < candidateCount; index++) {
    final item = itemBuilder(items[index]);
    final separatorCharacters = renderedItems.isEmpty ? 0 : separator.length;
    if (renderedCharacters + separatorCharacters + item.length >
        maxCharacters) {
      break;
    }
    renderedItems.add(item);
    renderedCharacters += separatorCharacters + item.length;
  }

  var includedItemCount = renderedItems.length;
  while (true) {
    final omitted = items.length - includedItemCount;
    if (omitted <= 0) break;
    final marker = omissionMarkerBuilder(omitted);
    final separatorCharacters = renderedItems.isEmpty ? 0 : separator.length;
    if (renderedCharacters + separatorCharacters + marker.length <=
        maxCharacters) {
      renderedItems.add(marker);
      break;
    }
    if (renderedItems.isEmpty) {
      return (
        text: clipTextByCodeUnits(marker, maxCharacters, suffix: ''),
        includedItemCount: 0,
      );
    }
    final removed = renderedItems.removeLast();
    includedItemCount -= 1;
    renderedCharacters -=
        removed.length + (renderedItems.isEmpty ? 0 : separator.length);
  }

  return (
    text: renderedItems.join(separator),
    includedItemCount: includedItemCount,
  );
}
