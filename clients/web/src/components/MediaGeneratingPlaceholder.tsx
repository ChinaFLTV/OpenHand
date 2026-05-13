// 多媒体生成占位卡片：灰阶扫光效果 shimmer，对齐 APP 端
// _PendingCreationPlaceholderCard 的视觉语义。
import { useEffect, useRef } from 'preact/hooks';
import { t } from '../i18n';

type CreationMode = 'image' | 'video' | 'audio' | 'deep_research';

interface MediaGeneratingPlaceholderProps {
  mode: CreationMode;
}

const MODE_CONFIG: Record<CreationMode, { icon: string; labelKey: string; fallback: string }> = {
  image: { icon: '🖼️', labelKey: 'detail.creation.generatingImage', fallback: '正在生成图片…' },
  video: { icon: '🎬', labelKey: 'detail.creation.generatingVideo', fallback: '正在生成视频…' },
  audio: { icon: '🎵', labelKey: 'detail.creation.generatingAudio', fallback: '正在生成音频…' },
  deep_research: { icon: '🔍', labelKey: 'detail.creation.researching', fallback: '正在深度研究…' },
};

export function MediaGeneratingPlaceholder({ mode }: MediaGeneratingPlaceholderProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const rafRef = useRef<number>(0);
  const startRef = useRef<number>(0);

  useEffect(() => {
    startRef.current = performance.now();
    const animate = () => {
      const el = containerRef.current;
      if (!el) return;
      const elapsed = performance.now() - startRef.current;
      // 1800ms 周期，与 APP 端一致
      const t = (elapsed % 1800) / 1800;
      const x = -100 + t * 300;
      el.style.setProperty('--shimmer-x', `${x}%`);
      rafRef.current = requestAnimationFrame(animate);
    };
    rafRef.current = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(rafRef.current);
  }, []);

  const config = MODE_CONFIG[mode] ?? MODE_CONFIG.image;
  const label = t(config.labelKey, config.fallback);

  return (
    <div
      ref={containerRef}
      class="oh-media-generating-placeholder"
      role="status"
      aria-label={label}
    >
      <div class="oh-media-generating-shimmer" />
      <div class="oh-media-generating-content">
        <span class="oh-media-generating-icon" aria-hidden>{config.icon}</span>
        <span class="oh-media-generating-label">{label}</span>
      </div>
    </div>
  );
}
