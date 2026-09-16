import 'package:flutter/material.dart';

/// 提示条、弹窗和状态标记共用的语义色。
@immutable
class OpenHandStatusColors {
  const OpenHandStatusColors._();

  /// 成功、已保存或在线。
  static const Color success = Color(0xFF22C55E);

  /// 错误、失败或破坏性操作。
  static const Color error = Color(0xFFEF4444);

  /// 等待、部分完成或需要注意。
  static const Color warning = Color(0xFFF59E0B);

  /// 轻微波动或接近风险阈值。
  static const Color caution = Color(0xFFEAB308);

  /// 信息或中性提示。
  static const Color info = Color(0xFF3B82F6);

  /// 圆形语义操作按钮的浅底透明度。
  static const double iconButtonFillAlpha = 0.15;

  /// 按语义色给圆形 IconButton 上色，登录/停止/破坏性操作共用。
  static ButtonStyle tintedIconButtonStyle(Color color) => IconButton.styleFrom(
    backgroundColor: color.withValues(alpha: iconButtonFillAlpha),
    foregroundColor: color,
  );

  /// 运行中服务的停止操作按钮样式，与 MCP 服务卡片保持一致。
  static ButtonStyle runningStopButtonStyle() => tintedIconButtonStyle(success);

  /// 登出、取消授权等破坏性圆形操作。
  static ButtonStyle destructiveIconButtonStyle() =>
      tintedIconButtonStyle(error);
}
