import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'hover_lift.dart';
import 'micro_press_feedback.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_spacing.dart';

const int kOpenHandTableDefaultPageSize = 20;
const int kOpenHandTableMinPageSize = 1;
const int kOpenHandTableMaxPageSize = 200;
const int kOpenHandTablePagerCount = 7;
const double kOpenHandTablePagerButtonSize = 32;
const double kOpenHandTableJumperWidth = 48;
const double kOpenHandTablePagerGap = 6;
const double kOpenHandTablePagerClusterGap = 12;
const double kOpenHandTablePagerStackBreakpoint = 560;
const List<int> kOpenHandTablePageSizes = <int>[10, 20, 50, 100];
const int _kOpenHandPagerEllipsis = -1;

/// 分页窗口：1 基页码、偏移与切片。
final class OpenHandPageWindow {
  const OpenHandPageWindow({
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final int page;
  final int pageSize;
  final int total;

  int get pageCount => total <= 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);

  int get offset => (page - 1) * pageSize;

  List<T> slice<T>(List<T> items) {
    if (items.isEmpty) return items;
    final start = offset.clamp(0, items.length);
    final end = (start + pageSize).clamp(0, items.length);
    if (start >= end) return const [];
    return items.sublist(start, end);
  }

  static int clampPageSize(int pageSize) {
    if (pageSize < kOpenHandTableMinPageSize) {
      return kOpenHandTableDefaultPageSize;
    }
    if (pageSize > kOpenHandTableMaxPageSize) {
      return kOpenHandTableMaxPageSize;
    }
    return pageSize;
  }

  static OpenHandPageWindow normalize({
    required int page,
    required int pageSize,
    required int total,
  }) {
    final safeTotal = total < 0 ? 0 : total;
    final size = clampPageSize(pageSize);
    final count = safeTotal <= 0 ? 1 : ((safeTotal + size - 1) ~/ size);
    var nextPage = page;
    if (nextPage < 1) nextPage = 1;
    if (nextPage > count) nextPage = count;
    return OpenHandPageWindow(page: nextPage, pageSize: size, total: safeTotal);
  }

  /// Element Plus 风格页码：首页、尾页、当前页邻域、省略号。
  static List<int> pagerItems({
    required int currentPage,
    required int pageCount,
    int maxButtons = kOpenHandTablePagerCount,
  }) {
    if (pageCount <= 0) return const <int>[1];
    if (maxButtons < 5) maxButtons = 5;
    if (pageCount <= maxButtons) {
      return <int>[for (var i = 1; i <= pageCount; i++) i];
    }
    final items = <int>[1];
    if (currentPage <= 4) {
      final end = maxButtons - 2;
      for (var i = 2; i <= end; i++) {
        items.add(i);
      }
      items
        ..add(_kOpenHandPagerEllipsis)
        ..add(pageCount);
      return items;
    }
    if (currentPage >= pageCount - 3) {
      items.add(_kOpenHandPagerEllipsis);
      final start = pageCount - (maxButtons - 3);
      for (var i = start < 2 ? 2 : start; i <= pageCount; i++) {
        items.add(i);
      }
      return items;
    }
    items
      ..add(_kOpenHandPagerEllipsis)
      ..add(currentPage - 1)
      ..add(currentPage)
      ..add(currentPage + 1)
      ..add(_kOpenHandPagerEllipsis)
      ..add(pageCount);
    return items;
  }
}

typedef OpenHandPageFetch<T> =
    Future<(int total, List<T> items)> Function({
      required int offset,
      required int limit,
    });

/// 远程/DB 分页：先按请求页拉取，总数不足时回退到最后一页。
Future<(List<T> items, OpenHandPageWindow window)> openHandFetchPage<T>({
  required int page,
  required int pageSize,
  required OpenHandPageFetch<T> fetch,
}) async {
  final size = OpenHandPageWindow.clampPageSize(pageSize);
  final requestedPage = page < 1 ? 1 : page;
  var result = await fetch(offset: (requestedPage - 1) * size, limit: size);
  var window = OpenHandPageWindow.normalize(
    page: requestedPage,
    pageSize: size,
    total: result.$1,
  );
  if (window.page != requestedPage && result.$1 > 0) {
    result = await fetch(offset: window.offset, limit: window.pageSize);
    window = OpenHandPageWindow.normalize(
      page: window.page,
      pageSize: window.pageSize,
      total: result.$1,
    );
  }
  return (result.$2, window);
}

/// 内存列表的分页外壳：切片 + 底部分页条。
class OpenHandClientPager<T> extends StatefulWidget {
  const OpenHandClientPager({
    super.key,
    required this.items,
    required this.builder,
    this.initialPageSize = kOpenHandTableDefaultPageSize,
    this.pageSizes = kOpenHandTablePageSizes,
    this.enabled = true,
    this.padding,
    this.showWhenEmpty = false,
    this.expand = false,
    this.bar = false,
  });

  final List<T> items;
  final Widget Function(BuildContext context, List<T> pageItems) builder;
  final int initialPageSize;
  final List<int> pageSizes;
  final bool enabled;
  final EdgeInsetsGeometry? padding;
  final bool showWhenEmpty;
  final bool expand;
  final bool bar;

  @override
  State<OpenHandClientPager<T>> createState() => _OpenHandClientPagerState<T>();
}

class _OpenHandClientPagerState<T> extends State<OpenHandClientPager<T>> {
  late int _page = 1;
  late int _pageSize = widget.initialPageSize;

  OpenHandPageWindow get _window => OpenHandPageWindow.normalize(
    page: _page,
    pageSize: _pageSize,
    total: widget.items.length,
  );

  @override
  void didUpdateWidget(covariant OpenHandClientPager<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPageSize != widget.initialPageSize &&
        _pageSize == oldWidget.initialPageSize) {
      _pageSize = widget.initialPageSize;
    }
    final window = _window;
    _page = window.page;
    _pageSize = window.pageSize;
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final pageItems = window.slice(widget.items);
    final showPager = widget.items.isNotEmpty || widget.showWhenEmpty;
    void goToPage(int page) => setState(() => _page = page);
    void changePageSize(int size) => setState(() {
      _pageSize = size;
      _page = 1;
    });
    Widget list = KeyedSubtree(
      key: ValueKey<String>('oh-page-${window.page}-${window.pageSize}'),
      child: widget.builder(context, pageItems),
    );
    if (widget.expand) {
      list = Expanded(child: list);
    }
    return Column(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        list,
        if (showPager)
          widget.bar
              ? OpenHandTablePaginationBar(
                  total: window.total,
                  page: window.page,
                  pageSize: window.pageSize,
                  pageSizes: widget.pageSizes,
                  enabled: widget.enabled,
                  onPageChanged: goToPage,
                  onPageSizeChanged: changePageSize,
                )
              : Padding(
                  padding: widget.padding ?? const EdgeInsets.only(top: 10),
                  child: OpenHandTablePagination(
                    total: window.total,
                    page: window.page,
                    pageSize: window.pageSize,
                    pageSizes: widget.pageSizes,
                    enabled: widget.enabled,
                    onPageChanged: goToPage,
                    onPageSizeChanged: changePageSize,
                  ),
                ),
      ],
    );
  }
}

/// 贴在表格圆角容器底部的分页条。
class OpenHandTablePaginationBar extends StatelessWidget {
  const OpenHandTablePaginationBar({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
    this.onPageSizeChanged,
    this.pageSizes = kOpenHandTablePageSizes,
    this.enabled = true,
    this.showPageNumbers = true,
    this.showJumper = true,
    this.showPageSize = true,
    this.showTotal = true,
    this.canPrevious,
    this.canNext,
    this.onPrevious,
    this.onNext,
    this.leading,
  });

  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final List<int> pageSizes;
  final bool enabled;
  final bool showPageNumbers;
  final bool showJumper;
  final bool showPageSize;
  final bool showTotal;
  final bool? canPrevious;
  final bool? canNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: 0.72),
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: OpenHandTablePagination(
            total: total,
            page: page,
            pageSize: pageSize,
            onPageChanged: onPageChanged,
            onPageSizeChanged: onPageSizeChanged,
            pageSizes: pageSizes,
            enabled: enabled,
            showPageNumbers: showPageNumbers,
            showJumper: showJumper,
            showPageSize: showPageSize,
            showTotal: showTotal,
            canPrevious: canPrevious,
            canNext: canNext,
            onPrevious: onPrevious,
            onNext: onNext,
            leading: leading,
          ),
        ),
      ),
    );
  }
}

/// Element Plus 风格分页器，配色跟随当前主题。
class OpenHandTablePagination extends StatefulWidget {
  const OpenHandTablePagination({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
    this.onPageSizeChanged,
    this.pageSizes = kOpenHandTablePageSizes,
    this.enabled = true,
    this.showPageNumbers = true,
    this.showJumper = true,
    this.showPageSize = true,
    this.showTotal = true,
    this.canPrevious,
    this.canNext,
    this.onPrevious,
    this.onNext,
    this.leading,
  });

  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final List<int> pageSizes;
  final bool enabled;
  final bool showPageNumbers;
  final bool showJumper;
  final bool showPageSize;
  final bool showTotal;
  final bool? canPrevious;
  final bool? canNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Widget? leading;

  @override
  State<OpenHandTablePagination> createState() =>
      _OpenHandTablePaginationState();
}

class _OpenHandTablePaginationState extends State<OpenHandTablePagination> {
  final TextEditingController _jumper = TextEditingController();
  final FocusNode _jumperFocus = FocusNode();

  OpenHandPageWindow get _window => OpenHandPageWindow.normalize(
    page: widget.page,
    pageSize: widget.pageSize,
    total: widget.total,
  );

  @override
  void initState() {
    super.initState();
    _jumper.text = '${_window.page}';
    _jumperFocus.addListener(_handleJumperFocus);
  }

  @override
  void didUpdateWidget(covariant OpenHandTablePagination oldWidget) {
    super.didUpdateWidget(oldWidget);
    final window = _window;
    if (!_jumperFocus.hasFocus && _jumper.text != '${window.page}') {
      _jumper.text = '${window.page}';
    }
  }

  @override
  void dispose() {
    _jumperFocus.removeListener(_handleJumperFocus);
    _jumperFocus.dispose();
    _jumper.dispose();
    super.dispose();
  }

  void _handleJumperFocus() {
    if (mounted) setState(() {});
    _syncJumperOnBlur();
  }

  void _syncJumperOnBlur() {
    if (_jumperFocus.hasFocus) return;
    final window = _window;
    if (_jumper.text != '${window.page}') {
      _jumper.text = '${window.page}';
    }
  }

  void _go(int page) {
    if (!widget.enabled) return;
    final window = OpenHandPageWindow.normalize(
      page: page,
      pageSize: widget.pageSize,
      total: widget.total,
    );
    if (window.page == _window.page) return;
    widget.onPageChanged(window.page);
  }

  void _submitJumper() {
    final parsed = int.tryParse(_jumper.text.trim());
    if (parsed == null) {
      _jumper.text = '${_window.page}';
      return;
    }
    _go(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final window = _window;
    final pageCount = window.pageCount;
    final canPrevious =
        widget.enabled && (widget.canPrevious ?? window.page > 1);
    final canNext =
        widget.enabled && (widget.canNext ?? window.page < pageCount);
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final sizes = <int>{
      ...widget.pageSizes.where(
        (size) =>
            size >= kOpenHandTableMinPageSize &&
            size <= kOpenHandTableMaxPageSize,
      ),
      window.pageSize,
    }.toList()..sort();

    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      height: 1,
    );
    final left = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: kOpenHandTablePagerClusterGap),
        ],
        _PagerIconButton(
          tooltip: text(zh: '上一页', en: 'Previous'),
          icon: Icons.chevron_left_rounded,
          enabled: canPrevious,
          onPressed: () {
            if (widget.onPrevious != null) {
              widget.onPrevious!();
              return;
            }
            _go(window.page - 1);
          },
        ),
        if (widget.showPageNumbers) ...[
          for (final item in OpenHandPageWindow.pagerItems(
            currentPage: window.page,
            pageCount: pageCount,
          )) ...[
            const SizedBox(width: kOpenHandTablePagerGap),
            if (item == _kOpenHandPagerEllipsis)
              SizedBox(
                width: 22,
                height: kOpenHandTablePagerButtonSize,
                child: Center(
                  child: Text(
                    '…',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              )
            else
              _PagerNumberButton(
                page: item,
                selected: item == window.page,
                enabled: widget.enabled,
                duration: duration,
                onPressed: () => _go(item),
              ),
          ],
        ],
        const SizedBox(width: kOpenHandTablePagerGap),
        _PagerIconButton(
          tooltip: text(zh: '下一页', en: 'Next'),
          icon: Icons.chevron_right_rounded,
          enabled: canNext,
          onPressed: () {
            if (widget.onNext != null) {
              widget.onNext!();
              return;
            }
            _go(window.page + 1);
          },
        ),
      ],
    );
    final rightChildren = <Widget>[
      if (widget.showPageSize && widget.onPageSizeChanged != null)
        _PageSizeSelect(
          value: window.pageSize,
          sizes: sizes,
          enabled: widget.enabled,
          labelBuilder: (size) => text(zh: '$size 条/页', en: '$size / page'),
          onChanged: (size) {
            if (size == window.pageSize) return;
            widget.onPageSizeChanged!(size);
          },
        ),
      if (widget.showJumper) ...[
        Text(
          text(zh: '前往', en: 'Go to'),
          style: labelStyle,
        ),
        AnimatedContainer(
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          width: kOpenHandTableJumperWidth,
          height: kOpenHandTablePagerButtonSize,
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: kOpenHandBorderRadius8,
            border: Border.all(
              color: _jumperFocus.hasFocus
                  ? colors.primary
                  : colors.outlineVariant,
              width: _jumperFocus.hasFocus ? 1.4 : 1,
            ),
          ),
          child: TextField(
            controller: _jumper,
            focusNode: _jumperFocus,
            enabled: widget.enabled,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submitJumper(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              isDense: true,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ),
        Text(
          text(zh: '页', en: 'page'),
          style: labelStyle,
        ),
      ],
      if (widget.showTotal)
        Text(
          text(zh: '共 ${window.total} 条', en: '${window.total} total'),
          style: labelStyle?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
    ];
    final right = rightChildren.isEmpty
        ? const SizedBox.shrink()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rightChildren.length; i++) ...[
                if (i > 0) const SizedBox(width: kOpenHandTablePagerGap),
                rightChildren[i],
              ],
            ],
          );
    return _PagerSplitBar(left: left, right: right);
  }
}

class _PagerSplitBar extends StatelessWidget {
  const _PagerSplitBar({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              left,
              const SizedBox(width: kOpenHandTablePagerClusterGap),
              right,
            ],
          );
        }
        if (constraints.maxWidth < kOpenHandTablePagerStackBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: left),
              const SizedBox(height: kOpenHandTablePagerGap),
              Align(alignment: Alignment.centerRight, child: right),
            ],
          );
        }
        return SizedBox(
          width: constraints.maxWidth,
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: left,
                  ),
                ),
              ),
              const SizedBox(width: kOpenHandTablePagerClusterGap),
              right,
            ],
          ),
        );
      },
    );
  }
}

class _PageSizeSelect extends StatefulWidget {
  const _PageSizeSelect({
    required this.value,
    required this.sizes,
    required this.enabled,
    required this.labelBuilder,
    required this.onChanged,
  });

  final int value;
  final List<int> sizes;
  final bool enabled;
  final String Function(int size) labelBuilder;
  final ValueChanged<int> onChanged;

  @override
  State<_PageSizeSelect> createState() => _PageSizeSelectState();
}

class _PageSizeSelectState extends State<_PageSizeSelect> {
  bool _open = false;

  Future<void> _pick() async {
    if (!widget.enabled || _open) return;
    _open = true;
    try {
      final next = await showAnimatedAnchoredPopupMenu<int>(
        context: context,
        items: [
          for (final size in widget.sizes)
            PopupMenuItem<int>(
              value: size,
              height: kOpenHandTablePagerButtonSize + 12,
              child: Text(widget.labelBuilder(size)),
            ),
        ],
        initialValue: widget.value,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
      );
      if (!mounted || next == null || next == widget.value) return;
      widget.onChanged(next);
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = widget.labelBuilder(widget.value);
    return Tooltip(
      message: label,
      child: HoverLift(
        liftDistance: 1.5,
        child: MicroPressFeedback(
          enabled: widget.enabled,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.enabled ? _pick : null,
              borderRadius: kOpenHandBorderRadius8,
              child: AnimatedContainer(
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                curve: kOpenHandSwitchInCurve,
                height: kOpenHandTablePagerButtonSize,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: kOpenHandBorderRadius8,
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: widget.enabled
                            ? colors.onSurface
                            : colors.outline,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: widget.enabled
                          ? colors.onSurfaceVariant
                          : colors.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PagerIconButton extends StatelessWidget {
  const _PagerIconButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: _PagerChrome(
        selected: false,
        enabled: enabled,
        onPressed: onPressed,
        child: Icon(
          icon,
          size: 20,
          color: enabled ? colors.onSurface : colors.outline,
        ),
      ),
    );
  }
}

class _PagerNumberButton extends StatelessWidget {
  const _PagerNumberButton({
    required this.page,
    required this.selected,
    required this.enabled,
    required this.duration,
    required this.onPressed,
  });

  final int page;
  final bool selected;
  final bool enabled;
  final Duration duration;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$page',
      child: _PagerChrome(
        selected: selected,
        enabled: enabled,
        onPressed: onPressed,
        duration: duration,
        child: AnimatedDefaultTextStyle(
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
            color: selected ? colors.onPrimary : colors.onSurface,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: Text('$page'),
        ),
      ),
    );
  }
}

class _PagerChrome extends StatelessWidget {
  const _PagerChrome({
    required this.selected,
    required this.enabled,
    required this.onPressed,
    required this.child,
    this.duration,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final Widget child;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final motion =
        duration ?? openHandMotionDuration(context, kOpenHandMotion180);
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: kOpenHandBorderRadius8,
        child: AnimatedContainer(
          duration: motion,
          curve: kOpenHandSwitchInCurve,
          width: kOpenHandTablePagerButtonSize,
          height: kOpenHandTablePagerButtonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.surfaceContainerHighest,
            borderRadius: kOpenHandBorderRadius8,
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: child,
        ),
      ),
    );
    if (!enabled) return button;
    return HoverLift(
      liftDistance: selected ? 1 : 2,
      child: MicroPressFeedback(child: button),
    );
  }
}
