import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../model/workflow_definition.dart';

class WorkflowAnnotationCard extends StatefulWidget {
  const WorkflowAnnotationCard({
    super.key,
    required this.annotation,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    required this.onMove,
    required this.onResize,
    required this.onDuplicate,
    required this.onDelete,
    required this.onEditingChanged,
  });

  final WorkflowAnnotation annotation;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<WorkflowAnnotation> onChanged;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEditingChanged;

  @override
  State<WorkflowAnnotationCard> createState() => _WorkflowAnnotationCardState();
}

class _WorkflowAnnotationCardState extends State<WorkflowAnnotationCard> {
  late final _WorkflowAnnotationTextController _controller =
      _WorkflowAnnotationTextController(
        text: widget.annotation.text,
        annotation: widget.annotation,
      );
  final FocusNode _focusNode = FocusNode(debugLabel: 'workflow-annotation');
  bool _visible = false;
  bool _syncingController = false;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _lastText = _controller.text;
    _controller.addListener(_handleControllerChanged);
    _focusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
      if (widget.selected) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant WorkflowAnnotationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.annotation = widget.annotation;
    if (_controller.text != widget.annotation.text) {
      final offset = _controller.selection.extentOffset.clamp(
        0,
        widget.annotation.text.length,
      );
      _syncingController = true;
      try {
        _controller.value = TextEditingValue(
          text: widget.annotation.text,
          selection: TextSelection.collapsed(offset: offset),
        );
      } finally {
        _syncingController = false;
      }
      _lastText = widget.annotation.text;
    }
    if (!oldWidget.selected && widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else if (oldWidget.selected && !widget.selected) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() => widget.onEditingChanged(_focusNode.hasFocus);

  void _handleControllerChanged() {
    if (!mounted || _syncingController) return;
    setState(() {});
  }

  void _updateText(String value) {
    if (value.runes.length > kWorkflowAnnotationMaxCharacters) return;
    final ranges = _adjustStyleRangesForTextChange(
      widget.annotation.styleRanges,
      _lastText,
      value,
    );
    _lastText = value;
    widget.onChanged(
      widget.annotation.copyWith(text: value, styleRanges: ranges),
    );
  }

  void _applyTextStyle({
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? strikethrough,
  }) {
    final selection = _controller.selection;
    final textLength = _controller.text.length;
    final start = selection.start.clamp(0, textLength).toInt();
    final end = selection.end.clamp(0, textLength).toInt();
    final rangeStart = math.min(start, end);
    final rangeEnd = math.max(start, end);
    final nextRanges = _applyStyleToSelection(
      annotation: widget.annotation,
      start: rangeStart,
      end: rangeEnd,
      fontSize: fontSize,
      bold: bold,
      italic: italic,
      strikethrough: strikethrough,
    );
    widget.onChanged(widget.annotation.copyWith(styleRanges: nextRanges));
    _controller.annotation = widget.annotation.copyWith(
      styleRanges: nextRanges,
    );
    _focusNode.requestFocus();
  }

  _AnnotationResolvedStyle _selectionStyle() {
    final textLength = _controller.text.length;
    final selection = _controller.selection;
    final start = selection.start.clamp(0, textLength).toInt();
    final end = selection.end.clamp(0, textLength).toInt();
    return _resolveAnnotationStyleAt(widget.annotation, math.min(start, end));
  }

  void _toggleBullets() {
    final lines = _controller.text.split('\n');
    final populated = lines.where((line) => line.trim().isNotEmpty).toList();
    final remove =
        populated.isNotEmpty &&
        populated.every((line) => line.trimLeft().startsWith('• '));
    final next = lines
        .map((line) {
          if (line.trim().isEmpty) return line;
          if (remove) return line.replaceFirst(RegExp(r'^(\s*)•\s?'), r'$1');
          return line.trimLeft().startsWith('• ') ? line : '• $line';
        })
        .join('\n');
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _updateText(next);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _workflowAnnotationAccent(widget.annotation.theme, colors);
    final selectionStyle = _selectionStyle();
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: colors.onSurface,
      fontSize: selectionStyle.fontSize,
      fontWeight: selectionStyle.bold ? FontWeight.w800 : FontWeight.w500,
      fontStyle: selectionStyle.italic ? FontStyle.italic : FontStyle.normal,
      decoration: selectionStyle.strikethrough
          ? TextDecoration.lineThrough
          : TextDecoration.none,
      height: 1.45,
    );
    final background = Color.alphaBlend(
      accent.withValues(alpha: 0.13),
      colors.surfaceContainerLow,
    );
    return AnimatedScale(
      scale: _visible ? (widget.selected ? 1.012 : 1) : 0.94,
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: openHandMotionDuration(context, kOpenHandMotion180),
        curve: Curves.easeOutCubic,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: openHandMotionDuration(context, kOpenHandMotion180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: background,
                borderRadius: kOpenHandBorderRadius14,
                border: Border.all(
                  color: widget.selected
                      ? accent
                      : accent.withValues(alpha: 0.38),
                  width: widget.selected ? 2 : 1,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow.withValues(
                      alpha: widget.selected ? 0.17 : 0.09,
                    ),
                    blurRadius: widget.selected ? 24 : 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  MouseRegion(
                    key: ValueKey<String>(
                      'workflow-annotation-move-${widget.annotation.id}',
                    ),
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onSelect,
                      onPanStart: (_) => widget.onSelect(),
                      onPanUpdate: (details) => widget.onMove(details.delta),
                      child: Container(
                        height: 14,
                        color: accent.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion180,
                    ),
                    curve: Curves.easeOutCubic,
                    child: widget.selected
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: _AnnotationToolbar(
                                annotation: widget.annotation,
                                selectionStyle: selectionStyle,
                                onApplyTextStyle: _applyTextStyle,
                                onThemeChanged: (theme) => widget.onChanged(
                                  widget.annotation.copyWith(theme: theme),
                                ),
                                onToggleBullets: _toggleBullets,
                                onDuplicate: widget.onDuplicate,
                                onDelete: widget.onDelete,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey<String>(
                        'workflow-annotation-input-${widget.annotation.id}',
                      ),
                      controller: _controller,
                      focusNode: _focusNode,
                      readOnly: !widget.selected,
                      expands: true,
                      maxLines: null,
                      maxLength: kWorkflowAnnotationMaxCharacters,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      onTap: widget.onSelect,
                      onChanged: _updateText,
                      style: textStyle,
                      decoration: InputDecoration(
                        hintText: '写下说明、约束或协作提示…',
                        hintStyle: TextStyle(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(
                          18,
                          15,
                          18,
                          18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.selected)
              Positioned(
                right: 2,
                bottom: 2,
                child: MouseRegion(
                  key: ValueKey<String>(
                    'workflow-annotation-resize-${widget.annotation.id}',
                  ),
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => widget.onResize(details.delta),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.south_east_rounded,
                        size: 17,
                        color: accent.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowAnnotationTextController extends TextEditingController {
  _WorkflowAnnotationTextController({
    required super.text,
    required this.annotation,
  });

  WorkflowAnnotation annotation;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) return TextSpan(text: text, style: style);
    final boundaries = <int>{0, text.length};
    for (final range in annotation.styleRanges) {
      boundaries
        ..add(range.start.clamp(0, text.length).toInt())
        ..add(range.end.clamp(0, text.length).toInt());
    }
    final composing = value.composing;
    if (withComposing && composing.isValid) {
      boundaries
        ..add(composing.start.clamp(0, text.length).toInt())
        ..add(composing.end.clamp(0, text.length).toInt());
    }
    final points = boundaries.toList()..sort();
    return TextSpan(
      style: style,
      children: <InlineSpan>[
        for (var index = 0; index < points.length - 1; index++)
          _buildStyledSpan(
            start: points[index],
            end: points[index + 1],
            style: style,
            composing: withComposing ? composing : TextRange.empty,
          ),
      ],
    );
  }

  TextSpan _buildStyledSpan({
    required int start,
    required int end,
    required TextStyle? style,
    required TextRange composing,
  }) {
    final resolved = _resolveAnnotationStyleAt(annotation, start);
    final overlapsComposing =
        composing.isValid && start < composing.end && end > composing.start;
    return TextSpan(
      text: text.substring(start, end),
      style: (style ?? const TextStyle()).copyWith(
        fontSize: resolved.fontSize,
        fontWeight: resolved.bold ? FontWeight.w800 : FontWeight.w500,
        fontStyle: resolved.italic ? FontStyle.italic : FontStyle.normal,
        decoration: overlapsComposing
            ? TextDecoration.combine(<TextDecoration>[
                if (resolved.strikethrough) TextDecoration.lineThrough,
                TextDecoration.underline,
              ])
            : resolved.strikethrough
            ? TextDecoration.lineThrough
            : TextDecoration.none,
      ),
    );
  }
}

class _AnnotationResolvedStyle {
  const _AnnotationResolvedStyle({
    required this.fontSize,
    required this.bold,
    required this.italic,
    required this.strikethrough,
  });

  final double fontSize;
  final bool bold;
  final bool italic;
  final bool strikethrough;

  _AnnotationResolvedStyle copyWith({
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? strikethrough,
  }) => _AnnotationResolvedStyle(
    fontSize: fontSize ?? this.fontSize,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strikethrough: strikethrough ?? this.strikethrough,
  );
}

_AnnotationResolvedStyle _resolveAnnotationStyleAt(
  WorkflowAnnotation annotation,
  int offset,
) {
  var style = _AnnotationResolvedStyle(
    fontSize: annotation.fontSize,
    bold: annotation.bold,
    italic: annotation.italic,
    strikethrough: annotation.strikethrough,
  );
  for (final range in annotation.styleRanges) {
    final contains = range.start == range.end
        ? offset == range.start
        : offset >= range.start && offset < range.end;
    if (!contains) continue;
    style = style.copyWith(
      fontSize: range.fontSize,
      bold: range.bold,
      italic: range.italic,
      strikethrough: range.strikethrough,
    );
  }
  return style;
}

List<WorkflowAnnotationTextStyleRange> _applyStyleToSelection({
  required WorkflowAnnotation annotation,
  required int start,
  required int end,
  double? fontSize,
  bool? bold,
  bool? italic,
  bool? strikethrough,
}) {
  final ranges = <WorkflowAnnotationTextStyleRange>[];
  final selected = start != end;
  for (final range in annotation.styleRanges) {
    final overlaps = selected
        ? (range.start == range.end
              ? range.start >= start && range.start <= end
              : range.start < end && range.end > start)
        : range.start == start && range.end == start;
    if (!overlaps) {
      ranges.add(range);
      continue;
    }
    if (range.start < start) ranges.add(range.copyWith(end: start));
    if (range.end > end) ranges.add(range.copyWith(start: end));
  }

  if (!selected) {
    ranges.add(
      _styleRange(
        start: start,
        end: end,
        style: _resolveAnnotationStyleAt(annotation, start).copyWith(
          fontSize: fontSize,
          bold: bold,
          italic: italic,
          strikethrough: strikethrough,
        ),
      ),
    );
    return _mergeStyleRanges(ranges);
  }

  final boundaries = <int>{start, end};
  for (final range in annotation.styleRanges) {
    if (range.start > start && range.start < end) boundaries.add(range.start);
    if (range.end > start && range.end < end) boundaries.add(range.end);
  }
  final points = boundaries.toList()..sort();
  for (var index = 0; index < points.length - 1; index++) {
    ranges.add(
      _styleRange(
        start: points[index],
        end: points[index + 1],
        style: _resolveAnnotationStyleAt(annotation, points[index]).copyWith(
          fontSize: fontSize,
          bold: bold,
          italic: italic,
          strikethrough: strikethrough,
        ),
      ),
    );
  }
  return _mergeStyleRanges(ranges);
}

WorkflowAnnotationTextStyleRange _styleRange({
  required int start,
  required int end,
  required _AnnotationResolvedStyle style,
}) => WorkflowAnnotationTextStyleRange(
  start: start,
  end: end,
  fontSize: style.fontSize,
  bold: style.bold,
  italic: style.italic,
  strikethrough: style.strikethrough,
);

List<WorkflowAnnotationTextStyleRange> _adjustStyleRangesForTextChange(
  Iterable<WorkflowAnnotationTextStyleRange> ranges,
  String previous,
  String next,
) {
  if (previous == next) {
    return List<WorkflowAnnotationTextStyleRange>.of(ranges);
  }
  var prefix = 0;
  final prefixLimit = math.min(previous.length, next.length);
  while (prefix < prefixLimit &&
      previous.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  final suffixLimit = math.min(previous.length - prefix, next.length - prefix);
  while (suffix < suffixLimit &&
      previous.codeUnitAt(previous.length - suffix - 1) ==
          next.codeUnitAt(next.length - suffix - 1)) {
    suffix++;
  }
  final previousEnd = previous.length - suffix;
  final nextEnd = next.length - suffix;
  final delta = next.length - previous.length;
  final insertion = previousEnd == prefix && nextEnd > prefix;
  final adjusted = <WorkflowAnnotationTextStyleRange>[];

  for (final range in ranges) {
    if (range.start == range.end && range.start == prefix && insertion) {
      adjusted.add(range.copyWith(end: nextEnd));
      continue;
    }
    if (range.end <= prefix) {
      adjusted.add(range);
      continue;
    }
    if (range.start >= previousEnd) {
      adjusted.add(
        range.copyWith(start: range.start + delta, end: range.end + delta),
      );
      continue;
    }
    if (insertion && range.start < prefix && range.end > prefix) {
      adjusted.add(range.copyWith(end: range.end + delta));
      continue;
    }
    if (range.start < prefix) {
      adjusted.add(range.copyWith(end: prefix));
    }
    if (range.end > previousEnd) {
      adjusted.add(range.copyWith(start: nextEnd, end: range.end + delta));
    }
  }
  return _mergeStyleRanges(adjusted);
}

List<WorkflowAnnotationTextStyleRange> _mergeStyleRanges(
  Iterable<WorkflowAnnotationTextStyleRange> ranges,
) {
  final sorted = ranges.toList()
    ..sort((a, b) {
      final startOrder = a.start.compareTo(b.start);
      return startOrder != 0 ? startOrder : a.end.compareTo(b.end);
    });
  final merged = <WorkflowAnnotationTextStyleRange>[];
  for (final range in sorted) {
    final previous = merged.isEmpty ? null : merged.last;
    if (previous != null &&
        previous.end == range.start &&
        previous.fontSize == range.fontSize &&
        previous.bold == range.bold &&
        previous.italic == range.italic &&
        previous.strikethrough == range.strikethrough) {
      merged[merged.length - 1] = previous.copyWith(end: range.end);
    } else {
      merged.add(range);
    }
  }
  return merged;
}

class _AnnotationToolbar extends StatelessWidget {
  const _AnnotationToolbar({
    required this.annotation,
    required this.selectionStyle,
    required this.onApplyTextStyle,
    required this.onThemeChanged,
    required this.onToggleBullets,
    required this.onDuplicate,
    required this.onDelete,
  });

  final WorkflowAnnotation annotation;
  final _AnnotationResolvedStyle selectionStyle;
  final void Function({
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? strikethrough,
  })
  onApplyTextStyle;
  final ValueChanged<WorkflowAnnotationTheme> onThemeChanged;
  final VoidCallback onToggleBullets;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _workflowAnnotationAccent(annotation.theme, colors);
    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 7,
      shadowColor: colors.shadow.withValues(alpha: 0.18),
      borderRadius: kOpenHandBorderRadius12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedPopupMenuButton<WorkflowAnnotationTheme>(
              key: ValueKey<String>(
                'workflow-annotation-theme-${annotation.id}',
              ),
              tooltip: '注释配色',
              icon: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
              padding: EdgeInsets.zero,
              style: _toolbarButtonStyle,
              shape: const RoundedRectangleBorder(
                borderRadius: kOpenHandBorderRadius12,
              ),
              onSelected: onThemeChanged,
              itemBuilder: (_) => WorkflowAnnotationTheme.values
                  .map(
                    (theme) => PopupMenuItem<WorkflowAnnotationTheme>(
                      value: theme,
                      height: 42,
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: _workflowAnnotationAccent(theme, colors),
                              shape: BoxShape.circle,
                            ),
                          ),
                          kOpenHandHGap10,
                          Text(theme.label),
                          const Spacer(),
                          if (theme == annotation.theme)
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: colors.primary,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            _ToolbarDivider(color: colors.outlineVariant),
            AnimatedPopupMenuButton<double>(
              key: ValueKey<String>(
                'workflow-annotation-size-${annotation.id}',
              ),
              tooltip: '文字大小',
              icon: Text(
                'Aa',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              padding: EdgeInsets.zero,
              style: _toolbarButtonStyle,
              shape: const RoundedRectangleBorder(
                borderRadius: kOpenHandBorderRadius12,
              ),
              onSelected: (size) => onApplyTextStyle(fontSize: size),
              itemBuilder: (_) =>
                  const <(double, String)>[
                        (14, '小号'),
                        (18, '正文'),
                        (22, '标题'),
                        (28, '大标题'),
                      ]
                      .map(
                        (item) => PopupMenuItem<double>(
                          value: item.$1,
                          child: Text(
                            item.$2,
                            style: TextStyle(fontSize: item.$1),
                          ),
                        ),
                      )
                      .toList(growable: false),
            ),
            _ToolbarDivider(color: colors.outlineVariant),
            _AnnotationToolbarButton(
              tooltip: '粗体',
              icon: Icons.format_bold_rounded,
              selected: selectionStyle.bold,
              onPressed: () => onApplyTextStyle(bold: !selectionStyle.bold),
            ),
            _AnnotationToolbarButton(
              tooltip: '斜体',
              icon: Icons.format_italic_rounded,
              selected: selectionStyle.italic,
              onPressed: () => onApplyTextStyle(italic: !selectionStyle.italic),
            ),
            _AnnotationToolbarButton(
              tooltip: '删除线',
              icon: Icons.format_strikethrough_rounded,
              selected: selectionStyle.strikethrough,
              onPressed: () => onApplyTextStyle(
                strikethrough: !selectionStyle.strikethrough,
              ),
            ),
            _AnnotationToolbarButton(
              tooltip: '项目符号',
              icon: Icons.format_list_bulleted_rounded,
              onPressed: onToggleBullets,
            ),
            _ToolbarDivider(color: colors.outlineVariant),
            AnimatedPopupMenuButton<String>(
              key: ValueKey<String>(
                'workflow-annotation-more-${annotation.id}',
              ),
              tooltip: '更多操作',
              icon: const Icon(Icons.more_horiz_rounded, size: 19),
              padding: EdgeInsets.zero,
              style: _toolbarButtonStyle,
              shape: const RoundedRectangleBorder(
                borderRadius: kOpenHandBorderRadius12,
              ),
              onSelected: (action) {
                if (action == 'duplicate') onDuplicate();
                if (action == 'delete') onDelete();
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'duplicate',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_rounded),
                    title: Text('复制注释'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('删除注释'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnotationToolbarButton extends StatelessWidget {
  const _AnnotationToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        style: _toolbarButtonStyle.copyWith(
          backgroundColor: WidgetStatePropertyAll<Color?>(
            selected ? colors.primaryContainer : Colors.transparent,
          ),
          foregroundColor: WidgetStatePropertyAll<Color?>(
            selected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: color,
  );
}

ButtonStyle get _toolbarButtonStyle => IconButton.styleFrom(
  fixedSize: const Size.square(36),
  padding: EdgeInsets.zero,
  backgroundColor: Colors.transparent,
  shape: const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius10),
);

Color _workflowAnnotationAccent(
  WorkflowAnnotationTheme theme,
  ColorScheme colors,
) => theme == WorkflowAnnotationTheme.blue
    ? colors.primary
    : Color(theme.accentColorValue);
