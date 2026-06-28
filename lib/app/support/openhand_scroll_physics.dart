import 'package:flutter/widgets.dart';

/// 线程会话窗口使用的稳定滚动控制器。
/// 保持 Flutter 原生 [ScrollPosition] 行为，滚动活动分类与自动贴底保护
/// 统一在 Home transcript 的 ScrollNotification 状态机中处理。
class OpenHandStableScrollController extends ScrollController {
  OpenHandStableScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });
}

const ClampingScrollPhysics kOpenHandClampingPhysics = ClampingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);
