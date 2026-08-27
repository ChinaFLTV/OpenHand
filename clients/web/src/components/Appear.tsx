// 列表/卡片入场动画封装。
// - 默认 fadeInUp，可选 'pop' 形态（用于按钮/胶囊态元素）。
// - index 控制错峰阶位，1..12 之间映射到 .oh-appear-stagger-N，超界回退到 12。
// - 「降低动效」开启时，CSS 媒体查询会把所有动画时长压到 0.001ms，等价于直出。
// - 同名 class 与 children 的 className 合并；不引入额外 DOM 包装层。

import type { ComponentChildren, JSX } from 'preact';
import { classNames } from '../shared/util/class_names';

type AppearVariant = 'up' | 'pop' | 'page';

interface AppearProps {
  children: ComponentChildren;
  /** 进场动画形态。默认 'up'（fade + translateY 8px）。 */
  variant?: AppearVariant;
  /** 错峰阶位，1..12。0 / undefined 不延迟。 */
  index?: number;
  /** 包装容器标签，默认 div。需要嵌在 <li> 等场景时改成 'li'/'section' 即可。 */
  as?: keyof JSX.IntrinsicElements;
  className?: string;
  style?: JSX.CSSProperties;
}

const variantClass: Record<AppearVariant, string> = {
  up: 'oh-appear-up',
  pop: 'oh-appear-pop',
  page: 'oh-page-fade',
};

export function Appear(props: AppearProps): JSX.Element {
  const { children, variant = 'up', index, as = 'div', className, style } = props;
  const Tag = as as 'div';
  const stagger = index && index > 0 ? `oh-appear-stagger-${Math.min(12, index)}` : '';
  const cls = classNames(variantClass[variant], stagger, className);
  return (
    <Tag class={cls} style={style}>
      {children}
    </Tag>
  );
}
