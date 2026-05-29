import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import '../../app/theme/openhand_status_colors.dart';
import 'animated_dialog.dart';

/// 三态语义：success / error / info。`flash` 入口按 kind 派发到对应工厂。
enum OpenHandSnackKind { info, success, error }

/// Lightweight helpers for building consistent, icon-prefixed
/// [SnackBar]s on top of the global [SnackBarThemeData].
///
/// Use whenever a transient outcome notice would benefit from a
/// success/error/info affordance. The plain string-only
/// `OpenHandSnackBar.show(context, messenger, snackBar)` also applies
/// the app-wide presentation animation so legacy and custom snackbars
/// can opt into the same motion language.
class OpenHandSnackBar {
  OpenHandSnackBar._();

  static const DialogAnimationSettings _fallbackMotionSettings =
      DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.springScale,
        exitStyle: DialogAnimationStyle.springScale,
        durationMs: 360,
      );

  static const DialogAnimationSettings _disabledMotionSettings =
      DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.none,
        exitStyle: DialogAnimationStyle.none,
        durationMs: 0,
      );

  static const Duration _maximumDisplayDuration = Duration(seconds: 8);

  static bool _motionDisabled(DialogAnimationSettings settings) {
    return settings.entranceStyle == DialogAnimationStyle.none &&
        settings.exitStyle == DialogAnimationStyle.none;
  }

  static DialogAnimationSettings _resolveMotionSettings(BuildContext context) {
    try {
      return context.read<SettingsController>().dialogAnimationSettings;
    } catch (_) {
      return _fallbackMotionSettings;
    }
  }

  static AnimationStyle _resolveRouteAnimationStyle(
    DialogAnimationSettings settings,
  ) {
    if (_motionDisabled(settings)) return AnimationStyle.noAnimation;
    return AnimationStyle(
      duration: settings.duration,
      reverseDuration: settings.duration,
      curve: settings.curve.curve,
      reverseCurve: settings.curve.reverseCurve,
    );
  }

  static Widget _modernizeLegacyTextContent(
    BuildContext context,
    Widget content,
  ) {
    if (content is! Text) return content;
    final cs = Theme.of(context).colorScheme;
    return _OpenHandSnackBarMessage(
      icon: Icons.info_rounded,
      tint: cs.inversePrimary,
      child: content,
    );
  }

  static Duration _boundedDuration(Duration duration) {
    if (duration > _maximumDisplayDuration) return _maximumDisplayDuration;
    return duration;
  }

  static Widget _withActionsAndDismissControl(
    Widget content,
    SnackBarAction? action,
  ) {
    return _OpenHandSnackBarContent(message: content, action: action);
  }

  static Widget _messageContent({
    required IconData icon,
    required Color tint,
    required Widget child,
  }) {
    return _OpenHandSnackBarMessage(icon: icon, tint: tint, child: child);
  }

  static TextStyle? _foregroundTextStyle(Color? foregroundColor) {
    return foregroundColor == null ? null : TextStyle(color: foregroundColor);
  }

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    ScaffoldMessengerState messenger,
    SnackBar snackBar,
  ) {
    final animationsDisabled =
        MediaQuery.maybeDisableAnimationsOf(context) == true;
    final motionSettings = animationsDisabled
        ? _disabledMotionSettings
        : _resolveMotionSettings(context);
    final wrapped = _ensureMotionWrapped(context, snackBar, motionSettings);
    return messenger.showSnackBar(
      wrapped,
      snackBarAnimationStyle: _resolveRouteAnimationStyle(motionSettings),
    );
  }

  /// Re-emits a [SnackBar] with modern OpenHand content treatment, preserving
  /// caller-supplied timing, action and layout fields. This is the compatibility
  /// gate for older call sites: raw text snackbars get the neutral info affordance,
  /// every snackbar gets the same close control, and all motion follows the app's
  /// dialog animation settings / reduce-motion signal.
  static SnackBar _ensureMotionWrapped(
    BuildContext context,
    SnackBar snackBar,
    DialogAnimationSettings motionSettings,
  ) {
    final content = snackBar.content;
    if (content is _OpenHandSnackBarMotion) return snackBar;
    final modernContent = _modernizeLegacyTextContent(context, content);
    final wrappedContent = _withActionsAndDismissControl(
      modernContent,
      snackBar.action,
    );
    return SnackBar(
      key: snackBar.key,
      content: _OpenHandSnackBarMotion(
        settings: motionSettings,
        child: wrappedContent,
      ),
      duration: _boundedDuration(snackBar.duration),
      persist: false,
      backgroundColor: snackBar.backgroundColor,
      behavior: snackBar.behavior,
      dismissDirection: snackBar.dismissDirection,
      elevation: snackBar.elevation,
      margin: snackBar.margin,
      padding: snackBar.padding,
      width: snackBar.width,
      shape: snackBar.shape,
      showCloseIcon: false,
      onVisible: snackBar.onVisible,
      hitTestBehavior: snackBar.hitTestBehavior,
      clipBehavior: snackBar.clipBehavior,
      actionOverflowThreshold: snackBar.actionOverflowThreshold,
    );
  }

  /// Green-leaning tick variant. Primary use: confirming a save /
  /// commit / restore action when a `HighlightPulse` is not
  /// reachable from the current widget.
  static SnackBar success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
    int? maxLines,
  }) {
    return _build(
      context,
      message,
      icon: Icons.check_circle_rounded,
      tint: OpenHandStatusColors.success,
      duration: duration,
      action: action,
      maxLines: maxLines,
    );
  }

  /// Red-leaning warning. Primary use: surfacing a failure that the
  /// user should notice but that doesn't require a modal.
  static SnackBar error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    int? maxLines,
  }) {
    return _build(
      context,
      message,
      icon: Icons.error_rounded,
      tint: OpenHandStatusColors.error,
      duration: duration,
      action: action,
      maxLines: maxLines,
    );
  }

  /// Neutral info variant — picks the inverse-primary color from
  /// the active theme so it follows light/dark mode correctly.
  static SnackBar info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    int? maxLines,
  }) {
    final cs = Theme.of(context).colorScheme;
    return _build(
      context,
      message,
      icon: Icons.info_rounded,
      tint: cs.inversePrimary,
      duration: duration,
      action: action,
      maxLines: maxLines,
    );
  }

  /// One-shot helper: build + show an info snackbar with the unified
  /// motion / close-affordance treatment. Used as the single replacement
  /// for legacy plain-text call sites so every snackbar in the app travels
  /// through the same presentation pipeline.
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    show(
      context,
      messenger,
      info(context, message, duration: duration, action: action),
    );
  }

  /// Same as [showInfo] but reuses an already-resolved [ScaffoldMessengerState].
  /// Prefer this overload when the call site has cached the messenger before
  /// awaiting an async gap.
  static void showInfoOn(
    BuildContext context,
    ScaffoldMessengerState messenger,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    show(
      context,
      messenger,
      info(context, message, duration: duration, action: action),
    );
  }

  /// One-shot helper: success snackbar.
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    show(
      context,
      messenger,
      success(context, message, duration: duration, action: action),
    );
  }

  static void showSuccessOn(
    BuildContext context,
    ScaffoldMessengerState messenger,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    show(
      context,
      messenger,
      success(context, message, duration: duration, action: action),
    );
  }

  /// One-shot helper: error snackbar.
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    show(
      context,
      messenger,
      error(context, message, duration: duration, action: action),
    );
  }

  static void showErrorOn(
    BuildContext context,
    ScaffoldMessengerState messenger,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    show(
      context,
      messenger,
      error(context, message, duration: duration, action: action),
    );
  }

  /// 按 [kind] 派发到 success/error/info 工厂并立即（或下一帧）展示。
  /// 当调用方处于 `setState` 同步路径（例如 controller 通知期间）时，
  /// 传 `postFrame: true` 可以避免 `ScaffoldMessenger.of` 在 build 阶段
  /// 抛出 assertion。
  static void flash(
    BuildContext context,
    String message, {
    OpenHandSnackKind kind = OpenHandSnackKind.info,
    Duration? duration,
    SnackBarAction? action,
    bool postFrame = false,
  }) {
    void dispatch() {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      final snackBar = switch (kind) {
        OpenHandSnackKind.success => success(
          context,
          message,
          duration: duration ?? const Duration(seconds: 2),
          action: action,
        ),
        OpenHandSnackKind.error => error(
          context,
          message,
          duration: duration ?? const Duration(seconds: 4),
          action: action,
        ),
        OpenHandSnackKind.info => info(
          context,
          message,
          duration: duration ?? const Duration(seconds: 3),
          action: action,
        ),
      };
      show(context, messenger, snackBar);
    }

    if (postFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => dispatch());
    } else {
      dispatch();
    }
  }

  static SnackBar notification(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color tint,
    required Color backgroundColor,
    required Color foregroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    return _build(
      context,
      message,
      icon: icon,
      tint: tint,
      duration: duration,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      maxLines: 3,
    );
  }

  static SnackBar _build(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color tint,
    required Duration duration,
    SnackBarAction? action,
    Color? backgroundColor,
    Color? foregroundColor,
    int? maxLines,
  }) {
    final textStyle = _foregroundTextStyle(foregroundColor);
    return SnackBar(
      duration: duration,
      action: action,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.down,
      content: _messageContent(
        icon: icon,
        tint: tint,
        child: Text(
          message,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: textStyle,
        ),
      ),
    );
  }
}

class _OpenHandSnackBarMessage extends StatelessWidget {
  const _OpenHandSnackBarMessage({
    required this.icon,
    required this.tint,
    required this.child,
  });

  final IconData icon;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: tint, size: 20),
        const SizedBox(width: 12),
        Flexible(child: child),
      ],
    );
  }
}

class _OpenHandSnackBarContent extends StatelessWidget {
  const _OpenHandSnackBarContent({required this.message, required this.action});

  final Widget message;
  final SnackBarAction? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Row(
      children: [
        Expanded(child: message),
        if (action != null) ...[
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: action,
          ),
        ],
        const SizedBox(width: 6),
        const _SnackBarCloseButton(),
      ],
    );
  }
}

class _OpenHandSnackBarMotion extends StatelessWidget {
  const _OpenHandSnackBarMotion({required this.settings, required this.child});

  final DialogAnimationSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        OpenHandSnackBar._motionDisabled(settings)) {
      return child;
    }
    final animation = context
        .findAncestorWidgetOfExactType<SnackBar>()
        ?.animation;
    if (animation == null) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        return buildAnimationStyleTransition(
          animation: animation,
          settings: settings,
          child: child!,
        );
      },
    );
  }
}

/// 无背景的 SnackBar 关闭按钮。
/// 替代 Flutter 框架内置的 IconButton（M3 下有不可控的白色圆形背景），
/// 使用纯透明背景 + 半透明前景色，视觉上更干净。
class _SnackBarCloseButton extends StatelessWidget {
  const _SnackBarCloseButton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onInverseSurface.withValues(alpha: 0.7);
    final tooltip = MaterialLocalizations.of(context).closeButtonTooltip;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(
              context,
            ).hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.close_rounded, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
