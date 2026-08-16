/// 深色控制台日志区共用的配色、行着色规则与面板组件。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

import '../../shared/ui/openhand_spacing.dart';
import 'openhand_typography.dart';

/// 深色控制台面板的配色令牌。
abstract final class OpenHandConsolePalette {
  /// 面板底色。
  static const Color surface = Color(0xFF1E1E1E);

  /// 更深一档的面板底色，用于带边框的嵌入式日志区。
  static const Color deepSurface = Color(0xFF0D1117);

  /// 普通正文行。
  static const Color text = Color(0xFFD4D4D4);

  /// 空行与占位说明这类弱化文本。
  static const Color muted = Color(0xFF808080);

  /// 成功标记行。
  static const Color success = Color(0xFF4ADE80);

  /// 警告标记行。
  static const Color warning = Color(0xFFFBBF24);

  /// 失败标记行。
  static const Color error = Color(0xFFFF6B6B);

  /// 带方括号前缀的提示行（如 `[npm] ...`）。
  static const Color notice = Color(0xFF7DD3FC);

  /// 时间戳前缀行（如 `[19:38:23] 进程已启动`）。
  static const Color timestamp = Color(0xFF93C5FD);

  /// JSON-RPC 摘要行。
  static const Color jsonRpc = Color(0xFFA78BFA);

  // ── GitHub 深色终端配色 ──────────────────────────────────────────
  // 以下取自 GitHub Dark Default 主题，用于 LSP 安装终端与代码高亮。

  /// GitHub 终端：命令行前缀（`$`）。
  static const Color githubCommand = Color(0xFF79C0FF);

  /// GitHub 终端：成功标记（`✓`）。
  static const Color githubSuccess = Color(0xFF3FB950);

  /// GitHub 终端：失败标记（`✗`）。
  static const Color githubError = Color(0xFFF85149);

  /// GitHub 终端：应用前缀（如 `OpenHand:`）。
  static const Color githubNotice = Color(0xFFD29922);

  /// GitHub 终端：默认正文。
  static const Color githubText = Color(0xFFC9D1D9);

  /// GitHub 终端：面板底色。
  static const Color githubSurface = Color(0xFF161B22);

  /// GitHub 终端：边框。
  static const Color githubBorder = Color(0xFF30363D);

  /// GitHub 终端：弱化文本。
  static const Color githubMuted = Color(0xFF8B949E);
}

/// 控制台日志正文的字号与行高。
const double kOpenHandConsoleLogFontSize = 11;
const double kOpenHandConsoleLogLineHeight = 1.5;

/// 安装 / 运维控制台的单行着色规则；仅本文件的面板使用。
///
/// 判定顺序为失败 → 成功 → 方括号提示 → 正文；失败优先，避免
/// `[npm] ✗ failed` 这类同时命中多条时被标成提示色。
Color _consoleLogLineColor(String line) {
  final lower = line.toLowerCase();
  if (line.contains('✗') ||
      lower.contains('error') ||
      lower.contains('[error]') ||
      line.contains('错误')) {
    return OpenHandConsolePalette.error;
  }
  if (line.contains('✓') ||
      lower.contains('[success]') ||
      line.contains('成功')) {
    return OpenHandConsolePalette.success;
  }
  if (lower.contains('[warn') ||
      lower.contains('warning') ||
      line.contains('警告')) {
    return OpenHandConsolePalette.warning;
  }
  if (lower.contains('[debug]') || line.contains('调试')) {
    return OpenHandConsolePalette.muted;
  }
  if (line.startsWith('[') && line.contains(']')) {
    return OpenHandConsolePalette.notice;
  }
  return OpenHandConsolePalette.text;
}

/// 控制台日志正文的文本样式；仅本文件的面板使用。
TextStyle _consoleLogTextStyle(Color color) {
  return TextStyle(
    fontFamily: kOpenHandMonospaceFontFamily,
    fontSize: kOpenHandConsoleLogFontSize,
    height: kOpenHandConsoleLogLineHeight,
    color: color,
  );
}

/// 深色控制台输出面板：等宽正文 + 自动跟随滚动 + 空态占位。
class OpenHandConsoleLogPanel extends StatefulWidget {
  const OpenHandConsoleLogPanel({
    super.key,
    required this.lineCount,
    required this.lineAt,
    required this.controller,
    required this.onNotification,
    required this.emptyPlaceholder,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(10),
    this.borderRadius = kOpenHandBorderRadius8,
    this.lineSpacing = 0,
    this.reverse = false,
  });

  /// 行数与按下标取行分开传入：BoundedLogBuffer 这类环形缓冲因此不必
  /// 每帧复制出一份 List 快照。
  final int lineCount;
  final String Function(int index) lineAt;

  final ScrollController controller;
  final NotificationListenerCallback<ScrollNotification> onNotification;

  /// 尚无输出时展示的占位内容（加载指示器或等待提示）。
  final Widget emptyPlaceholder;

  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// 行间距；0 表示仅靠行高分隔。
  final double lineSpacing;

  /// 是否以倒序列表呈现。倒序列表将最新行固定在滚动起点，适合持续追加日志。
  final bool reverse;

  @override
  State<OpenHandConsoleLogPanel> createState() =>
      _OpenHandConsoleLogPanelState();
}

class _OpenHandConsoleLogPanelState extends State<OpenHandConsoleLogPanel> {
  bool _selectionHeld = false;
  List<String>? _selectionSnapshot;
  bool _selectionUpdateScheduled = false;
  bool _pendingSelectionHeld = false;
  List<String>? _pendingSelectionSnapshot;

  List<String> _snapshotLines() {
    final count = widget.lineCount > 0 ? widget.lineCount : 0;
    return List<String>.generate(count, (index) {
      try {
        return widget.lineAt(index);
      } on Object {
        return '';
      }
    }, growable: false);
  }

  void _queueSelectionUpdate(bool held, {List<String>? snapshot}) {
    _pendingSelectionHeld = held;
    _pendingSelectionSnapshot = snapshot;
    if (_selectionUpdateScheduled) return;
    _selectionUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionUpdateScheduled = false;
      if (!mounted) return;
      final nextHeld = _pendingSelectionHeld;
      final nextSnapshot = _pendingSelectionSnapshot;
      _pendingSelectionSnapshot = null;
      if (_selectionHeld == nextHeld &&
          (nextHeld || _selectionSnapshot == null)) {
        return;
      }
      setState(() {
        _selectionHeld = nextHeld;
        _selectionSnapshot = nextHeld ? nextSnapshot : null;
      });
    });
  }

  void _handleSelectionChanged(SelectedContent? content) {
    final hasContent = content?.plainText.trim().isNotEmpty ?? false;
    if (hasContent) {
      // 选区存在期间冻结日志快照，避免日志追加/环形淘汰同时修改
      // ListView 的可选节点集合。
      _queueSelectionUpdate(true, snapshot: _snapshotLines());
    } else if (_selectionHeld || _pendingSelectionHeld) {
      _queueSelectionUpdate(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _selectionHeld ? _selectionSnapshot : null;
    final lineCount = snapshot?.length ?? widget.lineCount;
    final sourceLineAt = snapshot == null ? widget.lineAt : snapshot.elementAt;
    String lineAt(int index) {
      final sourceIndex = widget.reverse ? lineCount - index - 1 : index;
      return sourceLineAt(sourceIndex);
    }

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: OpenHandConsolePalette.surface,
        borderRadius: widget.borderRadius,
      ),
      child: lineCount <= 0
          ? Center(child: widget.emptyPlaceholder)
          : NotificationListener<ScrollNotification>(
              onNotification: widget.onNotification,
              child: SelectionArea(
                onSelectionChanged: _handleSelectionChanged,
                child: ListView.builder(
                  controller: widget.controller,
                  reverse: widget.reverse,
                  padding: widget.padding,
                  itemCount: lineCount,
                  itemBuilder: (listContext, index) {
                    final line = lineAt(index);
                    final text = Text(
                      line,
                      style: _consoleLogTextStyle(_consoleLogLineColor(line)),
                    );
                    if (widget.lineSpacing <= 0) return text;
                    return Padding(
                      padding: EdgeInsets.only(bottom: widget.lineSpacing),
                      child: text,
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// 终端提示卡片的固定尺寸与配色权重。
const EdgeInsets kOpenHandTerminalCardPadding = EdgeInsets.fromLTRB(
  14,
  12,
  14,
  12,
);
const double _kTerminalCardBorderAlpha = 0.34;
const double _kTerminalCardShadowAlpha = 0.18;
const double _kTerminalCardShadowBlur = 22;
const double _kTerminalCardShadowOffsetY = 12;
const double _kTerminalCardTextAlpha = 0.90;
const double _kTerminalCardFontSize = 13;
const double _kTerminalCardLineHeight = 1.45;

/// 终端风格的命令提示卡片：深色底 + 细描边 + 柔和投影 + 等宽正文。
class OpenHandTerminalHintCard extends StatelessWidget {
  const OpenHandTerminalHintCard({
    super.key,
    required this.backgroundColor,
    required this.borderRadius,
    required this.children,
  });

  final Color backgroundColor;
  final double borderRadius;

  /// 卡片内的命令行，纵向铺开。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(
            alpha: _kTerminalCardBorderAlpha,
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: _kTerminalCardShadowAlpha),
            blurRadius: _kTerminalCardShadowBlur,
            offset: const Offset(0, _kTerminalCardShadowOffsetY),
          ),
        ],
      ),
      child: Padding(
        padding: kOpenHandTerminalCardPadding,
        child: DefaultTextStyle(
          style: TextStyle(
            color: Colors.white.withValues(alpha: _kTerminalCardTextAlpha),
            fontSize: _kTerminalCardFontSize,
            height: _kTerminalCardLineHeight,
            fontFamily: kOpenHandMonospaceFontFamily,
            fontWeight: FontWeight.w700,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
