import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../util/timer_safety.dart';
import 'markdown_ast_sanitizer.dart';
import 'markdown_math.dart';

List<Widget> buildOpenHandMarkdownWidgets({
  required List<md.Node> nodes,
  required MarkdownBuilderDelegate delegate,
  required bool selectable,
  required MarkdownStyleSheet styleSheet,
  MarkdownImageBuilder? imageBuilder,
  Map<String, MarkdownElementBuilder> builders =
      const <String, MarkdownElementBuilder>{},
}) {
  return MarkdownBuilder(
    delegate: delegate,
    selectable: selectable,
    styleSheet: styleSheet,
    imageDirectory: null,
    imageBuilder: imageBuilder,
    checkboxBuilder: null,
    bulletBuilder: null,
    builders: withOpenHandMarkdownMathBuilders(
      builders,
      fallbackTextStyle: styleSheet.p,
      textColor: styleSheet.p?.color,
    ),
    paddingBuilders: const <String, MarkdownPaddingBuilder>{},
    fitContent: true,
    listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
  ).build(nodes);
}

class _OpenHandMarkdownSelectionDelegate
    extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final selections = selectables
        .map((item) => item.getSelectedContent())
        .whereType<SelectedContent>()
        .toList(growable: false);
    if (selections.isEmpty) return null;
    return SelectedContent(
      plainText: selections.map((item) => item.plainText).join('\n'),
    );
  }
}

class _OpenHandMarkdownSelectionContainer extends StatefulWidget {
  const _OpenHandMarkdownSelectionContainer({required this.child});

  final Widget child;

  @override
  State<_OpenHandMarkdownSelectionContainer> createState() =>
      _OpenHandMarkdownSelectionContainerState();
}

class _OpenHandMarkdownSelectionContainerState
    extends State<_OpenHandMarkdownSelectionContainer> {
  late final _OpenHandMarkdownSelectionDelegate _delegate =
      _OpenHandMarkdownSelectionDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

/// 使用 OpenHand 统一语法解析 Markdown，失败时保留完整原文。
class OpenHandSafeMarkdownBody extends StatefulWidget {
  const OpenHandSafeMarkdownBody({
    super.key,
    required this.data,
    required this.styleSheet,
    this.selectable = false,
    this.streaming = false,
    this.onTapLink,
    this.imageBuilder,
    this.builders = const <String, MarkdownElementBuilder>{},
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final bool selectable;
  final bool streaming;
  final MarkdownTapLinkCallback? onTapLink;
  final MarkdownImageBuilder? imageBuilder;
  final Map<String, MarkdownElementBuilder> builders;

  @override
  State<OpenHandSafeMarkdownBody> createState() =>
      _OpenHandSafeMarkdownBodyState();
}

class _OpenHandSafeMarkdownBodyState extends State<OpenHandSafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  static const Duration _streamingParseInterval = Duration(milliseconds: 96);

  List<Widget> _children = const <Widget>[];
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  String? _lastData;
  int? _lastRenderSignature;
  Timer? _streamingParseTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  @override
  void didUpdateWidget(covariant OpenHandSafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming &&
        oldWidget.streaming &&
        oldWidget.data != widget.data &&
        _children.isNotEmpty) {
      _streamingParseTimer ??= startSafeTimer(_streamingParseInterval, () {
        _streamingParseTimer = null;
        if (mounted) setState(_rebuildIfNeeded);
      });
      return;
    }
    _streamingParseTimer?.cancel();
    _streamingParseTimer = null;
    _rebuildIfNeeded();
  }

  @override
  void dispose() {
    _streamingParseTimer?.cancel();
    _disposeRecognizers(_recognizers);
    super.dispose();
  }

  void _rebuildIfNeeded() {
    final builderKeys = widget.builders.keys.toList(growable: false)..sort();
    final signature = Object.hashAll(<Object?>[
      Theme.of(context).brightness,
      widget.styleSheet.hashCode,
      widget.selectable,
      widget.streaming,
      widget.styleSheet.p,
      widget.styleSheet.code,
      widget.styleSheet.h1,
      widget.styleSheet.h2,
      widget.styleSheet.h3,
      widget.styleSheet.h4,
      widget.styleSheet.h5,
      widget.styleSheet.h6,
      widget.styleSheet.tableHead,
      widget.styleSheet.tableBody,
      widget.styleSheet.tableBorder,
      widget.styleSheet.tableCellsDecoration,
      widget.styleSheet.tableHeadCellsDecoration,
      widget.styleSheet.blockquoteDecoration,
      widget.styleSheet.codeblockDecoration,
      ...builderKeys,
      for (final key in builderKeys) widget.builders[key].runtimeType,
    ]);
    if (_lastData == widget.data && _lastRenderSignature == signature) return;
    _lastData = widget.data;
    _lastRenderSignature = signature;

    final previousRecognizers = List<GestureRecognizer>.of(_recognizers);
    _recognizers.clear();
    final source = normalizeOpenHandMarkdownSource(
      widget.data.isEmpty ? ' ' : widget.data,
    );
    try {
      final styleSheet = MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).merge(widget.styleSheet);
      final nodes = parseOpenHandMarkdown(
        source,
        inlineSyntaxes: withOpenHandMarkdownMathInlineSyntaxes(const []),
      );
      _children = buildOpenHandMarkdownWidgets(
        nodes: nodes,
        delegate: this,
        selectable: false,
        styleSheet: styleSheet,
        imageBuilder: widget.imageBuilder,
        builders: widget.builders,
      );
      if (_children.isEmpty && widget.data.isNotEmpty) {
        _children = <Widget>[_buildFallback(styleSheet.p)];
      }
    } catch (_) {
      _disposeRecognizers(_recognizers);
      final styleSheet = MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).merge(widget.styleSheet);
      _children = <Widget>[_buildFallback(styleSheet.p)];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposeRecognizers(previousRecognizers);
    });
  }

  Widget _buildFallback(TextStyle? style) {
    return Text(widget.data, style: style);
  }

  static void _disposeRecognizers(List<GestureRecognizer> recognizers) {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }
    recognizers.clear();
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    final callback = widget.onTapLink;
    if (callback != null) {
      recognizer.onTap = () => callback(text, href, title);
    }
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    return TextSpan(
      text: code.replaceFirst(RegExp(r'\n$'), ''),
      style: styleSheet.code,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _children,
    );
    return widget.selectable && !widget.streaming
        ? SelectionArea(child: _OpenHandMarkdownSelectionContainer(child: body))
        : body;
  }
}
