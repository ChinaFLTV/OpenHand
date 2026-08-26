import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/model/dialog_animation_settings.dart';
import 'animated_dialog.dart';
import 'micro_press_feedback.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_safe_scrollbar.dart';

DialogAnimationSettings _resolveAnimatedMenuSettings(
  BuildContext context,
  DialogAnimationSettings? settings,
) {
  return openHandMotionSettingsOf(
    context,
    OpenHandMotionSettingsScope.menu,
    override: settings,
  );
}

/// 显示支持全局进退场动画设置的弹出菜单。
///
/// [settings] 为空时从组件树最近的 [SettingsController] 读取配置。
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
  bool barrierDismissible = true,
}) {
  if (items.isEmpty || !context.mounted) return Future<T?>.value();
  final navigator = Navigator.maybeOf(context, rootNavigator: useRootNavigator);
  if (navigator == null || !navigator.mounted) return Future<T?>.value();
  final effectiveSettings = _resolveAnimatedMenuSettings(context, settings);
  final route = _AnimatedPopupMenuRoute<T>(
    position: position,
    items: items,
    initialValue: initialValue,
    elevation: elevation,
    color: color,
    shape: shape,
    constraints: constraints,
    animationSettings: effectiveSettings,
    enableBidirectionalScroll: enableBidirectionalScroll,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
  );
  return pushOpenHandTransitionRoute(navigator, route, sourceContext: context);
}

/// 以全局坐标点为锚显示上下文菜单（右键、长按、指针命中等场景）。
///
/// 统一解析 Overlay、校验挂载状态，并把锚点夹取到 Overlay 可视范围内，
/// 避免贴边触发时菜单落到窗口外。[globalPosition] 为空时回落到 Overlay 中心。
Future<T?> showAnimatedPointerMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  Offset? globalPosition,
  double? elevation,
  Color? color,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  DialogAnimationSettings? settings,
  bool useRootNavigator = false,
  bool rootOverlay = false,
  bool enableBidirectionalScroll = false,
  bool barrierDismissible = true,
}) {
  if (items.isEmpty || !context.mounted) return Future<T?>.value();
  final overlay = Overlay.maybeOf(
    context,
    rootOverlay: rootOverlay,
  )?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.hasSize) return Future<T?>.value();
  final overlaySize = overlay.size;
  final origin =
      globalPosition ?? overlay.localToGlobal(overlaySize.center(Offset.zero));
  final local = overlay.globalToLocal(origin);
  final anchor = Offset(
    local.dx.clamp(0.0, overlaySize.width),
    local.dy.clamp(0.0, overlaySize.height),
  );
  return showAnimatedMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0),
      Offset.zero & overlaySize,
    ),
    items: items,
    elevation: elevation,
    color: color,
    shape: shape,
    constraints: constraints,
    settings: settings,
    useRootNavigator: useRootNavigator,
    enableBidirectionalScroll: enableBidirectionalScroll,
    barrierDismissible: barrierDismissible,
  );
}

/// 以当前组件为锚点显示标准弹出菜单，并统一处理挂载对象与窗口尺寸校验。
Future<T?> showAnimatedAnchoredPopupMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  Color? color,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  DialogAnimationSettings? settings,
  PopupMenuPosition position = PopupMenuPosition.over,
  Offset offset = Offset.zero,
  bool useRootNavigator = false,
  bool enableBidirectionalScroll = false,
  bool barrierDismissible = true,
}) {
  if (items.isEmpty || !context.mounted) return Future<T?>.value();
  final navigator = Navigator.maybeOf(context, rootNavigator: useRootNavigator);
  if (navigator == null || !navigator.mounted) return Future<T?>.value();
  final relativePosition = _resolveAnimatedMenuPosition(
    anchorObject: context.findRenderObject(),
    overlayObject: navigator.overlay?.context.findRenderObject(),
    position: position,
    offset: offset,
  );
  if (relativePosition == null) return Future<T?>.value();
  return showAnimatedMenu<T>(
    context: context,
    position: relativePosition,
    items: items,
    initialValue: initialValue,
    elevation: elevation,
    color: color,
    shape: shape,
    constraints: constraints,
    settings: settings,
    useRootNavigator: useRootNavigator,
    enableBidirectionalScroll: enableBidirectionalScroll,
    barrierDismissible: barrierDismissible,
  );
}

/// 在锚定弹出路由中显示任意交互内容，并继承全局菜单动画设置。
///
/// 选择、ESC 和点击外部均通过路由退场，确保完整播放反向动画。
Future<T?> showAnimatedAnchoredMenu<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  PopupMenuPosition position = PopupMenuPosition.under,
  Offset offset = Offset.zero,
  bool useRootNavigator = false,
  bool barrierDismissible = true,
}) {
  if (!context.mounted) return Future<T?>.value();
  final navigator = Navigator.maybeOf(context, rootNavigator: useRootNavigator);
  if (navigator == null || !navigator.mounted) return Future<T?>.value();
  final relativePosition = _resolveAnimatedMenuPosition(
    anchorObject: context.findRenderObject(),
    overlayObject: navigator.overlay?.context.findRenderObject(),
    position: position,
    offset: offset,
  );
  if (relativePosition == null) return Future<T?>.value();
  final effectiveSettings = _resolveAnimatedMenuSettings(context, settings);
  final route = _AnimatedAnchoredMenuRoute<T>(
    position: relativePosition,
    animationSettings: effectiveSettings,
    textDirection: Directionality.of(context),
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    builder: builder,
  );
  return pushOpenHandTransitionRoute(navigator, route, sourceContext: context);
}

class _AnimatedAnchoredMenuRoute<T> extends PopupRoute<T> {
  _AnimatedAnchoredMenuRoute({
    required this.position,
    required this.animationSettings,
    required this.textDirection,
    required this.barrierDismissible,
    required this.barrierLabel,
    required this.capturedThemes,
    required this.builder,
  });

  final RelativeRect position;
  final DialogAnimationSettings animationSettings;
  final TextDirection textDirection;
  @override
  final bool barrierDismissible;
  final CapturedThemes capturedThemes;
  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => animationSettings.entranceDuration;

  @override
  Duration get reverseTransitionDuration => animationSettings.exitDuration;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final menu = _buildMenuTransition(
      animation,
      animationSettings,
      capturedThemes.wrap(Builder(builder: builder)),
    );
    return OpenHandEscapeDismissScope(
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        removeLeft: true,
        removeRight: true,
        child: CustomSingleChildLayout(
          delegate: _AnchoredMenuRouteLayout(
            position,
            textDirection,
            mediaPadding,
          ),
          child: menu,
        ),
      ),
    );
  }
}

class _AnchoredMenuRouteLayout extends SingleChildLayoutDelegate {
  const _AnchoredMenuRouteLayout(
    this.position,
    this.textDirection,
    this.padding,
  );

  final RelativeRect position;
  final TextDirection textDirection;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest).deflate(padding);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final preferredX = textDirection == TextDirection.rtl
        ? size.width - position.right - childSize.width
        : position.left;
    return Offset(
      _clampMenuCoordinate(
        preferredX,
        lower: padding.left,
        upper: size.width - childSize.width - padding.right,
      ),
      _clampMenuCoordinate(
        position.top,
        lower: padding.top,
        upper: size.height - childSize.height - padding.bottom,
      ),
    );
  }

  @override
  bool shouldRelayout(covariant _AnchoredMenuRouteLayout oldDelegate) {
    return position != oldDelegate.position ||
        textDirection != oldDelegate.textDirection ||
        padding != oldDelegate.padding;
  }
}

class _AnimatedPopupMenuRoute<T> extends PopupRoute<T> {
  _AnimatedPopupMenuRoute({
    required this.position,
    required this.items,
    required this.animationSettings,
    required this.barrierLabel,
    required this.capturedThemes,
    required this.enableBidirectionalScroll,
    required this.barrierDismissible,
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
  @override
  final bool barrierDismissible;
  final List<Size?> itemSizes;

  @override
  Duration get transitionDuration => animationSettings.entranceDuration;

  @override
  Duration get reverseTransitionDuration => animationSettings.exitDuration;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final menuContent = _buildMenuTransition(
      animation,
      animationSettings,
      capturedThemes.wrap(_PopupMenuContent<T>(route: this)),
    );

    // 仅监听安全边距，避免其他 MediaQuery 属性变化时重建浮层。
    final mediaPadding = MediaQuery.paddingOf(context);
    return OpenHandEscapeDismissScope(
      child: MediaQuery.removePadding(
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
                Directionality.of(context),
                mediaPadding,
              ),
              child: menuContent,
            );
          },
        ),
      ),
    );
  }
}

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
  static const Radius _kScrollbarRadius = kOpenHandPillRadius;

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  bool _initialScrollScheduled = false;

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
      controller: _verticalScrollController,
      primary: false,
      padding: padding,
      child: ListBody(children: children),
    );
    if (!enableScrollbar) {
      return list;
    }
    return OpenHandSafeScrollbar(
      controller: _verticalScrollController,
      thumbVisibility: true,
      thickness: _kScrollbarThickness,
      radius: _kScrollbarRadius,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.vertical,
      child: list,
    );
  }

  void _scheduleInitialSelectionScroll(
    _AnimatedPopupMenuRoute<T> route,
    EdgeInsetsGeometry padding,
  ) {
    if (_initialScrollScheduled || route.initialValue == null) return;
    final selectedIndex = route.items.indexWhere(
      (item) => item.represents(route.initialValue),
    );
    if (selectedIndex < 0) return;
    _initialScrollScheduled = true;
    final topPadding = padding.resolve(Directionality.of(context)).top;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalScrollController.hasClients) return;
      final selectedSize = route.itemSizes[selectedIndex];
      if (selectedSize == null) return;
      var offset = topPadding;
      for (var index = 0; index < selectedIndex; index++) {
        offset += route.itemSizes[index]?.height ?? 0;
      }
      final position = _verticalScrollController.position;
      final target =
          (offset - (position.viewportDimension - selectedSize.height) / 2)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((position.pixels - target).abs() > 0.5) {
        _verticalScrollController.jumpTo(target);
      }
    });
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
      child: OpenHandSafeScrollbar(
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
          primary: false,
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
    _scheduleInitialSelectionScroll(route, menuPadding);
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

class _PopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _PopupMenuRouteLayout(this.position, this.textDirection, this.padding);

  final RelativeRect position;
  final TextDirection textDirection;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // 尺寸只占用安全区域；位置由 getPositionForChild 单独夹取到屏幕内。
    return BoxConstraints.loose(constraints.biggest).deflate(padding);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 菜单默认位于锚点下方，并根据文字方向确定横向位置。
    final double y = position.top;
    double x;
    if (textDirection == TextDirection.rtl) {
      x = size.width - position.right - childSize.width;
    } else {
      x = position.left;
    }
    // 夹取到屏幕安全区域内。
    x = _clampMenuCoordinate(
      x,
      lower: padding.left,
      upper: size.width - childSize.width - padding.right,
    );
    final clampedY = _clampMenuCoordinate(
      y,
      lower: padding.top,
      upper: size.height - childSize.height - padding.bottom,
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

double _clampMenuCoordinate(
  double value, {
  required double lower,
  required double upper,
}) {
  if (!value.isFinite) return lower;
  if (upper < lower) return lower;
  return value.clamp(lower, upper).toDouble();
}

Widget _buildMenuTransition(
  Animation<double> animation,
  DialogAnimationSettings settings,
  Widget child,
) {
  if (openHandMotionDisabled(settings)) return child;
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, builtChild) => buildAnimationStyleTransition(
      animation: animation,
      settings: settings,
      child: builtChild!,
    ),
  );
}

class _AnimatedDropdownSelection<T> {
  const _AnimatedDropdownSelection({required this.index, required this.value});

  final int index;
  final T? value;

  @override
  bool operator ==(Object other) {
    return other is _AnimatedDropdownSelection<T> && other.index == index;
  }

  @override
  int get hashCode => index.hashCode;
}

/// 使用全局菜单进退场设置的 [DropdownButton] 等价实现。
///
/// 选中值仍由调用方持有；内部包装可空值，以区分选择 null 与未选择直接关闭。
class AnimatedDropdownButton<T> extends StatefulWidget {
  const AnimatedDropdownButton({
    super.key,
    required this.items,
    this.selectedItemBuilder,
    this.value,
    this.hint,
    this.disabledHint,
    required this.onChanged,
    this.onTap,
    this.elevation = 8,
    this.style,
    this.underline,
    this.icon,
    this.iconDisabledColor,
    this.iconEnabledColor,
    this.iconSize = 24,
    this.isDense = false,
    this.isExpanded = false,
    this.itemHeight = kMinInteractiveDimension,
    this.menuWidth,
    this.focusColor,
    this.focusNode,
    this.autofocus = false,
    this.dropdownColor,
    this.menuMaxHeight,
    this.enableFeedback,
    this.alignment = AlignmentDirectional.centerStart,
    this.borderRadius,
    this.padding,
    this.barrierDismissible = true,
    this.mouseCursor,
    this.dropdownMenuItemMouseCursor,
    this.useRootNavigator = false,
    this.animationSettings,
  }) : _inputDecoration = null,
       _isEmpty = false;

  const AnimatedDropdownButton._formField({
    required this.items,
    required this.selectedItemBuilder,
    required this.value,
    required this.hint,
    required this.disabledHint,
    required this.onChanged,
    required this.onTap,
    required this.elevation,
    required this.style,
    required this.icon,
    required this.iconDisabledColor,
    required this.iconEnabledColor,
    required this.iconSize,
    required this.isDense,
    required this.isExpanded,
    required this.itemHeight,
    required this.focusColor,
    required this.focusNode,
    required this.autofocus,
    required this.dropdownColor,
    required this.menuMaxHeight,
    required this.enableFeedback,
    required this.alignment,
    required this.borderRadius,
    required this.padding,
    required this.barrierDismissible,
    required this.mouseCursor,
    required this.dropdownMenuItemMouseCursor,
    required this.useRootNavigator,
    required this.animationSettings,
    required InputDecoration inputDecoration,
    required bool isEmpty,
  }) : underline = null,
       menuWidth = null,
       _inputDecoration = inputDecoration,
       _isEmpty = isEmpty;

  final List<DropdownMenuItem<T>>? items;
  final DropdownButtonBuilder? selectedItemBuilder;
  final T? value;
  final Widget? hint;
  final Widget? disabledHint;
  final ValueChanged<T?>? onChanged;
  final VoidCallback? onTap;
  final int elevation;
  final TextStyle? style;
  final Widget? underline;
  final Widget? icon;
  final Color? iconDisabledColor;
  final Color? iconEnabledColor;
  final double iconSize;
  final bool isDense;
  final bool isExpanded;
  final double? itemHeight;
  final double? menuWidth;
  final Color? focusColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final Color? dropdownColor;
  final double? menuMaxHeight;
  final bool? enableFeedback;
  final AlignmentGeometry alignment;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool barrierDismissible;
  final MouseCursor? mouseCursor;
  final MouseCursor? dropdownMenuItemMouseCursor;
  final bool useRootNavigator;
  final DialogAnimationSettings? animationSettings;
  final InputDecoration? _inputDecoration;
  final bool _isEmpty;

  @override
  State<AnimatedDropdownButton<T>> createState() =>
      _AnimatedDropdownButtonState<T>();
}

class _AnimatedDropdownButtonState<T> extends State<AnimatedDropdownButton<T>> {
  static const double _defaultMenuMaxWidth = 280;

  bool _menuOpen = false;
  bool _focused = false;
  bool _hovering = false;
  FocusNode? _internalFocusNode;

  bool get _enabled =>
      widget.onChanged != null && (widget.items?.isNotEmpty ?? false);

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ??
      (_internalFocusNode ??= FocusNode(debugLabel: 'animated-dropdown'));

  @override
  void didUpdateWidget(covariant AnimatedDropdownButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == null && widget.focusNode != null) {
      _internalFocusNode?.dispose();
      _internalFocusNode = null;
    }
  }

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
  }

  int? get _selectedIndex {
    final items = widget.items;
    if (items == null) return null;
    for (var index = 0; index < items.length; index++) {
      if (items[index].value == widget.value) return index;
    }
    return null;
  }

  BoxConstraints _menuConstraints(RenderBox button, RenderBox overlay) {
    final padding = MediaQuery.paddingOf(context);
    final availableWidth = math.max(
      0.0,
      overlay.size.width - padding.horizontal,
    );
    final requestedWidth = switch (widget.menuWidth) {
      final width? when width.isFinite && width > 0 => width,
      _ => button.size.width,
    };
    final preferredMaxWidth =
        widget.isExpanded || widget._inputDecoration != null
        ? requestedWidth
        : math.max(requestedWidth, _defaultMenuMaxWidth);
    final maxWidth = math.min(preferredMaxWidth, availableWidth);
    final minWidth = math.min(requestedWidth, maxWidth);
    final requestedMaxHeight = widget.menuMaxHeight;
    final maxHeight =
        requestedMaxHeight != null &&
            requestedMaxHeight.isFinite &&
            requestedMaxHeight > 0
        ? requestedMaxHeight
        : double.infinity;
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  Future<void> _showDropdown() async {
    if (!_enabled || _menuOpen) return;
    _effectiveFocusNode.requestFocus();
    if (widget._inputDecoration != null && widget.enableFeedback != false) {
      Feedback.forTap(context);
    }
    final buttonObject = context.findRenderObject();
    final navigator = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    );
    final overlayObject = navigator.overlay?.context.findRenderObject();
    if (buttonObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !buttonObject.hasSize ||
        !overlayObject.hasSize) {
      return;
    }
    final sourceItems = widget.items;
    if (sourceItems == null || sourceItems.isEmpty) return;
    final selections = <_AnimatedDropdownSelection<T>>[
      for (var index = 0; index < sourceItems.length; index++)
        _AnimatedDropdownSelection<T>(
          index: index,
          value: sourceItems[index].value,
        ),
    ];
    final menuItems = <PopupMenuEntry<_AnimatedDropdownSelection<T>>>[
      for (var index = 0; index < sourceItems.length; index++)
        PopupMenuItem<_AnimatedDropdownSelection<T>>(
          value: selections[index],
          enabled: sourceItems[index].enabled,
          onTap: sourceItems[index].onTap,
          height: _validItemHeight(widget.itemHeight),
          textStyle: widget.style,
          mouseCursor: widget.dropdownMenuItemMouseCursor,
          child: Align(
            alignment: sourceItems[index].alignment,
            child: sourceItems[index].child,
          ),
        ),
    ];
    final anchorRect = _animatedPopupMenuAnchorRect(
      button: buttonObject,
      overlay: overlayObject,
      position: PopupMenuPosition.under,
      offset: Offset.zero,
    );
    final position = RelativeRect.fromRect(
      anchorRect,
      Offset.zero & overlayObject.size,
    );
    final selectedIndex = _selectedIndex;
    if (mounted) setState(() => _menuOpen = true);
    try {
      final selectionFuture = showAnimatedMenu<_AnimatedDropdownSelection<T>>(
        context: context,
        position: position,
        items: menuItems,
        initialValue: selectedIndex == null ? null : selections[selectedIndex],
        elevation: widget.elevation.toDouble(),
        color: widget.dropdownColor,
        shape: widget.borderRadius == null
            ? null
            : RoundedRectangleBorder(borderRadius: widget.borderRadius!),
        constraints: _menuConstraints(buttonObject, overlayObject),
        settings: widget.animationSettings,
        useRootNavigator: widget.useRootNavigator,
        barrierDismissible: widget.barrierDismissible,
      );
      try {
        widget.onTap?.call();
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'openhand menu',
            context: ErrorDescription('while opening an animated dropdown'),
          ),
        );
      }
      final selected = await selectionFuture;
      if (mounted && selected != null) {
        try {
          widget.onChanged?.call(selected.value);
        } catch (error, stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'openhand menu',
              context: ErrorDescription(
                'while applying an animated dropdown selection',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  double _validItemHeight(double? value) {
    return value != null && value.isFinite && value > 0
        ? math.max(value, kMinInteractiveDimension)
        : kMinInteractiveDimension;
  }

  Widget _selectedChild(BuildContext context) {
    final items = widget.items;
    final selectedIndex = _selectedIndex;
    if (items != null && selectedIndex != null) {
      final selectedItems = widget.selectedItemBuilder?.call(context);
      if (selectedItems != null && selectedIndex < selectedItems.length) {
        return selectedItems[selectedIndex];
      }
      return items[selectedIndex].child;
    }
    if (!_enabled && widget.disabledHint != null) {
      return widget.disabledHint!;
    }
    return widget.hint ?? const SizedBox.shrink();
  }

  Widget _buildContents(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStyle = widget.style ?? theme.textTheme.titleMedium!;
    final selected = Align(
      alignment: widget.alignment,
      widthFactor: widget.isExpanded ? null : 1,
      child: _selectedChild(context),
    );
    final children = <Widget>[
      if (widget.isExpanded)
        Expanded(child: selected)
      else
        Flexible(child: selected),
      if (widget._inputDecoration == null) ...<Widget>[
        kOpenHandHGap8,
        _buildMenuIcon(theme),
      ],
    ];
    final row = Row(
      mainAxisSize: widget.isExpanded ? MainAxisSize.max : MainAxisSize.min,
      children: children,
    );
    final styled = DefaultTextStyle(
      style: _enabled
          ? effectiveStyle
          : effectiveStyle.copyWith(color: theme.disabledColor),
      child: row,
    );
    final itemHeight = widget.itemHeight;
    if (itemHeight != null && itemHeight.isFinite && itemHeight > 0) {
      return SizedBox(height: itemHeight, child: styled);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: widget.isDense ? 24 : kMinInteractiveDimension,
      ),
      child: styled,
    );
  }

  Widget _buildMenuIcon(ThemeData theme, {Widget? icon}) {
    final iconColor = _enabled
        ? widget.iconEnabledColor ?? theme.colorScheme.onSurfaceVariant
        : widget.iconDisabledColor ?? theme.disabledColor;
    return IconTheme(
      data: IconThemeData(color: iconColor, size: widget.iconSize),
      child: icon ?? widget.icon ?? const Icon(Icons.arrow_drop_down_rounded),
    );
  }

  void _handleFocusChanged(bool focused) {
    if (mounted && focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  void _handleHoverChanged(bool hovering) {
    if (mounted && hovering != _hovering) {
      setState(() => _hovering = hovering);
    }
  }

  KeyEventResult _handleFormKeyEvent(FocusNode node, KeyEvent event) {
    if (!_enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    unawaited(_showDropdown());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    Widget result = _buildContents(context);
    final padding = widget.padding;
    if (padding != null) result = Padding(padding: padding, child: result);
    final inputDecoration = widget._inputDecoration;
    if (inputDecoration != null) {
      final decorationTheme = InputDecorationTheme.of(context);
      final filled = inputDecoration.filled ?? decorationTheme.filled;
      final outlined =
          inputDecoration.border?.isOutline ??
          decorationTheme.border?.isOutline ??
          false;
      final suffixIconEndMargin = filled || outlined ? 12.0 : 0.0;
      var effectiveDecoration = inputDecoration.copyWith(
        suffixIconConstraints: BoxConstraints(
          minWidth: widget.iconSize + suffixIconEndMargin,
          minHeight: widget.iconSize,
        ),
        suffixIcon: Padding(
          padding: EdgeInsetsDirectional.only(end: suffixIconEndMargin),
          child: _buildMenuIcon(
            Theme.of(context),
            icon: widget.icon ?? inputDecoration.suffixIcon,
          ),
        ),
      );
      if (_focused) {
        final focusColor = widget.focusColor ?? effectiveDecoration.focusColor;
        if (focusColor != null) {
          effectiveDecoration = effectiveDecoration.copyWith(
            fillColor: focusColor,
          );
        }
      }
      result = InputDecorator(
        decoration: effectiveDecoration,
        isEmpty: widget._isEmpty,
        isFocused: _focused,
        isHovering: _hovering,
        child: result,
      );
      final effectiveMouseCursor = WidgetStateProperty.resolveAs<MouseCursor>(
        widget.mouseCursor ?? WidgetStateMouseCursor.adaptiveClickable,
        <WidgetState>{if (!_enabled) WidgetState.disabled},
      );
      result = Focus(
        canRequestFocus: _enabled,
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        onFocusChange: _handleFocusChanged,
        onKeyEvent: _handleFormKeyEvent,
        child: MouseRegion(
          cursor: effectiveMouseCursor,
          onEnter: (_) => _handleHoverChanged(true),
          onExit: (_) => _handleHoverChanged(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? _showDropdown : null,
            child: result,
          ),
        ),
      );
    } else if (!DropdownButtonHideUnderline.at(context)) {
      result = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          result,
          widget.underline ??
              Container(
                height: 1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ],
      );
    }
    if (inputDecoration == null) {
      result = InkWell(
        onTap: _enabled ? _showDropdown : null,
        onFocusChange: _handleFocusChanged,
        onHover: _handleHoverChanged,
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        focusColor: widget.focusColor,
        borderRadius: widget.borderRadius,
        enableFeedback: widget.enableFeedback ?? true,
        mouseCursor: widget.mouseCursor,
        child: result,
      );
    }
    return Semantics(
      button: true,
      enabled: _enabled,
      expanded: _menuOpen,
      child: result,
    );
  }
}

/// 集成表单状态的 [AnimatedDropdownButton]。
class AnimatedDropdownButtonFormField<T> extends FormField<T> {
  AnimatedDropdownButtonFormField({
    super.key,
    required List<DropdownMenuItem<T>>? items,
    DropdownButtonBuilder? selectedItemBuilder,
    T? value,
    T? initialValue,
    Widget? hint,
    Widget? disabledHint,
    required this.onChanged,
    VoidCallback? onTap,
    int elevation = 8,
    TextStyle? style,
    Widget? icon,
    Color? iconDisabledColor,
    Color? iconEnabledColor,
    double iconSize = 24,
    bool isDense = true,
    bool isExpanded = false,
    double? itemHeight,
    Color? focusColor,
    FocusNode? focusNode,
    bool autofocus = false,
    Color? dropdownColor,
    InputDecoration? decoration,
    super.onSaved,
    super.validator,
    super.errorBuilder,
    super.forceErrorText,
    AutovalidateMode? autovalidateMode,
    double? menuMaxHeight,
    bool? enableFeedback,
    AlignmentGeometry alignment = AlignmentDirectional.centerStart,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    bool barrierDismissible = true,
    MouseCursor? mouseCursor,
    MouseCursor? dropdownMenuItemMouseCursor,
    bool useRootNavigator = false,
    DialogAnimationSettings? animationSettings,
  }) : decoration = decoration ?? const InputDecoration(),
       super(
         initialValue: initialValue ?? value,
         autovalidateMode: autovalidateMode ?? AutovalidateMode.disabled,
         builder: (field) {
           final state = field as _AnimatedDropdownButtonFormFieldState<T>;
           var effectiveDecoration = (decoration ?? const InputDecoration())
               .applyDefaults(InputDecorationTheme.of(field.context));
           final hasSelectedItem =
               items?.any((item) => item.value == state.value) ?? false;
           final enabled = onChanged != null && (items?.isNotEmpty ?? false);
           final decorationHint = effectiveDecoration.hintText == null
               ? null
               : Text(effectiveDecoration.hintText!);
           final effectiveHint = hint ?? decorationHint;
           final effectiveDisabledHint = disabledHint ?? effectiveHint;
           final hasHint = enabled
               ? effectiveHint != null
               : effectiveHint != null || effectiveDisabledHint != null;
           final isEmpty = !hasSelectedItem && !hasHint;
           if (field.errorText != null ||
               effectiveDecoration.hintText != null) {
             final error = field.errorText != null && errorBuilder != null
                 ? errorBuilder(state.context, field.errorText!)
                 : null;
             effectiveDecoration = effectiveDecoration.copyWith(
               error: error,
               errorText: error == null ? field.errorText : null,
               hintText: effectiveDecoration.hintText == null ? null : '',
             );
           }
           return Focus(
             canRequestFocus: false,
             skipTraversal: true,
             child: DropdownButtonHideUnderline(
               child: AnimatedDropdownButton<T>._formField(
                 items: items,
                 selectedItemBuilder: selectedItemBuilder,
                 value: state.value,
                 hint: effectiveHint,
                 disabledHint: effectiveDisabledHint,
                 onChanged: onChanged == null ? null : state.didChange,
                 onTap: onTap,
                 elevation: elevation,
                 style: style,
                 icon: icon,
                 iconDisabledColor: iconDisabledColor,
                 iconEnabledColor: iconEnabledColor,
                 iconSize: iconSize,
                 isDense: isDense,
                 isExpanded: isExpanded,
                 itemHeight: itemHeight,
                 focusColor: focusColor,
                 focusNode: focusNode,
                 autofocus: autofocus,
                 dropdownColor: dropdownColor,
                 menuMaxHeight: menuMaxHeight,
                 enableFeedback: enableFeedback,
                 alignment: alignment,
                 borderRadius: borderRadius,
                 padding: padding,
                 barrierDismissible: barrierDismissible,
                 mouseCursor: mouseCursor,
                 dropdownMenuItemMouseCursor: dropdownMenuItemMouseCursor,
                 useRootNavigator: useRootNavigator,
                 animationSettings: animationSettings,
                 inputDecoration: effectiveDecoration,
                 isEmpty: isEmpty,
               ),
             ),
           );
         },
       );

  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;

  @override
  FormFieldState<T> createState() => _AnimatedDropdownButtonFormFieldState<T>();
}

class _AnimatedDropdownButtonFormFieldState<T> extends FormFieldState<T> {
  AnimatedDropdownButtonFormField<T> get _formField =>
      widget as AnimatedDropdownButtonFormField<T>;

  @override
  void didChange(T? value) {
    super.didChange(value);
    _formField.onChanged?.call(value);
  }

  @override
  void didUpdateWidget(AnimatedDropdownButtonFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }

  @override
  void reset() {
    super.reset();
    _formField.onChanged?.call(value);
  }
}

/// [PopupMenuButton] 的动画替代实现，通过 [showAnimatedMenu] 显示菜单。
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
    this.style,
    this.enabled = true,
    this.constraints,
    this.buttonConstraints,
    this.useRootNavigator = false,
    this.barrierDismissible = true,
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
  final ButtonStyle? style;
  final bool enabled;
  final BoxConstraints? constraints;
  final BoxConstraints? buttonConstraints;
  final bool useRootNavigator;
  final bool barrierDismissible;

  @override
  State<AnimatedPopupMenuButton<T>> createState() =>
      _AnimatedPopupMenuButtonState<T>();
}

class _AnimatedPopupMenuButtonState<T>
    extends State<AnimatedPopupMenuButton<T>> {
  bool _menuOpen = false;

  Future<void> _showMenu() async {
    if (!widget.enabled || _menuOpen) return;
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;

    _menuOpen = true;
    try {
      final value = await showAnimatedAnchoredPopupMenu<T>(
        context: context,
        items: items,
        initialValue: widget.initialValue,
        elevation: widget.elevation,
        color: widget.color,
        shape: widget.shape,
        constraints: widget.constraints,
        position: widget.position,
        offset: widget.offset,
        useRootNavigator: widget.useRootNavigator,
        barrierDismissible: widget.barrierDismissible,
      );
      if (!mounted) return;
      if (value == null) {
        widget.onCanceled?.call();
      } else {
        widget.onSelected?.call(value);
      }
    } finally {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) {
      final button = widget.style == null
          ? InkWell(
              onTap: widget.enabled ? _showMenu : null,
              borderRadius: BorderRadius.circular(kOpenHandRadius4),
              child: widget.child,
            )
          : TextButton(
              onPressed: widget.enabled ? _showMenu : null,
              style: widget.style,
              child: widget.child!,
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
        style: widget.style,
        onPressed: widget.enabled ? _showMenu : null,
      ),
    );
  }
}

RelativeRect? _resolveAnimatedMenuPosition({
  required RenderObject? anchorObject,
  required RenderObject? overlayObject,
  required PopupMenuPosition position,
  required Offset offset,
}) {
  if (anchorObject is! RenderBox ||
      overlayObject is! RenderBox ||
      !anchorObject.hasSize ||
      !overlayObject.hasSize) {
    return null;
  }
  final anchorRect = _animatedPopupMenuAnchorRect(
    button: anchorObject,
    overlay: overlayObject,
    position: position,
    offset: offset,
  );
  return RelativeRect.fromRect(anchorRect, Offset.zero & overlayObject.size);
}

Rect _animatedPopupMenuAnchorRect({
  required RenderBox button,
  required RenderBox overlay,
  required PopupMenuPosition position,
  required Offset offset,
}) {
  if (position == PopupMenuPosition.under) {
    final origin = button.localToGlobal(
      Offset(offset.dx, button.size.height + offset.dy),
      ancestor: overlay,
    );
    return Rect.fromLTWH(origin.dx, origin.dy, button.size.width, 0);
  }
  return Rect.fromPoints(
    button.localToGlobal(offset, ancestor: overlay),
    button.localToGlobal(
      button.size.bottomRight(Offset.zero) + offset,
      ancestor: overlay,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Material 默认值（基于 Flutter 框架简化）
// ─────────────────────────────────────────────────────────────────────────────

class _PopupMenuDefaultsM2 extends PopupMenuThemeData {
  const _PopupMenuDefaultsM2(this.context) : super(elevation: 8.0);

  final BuildContext context;

  @override
  Color? get color => Theme.of(context).cardColor;

  @override
  ShapeBorder? get shape =>
      const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius16);

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
  ShapeBorder? get shape =>
      const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius16);

  @override
  EdgeInsets? get menuPadding => const EdgeInsets.symmetric(vertical: 8);
}
