import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/animated_overlay.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../model/workflow_definition.dart';

const int _firstReferenceMarker = 0xE000;
const int _lastReferenceMarker = 0xF8FF;
const double _referenceMenuGap = 8;
const double _referenceMenuMargin = 12;

class WorkflowParameterReferenceField extends StatefulWidget {
  const WorkflowParameterReferenceField({
    super.key,
    required this.value,
    required this.references,
    required this.decoration,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String value;
  final List<WorkflowParameterReference> references;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;

  @override
  State<WorkflowParameterReferenceField> createState() =>
      _WorkflowParameterReferenceFieldState();
}

class _WorkflowParameterReferenceFieldState
    extends State<WorkflowParameterReferenceField> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  final AnimatedOverlayEntryController _overlay =
      AnimatedOverlayEntryController();
  late final _WorkflowReferenceEditingController _controller;
  late final FocusNode _focusNode = FocusNode()..addListener(_handleFocus);
  late TextEditingValue _previousValue;
  late String _lastSerializedText;
  bool _applyingExternalValue = false;
  int _selectedIndex = 0;
  int _triggerOffset = -1;

  @override
  void initState() {
    super.initState();
    _controller = _WorkflowReferenceEditingController(
      serializedText: widget.value,
      references: widget.references,
    )..addListener(_handleTextChanged);
    _previousValue = _controller.value;
    _lastSerializedText = _controller.serializedText;
  }

  @override
  void didUpdateWidget(covariant WorkflowParameterReferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyingExternalValue = true;
    _controller.updateReferences(widget.references);
    if (_controller.serializedText != widget.value) {
      _controller.replaceSerializedText(widget.value);
      _dismissMenu(immediately: true);
    }
    _previousValue = _controller.value;
    _lastSerializedText = _controller.serializedText;
    _applyingExternalValue = false;
    if (widget.references.isEmpty) {
      _dismissMenu();
    } else if (_selectedIndex >= widget.references.length) {
      _selectedIndex = widget.references.length - 1;
    }
  }

  @override
  void dispose() {
    _overlay.dispose();
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: CompositedTransformTarget(
        key: _anchorKey,
        link: _layerLink,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: widget.maxLines > 1
              ? TextInputType.multiline
              : TextInputType.text,
          textInputAction: widget.maxLines > 1
              ? TextInputAction.newline
              : TextInputAction.done,
          decoration: widget.decoration,
        ),
      ),
    );
  }

  void _handleTextChanged() {
    final next = _controller.value;
    final previous = _previousValue;
    _previousValue = next;
    if (_applyingExternalValue) return;
    final serializedText = _controller.serializedText;
    if (serializedText == _lastSerializedText) return;
    _lastSerializedText = serializedText;
    widget.onChanged(serializedText);

    if (_isSlashInsertion(previous, next) && widget.references.isNotEmpty) {
      _triggerOffset = next.selection.baseOffset - 1;
      _selectedIndex = 0;
      _showMenu();
      return;
    }
    if (_overlay.hasEntry) _dismissMenu();
  }

  bool _isSlashInsertion(TextEditingValue previous, TextEditingValue next) {
    if (!next.selection.isValid || !next.selection.isCollapsed) return false;
    final offset = next.selection.baseOffset;
    if (offset <= 0 || next.text.length != previous.text.length + 1) {
      return false;
    }
    final slashOffset = offset - 1;
    return next.text.codeUnitAt(slashOffset) == 0x2F &&
        next.text.substring(0, slashOffset) ==
            previous.text.substring(0, slashOffset) &&
        next.text.substring(offset) == previous.text.substring(slashOffset);
  }

  void _handleFocus() {
    if (!_focusNode.hasFocus) _dismissMenu();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_overlay.hasEntry) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (widget.references.isEmpty) {
        _dismissMenu();
        return KeyEventResult.handled;
      }
      _selectReference(widget.references[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSelection(int delta) {
    if (widget.references.isEmpty) return;
    _selectedIndex =
        (_selectedIndex + delta + widget.references.length) %
        widget.references.length;
    _overlay.markNeedsBuild();
  }

  void _selectReference(WorkflowParameterReference reference) {
    if (!_controller.insertReference(_triggerOffset, reference)) {
      _dismissMenu();
      return;
    }
    _dismissMenu();
    _focusNode.requestFocus();
  }

  void _showMenu() {
    _overlay.show(
      overlay: Overlay.of(context, rootOverlay: true),
      builder: (context, visibility, onExitCompleted) {
        return _WorkflowReferenceMenu(
          link: _layerLink,
          anchorKey: _anchorKey,
          references: widget.references,
          selectedIndex: _selectedIndex,
          visibility: visibility,
          onSelected: _selectReference,
          onDismiss: _dismissMenu,
          onExitCompleted: onExitCompleted,
        );
      },
    );
  }

  void _dismissMenu({bool immediately = false}) {
    _triggerOffset = -1;
    _overlay.close(immediately: immediately || !mounted);
  }
}

class _WorkflowReferenceEditingController extends TextEditingController {
  _WorkflowReferenceEditingController({
    required String serializedText,
    required List<WorkflowParameterReference> references,
  }) : _references = references {
    replaceSerializedText(serializedText);
  }

  List<WorkflowParameterReference> _references;
  final Map<int, String> _tokens = <int, String>{};
  int _nextMarker = _firstReferenceMarker;

  String get serializedText {
    final buffer = StringBuffer();
    for (final codeUnit in text.codeUnits) {
      final name = _tokens[codeUnit];
      buffer.write(
        name == null
            ? String.fromCharCode(codeUnit)
            : workflowParameterPlaceholder(name),
      );
    }
    return buffer.toString();
  }

  void updateReferences(List<WorkflowParameterReference> references) {
    if (_sameReferences(_references, references)) return;
    _references = references;
    notifyListeners();
  }

  void replaceSerializedText(String serializedText) {
    _tokens.clear();
    _nextMarker = _firstReferenceMarker;
    final encoded = _encode(serializedText);
    value = TextEditingValue(
      text: encoded,
      selection: TextSelection.collapsed(offset: encoded.length),
    );
  }

  bool _sameReferences(
    List<WorkflowParameterReference> current,
    List<WorkflowParameterReference> next,
  ) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      final left = current[index];
      final right = next[index];
      if (left.nodeId != right.nodeId ||
          left.nodeTitle != right.nodeTitle ||
          left.name != right.name ||
          left.field.type != right.field.type) {
        return false;
      }
    }
    return true;
  }

  bool insertReference(int slashOffset, WorkflowParameterReference reference) {
    if (slashOffset < 0 ||
        slashOffset >= text.length ||
        text.codeUnitAt(slashOffset) != 0x2F) {
      return false;
    }
    final marker = _allocateMarker(reference.name);
    if (marker == null) return false;
    final next = text.replaceRange(slashOffset, slashOffset + 1, marker);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: slashOffset + 1),
    );
    return true;
  }

  String _encode(String value) {
    if (value.isEmpty) return '';
    final buffer = StringBuffer();
    var offset = 0;
    for (final match in workflowTemplatePlaceholderPattern.allMatches(value)) {
      buffer.write(value.substring(offset, match.start));
      final name = match.group(1)!;
      final marker = _references.any((item) => item.name == name)
          ? _allocateMarker(name)
          : null;
      buffer.write(marker ?? match.group(0));
      offset = match.end;
    }
    buffer.write(value.substring(offset));
    return buffer.toString();
  }

  String? _allocateMarker(String name) {
    if (_nextMarker > _lastReferenceMarker) return null;
    final marker = _nextMarker++;
    _tokens[marker] = name;
    return String.fromCharCode(marker);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final children = <InlineSpan>[];
    final plainText = StringBuffer();

    void flushText() {
      if (plainText.isEmpty) return;
      children.add(TextSpan(text: plainText.toString(), style: style));
      plainText.clear();
    }

    for (final codeUnit in text.codeUnits) {
      final name = _tokens[codeUnit];
      if (name == null) {
        plainText.writeCharCode(codeUnit);
        continue;
      }
      flushText();
      final reference = _references
          .where((item) => item.name == name)
          .firstOrNull;
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _WorkflowReferenceToken(name: name, reference: reference),
        ),
      );
    }
    flushText();
    return TextSpan(style: style, children: children);
  }
}

class _WorkflowReferenceToken extends StatelessWidget {
  const _WorkflowReferenceToken({required this.name, required this.reference});

  final String name;
  final WorkflowParameterReference? reference;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final valid = reference != null;
    final color = valid ? colors.primary : colors.error;
    return Semantics(
      label: valid ? '引用参数 $name' : '无效参数引用 $name',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(kOpenHandRadius7),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          name,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

class _WorkflowReferenceMenu extends StatefulWidget {
  const _WorkflowReferenceMenu({
    required this.link,
    required this.anchorKey,
    required this.references,
    required this.selectedIndex,
    required this.visibility,
    required this.onSelected,
    required this.onDismiss,
    required this.onExitCompleted,
  });

  final LayerLink link;
  final GlobalKey anchorKey;
  final List<WorkflowParameterReference> references;
  final int selectedIndex;
  final ValueListenable<bool> visibility;
  final ValueChanged<WorkflowParameterReference> onSelected;
  final VoidCallback onDismiss;
  final VoidCallback onExitCompleted;

  @override
  State<_WorkflowReferenceMenu> createState() => _WorkflowReferenceMenuState();
}

class _WorkflowReferenceMenuState extends State<_WorkflowReferenceMenu> {
  static const double _itemExtent = 54;
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _WorkflowReferenceMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final itemTop = widget.selectedIndex * _itemExtent;
      final itemBottom = itemTop + _itemExtent;
      final viewportTop = _scrollController.offset;
      final viewportBottom = viewportTop + position.viewportDimension;
      final target = itemTop < viewportTop
          ? itemTop
          : itemBottom > viewportBottom
          ? itemBottom - position.viewportDimension
          : null;
      if (target == null) return;
      _scrollController.animateTo(
        target.clamp(0, position.maxScrollExtent),
        duration: kOpenHandMotion120,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _resolveMenuLayout(context, widget.anchorKey);
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          targetAnchor: layout.targetAnchor,
          followerAnchor: layout.followerAnchor,
          offset: layout.offset,
          child: TextFieldTapRegion(
            child: SizedBox(
              width: layout.width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: layout.maxHeight),
                child: AnimatedOverlayContent(
                  visibility: widget.visibility,
                  onExitCompleted: widget.onExitCompleted,
                  alignment: layout.followerAnchor,
                  child: Material(
                    elevation: 8,
                    color: theme.colorScheme.surfaceContainerHigh,
                    shadowColor: theme.colorScheme.shadow.withValues(
                      alpha: 0.22,
                    ),
                    borderRadius: BorderRadius.circular(kOpenHandRadius14),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.data_object_rounded,
                                size: 17,
                                color: theme.colorScheme.primary,
                              ),
                              kOpenHandHGap7,
                              Expanded(
                                child: Text(
                                  '引用上游参数',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                '↑↓ 选择  ↵ 确认',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                            shrinkWrap: true,
                            itemExtent: _itemExtent,
                            itemCount: widget.references.length,
                            itemBuilder: (context, index) {
                              final reference = widget.references[index];
                              final selected = index == widget.selectedIndex;
                              return Material(
                                color: selected
                                    ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.48)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  kOpenHandRadius10,
                                ),
                                child: InkWell(
                                  onTap: () => widget.onSelected(reference),
                                  borderRadius: BorderRadius.circular(
                                    kOpenHandRadius10,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              kOpenHandRadius8,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.code_rounded,
                                            size: 16,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        kOpenHandHGap9,
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                reference.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              Text(
                                                '${reference.nodeTitle} · ${reference.field.type.storageValue}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

({
  Alignment targetAnchor,
  Alignment followerAnchor,
  Offset offset,
  double width,
  double maxHeight,
})
_resolveMenuLayout(BuildContext context, GlobalKey anchorKey) {
  final anchor = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()
          as RenderBox?;
  if (anchor == null ||
      overlay == null ||
      !anchor.hasSize ||
      !overlay.hasSize) {
    return (
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, _referenceMenuGap),
      width: 320,
      maxHeight: 280,
    );
  }
  final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final overlaySize = overlay.size;
  final width = math
      .max(anchor.size.width, 300)
      .clamp(240.0, math.max(240.0, overlaySize.width - 24))
      .toDouble();
  final alignRight =
      origin.dx + width > overlaySize.width - _referenceMenuMargin;
  final below = overlaySize.height - origin.dy - anchor.size.height;
  final above = origin.dy;
  final placeAbove = below < 220 && above > below;
  final available =
      (placeAbove ? above : below) - _referenceMenuGap - _referenceMenuMargin;
  return (
    targetAnchor: placeAbove
        ? (alignRight ? Alignment.topRight : Alignment.topLeft)
        : (alignRight ? Alignment.bottomRight : Alignment.bottomLeft),
    followerAnchor: placeAbove
        ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
        : (alignRight ? Alignment.topRight : Alignment.topLeft),
    offset: Offset(0, placeAbove ? -_referenceMenuGap : _referenceMenuGap),
    width: width,
    maxHeight: available.clamp(120.0, 300.0),
  );
}
