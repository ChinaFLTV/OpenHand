import 'package:flutter/widgets.dart';

/// 线程会话窗口实验性禁用所有自定义滚动物理与滚动纠偏逻辑。
///
/// 本轮仅保留最基础的 Flutter 原生滚动行为，排除自定义 ScrollPosition /
/// content-dimensions 修正 / 额外物理干预对线程会话窗口的影响。
class OpenHandStableScrollController extends ScrollController {
  OpenHandStableScrollController({
    ValueListenable<bool>? userScrollActivity,
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });
}

const ClampingScrollPhysics kOpenHandClampingPhysics = ClampingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);
