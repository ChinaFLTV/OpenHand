import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/bounded_animation.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_session_config.dart';
import 'web_reverse_session_controller.dart';

const EdgeInsets kWebReverseStatusBarPadding = EdgeInsets.fromLTRB(
  16,
  8,
  16,
  8,
);

const OpenHandAnimationTransitionProfile kWebReverseDialogMotionProfile =
    OpenHandAnimationTransitionProfile(
      fadeScaleBegin: 0.925,
      expandScaleBegin: 0.86,
      rotateScaleBegin: 0.88,
      elasticScaleBegin: 0.90,
      springScaleBegin: 0.90,
      slideUpOffset: Offset(0, 0.16),
      slideDownOffset: Offset(0, -0.14),
      slideLeftOffset: Offset(-0.18, 0),
      slideRightOffset: Offset(0.18, 0),
    );

/// 使用 Web 逆向模块统一的动效参数显示工具弹窗。
///
/// 路由仍通过 [showAnimatedDialog] 读取全局弹窗设置；这里只统一模块内的
/// 过渡几何参数。
const OpenHandProfiledDialogPresenter webReverseToolDialogs =
    OpenHandProfiledDialogPresenter(kWebReverseDialogMotionProfile);

Future<void> confirmWebReverseDiscardChanges({
  required BuildContext context,
  required FutureOr<void> Function() onConfirmed,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: l10n?.webReverseHooksDiscardTitle ?? 'Discard unsaved changes?',
    cancelLabel: l10n?.webReverseHooksKeepEditing ?? 'Keep editing',
    confirmLabel: l10n?.webReverseHooksDiscardConfirm ?? 'Discard',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await onConfirmed();
}

String webReverseLoginModeLabel(
  BuildContext context,
  WebReverseLoginMode mode,
) {
  return switch (mode) {
    WebReverseLoginMode.none => openHandLocalizedText(
      context,
      zh: '无需登录',
      zhHant: '無需登入',
      en: 'None',
      fr: 'Aucune',
      de: 'Keine',
      ja: '不要',
    ),
    WebReverseLoginMode.manual => openHandLocalizedText(
      context,
      zh: '手动登录',
      zhHant: '手動登入',
      en: 'Manual',
      fr: 'Manuelle',
      de: 'Manuell',
      ja: '手動',
    ),
    WebReverseLoginMode.storageState => openHandLocalizedText(
      context,
      zh: '已有状态',
      zhHant: '既有狀態',
      en: 'Storage state',
      fr: 'État stocké',
      de: 'Gespeicherter Status',
      ja: '保存済み状態',
    ),
  };
}

Future<void> removeWebReverseNewDocumentScriptBestEffort({
  required WebReverseSessionController controller,
  required String identifier,
}) async {
  try {
    await controller.sendRawCdp(
      method: 'Page.removeScriptToEvaluateOnNewDocument',
      paramsJson: jsonEncode(<String, Object?>{'identifier': identifier}),
      timeout: const Duration(seconds: 3),
    );
  } catch (error, stack) {
    silentLog('web_reverse_dialog', '移除页面预加载脚本', error, stack);
  }
}

Widget buildWebReverseStatusBar(
  BuildContext context, {
  required String status,
  EdgeInsetsGeometry padding = kWebReverseStatusBarPadding,
}) {
  final text = status.trim();
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final duration = openHandMotionDurationMs(context, 180);
  final child = text.isEmpty
      ? const SizedBox.shrink(key: ValueKey<String>('empty'))
      : Container(
          key: ValueKey<String>(text),
          width: double.infinity,
          color: colorScheme.surfaceContainerHigh,
          padding: padding,
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        );
  return AnimatedSwitcher(
    duration: duration,
    reverseDuration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (currentChild, previousChildren) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      );
    },
    transitionBuilder: (child, animation) {
      final curved = openHandBoundedCurveAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SizeTransition(
          sizeFactor: curved,
          axisAlignment: -1,
          child: child,
        ),
      );
    },
    child: child,
  );
}

Widget buildWebReverseStatusCard(BuildContext context, String status) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colorScheme.outlineVariant),
    ),
    child: Text(
      status,
      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
    ),
  );
}

class WebReverseSelectableListTile extends StatelessWidget {
  const WebReverseSelectableListTile({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(10, 6, 4, 6),
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 重置 profile 后的统一冷却状态（避免误连击把刚建好的空 profile 又删掉）。
///
/// 设置向导与仪表盘诊断横幅共用；使用方需在 [State.dispose] 中调用
/// [cancelProfileResetCooldown]。
mixin WebReverseProfileResetCooldown<T extends StatefulWidget> on State<T> {
  static const int _kCooldownSeconds = 60;

  Timer? _cooldownTimer;
  int _cooldownLeftSec = 0;

  bool get onProfileResetCooldown => _cooldownLeftSec > 0;

  int get profileResetCooldownLeftSec => _cooldownLeftSec;

  void startProfileResetCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeftSec = _kCooldownSeconds);
    _cooldownTimer = startSafePeriodicTimer(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldownLeftSec--);
      if (_cooldownLeftSec <= 0) {
        t.cancel();
      }
    });
  }

  void cancelProfileResetCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }
}
