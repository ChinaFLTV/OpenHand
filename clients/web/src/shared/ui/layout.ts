// Web 主工作台布局契约：会话列表 / 会话详情水平铺满视口。
// 气泡宽度用「百分比 + 像素上限」双约束，避免超宽屏长行难读，又充分利用横向空间。

export const PAGE_SHELL_CLASS = 'oh-page-shell';
export const SESSIONS_SHELL_CLASS = 'oh-sessions-shell';
export const SESSION_DETAIL_SHELL_CLASS = 'oh-session-detail-shell';

/** 消息气泡最大宽度：按消息形态分层，统一管理便于后续调优。 */
export const MESSAGE_BUBBLE_MAX_WIDTH = {
  wideSystem: 'min(96%, 1480px)',
  htmlAssistant: 'min(96%, 1520px)',
  expertRequest: 'min(92%, 1280px)',
  user: 'min(72%, 1040px)',
  assistant: 'min(94%, 1360px)',
} as const;

export type MessageBubbleWidthKey = keyof typeof MESSAGE_BUBBLE_MAX_WIDTH;

export function messageBubbleMaxWidth(
  key: MessageBubbleWidthKey,
): (typeof MESSAGE_BUBBLE_MAX_WIDTH)[MessageBubbleWidthKey] {
  return MESSAGE_BUBBLE_MAX_WIDTH[key];
}
