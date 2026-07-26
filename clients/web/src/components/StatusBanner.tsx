// 页面级状态横幅（成功 / 失败）。
//
// 此前全站有两套长相：设置页这一套走主题变量（--m3-error / --m3-error-container），
// Harness / 工具箱 / 插件三页那套写死 rgba 红。同一种「出错了」在不同页面长得不一样，
// 且写死的那套在暗色主题下对比度不受控。统一保留主题化的这一套。

import type { ComponentChildren, JSX } from 'preact';
import { Appear } from './Appear';
import { classNames } from '../shared/util/class_names';

export type StatusBannerTone = 'success' | 'error';

interface StatusBannerProps {
  tone: StatusBannerTone;
  children: ComponentChildren;
  /** 追加 class，用于覆盖默认外边距等。 */
  className?: string;
}

export function StatusBanner({
  tone,
  children,
  className,
}: StatusBannerProps): JSX.Element {
  return (
    <Appear
      variant="pop"
      className={classNames(
        'oh-status-banner',
        `is-${tone}`,
        tone === 'success' ? 'oh-pulse-soft' : '',
        className,
      )}
    >
      {children}
    </Appear>
  );
}

interface ErrorBannerProps {
  /** 错误文案；为空（含空串）时整条横幅不渲染。 */
  message?: string | null;
  /** 追加 class，用于覆盖默认外边距等。 */
  className?: string;
}

/// 错误横幅：[StatusBanner] 的常用形态，空文案时整条不渲染。
export function ErrorBanner({
  message,
  className,
}: ErrorBannerProps): JSX.Element | null {
  if (!message) return null;
  return (
    <StatusBanner tone="error" className={className ?? 'mb-4'}>
      {message}
    </StatusBanner>
  );
}
