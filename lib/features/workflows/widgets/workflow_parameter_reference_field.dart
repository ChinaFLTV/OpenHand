import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_overlay.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../model/workflow_definition.dart';

const int _firstReferenceMarker = 0xE000;
const int _lastReferenceMarker = 0xF8FF;
const double _referenceMenuGap = 8;
const double _referenceMenuMargin = 12;
const double _referenceMenuHeaderExtent = 32;
const double _referenceMenuSubheaderExtent = 30;
const double _referenceMenuItemExtent = 52;

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
  late final FocusNode _searchFocusNode = FocusNode()
    ..addListener(_handleFocus);
  late TextEditingValue _previousValue;
  late String _lastSerializedText;
  bool _applyingExternalValue = false;
  int _selectedIndex = 0;
  int _triggerOffset = -1;
  String _searchQuery = '';

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
    final references = _visibleReferences;
    if (references.isEmpty && widget.references.isEmpty) {
      _dismissMenu();
    } else if (_selectedIndex >= references.length) {
      _selectedIndex = math.max(0, references.length - 1);
    }
    if (_overlay.hasEntry) _overlay.markNeedsBuild();
  }

  @override
  void dispose() {
    _overlay.dispose();
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _searchFocusNode
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
    if (_focusNode.hasFocus || _searchFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusNode.hasFocus || _searchFocusNode.hasFocus) return;
      _dismissMenu();
    });
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
      final references = _visibleReferences;
      if (references.isEmpty) {
        _dismissMenu();
        return KeyEventResult.handled;
      }
      _selectReference(references[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissMenu();
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSelection(int delta) {
    final references = _visibleReferences;
    if (references.isEmpty) return;
    _selectedIndex = (_selectedIndex + delta).clamp(0, references.length - 1);
    _overlay.markNeedsBuild();
  }

  void _updateSearchQuery(String value) {
    _searchQuery = value;
    _selectedIndex = 0;
    _overlay.markNeedsBuild();
  }

  List<WorkflowParameterReference> get _visibleReferences {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.references;
    final terms = query.split(RegExp(r'\s+'));
    return widget.references
        .where((reference) {
          final nodeTitle = reference.nodeTitle.toLowerCase();
          if (terms.every(nodeTitle.contains)) return true;
          final searchable = <String>[
            nodeTitle,
            reference.name.toLowerCase(),
            reference.field.type.label.toLowerCase(),
            reference.field.description.toLowerCase(),
            reference.direction.label.toLowerCase(),
          ].join(' ');
          return terms.every(searchable.contains);
        })
        .toList(growable: false);
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
    _searchQuery = '';
    _selectedIndex = 0;
    _overlay.show(
      overlay: Overlay.of(context, rootOverlay: true),
      builder: (context, visibility, onExitCompleted) {
        final references = _visibleReferences;
        return _WorkflowReferenceMenu(
          link: _layerLink,
          anchorKey: _anchorKey,
          references: references,
          selectedIndex: _selectedIndex,
          searchQuery: _searchQuery,
          searchFocusNode: _searchFocusNode,
          visibility: visibility,
          onSelected: _selectReference,
          onHighlighted: (index) {
            if (_selectedIndex == index) return;
            _selectedIndex = index;
            _overlay.markNeedsBuild();
          },
          onSearchChanged: _updateSearchQuery,
          onSearchKeyEvent: _handleKeyEvent,
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
    required this.searchQuery,
    required this.searchFocusNode,
    required this.visibility,
    required this.onSelected,
    required this.onHighlighted,
    required this.onSearchChanged,
    required this.onSearchKeyEvent,
    required this.onDismiss,
    required this.onExitCompleted,
  });

  final LayerLink link;
  final GlobalKey anchorKey;
  final List<WorkflowParameterReference> references;
  final int selectedIndex;
  final String searchQuery;
  final FocusNode searchFocusNode;
  final ValueListenable<bool> visibility;
  final ValueChanged<WorkflowParameterReference> onSelected;
  final ValueChanged<int> onHighlighted;
  final ValueChanged<String> onSearchChanged;
  final KeyEventResult Function(FocusNode, KeyEvent) onSearchKeyEvent;
  final VoidCallback onDismiss;
  final VoidCallback onExitCompleted;

  @override
  State<_WorkflowReferenceMenu> createState() => _WorkflowReferenceMenuState();
}

class _WorkflowReferenceMenuState extends State<_WorkflowReferenceMenu> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _searchController = TextEditingController(
    text: widget.searchQuery,
  )..addListener(_handleSearchChanged);
  bool _syncingSearchQuery = false;

  @override
  void didUpdateWidget(covariant _WorkflowReferenceMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchController.text != widget.searchQuery) {
      _syncingSearchQuery = true;
      _searchController.value = TextEditingValue(
        text: widget.searchQuery,
        selection: TextSelection.collapsed(offset: widget.searchQuery.length),
      );
      _syncingSearchQuery = false;
    }
    if (oldWidget.selectedIndex == widget.selectedIndex &&
        _sameReferenceList(oldWidget.references, widget.references)) {
      return;
    }
    _ensureSelectionVisible();
  }

  void _handleSearchChanged() {
    if (_syncingSearchQuery) return;
    setState(() {});
    widget.onSearchChanged(_searchController.text);
  }

  void _ensureSelectionVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final rows = _referenceMenuRows(widget.references);
      var itemTop = 4.0;
      var found = false;
      for (final row in rows) {
        if (row.referenceIndex == widget.selectedIndex) {
          found = true;
          break;
        }
        itemTop += row.extent;
      }
      if (!found) return;
      final itemBottom = itemTop + _referenceMenuItemExtent;
      final viewportTop = _scrollController.offset;
      final viewportBottom = viewportTop + position.viewportDimension;
      final target = itemTop < viewportTop
          ? itemTop
          : itemBottom > viewportBottom
          ? itemBottom - position.viewportDimension
          : null;
      if (target == null) return;
      final offset = target.clamp(0, position.maxScrollExtent).toDouble();
      final duration = openHandMotionDuration(context, kOpenHandMotion120);
      if (duration == Duration.zero) {
        _scrollController.jumpTo(offset);
      } else {
        _scrollController.animateTo(
          offset,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _resolveMenuLayout(context, widget.anchorKey);
    final theme = Theme.of(context);
    final rows = _referenceMenuRows(widget.references);
    return OpenHandEscapeDismissScope(
      onDismiss: widget.onDismiss,
      child: Stack(
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kOpenHandRadius14),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.82,
                          ),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Focus(
                              onKeyEvent: widget.onSearchKeyEvent,
                              child: TextField(
                                controller: _searchController,
                                focusNode: widget.searchFocusNode,
                                textInputAction: TextInputAction.search,
                                style: theme.textTheme.bodyMedium,
                                decoration: InputDecoration(
                                  hintText: '搜索参数、节点或类型',
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 19,
                                  ),
                                  suffixIcon: _searchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: '清空搜索',
                                          onPressed: () {
                                            _searchController.clear();
                                            widget.searchFocusNode
                                                .requestFocus();
                                          },
                                          icon: const Icon(
                                            Icons.cancel_rounded,
                                            size: 17,
                                          ),
                                        ),
                                  isDense: true,
                                  filled: true,
                                  fillColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 11,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      kOpenHandRadius12,
                                    ),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      kOpenHandRadius12,
                                    ),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          Flexible(
                            child: rows.isEmpty
                                ? SizedBox(
                                    height: 96,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 24,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          kOpenHandGap6,
                                          Text(
                                            '没有匹配的参数',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : OpenHandSafeScrollbar(
                                    controller: _scrollController,
                                    thumbVisibility: true,
                                    interactive: true,
                                    thickness: 5,
                                    radius: kOpenHandPillRadius,
                                    notificationPredicate: (notification) =>
                                        notification.metrics.axis ==
                                        Axis.vertical,
                                    child: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(
                                        context,
                                      ).copyWith(scrollbars: false),
                                      child: ListView.builder(
                                        controller: _scrollController,
                                        primary: false,
                                        shrinkWrap: true,
                                        padding: const EdgeInsets.fromLTRB(
                                          6,
                                          4,
                                          6,
                                          6,
                                        ),
                                        itemCount: rows.length,
                                        itemBuilder: (context, index) {
                                          final row = rows[index];
                                          return switch (row.kind) {
                                            _WorkflowReferenceMenuRowKind
                                                .nodeHeader =>
                                              _WorkflowReferenceGroupHeader(
                                                title: row.headerTitle!,
                                              ),
                                            _WorkflowReferenceMenuRowKind
                                                .ioHeader =>
                                              _WorkflowReferenceIoHeader(
                                                direction: row.direction!,
                                              ),
                                            _WorkflowReferenceMenuRowKind
                                                .item =>
                                              _WorkflowReferenceMenuItem(
                                                reference: row.reference!,
                                                selected:
                                                    row.referenceIndex ==
                                                    widget.selectedIndex,
                                                onTap: () => widget.onSelected(
                                                  row.reference!,
                                                ),
                                                onHover: () =>
                                                    widget.onHighlighted(
                                                      row.referenceIndex,
                                                    ),
                                              ),
                                          };
                                        },
                                      ),
                                    ),
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
      ),
    );
  }

  bool _sameReferenceList(
    List<WorkflowParameterReference> left,
    List<WorkflowParameterReference> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].nodeId != right[index].nodeId ||
          left[index].name != right[index].name ||
          left[index].direction != right[index].direction) {
        return false;
      }
    }
    return true;
  }
}

enum _WorkflowReferenceMenuRowKind { nodeHeader, ioHeader, item }

class _WorkflowReferenceMenuRow {
  const _WorkflowReferenceMenuRow.nodeHeader(this.headerTitle)
    : kind = _WorkflowReferenceMenuRowKind.nodeHeader,
      direction = null,
      reference = null,
      referenceIndex = -1,
      extent = _referenceMenuHeaderExtent;

  const _WorkflowReferenceMenuRow.ioHeader(this.direction)
    : kind = _WorkflowReferenceMenuRowKind.ioHeader,
      headerTitle = null,
      reference = null,
      referenceIndex = -1,
      extent = _referenceMenuSubheaderExtent;

  const _WorkflowReferenceMenuRow.item(this.reference, this.referenceIndex)
    : kind = _WorkflowReferenceMenuRowKind.item,
      headerTitle = null,
      direction = null,
      extent = _referenceMenuItemExtent;

  final _WorkflowReferenceMenuRowKind kind;
  final String? headerTitle;
  final WorkflowParameterDirection? direction;
  final WorkflowParameterReference? reference;
  final int referenceIndex;
  final double extent;
}

List<_WorkflowReferenceMenuRow> _referenceMenuRows(
  List<WorkflowParameterReference> references,
) {
  final grouped =
      <String, List<({int index, WorkflowParameterReference ref})>>{};
  final titles = <String, String>{};
  for (final (index, reference) in references.indexed) {
    titles.putIfAbsent(reference.nodeId, () => reference.nodeTitle);
    (grouped[reference.nodeId] ??=
            <({int index, WorkflowParameterReference ref})>[])
        .add((index: index, ref: reference));
  }
  final rows = <_WorkflowReferenceMenuRow>[];
  for (final group in grouped.entries) {
    rows.add(
      _WorkflowReferenceMenuRow.nodeHeader(titles[group.key] ?? '未命名节点'),
    );
    final inputs = group.value
        .where((item) => item.ref.direction == WorkflowParameterDirection.input)
        .toList(growable: false);
    final outputs = group.value
        .where(
          (item) => item.ref.direction == WorkflowParameterDirection.output,
        )
        .toList(growable: false);
    if (inputs.isNotEmpty) {
      rows.add(
        const _WorkflowReferenceMenuRow.ioHeader(
          WorkflowParameterDirection.input,
        ),
      );
      for (final item in inputs) {
        rows.add(_WorkflowReferenceMenuRow.item(item.ref, item.index));
      }
    }
    if (outputs.isNotEmpty) {
      rows.add(
        const _WorkflowReferenceMenuRow.ioHeader(
          WorkflowParameterDirection.output,
        ),
      );
      for (final item in outputs) {
        rows.add(_WorkflowReferenceMenuRow.item(item.ref, item.index));
      }
    }
  }
  return rows;
}

class _WorkflowReferenceGroupHeader extends StatelessWidget {
  const _WorkflowReferenceGroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _referenceMenuHeaderExtent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
        child: Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.45,
          ),
        ),
      ),
    );
  }
}

class _WorkflowReferenceIoHeader extends StatelessWidget {
  const _WorkflowReferenceIoHeader({required this.direction});

  final WorkflowParameterDirection direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (direction) {
      WorkflowParameterDirection.input => OpenHandStatusColors.info,
      WorkflowParameterDirection.output => theme.colorScheme.primary,
    };
    final icon = switch (direction) {
      WorkflowParameterDirection.input => Icons.login_rounded,
      WorkflowParameterDirection.output => Icons.output_rounded,
    };
    return SizedBox(
      height: _referenceMenuSubheaderExtent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kOpenHandRadius8),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: accent),
                  kOpenHandHGap4,
                  Text(
                    direction.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandHGap8,
            Expanded(
              child: Container(
                height: 1,
                color: accent.withValues(alpha: 0.16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowReferenceMenuItem extends StatelessWidget {
  const _WorkflowReferenceMenuItem({
    required this.reference,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final WorkflowParameterReference reference;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = reference.field.description.trim();
    final accent = switch (reference.direction) {
      WorkflowParameterDirection.input => OpenHandStatusColors.info,
      WorkflowParameterDirection.output => theme.colorScheme.primary,
    };
    final icon = switch (reference.direction) {
      WorkflowParameterDirection.input => Icons.login_rounded,
      WorkflowParameterDirection.output => Icons.output_rounded,
    };
    return SizedBox(
      height: _referenceMenuItemExtent,
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '${reference.nodeTitle}，${reference.direction.label}，${reference.name}，'
            '${reference.field.type.label}'
            '${description.isEmpty ? '' : '，$description'}',
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kOpenHandRadius9),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onHover: (hovering) {
                if (hovering) onHover();
              },
              borderRadius: BorderRadius.circular(kOpenHandRadius9),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(kOpenHandRadius7),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Icon(icon, size: 16, color: accent),
                    ),
                    kOpenHandHGap8,
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reference.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          if (description.isNotEmpty)
                            Text(
                              description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.15,
                              ),
                            ),
                        ],
                      ),
                    ),
                    kOpenHandHGap8,
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.58,
                        ),
                        borderRadius: kOpenHandPillBorderRadius,
                      ),
                      child: Text(
                        reference.field.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
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
      width: 360,
      maxHeight: 380,
    );
  }
  final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final overlaySize = overlay.size;
  final width = math
      .max(anchor.size.width, 360)
      .clamp(280.0, math.max(280.0, overlaySize.width - 24))
      .toDouble();
  final alignRight =
      origin.dx + width > overlaySize.width - _referenceMenuMargin;
  final below = overlaySize.height - origin.dy - anchor.size.height;
  final above = origin.dy;
  final placeAbove = below < 280 && above > below;
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
    maxHeight: available.clamp(160.0, 420.0),
  );
}
