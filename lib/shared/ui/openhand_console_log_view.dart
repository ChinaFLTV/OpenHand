import 'package:flutter/material.dart';

import 'openhand_safe_scrollbar.dart';

class OpenHandConsoleLogView extends StatelessWidget {
  const OpenHandConsoleLogView({
    super.key,
    required this.controller,
    required this.onNotification,
    required this.itemCount,
    required this.itemBuilder,
  });

  final ScrollController controller;
  final NotificationListenerCallback<ScrollNotification> onNotification;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: OpenHandSafeScrollbar(
        controller: controller,
        thumbVisibility: true,
        child: NotificationListener<ScrollNotification>(
          onNotification: onNotification,
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.all(12),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
      ),
    );
  }
}
