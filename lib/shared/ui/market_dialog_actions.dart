import 'package:flutter/material.dart';

import 'openhand_dialog_action_button.dart';
import 'openhand_spacing.dart';

/// 三个市场共用底部操作布局，窄窗口只收窄按钮宽度，保持高度一致。
class MarketDialogActions extends StatelessWidget {
  const MarketDialogActions({
    super.key,
    required this.hint,
    required this.closeButton,
    required this.providerButton,
    required this.actionButton,
  });

  final Widget hint, closeButton, providerButton, actionButton;
  static const double _buttonGap = 12;
  static const double _inlineHintBreakpoint = 720;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = ((constraints.maxWidth - 2 * _buttonGap) / 3).clamp(
        0.0,
        kOpenHandDialogActionButtonWidth,
      );
      final buttons = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: width, child: closeButton),
          const SizedBox(width: _buttonGap),
          SizedBox(width: width, child: providerButton),
          const SizedBox(width: _buttonGap),
          SizedBox(width: width, child: actionButton),
        ],
      );
      if (constraints.maxWidth < _inlineHintBreakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hint,
            kOpenHandGap12,
            Align(alignment: Alignment.centerRight, child: buttons),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: hint),
          kOpenHandHGap16,
          buttons,
        ],
      );
    },
  );
}
