import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 给整数滑杆补一个无障碍键盘微调入口：
///   - 焦点在滑杆上时按 ←/↓ 触发 -1，→/↑ 触发 +1
///   - 每次微调发一次轻微 [HapticFeedback.selectionClick]
///   - 鼠标拖动仍走 `Slider.onChanged`，行为不变
///   - 不消费 Tab 等其它按键（返回 [KeyEventResult.ignored]，焦点链可正常前进）
///
/// 用法：
/// ```dart
/// KeyTweakableSlider(
///   value: cap,
///   min: 1, max: 64,
///   onChanged: (next) async {
///     final saved = await controller.updateX(next);
///     if (!saved) showOpenHandErrorSnack(context, '...');
///   },
///   buildSlider: (context, current) => Slider(
///     value: current.toDouble(),
///     min: 1, max: 64,
///     onChanged: (v) => controller.updateX(v.round()),
///   ),
/// )
/// ```
class KeyTweakableSlider extends StatefulWidget {
  const KeyTweakableSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.buildSlider,
    this.debugLabel,
  });

  final int value;
  final int min;
  final int max;

  /// fire-and-forget 写入回调；失败提示由调用方在内部处理。
  final Future<void> Function(int newValue) onChanged;

  /// 构造内层 [Slider]。把当前 value 透传回去即可，外层只关心键盘 + Focus 装饰。
  final Widget Function(BuildContext context, int value) buildSlider;

  /// 可选的 [FocusNode.debugLabel]，方便排查焦点链。
  final String? debugLabel;

  @override
  State<KeyTweakableSlider> createState() => _KeyTweakableSliderState();
}

class _KeyTweakableSliderState extends State<KeyTweakableSlider> {
  late final FocusNode _focus = FocusNode(
    debugLabel: widget.debugLabel ?? 'KeyTweakableSlider',
  );

  ({int lower, int upper}) get _bounds {
    return widget.min <= widget.max
        ? (lower: widget.min, upper: widget.max)
        : (lower: widget.max, upper: widget.min);
  }

  int get _safeValue {
    final (:lower, :upper) = _bounds;
    return widget.value.clamp(lower, upper);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    int delta;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      delta = -1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      delta = 1;
    } else {
      return KeyEventResult.ignored;
    }
    final (:lower, :upper) = _bounds;
    final current = _safeValue;
    final next = (current + delta).clamp(lower, upper);
    if (next == current) return KeyEventResult.handled;
    HapticFeedback.selectionClick();
    widget.onChanged(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _handleKey,
      child: widget.buildSlider(context, _safeValue),
    );
  }
}
