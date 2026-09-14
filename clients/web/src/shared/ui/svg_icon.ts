// 线性图标的共享 SVG 属性；未指定的尺寸与 class 由调用方控制。

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
