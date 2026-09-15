import { createContext } from 'preact';
import type { MediaItem } from './MessageMedia';

export interface ImageGalleryEntry {
  item: MediaItem;
  url: string;
  messageId?: string;
  onLocate?: () => void;
}
export const ImageMessageContext = createContext<{
  messageId: string;
  onLocate?: () => void;
  images?: () => Iterable<ImageGalleryEntry>;
} | undefined>(undefined);
const MAX_GALLERY_IMAGES = 256;

export function collectImageGallery(root: HTMLElement, selected: HTMLImageElement): {
  images: ImageGalleryEntry[]; index: number;
} {
  function* entries(): Iterable<ImageGalleryEntry> {
    const seen = new Set<string>();
    for (const image of root.querySelectorAll('img')) {
      const url = image.currentSrc || image.src;
      if (!url || seen.has(url) || !/^(https?:|blob:|data:image\/)/i.test(url)) continue;
      seen.add(url);
      yield { item: { path: url, name: image.alt || image.title || '图片', kind: 'image', isDirectUrl: true }, url };
    }
  }
  const url = selected.currentSrc || selected.src;
  const image: ImageGalleryEntry = {
    item: { path: url, name: selected.alt || selected.title || '图片', kind: 'image', isDirectUrl: true }, url,
  };
  return resolveImageGallery(entries(), image)
    ?? { images: /^(https?:|blob:|data:image\/)/i.test(url) ? [image] : [], index: 0 };
}

// 点击时收集有界快照，同一图片在不同消息中保留独立定位。
export function resolveImageGallery(
  images: Iterable<ImageGalleryEntry>, selected: ImageGalleryEntry, messageId?: string,
): { images: ImageGalleryEntry[]; index: number } | undefined {
  const window: ImageGalleryEntry[] = [];
  let index = -1;
  for (const image of images) {
    if (index < 0 && (image.url === selected.url || image.item.path === selected.item.path)
      && (messageId === undefined || image.messageId === messageId)) index = window.length;
    window.push(image);
    if (window.length > MAX_GALLERY_IMAGES) {
      window.shift();
      if (index >= 0) index--;
    }
    if (index >= 0 && index <= MAX_GALLERY_IMAGES / 2 && window.length === MAX_GALLERY_IMAGES) break;
  }
  return index < 0 ? undefined : { images: window, index };
}
