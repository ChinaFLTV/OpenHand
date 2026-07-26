/// 深色控制台日志区共用的配色令牌、行着色规则与面板组件。
///
/// 插件服务与 MCP STDIO 的安装 / 运维弹窗此前各自内联了一份深色终端面板，
/// 连「哪一行算失败」都有三套互不一致的判定（一处只认行首 `✗`、一处不上
/// 成功色、一处另认方括号前缀），配色也全是散落的十六进制字面量。这里收敛
/// 为一份规则与一组具名令牌。
library;

import 'package:flutter/material.dart';

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
}

/// 控制台日志正文的字号与行高。
const double kOpenHandConsoleLogFontSize = 11;
const double kOpenHandConsoleLogLineHeight = 1.5;

/// 安装 / 运维控制台的单行着色规则；仅本文件的面板使用。
///
/// 判定顺序为失败 → 成功 → 方括号提示 → 正文；失败优先，避免
/// `[npm] ✗ failed` 这类同时命中多条时被标成提示色。
Color _consoleLogLineColor(String line) {
  if (line.contains('✗') || line.toLowerCase().contains('error')) {
    return OpenHandConsolePalette.error;
  }
  if (line.contains('✓')) return OpenHandConsolePalette.success;
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
class OpenHandConsoleLogPanel extends StatelessWidget {
  const OpenHandConsoleLogPanel({
    super.key,
    required this.lineCount,
    required this.lineAt,
    required this.controller,
    required this.onNotification,
    required this.emptyPlaceholder,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(10),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.lineSpacing = 0,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: OpenHandConsolePalette.surface,
        borderRadius: borderRadius,
      ),
      child: lineCount <= 0
          ? Center(child: emptyPlaceholder)
          : NotificationListener<ScrollNotification>(
              onNotification: onNotification,
              child: ListView.builder(
                controller: controller,
                padding: padding,
                itemCount: lineCount,
                itemBuilder: (listContext, index) {
                  final line = lineAt(index);
                  final text = Text(
                    line,
                    style: _consoleLogTextStyle(
                      _consoleLogLineColor(line),
                    ),
                  );
                  if (lineSpacing <= 0) return text;
                  return Padding(
                    padding: EdgeInsets.only(bottom: lineSpacing),
                    child: text,
                  );
                },
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
///
/// MCP 运维与消息网关运维各写了一份完全相同的外壳，只有底色与圆角按各自面板
/// 定；描边透明度、投影参数、正文排版这些则是逐字重复的。
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
