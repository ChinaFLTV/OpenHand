import { useEffect, useState } from 'preact/hooks';
import { t } from '../i18n';
import { useReducedMotion } from '../hooks/useReducedMotion';

export type MediaGenerationMode = 'image' | 'video' | 'audio' | 'deep_research';

interface MediaGeneratingPlaceholderProps {
  mode: MediaGenerationMode;
}

const MEDIA_GENERATION_PLACEHOLDER_EXIT_MS = 260;

const MODE_CONFIG: Record<MediaGenerationMode, { labelKey: string; fallback: string }> = {
  image: { labelKey: 'detail.creation.generatingImage', fallback: '正在生成图片…' },
  video: { labelKey: 'detail.creation.generatingVideo', fallback: '正在生成视频…' },
  audio: { labelKey: 'detail.creation.generatingAudio', fallback: '正在生成音频…' },
  deep_research: { labelKey: 'detail.creation.researching', fallback: '正在深度研究…' },
};

function MediaGeneratingIcon({ mode }: { mode: MediaGenerationMode }) {
  const common = {
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: '1.9',
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
    'aria-hidden': true,
  } as const;
  switch (mode) {
    case 'image':
      return <svg {...common}><rect x="3.5" y="5" width="17" height="14" rx="2.5" /><path d="m6.5 16 4.2-4.2 3 3 2-2 2.8 3.2" /><circle cx="8.7" cy="9" r="1.1" /></svg>;
    case 'audio':
      return <svg {...common}><path d="M9 18V6l10-2v12" /><circle cx="7" cy="18" r="2" /><circle cx="17" cy="16" r="2" /></svg>;
    case 'deep_research':
      return <svg {...common}><circle cx="11" cy="11" r="6" /><path d="m16 16 4 4" /><path d="M9 9.5h4M9 12.5h3" /></svg>;
    case 'video':
    default:
      return <svg {...common}><rect x="4" y="7" width="12.5" height="10" rx="2" /><path d="m16.5 11 4-2.4v6.8l-4-2.4" /></svg>;
  }
}

export function MediaGeneratingPlaceholder({ mode }: MediaGeneratingPlaceholderProps) {
  const config = MODE_CONFIG[mode] ?? MODE_CONFIG.image;
  const label = t(config.labelKey, config.fallback);

  return (
    <div
      class="oh-media-generating-placeholder"
      role="status"
      aria-label={label}
    >
      <div class="oh-media-generating-shimmer" />
      <div class="oh-media-generating-content">
        <span class="oh-media-generating-indicator" aria-hidden="true">
          <span class="oh-media-generating-icon">
            <MediaGeneratingIcon mode={mode} />
          </span>
        </span>
        <span class="oh-media-generating-label">{label}</span>
      </div>
    </div>
  );
}

export function MediaGeneratingPlaceholderTransition(props: {
  mode: MediaGenerationMode | null;
  className?: string;
}) {
  const reduceMotion = useReducedMotion();
  const [renderedMode, setRenderedMode] = useState<MediaGenerationMode | null>(props.mode);
  const [exiting, setExiting] = useState(false);

  useEffect(() => {
    if (props.mode) {
      setRenderedMode(props.mode);
      setExiting(false);
      return undefined;
    }
    if (!renderedMode) return undefined;
    if (reduceMotion) {
      setRenderedMode(null);
      setExiting(false);
      return undefined;
    }
    setExiting(true);
    const timer = window.setTimeout(() => {
      setRenderedMode(null);
      setExiting(false);
    }, MEDIA_GENERATION_PLACEHOLDER_EXIT_MS);
    return () => window.clearTimeout(timer);
  }, [props.mode, reduceMotion, renderedMode]);

  if (!renderedMode) return null;
  const shellClass = [
    props.className ?? '',
    exiting ? 'oh-media-generation-exit-shell' : '',
  ].filter(Boolean).join(' ');
  return (
    <div class={shellClass || undefined}>
      <MediaGeneratingPlaceholder mode={renderedMode} />
    </div>
  );
}
