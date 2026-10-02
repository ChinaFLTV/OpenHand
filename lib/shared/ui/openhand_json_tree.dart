import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/state/settings_controller.dart';
import '../../app/support/silent_log.dart';
import '../util/bounded_json_conversion.dart';
import '../util/input_value_parsing.dart';
import '../util/localized_text.dart';
import '../util/structured_content.dart';
import '../util/text_clip.dart';
import '../util/timer_safety.dart';
import 'animated_dialog.dart';
import 'animated_expandable.dart';
import 'bounded_animation.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_clipboard.dart';
import 'openhand_code_editor.dart';
import 'openhand_inline_empty_state.dart';
import 'openhand_spacing.dart';
import 'openhand_typography.dart';

export '../util/structured_content.dart'
    show
        kOpenHandJsonTreeMaxCharacters,
        kOpenHandJsonTreeMaxDepth,
        kOpenHandJsonTreeMaxNodes;

const _openHandJsonTreeConversionConfig = openHandContentConversionConfig;
const int kOpenHandJsonTreeFullViewMinCharacters = 360;
const double kOpenHandJsonTreePreviewMaxHeight = 260;
const Duration kOpenHandJsonTreeCopyFeedbackDuration = Duration(seconds: 2);
const Duration kOpenHandJsonTreeFullLoadTimeout = Duration(seconds: 12);

const _JsonTreePalette _kJsonTreeLightColors = (
  key: Color(0xFF0B6E75),
  string: Color(0xFF2F5FA7),
  number: Color(0xFF8B3F8F),
  boolValue: Color(0xFFB45309),
  nullValue: Color(0xFFBE3455),
  punctuation: Color(0xFF667085),
  count: Color(0xFF6D4AC8),
);

const _JsonTreePalette _kJsonTreeDarkColors = (
  key: Color(0xFF67D4D0),
  string: Color(0xFF8CB8FF),
  number: Color(0xFFE69BD3),
  boolValue: Color(0xFFF7B955),
  nullValue: Color(0xFFFF8296),
  punctuation: Color(0xFFAAB3C2),
  count: Color(0xFFB6A0FF),
);

typedef _JsonTreePalette = ({
  Color key,
  Color string,
  Color number,
  Color boolValue,
  Color nullValue,
  Color punctuation,
  Color count,
});

class OpenHandJsonFullText {
  const OpenHandJsonFullText({required this.text, this.hint});

  final String text;
  final String? hint;
}

typedef OpenHandJsonFullTextLoader = Future<OpenHandJsonFullText> Function();

class OpenHandJsonTreeDocument {
  const OpenHandJsonTreeDocument({
    required this.value,
    required this.containerPaths,
  });

  final Object value;
  final Set<String> containerPaths;
}

bool openHandJsonTreeNeedsFullView(String text) {
  final trimmed = text.trim();
  if (trimmed.length >= kOpenHandJsonTreeFullViewMinCharacters) return true;
  return trimmed.endsWith('…') && trimmed.length >= 80;
}

String? tryPrettyOpenHandJsonText(String text) {
  final trimmed = text.trim();
  if (trimmed.length < 2 ||
      trimmed.length > kOpenHandJsonTreeMaxCharacters ||
      !(trimmed.startsWith('{') && trimmed.endsWith('}')) &&
          !(trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    return null;
  }
  try {
    final decoded = decodeJsonTextUsingConfig(
      trimmed,
      maxTextCodeUnits: kOpenHandJsonTreeMaxCharacters,
      config: _openHandJsonTreeConversionConfig,
    );
    return prettyPrintJson(decoded);
  } catch (_) {
    return null;
  }
}

Future<void> showOpenHandJsonFullViewDialog({
  required BuildContext context,
  required String text,
  String? label,
  bool error = false,
  String logTag = 'json_tree',
  OpenHandJsonFullTextLoader? loadFullText,
  bool parseStructuredText = false,
  String? language,
  bool showSource = false,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final media = MediaQuery.sizeOf(dialogContext);
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return buildOpenHandDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius30,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        maxWidth: kOpenHandDialogWidthWide,
        height: math.min(kOpenHandDialogHeightTall, media.height * 0.86),
        child: _OpenHandJsonFullViewDialog(
          initialText: text,
          label: label,
          error: error,
          logTag: logTag,
          loadFullText: loadFullText,
          parseStructuredText: parseStructuredText,
          language: language,
          showSource: showSource,
        ),
      );
    },
  );
}

OpenHandJsonTreeDocument? tryParseOpenHandJsonTreeDocument(String text) {
  final trimmed = text.trim();
  if (trimmed.length < 2 ||
      trimmed.length > kOpenHandJsonTreeMaxCharacters ||
      !(trimmed.startsWith('{') && trimmed.endsWith('}')) &&
          !(trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    return null;
  }
  Object? decoded;
  try {
    decoded = decodeJsonTextUsingConfig(
      trimmed,
      maxTextCodeUnits: kOpenHandJsonTreeMaxCharacters,
      config: _openHandJsonTreeConversionConfig,
    );
  } on FormatException {
    return null;
  }
  if (decoded is! Map && decoded is! List) return null;
  final root = decoded as Object;
  return _jsonTreeDocumentFromValue(root);
}

OpenHandJsonTreeDocument _jsonTreeDocumentFromValue(Object root) {
  final paths = <String>{r'$'};
  final pending = <(Object?, String)>[(root, r'$')];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    final value = current.$1;
    final children = value is Map
        ? value.values.toList(growable: false)
        : value is List
        ? value
        : const <Object?>[];
    for (var index = 0; index < children.length; index += 1) {
      final child = children[index];
      if ((child is Map && child.isNotEmpty) ||
          (child is List && child.isNotEmpty)) {
        final path = '${current.$2}/$index';
        paths.add(path);
        pending.add((child, path));
      }
    }
  }
  return OpenHandJsonTreeDocument(
    value: root,
    containerPaths: Set<String>.unmodifiable(paths),
  );
}

/// 将任意值整理为 JSON 树可解析的文本：对象/数组美化，JSON 字符串解码后再美化。
String openHandJsonTreeTextFromValue(Object? value) {
  if (value == null) return '';
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return tryPrettyOpenHandJsonText(trimmed) ?? value;
  }
  try {
    return prettyPrintJson(value);
  } catch (_) {
    try {
      return prettyPrintJson(
        convertToJsonSafeValue(
          value,
          config: _openHandJsonTreeConversionConfig,
        ),
      );
    } catch (_) {
      return '$value';
    }
  }
}

/// 结构化阅读视图：语法高亮、按节点展开、复制，超限或非法内容回退为原文。
class OpenHandJsonTreeView extends StatefulWidget {
  const OpenHandJsonTreeView({
    super.key,
    required this.text,
    this.emptyText = '',
    this.label,
    this.error = false,
    this.enableFullView = true,
    this.showCopyButton = true,
    this.bodyMaxHeight,
    this.logTag = 'json_tree',
    this.loadFullText,
    this.parseStructuredText = false,
    this.language,
    this.showSource = false,
  }) : assert(bodyMaxHeight == null || bodyMaxHeight > 0);

  OpenHandJsonTreeView.fromValue({
    super.key,
    required Object? value,
    this.emptyText = '',
    this.label,
    this.error = false,
    this.enableFullView = true,
    this.showCopyButton = true,
    this.bodyMaxHeight,
    this.logTag = 'json_tree',
    this.loadFullText,
    this.parseStructuredText = false,
    this.language,
    this.showSource = false,
  }) : text = openHandJsonTreeTextFromValue(value),
       assert(bodyMaxHeight == null || bodyMaxHeight > 0);

  final String text;
  final bool parseStructuredText;
  final String? language;
  final bool showSource;
  final String emptyText;
  final String? label;
  final bool error;
  final bool enableFullView;
  final bool showCopyButton;
  final double? bodyMaxHeight;
  final String logTag;
  final OpenHandJsonFullTextLoader? loadFullText;

  @override
  State<OpenHandJsonTreeView> createState() => _OpenHandJsonTreeViewState();
}

class _OpenHandJsonTreeViewState extends State<OpenHandJsonTreeView> {
  OpenHandJsonTreeDocument? _document;
  Set<String> _expandedPaths = <String>{r'$'};
  Timer? _copiedResetTimer;
  bool _copied = false;
  bool _showSource = false;
  String? _language;
  TextSpan? _sourceSpan;
  TextStyle? _sourceStyle;
  String? _sourceText;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant OpenHandJsonTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.parseStructuredText != widget.parseStructuredText ||
        oldWidget.language != widget.language ||
        oldWidget.showSource != widget.showSource) {
      _copiedResetTimer?.cancel();
      _copied = false;
      _parse();
    }
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  void _parse() {
    final parsed = widget.parseStructuredText
        ? parseOpenHandStructuredContent(widget.text, language: widget.language)
        : null;
    _language = parsed?.language ?? widget.language;
    _document = widget.parseStructuredText
        ? parsed?.value == null
              ? null
              : _jsonTreeDocumentFromValue(parsed!.value!)
        : tryParseOpenHandJsonTreeDocument(widget.text);
    _showSource = widget.showSource;
    _sourceSpan = null;
    _expandedPaths = <String>{
      r'$',
      ...?_document?.containerPaths.where(
        (path) => path != r'$' && '/'.allMatches(path).length == 1,
      ),
    };
  }

  bool get _offersFullView =>
      widget.enableFullView && openHandJsonTreeNeedsFullView(widget.text);

  void _openFullView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showOpenHandJsonFullViewDialog(
        context: context,
        text: widget.text,
        label: widget.label,
        error: widget.error,
        logTag: widget.logTag,
        loadFullText: widget.loadFullText,
        parseStructuredText: widget.parseStructuredText,
        language: _language,
        showSource: _showSource,
      );
    });
  }

  Future<void> _copy() async {
    final source = widget.text;
    final copied = await copyOpenHandTextToClipboard(
      context: context,
      text: source,
      logTag: widget.logTag,
      logAction: '复制结构化载荷',
      showSuccess: false,
    );
    if (!copied || !mounted || source != widget.text) return;
    _copiedResetTimer?.cancel();
    setState(() => _copied = true);
    _copiedResetTimer = startSafeTimer(
      kOpenHandJsonTreeCopyFeedbackDuration,
      () {
        if (mounted) setState(() => _copied = false);
      },
    );
  }

  Widget _buildSource(BuildContext context) {
    final theme = Theme.of(context);
    final style = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontFamily: kOpenHandMonospaceFontFamily,
      color: widget.error
          ? theme.colorScheme.error
          : theme.colorScheme.onSurface,
      height: 1.5,
    );
    final text =
        widget.enableFullView &&
            widget.text.length > kOpenHandNativeContentMaxCharacters
        ? '${widget.text.substring(0, safeUtf16PrefixCodeUnits(widget.text, kOpenHandNativeContentMaxCharacters))}\n…'
        : widget.text;
    if (_sourceSpan == null || _sourceStyle != style || _sourceText != text) {
      _sourceText = text;
      _sourceStyle = style;
      _sourceSpan = text.length <= kOpenHandNativeContentMaxCharacters
          ? OpenHandCodeSyntaxHighlighter(
              baseStyle: style,
              darkSurface: theme.brightness == Brightness.dark,
            ).build(text, language: _language)
          : TextSpan(text: text, style: style);
      if (_sourceSpan!.toPlainText() != text) {
        _sourceSpan = TextSpan(text: text, style: style);
      }
    }
    return SelectableText.rich(_sourceSpan!);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsController?>();
    final trimmed = widget.text.trim();
    if (trimmed.isEmpty) {
      if (widget.emptyText.trim().isEmpty) return const SizedBox.shrink();
      return OpenHandInlineEmptyState.compact(message: widget.emptyText);
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final document = _document;
    final labeled = (widget.label ?? '').trim().isNotEmpty;
    final description = _descriptionFor(
      context,
      _showSource ? null : document,
      widget.text.length,
    );
    final allExpanded =
        document != null &&
        document.containerPaths.every(_expandedPaths.contains);
    final radius = labeled ? kOpenHandBorderRadius12 : kOpenHandBorderRadius7;
    final body = Padding(
      padding: const EdgeInsets.all(10),
      child: document == null || _showSource
          ? _buildSource(context)
          : _buildJsonRoot(context, document.value),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fillHeight =
            !widget.enableFullView && constraints.hasBoundedHeight;
        final heading = Row(
          children: [
            Icon(
              document == null
                  ? Icons.notes_rounded
                  : Icons.data_object_rounded,
              size: 16,
              color: widget.error
                  ? colorScheme.error
                  : document == null
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.primary,
            ),
            kOpenHandHGap8,
            if (labeled) ...[
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.error
                        ? colorScheme.error.withValues(alpha: 0.14)
                        : colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: kOpenHandPillBorderRadius,
                  ),
                  child: Text(
                    widget.label!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: widget.error
                          ? colorScheme.error
                          : colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              kOpenHandHGap8,
            ],
            Expanded(
              child: Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        final actions = IconButtonTheme(
          data: const IconButtonThemeData(
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(30, 30)),
              maximumSize: WidgetStatePropertyAll(Size(30, 30)),
              fixedSize: WidgetStatePropertyAll(Size(30, 30)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          child: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.parseStructuredText && document != null) ...[
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: _showSource
                      ? openHandLocalizedText(
                          context,
                          zh: '查看结构',
                          zhHant: '查看結構',
                          en: 'Show structure',
                          fr: 'Afficher la structure',
                          de: 'Struktur anzeigen',
                          ja: '構造を表示',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '查看原文',
                          zhHant: '查看原文',
                          en: 'Show source',
                          fr: 'Afficher la source',
                          de: 'Quelltext anzeigen',
                          ja: '原文を表示',
                        ),
                  onPressed: () => setState(() => _showSource = !_showSource),
                  icon: Icon(
                    _showSource
                        ? Icons.account_tree_outlined
                        : Icons.code_rounded,
                    size: 16,
                  ),
                ),
              ],
              if (document != null &&
                  !_showSource &&
                  document.containerPaths.length > 1) ...[
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: allExpanded
                      ? openHandLocalizedText(
                          context,
                          zh: '全部收起',
                          zhHant: '全部收合',
                          en: 'Collapse all',
                          fr: 'Tout réduire',
                          de: 'Alle einklappen',
                          ja: 'すべて折りたたむ',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '全部展开',
                          zhHant: '全部展開',
                          en: 'Expand all',
                          fr: 'Tout développer',
                          de: 'Alle ausklappen',
                          ja: 'すべて展開',
                        ),
                  onPressed: () => setState(() {
                    _expandedPaths = allExpanded
                        ? <String>{r'$'}
                        : document.containerPaths.toSet();
                  }),
                  icon: Icon(
                    allExpanded
                        ? Icons.unfold_less_rounded
                        : Icons.unfold_more_rounded,
                    size: 17,
                  ),
                ),
              ],
              if (_offersFullView) ...[
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '显示全部内容',
                    zhHant: '顯示全部內容',
                    en: 'Show full content',
                    fr: 'Afficher tout le contenu',
                    de: 'Vollständigen Inhalt anzeigen',
                    ja: 'すべての内容を表示',
                  ),
                  onPressed: _openFullView,
                  icon: const Icon(Icons.open_in_full_rounded, size: 16),
                ),
              ],
              if (widget.showCopyButton)
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: _copied
                      ? openHandLocalizedText(
                          context,
                          zh: '已复制',
                          zhHant: '已複製',
                          en: 'Copied',
                          fr: 'Copié',
                          de: 'Kopiert',
                          ja: 'コピー済み',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: document == null || widget.parseStructuredText
                              ? '复制文本'
                              : '复制 JSON',
                          zhHant: document == null || widget.parseStructuredText
                              ? '複製文字'
                              : '複製 JSON',
                          en: document == null || widget.parseStructuredText
                              ? 'Copy text'
                              : 'Copy JSON',
                          fr: document == null || widget.parseStructuredText
                              ? 'Copier le texte'
                              : 'Copier le JSON',
                          de: document == null || widget.parseStructuredText
                              ? 'Text kopieren'
                              : 'JSON kopieren',
                          ja: document == null || widget.parseStructuredText
                              ? 'テキストをコピー'
                              : 'JSON をコピー',
                        ),
                  onPressed: _copy,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 16,
                    color: _copied ? colorScheme.primary : null,
                  ),
                ),
            ],
          ),
        );
        return Container(
          width: double.infinity,
          height: fillHeight ? constraints.maxHeight : null,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withValues(alpha: 0.78),
            borderRadius: radius,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: widget.error
                  ? colorScheme.error.withValues(alpha: 0.56)
                  : colorScheme.outlineVariant.withValues(alpha: 0.96),
              width: 1.25,
            ),
          ),
          child: Column(
            mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
                decoration: BoxDecoration(
                  color: widget.error
                      ? colorScheme.errorContainer.withValues(alpha: 0.5)
                      : document == null
                      ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.72)
                      : colorScheme.primaryContainer.withValues(
                          alpha: labeled ? 0.52 : 0.38,
                        ),
                  borderRadius: BorderRadius.vertical(top: radius.topLeft),
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                    ),
                  ),
                ),
                child: constraints.maxWidth < 320
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: heading),
                          actions,
                        ],
                      ),
              ),
              if (fillHeight)
                Expanded(
                  child: _jsonTreeScrollableBody(context: context, child: body),
                )
              else if (_offersFullView || widget.bodyMaxHeight != null)
                _jsonTreeAnimatedSize(
                  context: context,
                  expanding: !_showSource,
                  child: _jsonTreePreviewBody(
                    context: context,
                    maxHeight:
                        widget.bodyMaxHeight ??
                        kOpenHandJsonTreePreviewMaxHeight,
                    child: body,
                  ),
                )
              else
                _jsonTreeAnimatedSize(
                  context: context,
                  expanding: !_showSource,
                  child: body,
                ),
            ],
          ),
        );
      },
    );
  }

  String _descriptionFor(
    BuildContext context,
    OpenHandJsonTreeDocument? document,
    int characterCount,
  ) {
    final value = document?.value;
    final count = value is Map
        ? value.length
        : value is List
        ? value.length
        : 0;
    if (value is Map) {
      return openHandLocalizedText(
        context,
        zh: '对象 · $count 个字段',
        zhHant: '物件 · $count 個欄位',
        en: 'Object · $count ${count == 1 ? 'field' : 'fields'}',
        fr: 'Objet · $count ${count == 1 ? 'champ' : 'champs'}',
        de: 'Objekt · $count ${count == 1 ? 'Feld' : 'Felder'}',
        ja: 'オブジェクト · $count フィールド',
      );
    }
    if (value is List) {
      return openHandLocalizedText(
        context,
        zh: '数组 · $count 项',
        zhHant: '陣列 · $count 項',
        en: 'Array · $count ${count == 1 ? 'item' : 'items'}',
        fr: 'Tableau · $count ${count == 1 ? 'élément' : 'éléments'}',
        de: 'Array · $count ${count == 1 ? 'Eintrag' : 'Einträge'}',
        ja: '配列 · $count 件',
      );
    }
    return openHandLocalizedText(
      context,
      zh: '文本 · $characterCount 字符',
      zhHant: '文字 · $characterCount 字元',
      en: 'Text · $characterCount characters',
      fr: 'Texte · $characterCount caractères',
      de: 'Text · $characterCount Zeichen',
      ja: 'テキスト · $characterCount 文字',
    );
  }

  Widget _buildJsonRoot(BuildContext context, Object value) {
    final entries = _jsonEntries(value);
    if (entries.isEmpty) {
      final theme = Theme.of(context);
      return SelectableText(
        value is Map ? '{}' : '[]',
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: kOpenHandMonospaceFontFamily,
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < entries.length; index += 1)
          _buildJsonNode(
            context,
            name: entries[index].key,
            value: entries[index].value,
            path: '${r'$'}/$index',
            depth: 0,
          ),
      ],
    );
  }

  Widget _buildJsonNode(
    BuildContext context, {
    required String name,
    required Object? value,
    required String path,
    required int depth,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final jsonColors = theme.brightness == Brightness.dark
        ? _kJsonTreeDarkColors
        : _kJsonTreeLightColors;
    final isContainer = value is Map || value is List;
    final childCount = value is Map
        ? value.length
        : value is List
        ? value.length
        : 0;
    final expandable = isContainer && childCount > 0;
    final expanded = expandable && _expandedPaths.contains(path);
    final keyStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: kOpenHandMonospaceFontFamily,
      color: jsonColors.key,
      fontWeight: FontWeight.w600,
      height: 1.45,
    );
    final punctuationStyle = keyStyle?.copyWith(
      color: jsonColors.punctuation,
      fontWeight: FontWeight.w400,
    );
    final valueSpan = TextSpan(
      style: keyStyle,
      children: [
        TextSpan(text: _jsonLeaf(name)),
        TextSpan(text: ': ', style: punctuationStyle),
        if (isContainer) ...[
          TextSpan(
            text: value is Map
                ? childCount == 0
                      ? '{}'
                      : '{…}'
                : childCount == 0
                ? '[]'
                : '[…]',
            style: punctuationStyle,
          ),
          if (childCount > 0)
            TextSpan(
              text: '  $childCount',
              style: punctuationStyle?.copyWith(color: jsonColors.count),
            ),
        ] else
          TextSpan(
            text: _jsonLeaf(value),
            style: _jsonValueStyle(theme, jsonColors, value),
          ),
      ],
    );
    final row = Padding(
      padding: EdgeInsetsDirectional.only(start: depth == 0 ? 0 : 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 22,
            child: expandable
                ? AnimatedExpandChevron(
                    expanded: expanded,
                    size: 17,
                    color: colorScheme.onSurfaceVariant,
                    duration: _jsonTreeMotionDuration(context, expanded),
                  )
                : Icon(Icons.circle, size: 4, color: colorScheme.outline),
          ),
          Expanded(
            child: expandable
                ? Text.rich(valueSpan)
                : SelectableText.rich(valueSpan),
          ),
        ],
      ),
    );
    if (!expandable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      );
    }

    final children = _jsonEntries(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (expanded) {
                _expandedPaths.remove(path);
              } else {
                _expandedPaths.add(path);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: row,
            ),
          ),
        ),
        _jsonTreeAnimatedSize(
          context: context,
          expanding: expanded,
          child: expanded
              ? Container(
                  margin: const EdgeInsetsDirectional.only(start: 9),
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        color: jsonColors.key.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < children.length; index += 1)
                        _buildJsonNode(
                          context,
                          name: children[index].key,
                          value: children[index].value,
                          path: '$path/$index',
                          depth: depth + 1,
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

List<({String key, Object? value})> _jsonEntries(Object? value) {
  if (value is Map) {
    return value.entries
        .map((entry) => (key: '${entry.key}', value: entry.value))
        .toList(growable: false);
  }
  if (value is List) {
    return [
      for (var index = 0; index < value.length; index += 1)
        (key: '$index', value: value[index]),
    ];
  }
  return const [];
}

String _jsonLeaf(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return jsonEncode('$value');
  }
}

TextStyle? _jsonValueStyle(
  ThemeData theme,
  _JsonTreePalette colors,
  Object? value,
) {
  final color = switch (value) {
    String() => colors.string,
    num() => colors.number,
    bool() => colors.boolValue,
    null => colors.nullValue,
    _ => theme.colorScheme.onSurface,
  };
  return theme.textTheme.bodySmall?.copyWith(
    fontFamily: kOpenHandMonospaceFontFamily,
    color: color,
    fontWeight: value is bool ? FontWeight.w700 : FontWeight.w500,
    height: 1.45,
  );
}

Widget _jsonTreeAnimatedSize({
  required BuildContext context,
  required bool expanding,
  required Widget child,
}) {
  final motion = openHandMotionSettingsOf(
    context,
    OpenHandMotionSettingsScope.dialog,
  );
  if (motion.disablesAnimation) return child;
  return AnimatedSize(
    duration: expanding ? motion.entranceDuration : motion.exitDuration,
    curve: OpenHandBoundedCurve(
      expanding ? motion.curve.curve : motion.curve.reverseCurve,
    ),
    alignment: Alignment.topCenter,
    child: child,
  );
}

Duration _jsonTreeMotionDuration(BuildContext context, bool expanding) {
  final motion = openHandMotionSettingsOf(
    context,
    OpenHandMotionSettingsScope.dialog,
  );
  return motion.disablesAnimation
      ? Duration.zero
      : expanding
      ? motion.entranceDuration
      : motion.exitDuration;
}

Widget _jsonTreeScrollableBody({
  required BuildContext context,
  required Widget child,
}) {
  return SingleChildScrollView(
    primary: false,
    physics: openHandDialogAwareScrollPhysics(context),
    child: child,
  );
}

Widget _jsonTreePreviewBody({
  required BuildContext context,
  required double maxHeight,
  required Widget child,
}) {
  final constrainedBody = ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: _jsonTreeScrollableBody(context: context, child: child),
  );
  return constrainedBody;
}

class _OpenHandJsonFullViewDialog extends StatefulWidget {
  const _OpenHandJsonFullViewDialog({
    required this.initialText,
    required this.error,
    required this.logTag,
    this.label,
    this.loadFullText,
    this.parseStructuredText = false,
    this.language,
    this.showSource = false,
  });

  final bool parseStructuredText;
  final String? language;
  final bool showSource;
  final String initialText;
  final String? label;
  final bool error;
  final String logTag;
  final OpenHandJsonFullTextLoader? loadFullText;

  @override
  State<_OpenHandJsonFullViewDialog> createState() =>
      _OpenHandJsonFullViewDialogState();
}

class _OpenHandJsonFullViewDialogState
    extends State<_OpenHandJsonFullViewDialog> {
  late String _text = widget.initialText;
  String? _hint;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadFullText();
  }

  Future<void> _loadFullText() async {
    final loader = widget.loadFullText;
    if (loader == null) return;
    setState(() => _loading = true);
    try {
      final loaded = await loader().timeout(kOpenHandJsonTreeFullLoadTimeout);
      if (!mounted) return;
      final next = loaded.text.trim().isEmpty ? _text : loaded.text;
      setState(() {
        _text = next;
        _hint = loaded.hint?.trim().isEmpty == true
            ? null
            : loaded.hint?.trim();
        _loading = false;
      });
    } catch (error, stack) {
      silentLog(widget.logTag, '加载完整 JSON 内容', error, stack);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = (widget.label ?? '').trim().isEmpty
        ? openHandLocalizedText(
            context,
            zh: '完整内容',
            zhHant: '完整內容',
            en: 'Full content',
            fr: 'Contenu complet',
            de: 'Vollständiger Inhalt',
            ja: '完全な内容',
          )
        : widget.label!.trim();
    final displayText = widget.parseStructuredText
        ? _text
        : tryPrettyOpenHandJsonText(_text) ?? _text;
    final count = _text.trim().length;
    final subtitle = _loading
        ? openHandLocalizedText(
            context,
            zh: '正在展开完整内容…',
            zhHant: '正在展開完整內容…',
            en: 'Loading full content…',
            fr: 'Chargement du contenu complet…',
            de: 'Vollständiger Inhalt wird geladen…',
            ja: '完全な内容を読み込み中…',
          )
        : (_hint ??
              openHandLocalizedText(
                context,
                zh: '共 $count 字符 · 可滚动阅读与复制',
                zhHant: '共 $count 字元 · 可捲動閱讀與複製',
                en: '$count characters · scroll and copy',
                fr: '$count caractères · défiler et copier',
                de: '$count Zeichen · scrollen und kopieren',
                ja: '$count 文字 · スクロールとコピー',
              ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.error
                      ? colorScheme.errorContainer
                      : colorScheme.primaryContainer,
                  borderRadius: kOpenHandBorderRadius14,
                ),
                child: Icon(
                  Icons.data_object_rounded,
                  color: widget.error ? colorScheme.error : colorScheme.primary,
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (_loading)
          LinearProgressIndicator(
            minHeight: 3,
            color: colorScheme.primary,
            backgroundColor: colorScheme.secondaryContainer.withValues(
              alpha: 0.55,
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OpenHandJsonTreeView(
              text: displayText,
              label: widget.label,
              error: widget.error,
              enableFullView: false,
              parseStructuredText: widget.parseStructuredText,
              language: widget.language,
              showSource: widget.showSource,
              logTag: widget.logTag,
            ),
          ),
        ),
      ],
    );
  }
}
