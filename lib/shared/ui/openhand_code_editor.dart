import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' as highlight;

import '../../app/model/editor_code_theme.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_spacing.dart';
import 'openhand_typography.dart';

/// 编程专家与工作流共用的语法高亮器。
class OpenHandCodeSyntaxHighlighter {
  OpenHandCodeSyntaxHighlighter({
    required TextStyle baseStyle,
    required bool darkSurface,
    EditorCodeTheme codeTheme = EditorCodeTheme.materialYou,
  }) : _baseStyle = baseStyle {
    final colors = _codeThemeColors(codeTheme, darkSurface);
    _commentStyle = baseStyle.copyWith(
      color: colors.comment,
      fontStyle: FontStyle.italic,
    );
    _keywordStyle = baseStyle.copyWith(
      color: colors.keyword,
      fontWeight: FontWeight.w700,
    );
    _stringStyle = baseStyle.copyWith(color: colors.string);
    _numberStyle = baseStyle.copyWith(color: colors.number);
    _titleStyle = baseStyle.copyWith(
      color: colors.title,
      fontWeight: FontWeight.w700,
    );
    _typeStyle = baseStyle.copyWith(
      color: colors.type,
      fontWeight: FontWeight.w600,
    );
    _metaStyle = baseStyle.copyWith(color: colors.meta);
    _operatorStyle = baseStyle.copyWith(color: colors.operator);
  }

  final TextStyle _baseStyle;
  late final TextStyle _commentStyle;
  late final TextStyle _keywordStyle;
  late final TextStyle _stringStyle;
  late final TextStyle _numberStyle;
  late final TextStyle _titleStyle;
  late final TextStyle _typeStyle;
  late final TextStyle _metaStyle;
  late final TextStyle _operatorStyle;

  static const Set<String> _commentClasses = <String>{'comment', 'quote'};
  static const Set<String> _keywordClasses = <String>{
    'keyword',
    'selector-tag',
    'meta-keyword',
    'doctag',
  };
  static const Set<String> _stringClasses = <String>{
    'string',
    'regexp',
    'attribute',
    'template-variable',
  };
  static const Set<String> _numberClasses = <String>{
    'number',
    'literal',
    'symbol',
    'bullet',
  };
  static const Set<String> _titleClasses = <String>{
    'title',
    'function',
    'section',
    'title.function_',
    'title.class_',
  };
  static const Set<String> _typeClasses = <String>{
    'type',
    'built_in',
    'class',
    'params',
    'variable',
    'selector-id',
    'selector-class',
    'selector-attr',
    'selector-pseudo',
    'property',
  };
  static const Set<String> _metaClasses = <String>{
    'meta',
    'attr',
    'tag',
    'name',
  };
  static const Set<String> _operatorClasses = <String>{
    'operator',
    'punctuation',
  };

  TextSpan build(
    String source, {
    String? language,
    bool allowAutoDetection = false,
  }) {
    final normalizedLanguage = normalizeOpenHandCodeLanguage(language);
    if (normalizedLanguage == 'plaintext' ||
        normalizedLanguage == null && !allowAutoDetection) {
      return TextSpan(text: source, style: _baseStyle);
    }
    try {
      final parsed = highlight.highlight.parse(
        source,
        language: normalizedLanguage,
        autoDetection: allowAutoDetection && normalizedLanguage == null,
      );
      return TextSpan(
        style: _baseStyle,
        children: _buildHighlightedNodes(parsed.nodes),
      );
    } catch (_) {
      if (allowAutoDetection && normalizedLanguage != null) {
        try {
          final parsed = highlight.highlight.parse(source, autoDetection: true);
          return TextSpan(
            style: _baseStyle,
            children: _buildHighlightedNodes(parsed.nodes),
          );
        } catch (_) {
          // 解析失败时回退为纯文本。
        }
      }
      return TextSpan(text: source, style: _baseStyle);
    }
  }

  List<InlineSpan> _buildHighlightedNodes(List<highlight.Node>? nodes) {
    if (nodes == null || nodes.isEmpty) {
      return <InlineSpan>[TextSpan(style: _baseStyle)];
    }
    return <InlineSpan>[
      for (final node in nodes)
        if (node.value != null)
          TextSpan(
            text: node.value,
            style: node.className == null
                ? null
                : _styleForClass(node.className),
          )
        else
          TextSpan(
            style: node.className == null
                ? null
                : _styleForClass(node.className),
            children: _buildHighlightedNodes(node.children),
          ),
    ];
  }

  TextStyle _styleForClass(String? className) {
    for (final name in (className ?? '').split(' ')) {
      if (_commentClasses.contains(name)) return _commentStyle;
      if (_keywordClasses.contains(name)) return _keywordStyle;
      if (_stringClasses.contains(name)) return _stringStyle;
      if (_numberClasses.contains(name)) return _numberStyle;
      if (_titleClasses.contains(name)) return _titleStyle;
      if (_typeClasses.contains(name)) return _typeStyle;
      if (_metaClasses.contains(name)) return _metaStyle;
      if (_operatorClasses.contains(name)) return _operatorStyle;
    }
    return _baseStyle;
  }
}

String? normalizeOpenHandCodeLanguage(String? language) {
  final normalized = (language ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return null;
  return switch (normalized) {
    'text' || 'txt' || 'plain' || 'plaintext' => 'plaintext',
    'shell' || 'sh' || 'zsh' => 'bash',
    'yml' => 'yaml',
    'htm' => 'html',
    _ => normalized,
  };
}

class OpenHandCodeTextField extends StatelessWidget {
  const OpenHandCodeTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.style,
    required this.onChanged,
    this.undoController,
    this.readOnly = false,
    this.contentPadding = const EdgeInsets.all(14),
    this.contextMenuBuilder,
    this.cursorColor,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final TextStyle? style;
  final ValueChanged<String> onChanged;
  final UndoHistoryController? undoController;
  final bool readOnly;
  final EdgeInsetsGeometry contentPadding;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final Color? cursorColor;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      scrollController: scrollController,
      undoController: undoController,
      readOnly: readOnly,
      expands: true,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textAlignVertical: TextAlignVertical.top,
      style: style,
      cursorColor: cursorColor,
      contextMenuBuilder: contextMenuBuilder,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: contentPadding,
        isDense: true,
        isCollapsed: true,
        filled: false,
      ),
      onChanged: onChanged,
    );
  }
}

class OpenHandCodeEditor extends StatefulWidget {
  const OpenHandCodeEditor({
    super.key,
    required this.value,
    required this.language,
    required this.fileName,
    required this.codeTheme,
    required this.onChanged,
    this.icon = Icons.code_rounded,
    this.height = 360,
    this.borderRadius = BorderRadius.zero,
  });

  final String value;
  final String language;
  final String fileName;
  final EditorCodeTheme codeTheme;
  final ValueChanged<String> onChanged;
  final IconData icon;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<OpenHandCodeEditor> createState() => _OpenHandCodeEditorState();
}

class _OpenHandCodeEditorState extends State<OpenHandCodeEditor> {
  late final _HighlightingCodeController _controller =
      _HighlightingCodeController(
        text: widget.value,
        language: widget.language,
      );
  late final ScrollController _scrollController = ScrollController();
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'openhand-code-editor',
  );
  late final UndoHistoryController _undoController = UndoHistoryController();

  @override
  void didUpdateWidget(covariant OpenHandCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
    if (oldWidget.language != widget.language) {
      _controller.language = widget.language;
    }
  }

  @override
  void dispose() {
    _undoController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final editorStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurface,
      fontFamily: kOpenHandMonospaceFontFamily,
      height: 1.5,
    );
    _controller.highlighter = OpenHandCodeSyntaxHighlighter(
      baseStyle: editorStyle ?? const TextStyle(),
      darkSurface: theme.brightness == Brightness.dark,
      codeTheme: widget.codeTheme,
    );
    return Container(
      height: widget.height,
      clipBehavior: widget.borderRadius == BorderRadius.zero
          ? Clip.none
          : Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: widget.borderRadius,
      ),
      // 前景边框覆盖子内容，确保顶部圆角和四周边框始终可见。
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: widget.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_controller.text.length} 字符',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<UndoHistoryValue>(
                  valueListenable: _undoController,
                  builder: (context, value, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '撤销',
                        onPressed: value.canUndo ? _undoController.undo : null,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      kOpenHandHGap6,
                      IconButton(
                        tooltip: '重做',
                        onPressed: value.canRedo ? _undoController.redo : null,
                        icon: const Icon(Icons.redo_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: OpenHandSafeScrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              thickness: 8,
              radius: const Radius.circular(8),
              child: OpenHandCodeTextField(
                controller: _controller,
                focusNode: _focusNode,
                scrollController: _scrollController,
                undoController: _undoController,
                style: editorStyle,
                onChanged: (value) {
                  widget.onChanged(value);
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightingCodeController extends TextEditingController {
  _HighlightingCodeController({required String text, required this.language})
    : super(text: text);

  static const int _maxHighlightCharacters = 96 * 1024;
  OpenHandCodeSyntaxHighlighter? highlighter;
  String language;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.length > _maxHighlightCharacters || highlighter == null) {
      return TextSpan(text: text, style: style);
    }
    return highlighter!.build(text, language: language);
  }
}

({
  Color comment,
  Color keyword,
  Color string,
  Color number,
  Color title,
  Color type,
  Color meta,
  Color operator,
})
_codeThemeColors(EditorCodeTheme theme, bool darkSurface) {
  return switch (theme) {
    EditorCodeTheme.materialYou => (
      comment: darkSurface ? const Color(0xFF7DD3A7) : const Color(0xFF5B6472),
      keyword: darkSurface ? const Color(0xFFF9A8D4) : const Color(0xFF0B57D0),
      string: darkSurface ? const Color(0xFFFDE68A) : const Color(0xFFB42318),
      number: darkSurface ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
      title: darkSurface ? const Color(0xFF67E8F9) : const Color(0xFF7C3AED),
      type: darkSurface ? const Color(0xFFC4B5FD) : const Color(0xFF8A3C00),
      meta: darkSurface ? const Color(0xFFCBD5E1) : const Color(0xFF0F4C81),
      operator: darkSurface ? const Color(0xFFE2E8F0) : const Color(0xFF1F2937),
    ),
    EditorCodeTheme.monokai => (
      comment: darkSurface ? const Color(0xFF75715E) : const Color(0xFF8E908C),
      keyword: darkSurface ? const Color(0xFFF92672) : const Color(0xFFC7254E),
      string: darkSurface ? const Color(0xFFE6DB74) : const Color(0xFF718C00),
      number: darkSurface ? const Color(0xFFAE81FF) : const Color(0xFF8959A8),
      title: darkSurface ? const Color(0xFFA6E22E) : const Color(0xFF4271AE),
      type: darkSurface ? const Color(0xFF66D9EF) : const Color(0xFFC82828),
      meta: darkSurface ? const Color(0xFFFD971F) : const Color(0xFFEAB700),
      operator: darkSurface ? const Color(0xFFF8F8F2) : const Color(0xFF3E3D32),
    ),
    EditorCodeTheme.solarized => (
      comment: darkSurface ? const Color(0xFF586E75) : const Color(0xFF93A1A1),
      keyword: const Color(0xFF859900),
      string: const Color(0xFF2AA198),
      number: const Color(0xFFD33682),
      title: const Color(0xFF268BD2),
      type: const Color(0xFFB58900),
      meta: const Color(0xFF6C71C4),
      operator: darkSurface ? const Color(0xFF839496) : const Color(0xFF657B83),
    ),
    EditorCodeTheme.oneDark => (
      comment: darkSurface ? const Color(0xFF5C6370) : const Color(0xFFA0A1A7),
      keyword: darkSurface ? const Color(0xFFC678DD) : const Color(0xFFA626A4),
      string: darkSurface ? const Color(0xFF98C379) : const Color(0xFF50A14F),
      number: darkSurface ? const Color(0xFFD19A66) : const Color(0xFF986801),
      title: darkSurface ? const Color(0xFF61AFEF) : const Color(0xFF4078F2),
      type: darkSurface ? const Color(0xFFE5C07B) : const Color(0xFFC18401),
      meta: darkSurface ? const Color(0xFF56B6C2) : const Color(0xFF0184BC),
      operator: darkSurface ? const Color(0xFFABB2BF) : const Color(0xFF383A42),
    ),
    EditorCodeTheme.github => (
      comment: darkSurface ? const Color(0xFF8B949E) : const Color(0xFF6A737D),
      keyword: darkSurface ? const Color(0xFFFF7B72) : const Color(0xFFD73A49),
      string: darkSurface ? const Color(0xFFA5D6FF) : const Color(0xFF032F62),
      number: darkSurface ? const Color(0xFF79C0FF) : const Color(0xFF005CC5),
      title: darkSurface ? const Color(0xFFD2A8FF) : const Color(0xFF6F42C1),
      type: darkSurface ? const Color(0xFFFFA657) : const Color(0xFFE36209),
      meta: darkSurface ? const Color(0xFF7EE787) : const Color(0xFF22863A),
      operator: darkSurface ? const Color(0xFFC9D1D9) : const Color(0xFF24292E),
    ),
    EditorCodeTheme.dracula => (
      comment: darkSurface ? const Color(0xFF6272A4) : const Color(0xFF8E908C),
      keyword: darkSurface ? const Color(0xFFFF79C6) : const Color(0xFFD73A49),
      string: darkSurface ? const Color(0xFFF1FA8C) : const Color(0xFF50A14F),
      number: darkSurface ? const Color(0xFFBD93F9) : const Color(0xFF6F42C1),
      title: darkSurface ? const Color(0xFF50FA7B) : const Color(0xFF22863A),
      type: darkSurface ? const Color(0xFF8BE9FD) : const Color(0xFF005CC5),
      meta: darkSurface ? const Color(0xFFFFB86C) : const Color(0xFFE36209),
      operator: darkSurface ? const Color(0xFFF8F8F2) : const Color(0xFF24292E),
    ),
  };
}
