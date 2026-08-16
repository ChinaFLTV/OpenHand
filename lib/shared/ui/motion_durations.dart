/// 全局动效时长 token —— 收敛 `duration:` / `reverseDuration:` 位置的
/// 裸毫秒字面量，数值即现网手感，替换绝对零行为差异。
///
/// 约定：
///   * 仅动效使用这些 token；展示/交互计时（SnackBar 显示时长、Tooltip
///     waitDuration、轮询、超时等）不属于动效，继续用各自的具名常量。
///   * 命名以毫秒值为后缀（同值同源锚点）：全库同档动效可检索、可盘点，
///     调档时先改名再改值，避免名值背离。
///   * 全库仅出现一次的微调值允许继续写字面量（独有调参点，无漂移风险）；
///     出现两次即应改用或新增 token。
///   * 领域内已有语义 token 的继续用语义 token（如卡片折叠的
///     kCardMotionDuration*、对话框动画设置体系），本文件不替代它们。
library;

// ── 过渡档（进出场 / 状态切换） ──────────────────────────────────────────
const Duration kOpenHandMotion80 = Duration(milliseconds: 80);
const Duration kOpenHandMotion120 = Duration(milliseconds: 120);
const Duration kOpenHandMotion140 = Duration(milliseconds: 140);
const Duration kOpenHandMotion160 = Duration(milliseconds: 160);
const Duration kOpenHandMotion170 = Duration(milliseconds: 170);
const Duration kOpenHandMotion180 = Duration(milliseconds: 180);
const Duration kOpenHandMotion200 = Duration(milliseconds: 200);
const Duration kOpenHandMotion220 = Duration(milliseconds: 220);
const Duration kOpenHandMotion240 = Duration(milliseconds: 240);
const Duration kOpenHandMotion260 = Duration(milliseconds: 260);
const Duration kOpenHandMotion280 = Duration(milliseconds: 280);
const Duration kOpenHandMotion320 = Duration(milliseconds: 320);
const Duration kOpenHandMotion340 = Duration(milliseconds: 340);
const Duration kOpenHandMotion380 = Duration(milliseconds: 380);
const Duration kOpenHandMotion400 = Duration(milliseconds: 400);
const Duration kOpenHandMotion420 = Duration(milliseconds: 420);
const Duration kOpenHandMotion520 = Duration(milliseconds: 520);
const Duration kOpenHandMotion660 = Duration(milliseconds: 660);
const Duration kOpenHandMotion950 = Duration(milliseconds: 950);

// ── 环境循环档（shimmer / 呼吸脉冲 / 长渐变） ────────────────────────────
const Duration kOpenHandMotion1200 = Duration(milliseconds: 1200);
const Duration kOpenHandMotion1400 = Duration(milliseconds: 1400);
const Duration kOpenHandMotion1600 = Duration(milliseconds: 1600);
const Duration kOpenHandMotion1800 = Duration(milliseconds: 1800);
const Duration kOpenHandMotion2200 = Duration(milliseconds: 2200);
const Duration kOpenHandMotion2400 = Duration(milliseconds: 2400);
