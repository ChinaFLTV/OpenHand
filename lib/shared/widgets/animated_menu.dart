import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';

/// Shows a popup menu with configurable entrance and exit animations.
///
/// When [settings] is null, the configuration is automatically read from the
/// nearest [SettingsController] in the widget tree.
Future<T?> showAnimatedMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  Color? color,
  ShapeBorder? shape,
  DialogAnimationSettings? settings,
  bool useRootNavigator = false,
}) {
  final effectiveSettings =
      settings ?? context.read<SettingsController>().menuAnimationSettings;

  if (effectiveSettings.entranceStyle == DialogAnimationStyle.none &&
      effectiveSettings.exitStyle == DialogAnimationStyle.none) {
    return showMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      elevation: elevation,
      color: color,
      shape: shape,
      useRootNavigator: useRootNavigator,
    );
  }

  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    _AnimatedPopupMenuRoute<T>(
      position: position,
      items: items,
      initialValue: initialValue,
      elevation: elevation,
      color: color,
      shape: shape,
      animationSettings: effectiveSettings,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated popup menu route
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedPopupMenuRoute<T> extends PopupRoute<T> {
  _AnimatedPopupMenuRoute({
    required this.position,
    required this.items,
    required this.animationSettings,
    required this.barrierLabel,
    required this.capturedThemes,
    this.initialValue,
    this.elevation,
    this.color,
    this.shape,
  }) : itemSizes = List<Size?>.filled(items.length, null);

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final T? initialValue;
  final double? elevation;
  final Color? color;
  final ShapeBorder? shape;
  final DialogAnimationSettings animationSettings;
  final CapturedThemes capturedThemes;
  final List<Size?> itemSizes;

  @override
  Duration get transitionDuration => animationSettings.duration;

  @override
  Duration get reverseTransitionDuration => animationSettings.duration;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _buildMenuTransition(animation, animationSettings, child);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final menuContent = capturedThemes.wrap(_PopupMenuContent<T>(route: this));

    // `paddingOf` only subscribes to padding changes; full `MediaQuery.of`
    // would rebuild this overlay on unrelated viewInsets / textScale events.
    final mediaPadding = MediaQuery.paddingOf(context);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: Builder(
        builder: (context) {
          return CustomSingleChildLayout(
            delegate: _PopupMenuRouteLayout(
              position,
              itemSizes,
              Directionality.of(context),
              mediaPadding,
            ),
            child: menuContent,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu content
// ─────────────────────────────────────────────────────────────────────────────

class _PopupMenuContent<T> extends StatelessWidget {
  const _PopupMenuContent({required this.route});

  final _AnimatedPopupMenuRoute<T> route;

  @override
  Widget build(BuildContext context) {
    final popupMenuTheme = PopupMenuTheme.of(context);
    final defaults = Theme.of(context).useMaterial3
        ? _PopupMenuDefaultsM3(context)
        : _PopupMenuDefaultsM2(context);

    final children = <Widget>[];
    for (var i = 0; i < route.items.length; i++) {
      children.add(
        _MenuItemWidget(
          onLayout: (size) => route.itemSizes[i] = size,
          child: route.items[i],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
      child: Material(
        type: MaterialType.card,
        elevation:
            route.elevation ?? popupMenuTheme.elevation ?? defaults.elevation!,
        shadowColor: popupMenuTheme.shadowColor ?? defaults.shadowColor,
        surfaceTintColor:
            popupMenuTheme.surfaceTintColor ?? defaults.surfaceTintColor,
        color: route.color ?? popupMenuTheme.color ?? defaults.color,
        shape: route.shape ?? popupMenuTheme.shape ?? defaults.shape,
        clipBehavior: Clip.hardEdge,
        child: IntrinsicWidth(
          stepWidth: 56,
          child: SingleChildScrollView(
            padding: popupMenuTheme.menuPadding ?? defaults.menuPadding,
            child: ListBody(children: children),
          ),
        ),
      ),
    );
  }
}

class _MenuItemWidget extends SingleChildRenderObjectWidget {
  const _MenuItemWidget({required this.onLayout, required super.child});

  final ValueChanged<Size> onLayout;

  @override
  _MenuItemRenderObject createRenderObject(BuildContext context) =>
      _MenuItemRenderObject(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MenuItemRenderObject renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _MenuItemRenderObject extends RenderProxyBox {
  _MenuItemRenderObject(this.onLayout);

  ValueChanged<Size> onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout(size);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout delegate
// ─────────────────────────────────────────────────────────────────────────────

class _PopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _PopupMenuRouteLayout(
    this.position,
    this.itemSizes,
    this.textDirection,
    this.padding,
  );

  final RelativeRect position;
  final List<Size?> itemSizes;
  final TextDirection textDirection;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // Limit the menu to at most the screen size minus system safe-area padding.
    // getPositionForChild() handles clamping the *position* so the menu stays
    // on-screen; this method only constrains the menu's *size*.
    //
    // The previous two attempts both failed:
    //   1. `constraints.biggest - EdgeInsets(...).collapsedSize as Size`
    //      → `Size - Size` returns Offset, so `as Size` cast threw TypeError.
    //   2. `EdgeInsets(...).deflateSize(constraints.biggest)`
    //      → deflateSize subtracts (position.top + position.bottom) from the
    //        screen height.  For a right-click at y=500 on an 834px screen
    //        position.top=position.bottom=500, total=1000 > 834, yielding
    //        height=−166.  BoxConstraints.loose with a negative size asserts.
    //
    // BoxConstraints.deflate() is the correct API: it subtracts the padding
    // but clamps each dimension to ≥0, guaranteeing valid constraints.
    return BoxConstraints.loose(constraints.biggest).deflate(padding);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Position the menu below / to the right of the anchor, respecting bounds.
    final double y = position.top;
    double x;
    if (textDirection == TextDirection.rtl) {
      x = size.width - position.right - childSize.width;
    } else {
      x = position.left;
    }
    // Clamp to screen.
    x = x.clamp(padding.left, size.width - childSize.width - padding.right);
    final clampedY = y.clamp(
      padding.top,
      size.height - childSize.height - padding.bottom,
    );
    return Offset(x, clampedY);
  }

  @override
  bool shouldRelayout(covariant _PopupMenuRouteLayout oldDelegate) {
    return position != oldDelegate.position ||
        textDirection != oldDelegate.textDirection ||
        padding != oldDelegate.padding;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu transition builder
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildMenuTransition(
  Animation<double> animation,
  DialogAnimationSettings settings,
  Widget child,
) {
  final forward =
      animation.status == AnimationStatus.forward ||
      animation.status == AnimationStatus.completed;
  final style = forward ? settings.entranceStyle : settings.exitStyle;
  final curveData = settings.curve;
  final curved = CurvedAnimation(
    parent: animation,
    curve: curveData.curve,
    reverseCurve: curveData.reverseCurve,
  );

  return switch (style) {
    DialogAnimationStyle.none => FadeTransition(
      opacity: animation,
      child: child,
    ),
    DialogAnimationStyle.fade => FadeTransition(opacity: curved, child: child),
    DialogAnimationStyle.fadeScale => FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
    DialogAnimationStyle.slideUp => FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
    DialogAnimationStyle.slideDown => FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
    DialogAnimationStyle.expand => FadeTransition(
      opacity: CurvedAnimation(
        parent: curved,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: curved,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        ),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
    DialogAnimationStyle.rotateScale => FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.7, end: 1.0).animate(curved),
        child: RotationTransition(
          turns: Tween<double>(begin: -0.03, end: 0.0).animate(curved),
          child: child,
        ),
      ),
    ),
    DialogAnimationStyle.elastic => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInCubic),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
    DialogAnimationStyle.slideLeft => FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
    DialogAnimationStyle.slideRight => FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
    DialogAnimationStyle.springScale => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInCubic),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInBack,
          ),
        ),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
    DialogAnimationStyle.flipX => FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedPopupMenuButton — drop-in replacement for PopupMenuButton
// ─────────────────────────────────────────────────────────────────────────────

/// A drop-in replacement for [PopupMenuButton] that uses [showAnimatedMenu] to
/// display the popup with configurable entrance / exit transitions.
class AnimatedPopupMenuButton<T> extends StatefulWidget {
  const AnimatedPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.elevation,
    this.color,
    this.shape,
    this.icon,
    this.iconSize,
    this.offset = Offset.zero,
    this.padding = const EdgeInsets.all(8.0),
    this.splashRadius,
    this.child,
    this.enabled = true,
    this.constraints,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final double? elevation;
  final Color? color;
  final ShapeBorder? shape;
  final Widget? icon;
  final double? iconSize;
  final Offset offset;
  final EdgeInsetsGeometry padding;
  final double? splashRadius;
  final Widget? child;
  final bool enabled;
  final BoxConstraints? constraints;

  @override
  State<AnimatedPopupMenuButton<T>> createState() =>
      _AnimatedPopupMenuButtonState<T>();
}

class _AnimatedPopupMenuButtonState<T>
    extends State<AnimatedPopupMenuButton<T>> {
  void _showMenu() {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final offset = widget.offset;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(offset, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + offset,
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;

    showAnimatedMenu<T>(
      context: context,
      position: position,
      items: items,
      elevation: widget.elevation,
      color: widget.color,
      shape: widget.shape,
    ).then((value) {
      if (!mounted) return;
      if (value == null) {
        widget.onCanceled?.call();
      } else {
        widget.onSelected?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) {
      return Tooltip(
        message: widget.tooltip ?? '',
        child: InkWell(
          onTap: widget.enabled ? _showMenu : null,
          borderRadius: BorderRadius.circular(4),
          child: widget.child,
        ),
      );
    }
    return IconButton(
      icon: widget.icon ?? const Icon(Icons.more_vert),
      iconSize: widget.iconSize,
      tooltip: widget.tooltip,
      padding: widget.padding,
      splashRadius: widget.splashRadius,
      constraints: widget.constraints,
      onPressed: widget.enabled ? _showMenu : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PopupMenuSectionHeader — non-interactive section label for grouped menus
// ─────────────────────────────────────────────────────────────────────────────

/// A non-selectable section header for use in [showAnimatedMenu] item lists.
class PopupMenuSectionHeader<T> extends PopupMenuEntry<T> {
  const PopupMenuSectionHeader({super.key, required this.label});

  final String label;

  @override
  double get height => 32;

  @override
  bool represents(T? value) => false;

  @override
  State<PopupMenuSectionHeader<T>> createState() =>
      _PopupMenuSectionHeaderState<T>();
}

class _PopupMenuSectionHeaderState<T> extends State<PopupMenuSectionHeader<T>> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        widget.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Material defaults (simplified from Flutter framework)
// ─────────────────────────────────────────────────────────────────────────────

class _PopupMenuDefaultsM2 extends PopupMenuThemeData {
  const _PopupMenuDefaultsM2(this.context) : super(elevation: 8.0);

  final BuildContext context;

  @override
  Color? get color => Theme.of(context).cardColor;

  @override
  ShapeBorder? get shape => const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );

  @override
  EdgeInsets? get menuPadding => const EdgeInsets.symmetric(vertical: 8);
}

class _PopupMenuDefaultsM3 extends PopupMenuThemeData {
  const _PopupMenuDefaultsM3(this.context) : super(elevation: 3.0);

  final BuildContext context;

  @override
  Color? get color => Theme.of(context).colorScheme.surfaceContainer;

  @override
  Color? get shadowColor => Theme.of(context).colorScheme.shadow;

  @override
  Color? get surfaceTintColor => Colors.transparent;

  @override
  ShapeBorder? get shape => const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );

  @override
  EdgeInsets? get menuPadding => const EdgeInsets.symmetric(vertical: 8);
}
