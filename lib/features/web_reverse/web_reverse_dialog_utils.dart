import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_reveal_switcher.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
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

const EdgeInsets kWebReverseSurfaceCardPadding = EdgeInsets.all(10);
const double kWebReverseSurfaceCardRadius = 10;
const EdgeInsets kWebReverseDialogFooterPadding = EdgeInsets.all(12);

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

/// 「已保存到 <路径>」的统一文案。
///
/// 导出 HAR / Trace / 截图 / CSV 等入口散落在四个 part 文件里，此前各自内联
/// 了一份六语言字面量，改一处文案就得同步改九处。
String webReverseSavedToFileMessage(BuildContext context, String path) {
  return openHandLocalizedText(
    context,
    zh: '已保存到 $path',
    zhHant: '已儲存到 $path',
    en: 'Saved to $path',
    fr: 'Enregistré dans $path',
    de: 'Gespeichert unter $path',
    ja: '$path に保存しました',
  );
}

/// 「保存失败」的统一文案。
String webReverseSaveFailedMessage(BuildContext context) {
  return openHandSaveFailedLabel(context);
}

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
  final child = text.isEmpty
      ? null
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
  return OpenHandVerticalRevealSwitcher(
    duration: kOpenHandDialogValidationRevealDuration,
    child: child,
  );
}

Widget buildWebReverseStatusCard(BuildContext context, String status) {
  return buildWebReverseSurfaceCard(
    context,
    radius: 8,
    child: Text(
      status,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontFamily: kOpenHandMonospaceFontFamily),
    ),
  );
}

/// Web 逆向面板统一的信息卡外观：高对比表面 + 圆角 + 描边。
///
/// 收敛模块内四十余处同形 [BoxDecoration]，主题色令牌改动只需改这一处；
/// [radius] 保留在调用点，因为它承载的是卡片层级而非配色。
BoxDecoration webReverseSurfaceCardDecoration(
  ColorScheme colorScheme, {
  double radius = kWebReverseSurfaceCardRadius,
  Color? color,
}) {
  return BoxDecoration(
    color: color ?? colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: colorScheme.outlineVariant),
  );
}

Widget buildWebReverseSurfaceCard(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = kWebReverseSurfaceCardPadding,
  double radius = kWebReverseSurfaceCardRadius,
  Color? color,
}) {
  return Container(
    padding: padding,
    decoration: webReverseSurfaceCardDecoration(
      Theme.of(context).colorScheme,
      radius: radius,
      color: color,
    ),
    child: child,
  );
}

/// Web 逆向工具弹窗统一的底部操作条：分隔线 + 居中动作按钮组。
///
/// 按钮间距由公共动作栏统一处理，调用方只需给出按钮本身，避免每个弹窗
/// 各自重复摆放 Divider / Padding / Row。
Widget buildWebReverseDialogFooter(
  BuildContext context, {
  required List<Widget> actions,
  Widget? leading,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Divider(height: 1, color: colorScheme.outlineVariant),
      buildOpenHandDialogActionsBar(
        leading: leading,
        actions: actions,
        padding: kWebReverseDialogFooterPadding,
      ),
    ],
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
      borderRadius: kOpenHandBorderRadius8,
      child: InkWell(
        borderRadius: kOpenHandBorderRadius8,
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
