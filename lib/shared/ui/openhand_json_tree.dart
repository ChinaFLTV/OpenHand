import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../util/byte_size_format.dart';
import '../util/localized_text.dart';
import '../util/timer_safety.dart';
import 'animated_dialog.dart';
import 'animated_expandable.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_clipboard.dart';
import 'openhand_spacing.dart';
import 'openhand_typography.dart';

const int kOpenHandJsonTreeMaxCharacters = 512 * kBytesPerKiB;
const int kOpenHandJsonTreeMaxNodes = 4096;
const int kOpenHandJsonTreeMaxDepth = 32;
const int kOpenHandJsonTreeFullViewMinCharacters = 360;
const double kOpenHandJsonTreePreviewMaxHeight = 260;
const Duration kOpenHandJsonTreeCopyFeedbackDuration = Duration(seconds: 2);
const Duration kOpenHandJsonTreeExpandDuration = kOpenHandMotion280;
const Duration kOpenHandJsonTreeCollapseDuration = kOpenHandMotion220;
const Curve kOpenHandJsonTreeMotionCurve = Cubic(0.22, 1.22, 0.36, 1);

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
      !(trimmed.startsWith('{') && trimmed.endsWith('}')) &&
          !(trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    return null;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
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
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final media = MediaQuery.sizeOf(dialogContext);
      final colorScheme = Theme.of(dialogContext).colorScheme;
      final pretty = tryPrettyOpenHandJsonText(text);
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
          text: pretty ?? text,
          sourceText: text,
          label: label,
          error: error,
          logTag: logTag,
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
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map && decoded is! List) return null;
  final root = decoded as Object;

  final paths = <String>{r'$'};
  final pending = <(Object?, String, int)>[(root, r'$', 0)];
  var nodes = 0;
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (current.$3 > kOpenHandJsonTreeMaxDepth) return null;
    final value = current.$1;
    final children = value is Map
        ? value.values.toList(growable: false)
        : value is List
        ? value
        : const <Object?>[];
    for (var index = 0; index < children.length; index += 1) {
      nodes += 1;
      if (nodes > kOpenHandJsonTreeMaxNodes) return null;
      final child = children[index];
      if ((child is Map && child.isNotEmpty) ||
          (child is List && child.isNotEmpty)) {
        final path = '${current.$2}/$index';
        paths.add(path);
        pending.add((child, path, current.$3 + 1));
      }
    }
  }
  return OpenHandJsonTreeDocument(
    value: root,
    containerPaths: Set<String>.unmodifiable(paths),
  );
}

/// 结构化 JSON 树：语法高亮、按节点展开、复制，超限或非法 JSON 回退为文本。
class OpenHandJsonTreeView extends StatefulWidget {
  const OpenHandJsonTreeView({
    super.key,
    required this.text,
    this.emptyText = '',
    this.label,
    this.error = false,
    this.enableFullView = true,
    this.logTag = 'json_tree',
  });

  final String text;
  final String emptyText;
  final String? label;
  final bool error;
  final bool enableFullView;
  final String logTag;

  @override
  State<OpenHandJsonTreeView> createState() => _OpenHandJsonTreeViewState();
}

class _OpenHandJsonTreeViewState extends State<OpenHandJsonTreeView> {
  OpenHandJsonTreeDocument? _document;
  Set<String> _expandedPaths = <String>{r'$'};
  Timer? _copiedResetTimer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant OpenHandJsonTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
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
    _document = tryParseOpenHandJsonTreeDocument(widget.text);
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
      );
    });
  }

  Future<void> _copy() async {
    final copied = await copyOpenHandTextToClipboard(
      context: context,
      text: widget.text,
      logTag: widget.logTag,
      logAction: '复制结构化载荷',
      showSuccess: false,
    );
    if (!copied || !mounted) return;
    _copiedResetTimer?.cancel();
    setState(() => _copied = true);
    _copiedResetTimer = startSafeTimer(kOpenHandJsonTreeCopyFeedbackDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = widget.text.trim();
    if (trimmed.isEmpty) {
      if (widget.emptyText.trim().isEmpty) return const SizedBox.shrink();
      return _JsonTreeEmpty(text: widget.emptyText);
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final document = _document;
    final labeled = (widget.label ?? '').trim().isNotEmpty;
    final description = _descriptionFor(context, document, trimmed.length);
    final allExpanded =
        document != null &&
        document.containerPaths.every(_expandedPaths.contains);
    final radius = labeled
        ? kOpenHandBorderRadius12
        : kOpenHandBorderRadius7;
    final body = Padding(
      padding: const EdgeInsets.all(10),
      child: document == null
          ? SelectableText(
              widget.text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: kOpenHandMonospaceFontFamily,
                color: widget.error ? colorScheme.error : null,
                height: 1.5,
              ),
            )
          : _buildJsonRoot(context, document.value),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fillHeight =
            !widget.enableFullView && constraints.hasBoundedHeight;
        return Container(
          width: double.infinity,
          height: fillHeight ? constraints.maxHeight : null,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withValues(alpha: 0.78),
            borderRadius: radius,
            border: Border.all(
              color: widget.error
                  ? colorScheme.error.withValues(alpha: 0.38)
                  : colorScheme.outlineVariant.withValues(alpha: 0.78),
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
            child: Row(
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
                  Container(
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
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: widget.error
                            ? colorScheme.error
                            : colorScheme.primary,
                        fontWeight: FontWeight.w800,
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
                if (document != null && document.containerPaths.length > 1) ...[
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
                  kOpenHandHGap4,
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
                  kOpenHandHGap4,
                ],
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
                          zh: document == null ? '复制文本' : '复制 JSON',
                          zhHant: document == null ? '複製文字' : '複製 JSON',
                          en: document == null ? 'Copy text' : 'Copy JSON',
                          fr: document == null
                              ? 'Copier le texte'
                              : 'Copier le JSON',
                          de: document == null
                              ? 'Text kopieren'
                              : 'JSON kopieren',
                          ja: document == null ? 'テキストをコピー' : 'JSON をコピー',
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
          ),
          if (fillHeight)
            Expanded(
              child: _jsonTreeScrollableBody(context: context, child: body),
            )
          else
            _jsonTreePreviewBody(
              context: context,
              clipped: _offersFullView,
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
                    duration: expanded
                        ? kOpenHandJsonTreeExpandDuration
                        : kOpenHandJsonTreeCollapseDuration,
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
        InkWell(
          borderRadius: kOpenHandBorderRadius4,
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

class _JsonTreeEmpty extends StatelessWidget {
  const _JsonTreeEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.62),
        borderRadius: kOpenHandBorderRadius7,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.62),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          kOpenHandHGap8,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
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
  final duration = openHandMotionDuration(
    context,
    expanding
        ? kOpenHandJsonTreeExpandDuration
        : kOpenHandJsonTreeCollapseDuration,
  );
  if (duration <= Duration.zero) return child;
  return AnimatedSize(
    duration: duration,
    curve: kOpenHandJsonTreeMotionCurve,
    alignment: Alignment.topCenter,
    child: child,
  );
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
  required bool clipped,
  required Widget child,
}) {
  if (!clipped) return child;
  final fade = Theme.of(context).colorScheme.surfaceContainer;
  return ClipRRect(
    child: Stack(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: kOpenHandJsonTreePreviewMaxHeight,
          ),
          child: _jsonTreeScrollableBody(context: context, child: child),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 36,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    fade.withValues(alpha: 0),
                    fade.withValues(alpha: 0.94),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _OpenHandJsonFullViewDialog extends StatelessWidget {
  const _OpenHandJsonFullViewDialog({
    required this.text,
    required this.sourceText,
    required this.error,
    required this.logTag,
    this.label,
  });

  final String text;
  final String sourceText;
  final String? label;
  final bool error;
  final String logTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = (label ?? '').trim().isEmpty
        ? openHandLocalizedText(
            context,
            zh: '完整内容',
            zhHant: '完整內容',
            en: 'Full content',
            fr: 'Contenu complet',
            de: 'Vollständiger Inhalt',
            ja: '完全な内容',
          )
        : label!.trim();
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
                  color: error
                      ? colorScheme.errorContainer
                      : colorScheme.primaryContainer,
                  borderRadius: kOpenHandBorderRadius14,
                ),
                child: Icon(
                  Icons.data_object_rounded,
                  color: error ? colorScheme.error : colorScheme.primary,
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
                      openHandLocalizedText(
                        context,
                        zh: '共 ${sourceText.trim().length} 字符 · 可滚动阅读与复制',
                        zhHant: '共 ${sourceText.trim().length} 字元 · 可捲動閱讀與複製',
                        en: '${sourceText.trim().length} characters · scroll and copy',
                        fr: '${sourceText.trim().length} caractères · défiler et copier',
                        de: '${sourceText.trim().length} Zeichen · scrollen und kopieren',
                        ja: '${sourceText.trim().length} 文字 · スクロールとコピー',
                      ),
                      maxLines: 1,
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OpenHandJsonTreeView(
              text: text,
              label: label,
              error: error,
              enableFullView: false,
              logTag: logTag,
            ),
          ),
        ),
      ],
    );
  }
}
