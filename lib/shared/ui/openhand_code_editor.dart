import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:provider/provider.dart';

import '../../app/model/editor_code_theme.dart';
import '../../app/state/settings_controller.dart';
import '../util/bounded_xfile_io.dart';
import '../util/localized_text.dart';
import '../util/text_search.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_editor_chrome.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_scroll_behaviors.dart';
import 'openhand_snack_bar.dart';
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
    'md' => 'markdown',
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
    this.contentPadding = kOpenHandEditorContentPadding,
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
    required this.onChanged,
    this.codeTheme,
    this.icon = Icons.code_rounded,
    this.height = 360,
    this.borderRadius = BorderRadius.zero,
    this.readOnly = false,
  });

  final String value;
  final String language;
  final String fileName;
  final EditorCodeTheme? codeTheme;
  final ValueChanged<String> onChanged;
  final IconData icon;
  final double height;
  final BorderRadius borderRadius;
  final bool readOnly;

  @override
  OpenHandCodeEditorState createState() => OpenHandCodeEditorState();
}

class OpenHandCodeEditorState extends State<OpenHandCodeEditor> {
  static const int _maxImportedCodeBytes = 512 * 1024;
  static const int _formatterIndentWidth = 4;
  static const int _compactFormatterIndentWidth = 2;
  static const double _minEditorHeight = 180;
  static const double _maxEditorHeight = 720;
  static const int _maxLineNumberItems = 20000;
  static const Map<String, List<String>> _codeFileExtensions =
      <String, List<String>>{
        'python': <String>['py'],
        'python3': <String>['py'],
        'py': <String>['py'],
        'javascript': <String>['js', 'mjs', 'cjs'],
        'js': <String>['js', 'mjs', 'cjs'],
        'node': <String>['js', 'mjs', 'cjs'],
        'nodejs': <String>['js', 'mjs', 'cjs'],
        'shell': <String>['sh', 'bash', 'zsh'],
        'bash': <String>['sh', 'bash', 'zsh'],
        'sh': <String>['sh', 'bash', 'zsh'],
        'zsh': <String>['sh', 'bash', 'zsh'],
        'linuxshell': <String>['sh', 'bash', 'zsh'],
        'powershell': <String>['ps1', 'psm1', 'psd1'],
        'pwsh': <String>['ps1', 'psm1', 'psd1'],
        'ps': <String>['ps1', 'psm1', 'psd1'],
        'ps1': <String>['ps1', 'psm1', 'psd1'],
        'windowspowershell': <String>['ps1', 'psm1', 'psd1'],
        'markdown': <String>['md', 'markdown'],
        'md': <String>['md', 'markdown'],
      };
  static const Map<String, String> _codeLanguageLabels = <String, String>{
    'python': 'Python',
    'python3': 'Python',
    'py': 'Python',
    'javascript': 'JavaScript',
    'js': 'JavaScript',
    'node': 'JavaScript',
    'nodejs': 'JavaScript',
    'shell': 'Shell / Bash',
    'bash': 'Shell / Bash',
    'sh': 'Shell / Bash',
    'zsh': 'Shell / Bash',
    'linuxshell': 'Shell / Bash',
    'powershell': 'PowerShell',
    'pwsh': 'PowerShell',
    'ps': 'PowerShell',
    'ps1': 'PowerShell',
    'windowspowershell': 'PowerShell',
    'markdown': 'Markdown',
    'md': 'Markdown',
  };
  static final RegExp _languageSeparatorPattern = RegExp(r'[\s_-]+');
  static final RegExp _pythonDedentPattern = RegExp(
    r'^(?:elif|else|except|finally)\b',
  );
  static final RegExp _pythonBlockOpeningPattern = RegExp(
    r'^(?:async\s+)?(?:def|class|if|elif|else|for|while|try|except|finally|with|match|case)\b',
  );
  static final RegExp _shellDedentPattern = RegExp(
    r'^(?:fi|done|esac|elif|else)\b|^\}',
  );
  static final RegExp _shellBlockOpeningPattern = RegExp(
    r'(?:\bthen|\bdo)\s*(?:#.*)?$|^case\b.*\bin\s*$|^(?:else|elif)\b',
  );
  static final RegExp _continuationPattern = RegExp(r'(?:[+\-*/%=&|.,]|\\)$');

  late final _HighlightingCodeController _controller =
      _HighlightingCodeController(
        text: widget.value,
        language: widget.language,
      );
  late final ScrollController _scrollController = ScrollController();
  late final ScrollController _lineNumberScrollController = ScrollController();
  late final ScrollController _horizontalScrollController = ScrollController();
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'openhand-code-editor',
  );
  late final UndoHistoryController _undoController = UndoHistoryController();
  late final TextEditingController _findController = TextEditingController();
  late final TextEditingController _replaceController = TextEditingController();
  late final FocusNode _findFocusNode = FocusNode(
    debugLabel: 'openhand-code-editor-find',
  );
  late double _editorHeight = _boundedEditorHeight(widget.height);
  late double _defaultEditorHeight = _editorHeight;
  late double _fontSize = kOpenHandEditorFontSizeDefault;
  int _cursorLine = 1;
  int _cursorColumn = 1;
  bool _isImportingCodeFile = false;
  bool _findVisible = false;
  bool _replaceVisible = false;
  bool _findCaseSensitive = false;
  List<int> _findMatchOffsets = const <int>[];
  int _currentMatchIndex = -1;
  final Map<int, Offset> _activePointers = <int, Offset>{};
  double? _pinchStartDistance;
  double? _pinchStartFontSize;

  double _boundedEditorHeight(double value) =>
      value.clamp(_minEditorHeight, _maxEditorHeight);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncLineNumberScroll);
    _controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncLineNumberScroll();
    });
  }

  TextEditingValue get editingValue => _controller.value;

  void applyEditingValue(TextEditingValue value) {
    final text = value.text;
    final max = text.length;
    final next = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: value.selection.baseOffset.clamp(0, max),
        extentOffset: value.selection.extentOffset.clamp(0, max),
      ),
    );
    if (_controller.value == next) return;
    _controller.value = next;
    widget.onChanged(next.text);
  }

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
    if (oldWidget.height != widget.height) {
      _defaultEditorHeight = _boundedEditorHeight(widget.height);
      _editorHeight = _boundedEditorHeight(widget.height);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _findFocusNode.dispose();
    _replaceController.dispose();
    _findController.dispose();
    _undoController.dispose();
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _lineNumberScrollController.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final darkSurface = theme.brightness == Brightness.dark;
    final wordWrap = context.select<SettingsController, bool>(
      (controller) => controller.editorWordWrap,
    );
    final codeTheme =
        widget.codeTheme ??
        context.select<SettingsController, EditorCodeTheme>(
          (controller) => controller.editorCodeTheme,
        );
    final editorStyle = openHandEditorBaseStyle(
      _fontSize,
    ).copyWith(color: openHandEditorSurfaceTextColor(darkSurface: darkSurface));
    _controller.highlighter = OpenHandCodeSyntaxHighlighter(
      baseStyle: editorStyle,
      darkSurface: darkSurface,
      codeTheme: codeTheme,
    );
    final lineCount = math.min(
      _lineCount(_controller.text),
      _maxLineNumberItems,
    );
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _showFind,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _showFind,
      const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
          _showFindReplace,
      const SingleActivator(LogicalKeyboardKey.keyH, control: true):
          _showFindReplace,
    };
    if (_findVisible) {
      bindings[const SingleActivator(LogicalKeyboardKey.escape)] = _hideFind;
    }
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        skipTraversal: true,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: openHandEditorChromeDecoration(
            colorScheme,
            borderRadius: widget.borderRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: kOpenHandEditorHeaderHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon,
                        size: 13,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      kOpenHandHGap6,
                      Expanded(
                        child: Text(
                          widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<UndoHistoryValue>(
                        valueListenable: _undoController,
                        builder: (context, undo, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OpenHandEditorHeaderActionButton(
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '撤销',
                                  en: 'Undo',
                                ),
                                icon: Icons.undo_rounded,
                                color: colorScheme.onSurfaceVariant,
                                onPressed: widget.readOnly || !undo.canUndo
                                    ? null
                                    : _undo,
                              ),
                              OpenHandEditorHeaderActionButton(
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '重做',
                                  en: 'Redo',
                                ),
                                icon: Icons.redo_rounded,
                                color: colorScheme.onSurfaceVariant,
                                onPressed: widget.readOnly || !undo.canRedo
                                    ? null
                                    : _redo,
                              ),
                              OpenHandEditorHeaderActionButton(
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '查找',
                                  en: 'Find',
                                ),
                                icon: Icons.search_rounded,
                                color: _findVisible
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                                onPressed: _showFind,
                              ),
                              OpenHandEditorHeaderActionButton(
                                tooltip: _isImportingCodeFile
                                    ? openHandLocalizedText(
                                        context,
                                        zh: '导入中',
                                        en: 'Importing',
                                      )
                                    : openHandLocalizedText(
                                        context,
                                        zh: '从代码文件导入',
                                        en: 'Import file',
                                      ),
                                icon: Icons.file_open_outlined,
                                color: colorScheme.onSurfaceVariant,
                                onPressed:
                                    widget.readOnly || _isImportingCodeFile
                                    ? null
                                    : _importCodeFile,
                              ),
                            ],
                          );
                        },
                      ),
                      const OpenHandEditorWrapToggleButton(),
                    ],
                  ),
                ),
              ),
              Divider(
                height: kOpenHandEditorHairline,
                thickness: kOpenHandEditorHairline,
                color: colorScheme.outlineVariant.withValues(
                  alpha: kOpenHandEditorHairlineStrongAlpha,
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: openHandMotionDuration(context, kOpenHandMotion220),
                  curve: kOpenHandSwitchInCurve,
                  alignment: Alignment.bottomCenter,
                  child: _findVisible
                      ? _buildFindReplaceBar(context)
                      : const SizedBox.shrink(),
                ),
              ),
              Listener(
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerUp,
                onPointerPanZoomStart: _handlePanZoomStart,
                onPointerPanZoomUpdate: _handlePanZoomUpdate,
                onPointerPanZoomEnd: _handlePanZoomEnd,
                child: ColoredBox(
                  color: colorScheme.surface,
                  child: SizedBox(
                    height: _editorHeight,
                    child: _buildEditorBody(
                      context,
                      editorStyle: editorStyle,
                      lineCount: lineCount,
                      wordWrap: wordWrap,
                    ),
                  ),
                ),
              ),
              _buildStatusBar(context),
            ],
          ),
        ),
      ),
    );
  }

  void _showFind() {
    if (_findVisible && !_replaceVisible) {
      _hideFind();
      return;
    }
    setState(() {
      _findVisible = true;
      _replaceVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocusNode.requestFocus();
    });
  }

  void _showFindReplace() {
    if (_findVisible && _replaceVisible) {
      _hideFind();
      return;
    }
    setState(() {
      _findVisible = true;
      _replaceVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocusNode.requestFocus();
    });
  }

  void _hideFind() {
    setState(() {
      _findVisible = false;
      _replaceVisible = false;
      _findMatchOffsets = const <int>[];
      _currentMatchIndex = -1;
    });
    _focusNode.requestFocus();
  }

  void _updateFindMatches(String query, {bool selectMatch = true}) {
    if (query.isEmpty) {
      setState(() {
        _findMatchOffsets = const <int>[];
        _currentMatchIndex = -1;
      });
      return;
    }
    final offsets = findTextMatchOffsets(
      text: _controller.text,
      query: query,
      caseSensitive: _findCaseSensitive,
      allowOverlapping: false,
    );
    setState(() {
      _findMatchOffsets = offsets;
      _currentMatchIndex = offsets.isEmpty ? -1 : 0;
    });
    if (selectMatch && offsets.isNotEmpty) {
      _selectFindMatch(0);
    }
  }

  void _findNext() {
    if (_findMatchOffsets.isEmpty) return;
    final next = moveTextMatchIndex(
      currentIndex: _currentMatchIndex,
      matchCount: _findMatchOffsets.length,
      forward: true,
    );
    setState(() => _currentMatchIndex = next);
    _selectFindMatch(next);
  }

  void _findPrevious() {
    if (_findMatchOffsets.isEmpty) return;
    final previous = moveTextMatchIndex(
      currentIndex: _currentMatchIndex,
      matchCount: _findMatchOffsets.length,
      forward: false,
    );
    setState(() => _currentMatchIndex = previous);
    _selectFindMatch(previous);
  }

  void _selectFindMatch(int index) {
    if (index < 0 || index >= _findMatchOffsets.length) return;
    final offset = _findMatchOffsets[index];
    final length = _findController.text.length;
    final end = math.min(offset + length, _controller.text.length);
    if (offset < 0 || end <= offset) return;
    _controller.selection = TextSelection(
      baseOffset: offset,
      extentOffset: end,
    );
    _focusNode.requestFocus();
  }

  void _replaceCurrent() {
    if (widget.readOnly ||
        _currentMatchIndex < 0 ||
        _currentMatchIndex >= _findMatchOffsets.length ||
        _findController.text.isEmpty) {
      return;
    }
    final offset = _findMatchOffsets[_currentMatchIndex];
    final findLength = _findController.text.length;
    final replacement = _replaceController.text;
    final text = _controller.text;
    final end = math.min(offset + findLength, text.length);
    if (findLength == 0 || offset < 0 || end <= offset) return;
    final next = text.replaceRange(offset, end, replacement);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + replacement.length),
    );
    widget.onChanged(next);
    _updateFindMatches(_findController.text);
  }

  void _replaceAll() {
    if (widget.readOnly || _findController.text.isEmpty) return;
    final query = _findController.text;
    final replacement = _replaceController.text;
    final text = _controller.text;
    final offsets = findTextMatchOffsets(
      text: text,
      query: query,
      caseSensitive: _findCaseSensitive,
      allowOverlapping: false,
    );
    if (offsets.isEmpty) return;
    final buffer = StringBuffer();
    var cursor = 0;
    for (final offset in offsets) {
      if (offset < cursor) continue;
      buffer
        ..write(text.substring(cursor, offset))
        ..write(replacement);
      cursor = offset + query.length;
    }
    buffer.write(text.substring(cursor));
    final next = buffer.toString();
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onChanged(next);
    _updateFindMatches(query, selectMatch: false);
  }

  Widget _buildFindReplaceBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final matchLabel = _findMatchOffsets.isEmpty
        ? ''
        : '${_currentMatchIndex + 1}/${_findMatchOffsets.length}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: openHandEditorToolbarSurface(colorScheme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: kOpenHandEditorToolbarFieldHeight,
                  child: TextField(
                    controller: _findController,
                    focusNode: _findFocusNode,
                    style: TextStyle(
                      fontSize: kOpenHandEditorToolbarFieldFontSize,
                      color: colorScheme.onSurface,
                    ),
                    decoration: openHandEditorToolbarInputDecoration(
                      colorScheme,
                      hintText: openHandLocalizedText(
                        context,
                        zh: '查找',
                        en: 'Find',
                      ),
                    ),
                    onChanged: _updateFindMatches,
                    onSubmitted: (_) => _findNext(),
                  ),
                ),
              ),
              if (matchLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    matchLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              OpenHandEditorFindBarButton(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: openHandLocalizedText(
                  context,
                  zh: '上一个',
                  en: 'Previous',
                ),
                onPressed: _findMatchOffsets.isEmpty ? null : _findPrevious,
                colorScheme: colorScheme,
              ),
              OpenHandEditorFindBarButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: openHandLocalizedText(context, zh: '下一个', en: 'Next'),
                onPressed: _findMatchOffsets.isEmpty ? null : _findNext,
                colorScheme: colorScheme,
              ),
              OpenHandEditorFindBarButton(
                icon: Icons.font_download_rounded,
                tooltip: openHandLocalizedText(
                  context,
                  zh: '区分大小写',
                  en: 'Match case',
                ),
                isActive: _findCaseSensitive,
                onPressed: () {
                  setState(() => _findCaseSensitive = !_findCaseSensitive);
                  _updateFindMatches(_findController.text);
                },
                colorScheme: colorScheme,
              ),
              if (!_replaceVisible)
                OpenHandEditorFindBarButton(
                  icon: Icons.find_replace_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '显示替换',
                    en: 'Show replace',
                  ),
                  onPressed: () => setState(() => _replaceVisible = true),
                  colorScheme: colorScheme,
                ),
              OpenHandEditorFindBarButton(
                icon: Icons.close_rounded,
                tooltip: openHandLocalizedText(context, zh: '关闭', en: 'Close'),
                onPressed: _hideFind,
                colorScheme: colorScheme,
              ),
            ],
          ),
          if (_replaceVisible) ...[
            kOpenHandGap4,
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: kOpenHandEditorToolbarFieldHeight,
                    child: TextField(
                      controller: _replaceController,
                      enabled: !widget.readOnly,
                      style: TextStyle(
                        fontSize: kOpenHandEditorToolbarFieldFontSize,
                        color: colorScheme.onSurface,
                      ),
                      decoration: openHandEditorToolbarInputDecoration(
                        colorScheme,
                        hintText: openHandLocalizedText(
                          context,
                          zh: '替换',
                          en: 'Replace',
                        ),
                      ),
                      onSubmitted: (_) => _replaceCurrent(),
                    ),
                  ),
                ),
                kOpenHandHGap4,
                OpenHandEditorFindBarButton(
                  icon: Icons.find_replace_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '替换当前',
                    en: 'Replace',
                  ),
                  onPressed: widget.readOnly || _findMatchOffsets.isEmpty
                      ? null
                      : _replaceCurrent,
                  colorScheme: colorScheme,
                ),
                OpenHandEditorFindBarButton(
                  icon: Icons.done_all_rounded,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '全部替换',
                    en: 'Replace all',
                  ),
                  onPressed: widget.readOnly || _findMatchOffsets.isEmpty
                      ? null
                      : _replaceAll,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditorBody(
    BuildContext context, {
    required TextStyle editorStyle,
    required int lineCount,
    required bool wordWrap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    const noScrollbarBehavior = OpenHandEditorScrollBehavior();
    final lineExtent = _fontSize * kOpenHandEditorLineHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutterWidth = openHandEditorGutterWidth(
          lineCount: lineCount,
          fontSize: _fontSize,
        );
        List<double>? wrappedHeights;
        if (wordWrap) {
          final textLayoutWidth =
              constraints.maxWidth -
              gutterWidth -
              kOpenHandEditorTextPaddingLeft -
              kOpenHandEditorTextPaddingRight;
          if (textLayoutWidth > 0) {
            wrappedHeights = _computeWrappedLineHeights(
              textLayoutWidth,
              editorStyle,
            );
          }
        }
        Widget textField = OpenHandCodeTextField(
          controller: _controller,
          focusNode: _focusNode,
          scrollController: _scrollController,
          undoController: _undoController,
          readOnly: widget.readOnly,
          style: editorStyle,
          cursorColor: colorScheme.primary,
          onChanged: (value) {
            widget.onChanged(value);
            if (_findVisible && _findController.text.isNotEmpty) {
              _updateFindMatches(_findController.text, selectMatch: false);
            }
            setState(() {});
          },
        );
        if (!wordWrap) {
          final estimatedContentWidth = math.min(
            kOpenHandEditorMaxEstimatedContentWidth,
            math.max(
              constraints.maxWidth - gutterWidth,
              _longestLineLength(_controller.text) * (_fontSize * 0.62) +
                  kOpenHandEditorTextPaddingLeft +
                  kOpenHandEditorTextPaddingRight +
                  48,
            ),
          );
          textField = SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: estimatedContentWidth, child: textField),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: gutterWidth,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: colorScheme.outlineVariant.withValues(
                      alpha: kOpenHandEditorHairlineSoftAlpha,
                    ),
                    width: kOpenHandEditorHairline,
                  ),
                ),
              ),
              child: ScrollConfiguration(
                behavior: noScrollbarBehavior,
                child: ListView.builder(
                  key: ValueKey<String>('line-numbers-$_fontSize-$wordWrap'),
                  controller: _lineNumberScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(
                    top: kOpenHandEditorTextPaddingTop,
                    bottom: kOpenHandEditorTextPaddingBottom,
                  ),
                  itemCount: lineCount,
                  itemExtent: wrappedHeights != null ? null : lineExtent,
                  itemBuilder: (context, index) {
                    final lineNumber = index + 1;
                    final itemHeight = wrappedHeights != null
                        ? (index < wrappedHeights.length
                              ? wrappedHeights[index]
                              : lineExtent)
                        : null;
                    final lineWidget = Padding(
                      padding: const EdgeInsets.only(left: 8, right: 14),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          kOpenHandHGap6,
                          Expanded(
                            child: Text(
                              '$lineNumber',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: _fontSize,
                                height: kOpenHandEditorLineHeight,
                                fontWeight: FontWeight.w400,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.48,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (itemHeight != null) {
                      return SizedBox(height: itemHeight, child: lineWidget);
                    }
                    return lineWidget;
                  },
                ),
              ),
            ),
            Expanded(
              child: PrimaryScrollController.none(
                child: OpenHandSafeScrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  thickness: 9,
                  radius: kOpenHandPillRadius,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.vertical,
                  child: ScrollConfiguration(
                    behavior: noScrollbarBehavior,
                    child: textField,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleControllerChanged() {
    final next = _cursorFromOffset(_controller.selection.extentOffset);
    if (next.$1 == _cursorLine && next.$2 == _cursorColumn) return;
    setState(() {
      _cursorLine = next.$1;
      _cursorColumn = next.$2;
    });
  }

  (int, int) _cursorFromOffset(int offset) {
    final text = _controller.text;
    final clamped = offset.clamp(0, text.length);
    var line = 1;
    var col = 1;
    for (var i = 0; i < clamped; i++) {
      if (text.codeUnitAt(i) == 10) {
        line += 1;
        col = 1;
      } else {
        col += 1;
      }
    }
    return (line, col);
  }

  Widget _buildStatusBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final languageKey = widget.language.trim().toLowerCase().replaceAll(
      _languageSeparatorPattern,
      '',
    );
    final languageLabel = _codeLanguageLabels[languageKey] ?? widget.language;
    final zoomPct = (_fontSize / kOpenHandEditorFontSizeDefault * 100).round();
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          final next = _boundedEditorHeight(_editorHeight + details.delta.dy);
          if (next == _editorHeight) return;
          setState(() => _editorHeight = next);
        },
        onDoubleTap: _resetEditorViewport,
        child: Container(
          height: kOpenHandEditorStatusBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: openHandEditorStatusBarDecoration(colorScheme),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    children: [
                      Text(
                        'Ln $_cursorLine, Col $_cursorColumn',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                      kOpenHandHGap16,
                      Text(
                        languageLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (zoomPct != 100) ...[
                        kOpenHandHGap16,
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _resetEditorViewport,
                            child: Text(
                              '$zoomPct%',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                      kOpenHandHGap8,
                      OpenHandEditorStatusChip(
                        colorScheme: colorScheme,
                        icon: Icons.auto_fix_high_rounded,
                        label: openHandLocalizedText(
                          context,
                          zh: '格式化',
                          en: 'Format',
                        ),
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '格式化当前内容',
                          en: 'Format document',
                        ),
                        onPressed: widget.readOnly ? null : _formatCode,
                      ),
                    ],
                  ),
                ),
              ),
              kOpenHandHGap12,
              Text(
                'UTF-8',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importCodeFile() async {
    if (_isImportingCodeFile) return;
    setState(() => _isImportingCodeFile = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[_codeFileTypeGroup()],
      );
      if (file == null || !mounted) return;

      final bytes = await readBoundedXFileBytes(
        file,
        maxBytes: _maxImportedCodeBytes,
      );
      var importedCode = utf8.decode(bytes);
      if (importedCode.startsWith('\uFEFF')) {
        importedCode = importedCode.substring(1);
      }

      _controller.value = TextEditingValue(
        text: importedCode,
        selection: TextSelection.collapsed(offset: importedCode.length),
      );
      widget.onChanged(importedCode);
      if (!mounted) return;
      setState(() {});
      showOpenHandSuccessSnack(context, '已导入代码文件：${file.name}');
    } on BoundedXFileSizeException {
      if (mounted) {
        showOpenHandErrorSnack(context, '代码文件不能超过 512 KiB。');
      }
    } on FormatException {
      if (mounted) {
        showOpenHandErrorSnack(context, '代码文件不是有效的 UTF-8 文本。');
      }
    } catch (_) {
      if (mounted) {
        showOpenHandErrorSnack(context, '读取代码文件失败，请检查文件是否可访问。');
      }
    } finally {
      if (mounted) setState(() => _isImportingCodeFile = false);
    }
  }

  XTypeGroup _codeFileTypeGroup() {
    final languageKey = widget.language.trim().toLowerCase().replaceAll(
      _languageSeparatorPattern,
      '',
    );
    final extensions = _codeFileExtensions[languageKey] ?? <String>['txt'];
    final label = _codeLanguageLabels[languageKey] ?? '代码';
    return XTypeGroup(label: '$label代码文件', extensions: extensions);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2) {
      final points = _activePointers.values.toList(growable: false);
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartFontSize = _fontSize;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length < 2 ||
        _pinchStartDistance == null ||
        _pinchStartFontSize == null) {
      return;
    }
    final points = _activePointers.values.toList(growable: false);
    final distance = (points[0] - points[1]).distance;
    if (distance <= 0 || _pinchStartDistance! <= 0) return;
    final next = (_pinchStartFontSize! * distance / _pinchStartDistance!).clamp(
      kOpenHandEditorFontSizeMin,
      kOpenHandEditorFontSizeMax,
    );
    if ((next - _fontSize).abs() < 0.1) return;
    setState(() => _fontSize = next);
  }

  void _handlePointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _pinchStartDistance = null;
      _pinchStartFontSize = null;
    }
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    _pinchStartFontSize = _fontSize;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final base = _pinchStartFontSize ?? _fontSize;
    final next = (base * event.scale).clamp(
      kOpenHandEditorFontSizeMin,
      kOpenHandEditorFontSizeMax,
    );
    if ((next - _fontSize).abs() < 0.1) return;
    setState(() => _fontSize = next);
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    _pinchStartFontSize = null;
  }

  void _syncLineNumberScroll() {
    if (!_scrollController.hasClients ||
        !_lineNumberScrollController.hasClients) {
      return;
    }
    final target = _scrollController.offset.clamp(
      0.0,
      _lineNumberScrollController.position.maxScrollExtent,
    );
    if ((_lineNumberScrollController.offset - target).abs() > 0.1) {
      _lineNumberScrollController.jumpTo(target);
    }
  }

  int _lineCount(String text) {
    var count = 1;
    for (final codeUnit in text.codeUnits) {
      if (codeUnit == 10) count += 1;
    }
    return count;
  }

  int _longestLineLength(String text) {
    var longest = 0;
    var current = 0;
    for (final codeUnit in text.codeUnits) {
      if (codeUnit == 10) {
        if (current > longest) longest = current;
        current = 0;
      } else {
        current += 1;
      }
    }
    return current > longest ? current : longest;
  }

  List<double> _computeWrappedLineHeights(
    double textLayoutWidth,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: _controller.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textLayoutWidth);
    final lineExtent = _fontSize * kOpenHandEditorLineHeight;
    final lineHeights = <double>[];
    var currentLogicalLineHeight = 0.0;
    for (final metric in painter.computeLineMetrics()) {
      currentLogicalLineHeight += metric.height;
      if (metric.hardBreak) {
        lineHeights.add(math.max(currentLogicalLineHeight, lineExtent));
        currentLogicalLineHeight = 0;
      }
    }
    if (currentLogicalLineHeight > 0) {
      lineHeights.add(math.max(currentLogicalLineHeight, lineExtent));
    }
    if (lineHeights.isEmpty) {
      lineHeights.add(lineExtent);
    }
    painter.dispose();
    return lineHeights;
  }

  void _formatCode() {
    final source = _controller.text;
    final formatted = _formatSourceCode(source, widget.language);
    if (formatted == source) {
      showOpenHandInfoSnack(context, '代码已经是格式化状态。');
      return;
    }
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    widget.onChanged(formatted);
    setState(() {});
    showOpenHandSuccessSnack(context, '代码已格式化。');
  }

  String _formatSourceCode(String source, String language) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return '';

    final languageKey = language.trim().toLowerCase().replaceAll(
      _languageSeparatorPattern,
      '',
    );
    final isPython = languageKey == 'python' || languageKey == 'python3';
    final isShell =
        languageKey == 'shell' ||
        languageKey == 'bash' ||
        languageKey == 'sh' ||
        languageKey == 'zsh' ||
        languageKey == 'linuxshell';
    final isPowerShell =
        languageKey == 'powershell' ||
        languageKey == 'pwsh' ||
        languageKey == 'ps' ||
        languageKey == 'ps1' ||
        languageKey == 'windowspowershell';
    final indentWidth = isPython || isPowerShell
        ? _formatterIndentWidth
        : _compactFormatterIndentWidth;
    var blockDepth = 0;
    var delimiterDepth = 0;
    var previousContent = '';
    int? previousRawIndent;
    final formattedLines = <String>[];

    for (final rawLine in lines) {
      final content = rawLine.trim();
      if (content.isEmpty) {
        if (formattedLines.isNotEmpty && formattedLines.last.isNotEmpty) {
          formattedLines.add('');
        }
        previousContent = '';
        continue;
      }

      final rawIndent = _leadingWhitespaceLength(rawLine);
      var lineBlockDepth = blockDepth;
      if (isPython && _isPythonDedentLine(content)) {
        lineBlockDepth = math.max(0, lineBlockDepth - 1);
      } else if (isShell && _isShellDedentLine(content)) {
        lineBlockDepth = math.max(0, lineBlockDepth - 1);
      }
      final isContinuation = _continuesPreviousLine(previousContent);
      if (isPython &&
          delimiterDepth == 0 &&
          !isContinuation &&
          previousRawIndent != null &&
          rawIndent < previousRawIndent) {
        lineBlockDepth = math.min(
          lineBlockDepth,
          rawIndent ~/ _formatterIndentWidth,
        );
      }
      final leadingClosers = _leadingClosingDelimiterCount(content);
      final lineIndentDepth = math.max(
        0,
        lineBlockDepth + delimiterDepth - leadingClosers,
      );
      final continuationIndent = delimiterDepth == 0 && isContinuation ? 1 : 0;
      formattedLines.add(
        '${' ' * ((lineIndentDepth + continuationIndent) * indentWidth)}$content',
      );

      delimiterDepth = math.max(0, delimiterDepth + _delimiterDelta(content));
      blockDepth = lineBlockDepth;
      if (isPython && _isPythonBlockOpeningLine(content)) {
        blockDepth += 1;
      } else if (isShell && _isShellBlockOpeningLine(content)) {
        blockDepth += 1;
      }
      previousContent = content;
      previousRawIndent = rawIndent;
    }

    while (formattedLines.isNotEmpty && formattedLines.last.isEmpty) {
      formattedLines.removeLast();
    }
    return formattedLines.isEmpty ? '' : '${formattedLines.join('\n')}\n';
  }

  bool _isPythonDedentLine(String line) => _pythonDedentPattern.hasMatch(line);

  bool _isPythonBlockOpeningLine(String line) {
    if (!line.endsWith(':')) return false;
    return _pythonBlockOpeningPattern.hasMatch(line);
  }

  bool _isShellDedentLine(String line) => _shellDedentPattern.hasMatch(line);

  bool _isShellBlockOpeningLine(String line) =>
      _shellBlockOpeningPattern.hasMatch(line);

  int _leadingClosingDelimiterCount(String line) {
    var count = 0;
    for (final character in line.split('')) {
      if (!')]}'.contains(character)) break;
      count += 1;
    }
    return count;
  }

  int _leadingWhitespaceLength(String line) {
    var width = 0;
    for (var index = 0; index < line.length; index++) {
      final character = line[index];
      if (character == ' ') {
        width += 1;
      } else if (character == '\t') {
        width += _formatterIndentWidth;
      } else {
        break;
      }
    }
    return width;
  }

  int _delimiterDelta(String line) {
    var delta = 0;
    String? quote;
    var escaped = false;
    for (var index = 0; index < line.length; index++) {
      final character = line[index];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == quote) {
          quote = null;
        }
        continue;
      }
      if (character == '#' ||
          (character == '/' &&
              index + 1 < line.length &&
              line[index + 1] == '/')) {
        break;
      }
      if (character == "'" || character == '"' || character == '`') {
        quote = character;
      } else if ('([{'.contains(character)) {
        delta += 1;
      } else if (')]}'.contains(character)) {
        delta -= 1;
      }
    }
    return delta;
  }

  bool _continuesPreviousLine(String line) {
    if (line.isEmpty) return false;
    return _continuationPattern.hasMatch(line);
  }

  void _undo() {
    _undoController.undo();
    widget.onChanged(_controller.text);
    setState(() {});
  }

  void _redo() {
    _undoController.redo();
    widget.onChanged(_controller.text);
    setState(() {});
  }

  void _resetEditorViewport() {
    setState(() {
      _editorHeight = _defaultEditorHeight;
      _fontSize = kOpenHandEditorFontSizeDefault;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    if (_lineNumberScrollController.hasClients) {
      _lineNumberScrollController.jumpTo(0);
    }
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
    return highlighter!.build(
      text,
      language: language,
      allowAutoDetection: true,
    );
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
