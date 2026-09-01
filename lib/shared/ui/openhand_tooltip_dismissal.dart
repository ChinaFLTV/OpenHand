import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/support/silent_log.dart';

const String _kTooltipDismissLogTag = 'tooltip_dismissal';

bool _tooltipDismissScheduled = false;

/// 安全关闭 Material 工具提示，避免在布局阶段修改浮层。
void dismissOpenHandTooltipsSafely({
  String debugLabel = 'OpenHand.dismissTooltips',
}) {
  final scheduler = SchedulerBinding.instance;
  if (_canDismissTooltipsImmediately(scheduler.schedulerPhase)) {
    _dismissOpenHandTooltips();
    return;
  }
  if (_tooltipDismissScheduled) {
    return;
  }
  _tooltipDismissScheduled = true;
  scheduler.addPostFrameCallback((_) {
    _tooltipDismissScheduled = false;
    _dismissOpenHandTooltips();
  }, debugLabel: debugLabel);
  scheduler.ensureVisualUpdate();
}

bool _canDismissTooltipsImmediately(SchedulerPhase phase) {
  return phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks;
}

void _dismissOpenHandTooltips() {
  try {
    Tooltip.dismissAllToolTips();
  } catch (error, stack) {
    silentLog(_kTooltipDismissLogTag, '关闭全部工具提示', error, stack);
  }
}
