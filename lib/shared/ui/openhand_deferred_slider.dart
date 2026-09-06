import 'package:flutter/material.dart';

/// 拖动时仅更新本地预览，交互结束后再提交最终值。
class OpenHandDeferredSlider extends StatefulWidget {
  const OpenHandDeferredSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.divisions,
    this.labelBuilder,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onCommit;
  final String Function(double value)? labelBuilder;

  @override
  State<OpenHandDeferredSlider> createState() => _OpenHandDeferredSliderState();
}

class _OpenHandDeferredSliderState extends State<OpenHandDeferredSlider> {
  double? _draftValue;

  double get _lower => widget.min <= widget.max ? widget.min : widget.max;

  double get _upper => widget.min <= widget.max ? widget.max : widget.min;

  double _normalize(double value) {
    final finiteValue = value.isFinite ? value : _lower;
    return finiteValue.clamp(_lower, _upper);
  }

  double get _effectiveValue => _normalize(_draftValue ?? widget.value);

  @override
  void didUpdateWidget(covariant OpenHandDeferredSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.divisions != widget.divisions) {
      _draftValue = null;
    }
  }

  void _preview(double value) {
    setState(() => _draftValue = _normalize(value));
  }

  void _commit(double value) {
    final next = _normalize(value);
    if (next == _normalize(widget.value)) {
      setState(() => _draftValue = null);
      return;
    }
    setState(() => _draftValue = next);
    widget.onCommit?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final value = _effectiveValue;
    return Slider(
      value: value,
      min: _lower,
      max: _upper,
      divisions: widget.divisions != null && widget.divisions! > 0
          ? widget.divisions
          : null,
      label: widget.labelBuilder?.call(value),
      onChanged: widget.onCommit == null ? null : _preview,
      onChangeEnd: widget.onCommit == null ? null : _commit,
    );
  }
}
