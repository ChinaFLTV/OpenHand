import 'package:flutter/widgets.dart';

// 全局布局间距，名称后缀与像素值保持一致；领域内优先使用已有语义常量。

const SizedBox kOpenHandGap2 = SizedBox(height: 2);
const SizedBox kOpenHandGap1 = SizedBox(height: 1);
const SizedBox kOpenHandGap3 = SizedBox(height: 3);
const SizedBox kOpenHandGap4 = SizedBox(height: 4);
const SizedBox kOpenHandGap6 = SizedBox(height: 6);
const SizedBox kOpenHandGap8 = SizedBox(height: 8);
const SizedBox kOpenHandGap10 = SizedBox(height: 10);
const SizedBox kOpenHandGap12 = SizedBox(height: 12);
const SizedBox kOpenHandGap14 = SizedBox(height: 14);
const SizedBox kOpenHandGap16 = SizedBox(height: 16);
const SizedBox kOpenHandGap18 = SizedBox(height: 18);
const SizedBox kOpenHandGap20 = SizedBox(height: 20);
const SizedBox kOpenHandGap24 = SizedBox(height: 24);
const SizedBox kOpenHandGap5 = SizedBox(height: 5);
const SizedBox kOpenHandGap7 = SizedBox(height: 7);
const SizedBox kOpenHandGap9 = SizedBox(height: 9);
const SizedBox kOpenHandGap11 = SizedBox(height: 11);
const SizedBox kOpenHandGap13 = SizedBox(height: 13);
const SizedBox kOpenHandGap15 = SizedBox(height: 15);
const SizedBox kOpenHandGap22 = SizedBox(height: 22);
const SizedBox kOpenHandGap28 = SizedBox(height: 28);

const SizedBox kOpenHandHGap4 = SizedBox(width: 4);
const SizedBox kOpenHandHGap6 = SizedBox(width: 6);
const SizedBox kOpenHandHGap8 = SizedBox(width: 8);
const SizedBox kOpenHandHGap10 = SizedBox(width: 10);
const SizedBox kOpenHandHGap12 = SizedBox(width: 12);
const SizedBox kOpenHandHGap13 = SizedBox(width: 13);
const SizedBox kOpenHandHGap16 = SizedBox(width: 16);
const SizedBox kOpenHandHGap2 = SizedBox(width: 2);
const SizedBox kOpenHandHGap3 = SizedBox(width: 3);
const SizedBox kOpenHandHGap5 = SizedBox(width: 5);
const SizedBox kOpenHandHGap7 = SizedBox(width: 7);
const SizedBox kOpenHandHGap9 = SizedBox(width: 9);
const SizedBox kOpenHandHGap11 = SizedBox(width: 11);
const SizedBox kOpenHandHGap14 = SizedBox(width: 14);
const SizedBox kOpenHandHGap18 = SizedBox(width: 18);
const SizedBox kOpenHandHGap20 = SizedBox(width: 20);
const SizedBox kOpenHandHGap22 = SizedBox(width: 22);
const SizedBox kOpenHandHGap24 = SizedBox(width: 24);

// 全局圆角；重复尺寸使用这些常量，领域内优先使用已有语义常量。
const double kOpenHandRadius2 = 2;
const double kOpenHandRadius3 = 3;
const double kOpenHandRadius4 = 4;
const double kOpenHandRadius5 = 5;
const double kOpenHandRadius6 = 6;
const double kOpenHandRadius7 = 7;
const double kOpenHandRadius8 = 8;
const double kOpenHandRadius9 = 9;
const double kOpenHandRadius10 = 10;
const double kOpenHandRadius11 = 11;
const double kOpenHandRadius12 = 12;
const double kOpenHandRadius13 = 13;
const double kOpenHandRadius14 = 14;
const double kOpenHandRadius15 = 15;
const double kOpenHandRadius16 = 16;
const double kOpenHandRadius17 = 17;
const double kOpenHandRadius18 = 18;
const double kOpenHandRadius20 = 20;
const double kOpenHandRadius22 = 22;
const double kOpenHandRadius24 = 24;
const double kOpenHandRadius26 = 26;
const double kOpenHandRadius30 = 30;
const double kOpenHandRadius32 = 32;

/// 全局常用 [BorderRadius] token，按数值命名并复用高频圆角。
const BorderRadius kOpenHandBorderRadius3 = BorderRadius.all(
  Radius.circular(kOpenHandRadius3),
);
const BorderRadius kOpenHandBorderRadius4 = BorderRadius.all(
  Radius.circular(kOpenHandRadius4),
);
const BorderRadius kOpenHandBorderRadius5 = BorderRadius.all(
  Radius.circular(kOpenHandRadius5),
);
const BorderRadius kOpenHandBorderRadius6 = BorderRadius.all(
  Radius.circular(kOpenHandRadius6),
);
const BorderRadius kOpenHandBorderRadius7 = BorderRadius.all(
  Radius.circular(kOpenHandRadius7),
);
const BorderRadius kOpenHandBorderRadius8 = BorderRadius.all(
  Radius.circular(kOpenHandRadius8),
);
const BorderRadius kOpenHandBorderRadius10 = BorderRadius.all(
  Radius.circular(kOpenHandRadius10),
);
const BorderRadius kOpenHandBorderRadius12 = BorderRadius.all(
  Radius.circular(kOpenHandRadius12),
);
const BorderRadius kOpenHandBorderRadius14 = BorderRadius.all(
  Radius.circular(kOpenHandRadius14),
);
const BorderRadius kOpenHandBorderRadius16 = BorderRadius.all(
  Radius.circular(kOpenHandRadius16),
);
const BorderRadius kOpenHandBorderRadius18 = BorderRadius.all(
  Radius.circular(kOpenHandRadius18),
);
const BorderRadius kOpenHandBorderRadius20 = BorderRadius.all(
  Radius.circular(kOpenHandRadius20),
);
const BorderRadius kOpenHandBorderRadius22 = BorderRadius.all(
  Radius.circular(kOpenHandRadius22),
);
const BorderRadius kOpenHandBorderRadius24 = BorderRadius.all(
  Radius.circular(kOpenHandRadius24),
);
const BorderRadius kOpenHandBorderRadius26 = BorderRadius.all(
  Radius.circular(kOpenHandRadius26),
);
const BorderRadius kOpenHandBorderRadius30 = BorderRadius.all(
  Radius.circular(kOpenHandRadius30),
);
const BorderRadius kOpenHandBorderRadius32 = BorderRadius.all(
  Radius.circular(kOpenHandRadius32),
);

/// 全局布局约束 token —— 收敛重复的 BoxConstraints 字面量。
const BoxConstraints kOpenHandContentMaxWidth360 = BoxConstraints(
  maxWidth: 360,
);

/// 圆角面板左侧强调条宽度。Flutter 禁止 `borderRadius` 搭配非均匀
/// `Border`，强调条必须叠层绘制，不能写成四边不同色/宽的 `Border`。
const double kOpenHandAccentBarWidth = 5;
const double kOpenHandAccentBarWidthCompact = 3;
const double kOpenHandQuoteBorderOpacity = 0.42;
const EdgeInsets kOpenHandMarkdownQuotePadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 11,
);

/// Markdown 引用块等只能给 [BoxDecoration] 的场景。
/// 圆角必须配四边同色同宽边框；左侧强调条请改用叠层色条面板。
BoxDecoration openHandQuoteBoxDecoration({
  required Color accent,
  required Color fill,
  BorderRadius borderRadius = kOpenHandBorderRadius12,
  double borderOpacity = kOpenHandQuoteBorderOpacity,
}) {
  final opacity = borderOpacity.isFinite
      ? borderOpacity.clamp(0.0, 1.0)
      : kOpenHandQuoteBorderOpacity;
  return BoxDecoration(
    color: fill,
    borderRadius: borderRadius,
    border: Border.all(color: accent.withValues(alpha: opacity)),
  );
}

/// 按内容宽度排布子组件，避免 stretch Column 把提示条拉满整行。
/// 长文本仍可在父级最大宽度内换行。
class OpenHandHugWidth extends StatelessWidget {
  const OpenHandHugWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(children: [Flexible(child: child)]);
  }
}
