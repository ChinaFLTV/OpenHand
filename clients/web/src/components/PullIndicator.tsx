// 下拉刷新指示条：在顶部显示一个小圆环，跟随 pulled 距离呈现。
// 在 SessionsPage / SessionDetailPage 共用。
//
// 视觉：
// - 未达到阈值：半透明圆环 + "下拉以刷新"
// - 达到阈值：实心圆环 + "松开即可刷新"
// - 刷新中：旋转动画 + "正在刷新…"

import { t } from '../i18n';

export interface PullIndicatorProps {
  pulled: number;
  refreshing: boolean;
  willRelease: boolean;
  /// 触发阈值（来自 hook）。
  activationDistance: number;
}

export function PullIndicator({
  pulled,
  refreshing,
  willRelease,
  activationDistance,
}: PullIndicatorProps) {
  if (pulled <= 0 && !refreshing) return null;
  const progress = refreshing ? 1 : Math.min(1, pulled / activationDistance);
  const label = refreshing
    ? t('common.pull.refreshing', '正在刷新…')
    : willRelease
      ? t('common.pull.release', '松开即可刷新')
      : t('common.pull.pull', '下拉以刷新');
  return (
    <div
      class="flex items-center justify-center gap-2 text-xs select-none pointer-events-none"
      style={{
        height: `${Math.max(8, pulled)}px`,
        color: 'var(--m3-on-surface-variant)',
        transition: refreshing ? 'height 200ms ease-out' : 'none',
      }}
      aria-hidden
    >
      <svg
        width={18}
        height={18}
        viewBox="0 0 36 36"
        style={{
          transform: refreshing ? 'rotate(0deg)' : `rotate(${progress * 360}deg)`,
          animation: refreshing ? 'oh-spin 900ms linear infinite' : undefined,
          opacity: refreshing ? 1 : 0.45 + progress * 0.55,
        }}
      >
        <circle
          cx="18"
          cy="18"
          r="14"
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          stroke-linecap="round"
          stroke-dasharray={`${progress * 70} 200`}
        />
      </svg>
      <span>{label}</span>
    </div>
  );
}
