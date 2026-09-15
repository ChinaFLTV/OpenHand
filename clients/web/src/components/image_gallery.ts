import { createContext } from 'preact';
import type { MediaItem } from './MessageMedia';

export interface ImageGalleryEntry { item: MediaItem; url: string }
export const ImageMessageContext = createContext<(() => void) | undefined>(undefined);
const MAX_GALLERY_IMAGES = 256;

export function collectImageGallery(root: HTMLElement, selected: HTMLImageElement): {
  images: ImageGalleryEntry[]; index: number;
} {
  const images: ImageGalleryEntry[] = [];
  const seen = new Set<string>();
  for (const image of root.querySelectorAll('img')) {
    const url = image.currentSrc || image.src;
    if (!url || seen.has(url) || !/^(https?:|blob:|data:image\/)/i.test(url)) continue;
    if (images.length >= MAX_GALLERY_IMAGES) break;
    seen.add(url);
    images.push({ item: { path: url, name: image.alt || image.title || '图片', kind: 'image', isDirectUrl: true }, url });
  }
  const url = selected.currentSrc || selected.src;
  const index = images.findIndex((image) => image.url === url);
  if (index < 0 && /^(https?:|blob:|data:image\/)/i.test(url)) {
    return { images: [{ item: { path: url, name: selected.alt || selected.title || '图片', kind: 'image', isDirectUrl: true }, url }], index: 0 };
  }
  return { images, index };
}
