import 'package:flutter/widgets.dart';

/// 全局间距 token —— 收敛 `SizedBox(height:)` / `SizedBox(width:)` 位置
/// 的裸数值字面量，数值即现网常用值，替换绝对零行为差异。
///
/// 约定：
///   * 仅用于布局间距（SizedBox / Padding / EdgeInsets 的固定值）。
///   * 命名以像素值为后缀：全库同档间距可检索、可盘点，
///     调档时先改名再改值，避免名值背离。
///   * 领域内已有语义常量的继续用语义常量，本文件不替代它们。

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
const SizedBox kOpenHandGap26 = SizedBox(height: 26);
const SizedBox kOpenHandGap28 = SizedBox(height: 28);
const SizedBox kOpenHandWidth4 = SizedBox(width: 4);
const SizedBox kOpenHandWidth10 = SizedBox(width: 10);
const SizedBox kOpenHandWidth12 = SizedBox(width: 12);
const SizedBox kOpenHandWidth13 = SizedBox(width: 13);
const SizedBox kOpenHandWidth22 = SizedBox(width: 22);

const SizedBox kOpenHandHGap4 = SizedBox(width: 4);
const SizedBox kOpenHandHGap6 = SizedBox(width: 6);
const SizedBox kOpenHandHGap8 = SizedBox(width: 8);
const SizedBox kOpenHandHGap10 = SizedBox(width: 10);
const SizedBox kOpenHandHGap12 = SizedBox(width: 12);
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
const SizedBox kOpenHandHGap24 = SizedBox(width: 24);

/// 全局圆角 token —— 收敛散落的 `BorderRadius.circular(数字)` 字面量，
/// 数值即现网常用值。与间距 token 同源同文件，便于统一管理。
///
/// 约定：
///   * 仅用于 `BorderRadius.circular` / `BorderRadius.all(Radius.circular(...))`
///     位置。
///   * 出现两次及以上的值必须用 token；独有值允许写字面量。
///   * 语义化圆角（如 `_mcpOpsPanelRadius` 等领域内已有常量）继续用语义常量。
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

/// 全局 [BorderRadius] token —— 与上面的标量一一对应。
///
/// 此前各功能模块各自声明 `BorderRadius.all(Radius.circular(kOpenHandRadiusN))`，
/// 且尺寸命名互相矛盾（同一个 12 在一处叫 Medium、另一处叫 XLarge），改一次
/// 圆角要跨七八个文件对照。统一按数值命名后，一个值只有一个名字。
const BorderRadius kOpenHandBorderRadius2 = BorderRadius.all(
  Radius.circular(kOpenHandRadius2),
);
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
