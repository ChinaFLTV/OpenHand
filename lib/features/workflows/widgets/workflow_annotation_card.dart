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
  late final TextEditingController _controller = TextEditingController(
    text: widget.annotation.text,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'workflow-annotation');
  bool _visible = false;

  @override
  void initState() {
    super.initState();
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
    if (_controller.text != widget.annotation.text) {
      final offset = _controller.selection.extentOffset.clamp(
        0,
        widget.annotation.text.length,
      );
      _controller.value = TextEditingValue(
        text: widget.annotation.text,
        selection: TextSelection.collapsed(offset: offset),
      );
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
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() => widget.onEditingChanged(_focusNode.hasFocus);

  void _updateText(String value) {
    if (value.runes.length > kWorkflowAnnotationMaxCharacters) return;
    widget.onChanged(widget.annotation.copyWith(text: value));
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
                                onChanged: widget.onChanged,
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurface,
                        fontSize: widget.annotation.fontSize,
                        fontWeight: widget.annotation.bold
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontStyle: widget.annotation.italic
                            ? FontStyle.italic
                            : FontStyle.normal,
                        decoration: widget.annotation.strikethrough
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        height: 1.45,
                      ),
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

class _AnnotationToolbar extends StatelessWidget {
  const _AnnotationToolbar({
    required this.annotation,
    required this.onChanged,
    required this.onToggleBullets,
    required this.onDuplicate,
    required this.onDelete,
  });

  final WorkflowAnnotation annotation;
  final ValueChanged<WorkflowAnnotation> onChanged;
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
              onSelected: (theme) =>
                  onChanged(annotation.copyWith(theme: theme)),
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
              onSelected: (size) =>
                  onChanged(annotation.copyWith(fontSize: size)),
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
              selected: annotation.bold,
              onPressed: () =>
                  onChanged(annotation.copyWith(bold: !annotation.bold)),
            ),
            _AnnotationToolbarButton(
              tooltip: '斜体',
              icon: Icons.format_italic_rounded,
              selected: annotation.italic,
              onPressed: () =>
                  onChanged(annotation.copyWith(italic: !annotation.italic)),
            ),
            _AnnotationToolbarButton(
              tooltip: '删除线',
              icon: Icons.format_strikethrough_rounded,
              selected: annotation.strikethrough,
              onPressed: () => onChanged(
                annotation.copyWith(strikethrough: !annotation.strikethrough),
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
