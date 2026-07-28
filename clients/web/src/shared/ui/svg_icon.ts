// svg_icon —— 线性图标 <svg> 通用属性包。
//
// 各图标组件此前各自内联同一份 viewBox/stroke 属性对象（仅 strokeWidth、
// 尺寸与 class 不同，甚至存在 '1.9' 字符串与 1.9 数字的混写），统一从
// 这里生成。size / class 缺省时对应属性值为 undefined，Preact 渲染时
// 自动跳过，与原先不声明该属性完全等价。

interface SvgIconPropsOptions {
  /** 同时作为 width 与 height；不传则由使用处自行控制尺寸。 */
  size?: number;
  /** 线宽，默认 2（图标族另一常用档为 1.9）。 */
  strokeWidth?: number;
  /** 附加到 <svg> 上的 class。 */
  class?: string;
}

export function svgIconProps({
  size,
  strokeWidth = 2,
  class: className,
}: SvgIconPropsOptions = {}) {
  return {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    focusable: 'false',
    'aria-hidden': true,
    class: className,
  };
}
