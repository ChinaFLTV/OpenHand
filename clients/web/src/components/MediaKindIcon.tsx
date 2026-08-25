// 媒体类别图标（图片 / 视频 / 音频 / 文件）。

import type { JSX } from 'preact';
import { svgIconProps } from '../shared/ui/svg_icon';

type MediaKindIconName = 'image' | 'video' | 'audio' | 'file';

const MEDIA_KIND_ICON_STROKE_WIDTH = 1.9;

export function MediaKindIcon({
  kind,
  size = 16,
}: {
  kind: MediaKindIconName;
  size?: number;
}): JSX.Element {
  const common = svgIconProps({
    size,
    strokeWidth: MEDIA_KIND_ICON_STROKE_WIDTH,
  });
  switch (kind) {
    case 'image':
      return <svg {...common}><rect x="4" y="5" width="16" height="14" rx="2.5" /><path d="m7 16 4-4 3 3 2-2 3 3" /><circle cx="9" cy="9" r="1.2" /></svg>;
    case 'video':
      return <svg {...common}><rect x="4" y="7" width="12" height="10" rx="2" /><path d="m16 11 4-2.5v7L16 13" /></svg>;
    case 'audio':
      return <svg {...common}><path d="M9 18V6l10-2v12" /><circle cx="7" cy="18" r="2" /><circle cx="17" cy="16" r="2" /></svg>;
    default:
      return <svg {...common}><path d="M7 3h7l3 3v15H7z" /><path d="M14 3v4h4" /><path d="M9.5 12h5M9.5 16h4" /></svg>;
  }
}
