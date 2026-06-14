import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/model/dialog_animation_settings.dart';
import 'animated_dialog.dart';
import 'micro_press_feedback.dart';
import 'motion_preference.dart';

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
  BoxConstraints? constraints,
  DialogAnimationSettings? settings,
  bool useRootNavigator = false,
  bool enableBidirectionalScroll = false,
}) {
  final effectiveSettings = openHandMotionSettingsOf(
    context,
    OpenHandMotionSettingsScope.menu,
    override: settings,
  );

  if (openHandMotionDisabled(effectiveSettings)) {
    return showMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      elevation: elevation,
      color: color,
      shape: shape,
      constraints: constraints,
      useRootNavigator: useRootNavigator,
      popUpAnimationStyle: AnimationStyle.noAnimation,
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
      constraints: constraints,
      animationSettings: effectiveSettings,
      enableBidirectionalScroll: enableBidirectionalScroll,
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
    required this.enableBidirectionalScroll,
    this.initialValue,
    this.elevation,
    this.color,
    this.shape,
    this.constraints,
  }) : itemSizes = List<Size?>.filled(items.length, null);

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final T? initialValue;
  final double? elevation;
  final Color? color;
  final ShapeBorder? shape;
  final BoxConstraints? constraints;
  final DialogAnimationSettings animationSettings;
  final CapturedThemes capturedThemes;
  final bool enableBidirectionalScroll;
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

class _PopupMenuContent<T> extends StatefulWidget {
  const _PopupMenuContent({required this.route});

  final _AnimatedPopupMenuRoute<T> route;

  @override
  State<_PopupMenuContent<T>> createState() => _PopupMenuContentState<T>();
}

class _PopupMenuContentState<T> extends State<_PopupMenuContent<T>> {
  static const double _kMenuMinWidth = 112.0;
  static const double _kMenuMaxWidth = 280.0;
  static const double _kMenuWidthStep = 56.0;
  static const double _kScrollbarThickness = 6.0;
  static const Radius _kScrollbarRadius = Radius.circular(999);

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  double _resolvedMinWidth(BoxConstraints? constraints) {
    final minWidth = constraints?.minWidth ?? _kMenuMinWidth;
    if (!minWidth.isFinite) {
      return _kMenuMinWidth;
    }
    return minWidth < _kMenuMinWidth ? _kMenuMinWidth : minWidth;
  }

  BoxConstraints _resolvedMenuConstraints(BoxConstraints? constraints) {
    final fallback =
        constraints ??
        const BoxConstraints(
          minWidth: _kMenuMinWidth,
          maxWidth: _kMenuMaxWidth,
        );
    final resolvedMinWidth = _resolvedMinWidth(fallback);
    final resolvedMaxWidth = fallback.maxWidth.isFinite
        ? (fallback.maxWidth < resolvedMinWidth
              ? resolvedMinWidth
              : fallback.maxWidth)
        : fallback.maxWidth;
    final resolvedMinHeight = fallback.minHeight.isFinite
        ? fallback.minHeight.clamp(0.0, fallback.maxHeight).toDouble()
        : 0.0;
    return BoxConstraints(
      minWidth: resolvedMinWidth,
      maxWidth: resolvedMaxWidth,
      minHeight: resolvedMinHeight,
      maxHeight: fallback.maxHeight,
    );
  }

  Widget _buildVerticalMenuList({
    required EdgeInsetsGeometry padding,
    required List<Widget> children,
    bool enableScrollbar = false,
  }) {
    final list = SingleChildScrollView(
      controller: enableScrollbar ? _verticalScrollController : null,
      padding: padding,
      child: ListBody(children: children),
    );
    if (!enableScrollbar) {
      return list;
    }
    return Scrollbar(
      controller: _verticalScrollController,
      thumbVisibility: true,
      thickness: _kScrollbarThickness,
      radius: _kScrollbarRadius,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.vertical,
      child: list,
    );
  }

  Widget _buildScrollableBody({
    required EdgeInsetsGeometry padding,
    required List<Widget> children,
    required double minWidth,
  }) {
    if (!widget.route.enableBidirectionalScroll) {
      return IntrinsicWidth(
        stepWidth: _kMenuWidthStep,
        child: _buildVerticalMenuList(padding: padding, children: children),
      );
    }

    final resolvedPadding = padding.resolve(Directionality.of(context));
    final contentPadding = resolvedPadding.copyWith(
      right: resolvedPadding.right + 4,
      bottom: resolvedPadding.bottom + 10,
    );
    return PrimaryScrollController.none(
      child: Scrollbar(
        controller: _horizontalScrollController,
        thumbVisibility: true,
        thickness: _kScrollbarThickness,
        radius: _kScrollbarRadius,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: IntrinsicWidth(
              stepWidth: _kMenuWidthStep,
              child: _buildVerticalMenuList(
                padding: contentPadding,
                children: children,
                enableScrollbar: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
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
    final menuPadding =
        (popupMenuTheme.menuPadding ?? defaults.menuPadding) ?? EdgeInsets.zero;
    final menuConstraints = _resolvedMenuConstraints(route.constraints);
    final menuBody = _buildScrollableBody(
      padding: menuPadding,
      children: children,
      minWidth: _resolvedMinWidth(menuConstraints),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.menu,
      scopesRoute: true,
      namesRoute: true,
      child: ConstrainedBox(
        constraints: menuConstraints,
        child: Material(
          type: MaterialType.card,
          elevation:
              route.elevation ??
              popupMenuTheme.elevation ??
              defaults.elevation!,
          shadowColor: popupMenuTheme.shadowColor ?? defaults.shadowColor,
          surfaceTintColor:
              popupMenuTheme.surfaceTintColor ?? defaults.surfaceTintColor,
          color: route.color ?? popupMenuTheme.color ?? defaults.color,
          shape: route.shape ?? popupMenuTheme.shape ?? defaults.shape,
          clipBehavior: Clip.hardEdge,
          child: menuBody,
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
    // BoxConstraints.deflate() subtracts safe-area padding and clamps each
    // dimension to a valid non-negative value.
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
  return Align(
    alignment: Alignment.topLeft,
    child: buildAnimationStyleTransition(
      animation: animation,
      settings: settings,
      child: child,
    ),
  );
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
    this.initialValue,
    this.position = PopupMenuPosition.over,
    this.icon,
    this.iconSize,
    this.offset = Offset.zero,
    this.padding = const EdgeInsets.all(8.0),
    this.splashRadius,
    this.child,
    this.enabled = true,
    this.constraints,
    this.buttonConstraints,
    this.useRootNavigator = false,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final double? elevation;
  final Color? color;
  final ShapeBorder? shape;
  final T? initialValue;
  final PopupMenuPosition position;
  final Widget? icon;
  final double? iconSize;
  final Offset offset;
  final EdgeInsetsGeometry padding;
  final double? splashRadius;
  final Widget? child;
  final bool enabled;
  final BoxConstraints? constraints;
  final BoxConstraints? buttonConstraints;
  final bool useRootNavigator;

  @override
  State<AnimatedPopupMenuButton<T>> createState() =>
      _AnimatedPopupMenuButtonState<T>();
}

class _AnimatedPopupMenuButtonState<T>
    extends State<AnimatedPopupMenuButton<T>> {
  void _showMenu() {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(
              context,
              rootNavigator: widget.useRootNavigator,
            ).overlay!.context.findRenderObject()!
            as RenderBox;
    final offset = widget.offset;
    final anchorRect = widget.position == PopupMenuPosition.under
        ? Rect.fromLTWH(
            button
                .localToGlobal(
                  Offset(offset.dx, button.size.height + offset.dy),
                  ancestor: overlay,
                )
                .dx,
            button
                .localToGlobal(
                  Offset(offset.dx, button.size.height + offset.dy),
                  ancestor: overlay,
                )
                .dy,
            button.size.width,
            0,
          )
        : Rect.fromPoints(
            button.localToGlobal(offset, ancestor: overlay),
            button.localToGlobal(
              button.size.bottomRight(Offset.zero) + offset,
              ancestor: overlay,
            ),
          );
    final position = RelativeRect.fromRect(
      anchorRect,
      Offset.zero & overlay.size,
    );

    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;

    showAnimatedMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: widget.initialValue,
      elevation: widget.elevation,
      color: widget.color,
      shape: widget.shape,
      constraints: widget.constraints,
      useRootNavigator: widget.useRootNavigator,
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
      final button = InkWell(
        onTap: widget.enabled ? _showMenu : null,
        borderRadius: BorderRadius.circular(4),
        child: widget.child,
      );
      final pressed = MicroPressFeedback(
        enabled: widget.enabled,
        scale: 0.94,
        child: button,
      );
      final tooltip = widget.tooltip;
      if (tooltip == null || tooltip.isEmpty) return pressed;
      return Tooltip(message: tooltip, child: pressed);
    }
    return MicroPressFeedback(
      enabled: widget.enabled,
      scale: 0.92,
      child: IconButton(
        icon: widget.icon ?? const Icon(Icons.more_vert),
        iconSize: widget.iconSize,
        tooltip: widget.tooltip,
        padding: widget.padding,
        splashRadius: widget.splashRadius,
        constraints: widget.buttonConstraints,
        onPressed: widget.enabled ? _showMenu : null,
      ),
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
    borderRadius: BorderRadius.all(Radius.circular(8)),
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
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );

  @override
  EdgeInsets? get menuPadding => const EdgeInsets.symmetric(vertical: 8);
}
