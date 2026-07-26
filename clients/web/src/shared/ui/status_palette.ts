// status_palette —— 状态徽章 / 提示横幅统一配色。
//
// Harness / Plugins / Toolbox 等状态页此前各自内联相同的 rgba/hex 字面量
//（且存在 `.1` 与 `0.10` 混写），集中到这里保证同语义同色、改动一处生效。
// 语义主色（primary / error / on-surface-variant）继续走 M3 CSS 变量，
// 本文件只收敛无 CSS 变量可用的固定强调色与低透明度背景。

/** 成功 / 已完成状态前景色。 */
export const STATUS_SUCCESS_COLOR = '#16a34a';

/** 成功 / 已完成状态徽章背景。 */
export const STATUS_SUCCESS_BG = 'rgba(22,163,74,0.10)';

/** 进行中状态徽章背景（与 var(--m3-primary) 前景搭配）。 */
export const STATUS_ACTIVE_BG = 'rgba(99,102,241,0.10)';

/** 失败 / 错误状态徽章背景（与 var(--m3-error) 前景搭配）。 */
export const STATUS_ERROR_BG = 'rgba(239,68,68,0.10)';

/** 警示（卸载中 / 降级等）状态前景色。 */
export const STATUS_WARNING_COLOR = '#f59e0b';

/** 警示状态徽章背景。 */
export const STATUS_WARNING_BG = 'rgba(245,158,11,0.10)';

/** 中性 / 未启用状态徽章背景。 */
export const STATUS_NEUTRAL_BG = 'rgba(120,120,120,0.10)';

/** 中性状态的更淡背景（次级条目 / 兜底分支）。 */
export const STATUS_NEUTRAL_BG_FAINT = 'rgba(120,120,120,0.06)';
