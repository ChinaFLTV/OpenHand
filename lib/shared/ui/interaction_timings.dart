/// 交互计时 token —— 收敛「悬停多久才出提示」这类展示/交互延迟。
///
/// 与 `motion_durations.dart` 的分工：那里只放动效时长（进出场、状态切换），
/// 这里放的是不参与动画、但决定交互手感的等待时长。两者不可互相替代。
///
/// 约定与动效 token 一致：全库同档可检索、可盘点；出现两次即应改用或新增
/// token，只出现一次的独有调参点允许继续写字面量。
library;

/// 常规 Tooltip 的悬停停留时长。
///
/// 此前各界面在 200~600ms 之间各写各的，同一个文件里相邻的两个按钮都可能
/// 不一致；统一到一档后，全应用的悬停手感一致，调整也只需改这里。
const Duration kOpenHandTooltipWait = Duration(milliseconds: 400);

/// 密集可扫视区域（分段条、色带等）的 Tooltip 悬停时长。
///
/// 这类区域相邻命中目标很多，用户会连续横扫查看；沿用常规时长会让每次移动
/// 都要等待，因此单独给一档更短的延迟。
const Duration kOpenHandDenseTooltipWait = Duration(milliseconds: 250);

/// 关闭输入焦点后，等 IME / 焦点链落稳再做校验或发请求。
const Duration kOpenHandFocusSettleDelay = Duration(milliseconds: 80);
