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

const SizedBox kOpenHandHGap4 = SizedBox(width: 4);
const SizedBox kOpenHandHGap6 = SizedBox(width: 6);
const SizedBox kOpenHandHGap8 = SizedBox(width: 8);
const SizedBox kOpenHandHGap10 = SizedBox(width: 10);
const SizedBox kOpenHandHGap12 = SizedBox(width: 12);
const SizedBox kOpenHandHGap16 = SizedBox(width: 16);
