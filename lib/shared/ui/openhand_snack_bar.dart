import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'animated_dialog.dart';

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
        durationMs: 360,
      );

  static const DialogAnimationSettings _disabledMotionSettings =
      DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.none,
        exitStyle: DialogAnimationStyle.none,
      );

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

  static Widget _withDismissControl(Widget content) {
    return Row(
      children: [
        Expanded(child: content),
        const SizedBox(width: 8),
        const _SnackBarCloseButton(),
      ],
    );
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
    final wrappedContent = _withDismissControl(modernContent);
    return SnackBar(
      key: snackBar.key,
      content: _OpenHandSnackBarMotion(
        settings: motionSettings,
        child: wrappedContent,
      ),
      action: snackBar.action,
      duration: snackBar.duration,
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
      tint: const Color(0xFF22C55E),
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
      tint: const Color(0xFFEF4444),
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

class _OpenHandSnackBarMotion extends StatefulWidget {
  const _OpenHandSnackBarMotion({required this.settings, required this.child});

  final DialogAnimationSettings settings;
  final Widget child;

  @override
  State<_OpenHandSnackBarMotion> createState() =>
      _OpenHandSnackBarMotionState();
}

class _OpenHandSnackBarMotionState extends State<_OpenHandSnackBarMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _applyControllerDurations();
  }

  @override
  void didUpdateWidget(covariant _OpenHandSnackBarMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _applyControllerDurations();
    }
  }

  void _applyControllerDurations() {
    _controller.duration = widget.settings.duration;
    _controller.reverseDuration = widget.settings.duration;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        OpenHandSnackBar._motionDisabled(widget.settings)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        OpenHandSnackBar._motionDisabled(widget.settings)) {
      return widget.child;
    }
    return buildAnimationStyleTransition(
      animation: _controller,
      settings: widget.settings,
      child: widget.child,
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
