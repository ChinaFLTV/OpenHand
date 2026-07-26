// 页面级错误横幅。
//
// Harness / 工具箱 / 插件三个页面此前各自内联同一份 markup 与配色，调一处
// 视觉要同步改三处。收敛为一份，并统一补上入场动效——原先 error 一置位就
// 硬切出现，与全站其余内容的渐显节奏不一致。

import type { JSX } from 'preact';
import { Appear } from './Appear';
import { ERROR_BANNER_BG, ERROR_BANNER_BORDER } from '../shared/ui/status_palette';
import { classNames } from '../shared/util/class_names';

interface ErrorBannerProps {
  /** 错误文案；为空（含空串）时整条横幅不渲染。 */
  message?: string | null;
  /** 追加 class，用于覆盖默认外边距等。 */
  className?: string;
}

export function ErrorBanner({ message, className }: ErrorBannerProps): JSX.Element | null {
  if (!message) return null;
  return (
    <Appear
      variant="pop"
      className={classNames('rounded-m3-md px-3 py-2 text-sm', className ?? 'mb-4')}
      style={{
        background: ERROR_BANNER_BG,
        color: 'var(--m3-error)',
        border: `1px solid ${ERROR_BANNER_BORDER}`,
      }}
    >
      {message}
    </Appear>
  );
}
