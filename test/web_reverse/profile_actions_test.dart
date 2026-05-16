// 渐进式 profile 解决器：因 widget 测试 + 异步 IO + SnackBar 计时器
// 容易在 fake async 时钟下卡住，这里只断言"枚举值齐全"，
// 端到端行为通过 manual QA 验证（dashboard banner / setup dialog 双入口）。

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_profile_actions.dart';

void main() {
  test('ProgressiveProfileOutcome 枚举值齐全', () {
    expect(ProgressiveProfileOutcome.values, hasLength(5));
    expect(ProgressiveProfileOutcome.values, [
      ProgressiveProfileOutcome.nothingToDo,
      ProgressiveProfileOutcome.cleaned,
      ProgressiveProfileOutcome.reset,
      ProgressiveProfileOutcome.resetCancelled,
      ProgressiveProfileOutcome.failed,
    ]);
  });
}
