import 'package:flutter/widgets.dart';

mixin OpenHandHoverState<W extends StatefulWidget> on State<W> {
  bool _openHandHovered = false;
  bool _openHandHoverUpdateScheduled = false;

  bool get openHandHovered => _openHandHovered;

  void setOpenHandHovered(bool value) {
    if (_openHandHovered == value) return;
    _openHandHovered = value;
    if (_openHandHoverUpdateScheduled) return;
    _openHandHoverUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openHandHoverUpdateScheduled = false;
      if (mounted) setState(() {});
    });
  }
}
