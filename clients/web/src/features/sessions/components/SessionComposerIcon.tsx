import { svgIconProps } from '../../../shared/ui/svg_icon';

export type ComposerIconName = 'attachment' | 'chat' | 'chevronDown' | 'chevronUp' | 'close' | 'copy' | 'edit' | 'file' | 'follow' | 'goal' | 'guide' | 'history' | 'image' | 'knowledge' | 'model' | 'mode' | 'pause' | 'plan' | 'play' | 'permission' | 'plus' | 'research' | 'refresh' | 'restore' | 'send' | 'sound' | 'spark' | 'stop' | 'trash' | 'video';

export function ComposerIcon({ name, size = 18 }: { name: ComposerIconName; size?: number }) {
  // 描边属性挂在 <svg> 上由子元素继承，无需逐个图形重复下发。
  const common = svgIconProps({ size });
  switch (name) {
    case 'attachment':
      return (
        <svg {...common}>
          <path d="M21.4 11.6 12 21a5.2 5.2 0 0 1-7.4-7.4l9.7-9.7a3.5 3.5 0 0 1 5 5l-9.8 9.8a1.8 1.8 0 0 1-2.6-2.6l8.9-8.9" />
        </svg>
      );
    case 'chat':
      return (
        <svg {...common}>
          <path d="M5 6.5A3.5 3.5 0 0 1 8.5 3h7A3.5 3.5 0 0 1 19 6.5v5A3.5 3.5 0 0 1 15.5 15h-4.7L6 19v-4.2a3.5 3.5 0 0 1-1-2.3z" />
          <path d="M9 8h6M9 11h3.8" />
        </svg>
      );
    case 'chevronDown':
      return (
        <svg {...common}>
          <path d="m7 10 5 5 5-5" />
        </svg>
      );
    case 'chevronUp':
      return (
        <svg {...common}>
          <path d="m7 14 5-5 5 5" />
        </svg>
      );
    case 'close':
      return (
        <svg {...common}>
          <path d="M7 7l10 10M17 7 7 17" />
        </svg>
      );
    case 'copy':
      return (
        <svg {...common}>
          <rect x="8" y="8" width="11" height="11" rx="2" />
          <path d="M5 15V7a2 2 0 0 1 2-2h8" />
        </svg>
      );
    case 'edit':
      return (
        <svg {...common}>
          <path d="M4 20h4.4L19 9.4A2.1 2.1 0 0 0 16 6.4L5.4 17H4z" />
          <path d="m14.8 7.6 1.6 1.6" />
        </svg>
      );
    case 'file':
      return (
        <svg {...common}>
          <path d="M7 3h6l4 4v14H7z" />
          <path d="M13 3v5h5M9 13h6M9 17h4" />
        </svg>
      );
    case 'follow':
      return (
        <svg {...common}>
          <path d="M12 5v10M8 11l4 4 4-4M5 19h14" />
        </svg>
      );
    case 'goal':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="7" />
          <circle cx="12" cy="12" r="3" />
          <path d="M12 2v3M12 19v3M2 12h3M19 12h3" />
        </svg>
      );
    case 'guide':
      return (
        <svg {...common}>
          <path d="M9 18h6M10 22h4" />
          <path d="M8.2 14.4a6 6 0 1 1 7.6 0c-.8.6-1.1 1.4-1.2 2.6H9.4c-.1-1.2-.4-2-1.2-2.6z" />
          <path d="M12 7.5V11l2 1.2" />
        </svg>
      );
    case 'history':
      return (
        <svg {...common}>
          <path d="M3 12a9 9 0 1 0 3-6.7" />
          <path d="M3 4.5v4h4" />
          <path d="M12 7v5l3 2" />
        </svg>
      );
    case 'refresh':
      return (
        <svg {...common}>
          <path d="M4 12a8 8 0 0 1 13.4-5.9" />
          <path d="M17 3v4h-4" />
          <path d="M20 12a8 8 0 0 1-13.4 5.9" />
          <path d="M7 21v-4h4" />
        </svg>
      );
    case 'image':
      return (
        <svg {...common}>
          <path d="M5 5h14v14H5z" />
          <path d="m5 16 4.5-4.5 3.5 3.5 2-2 4 4" />
          <path d="M14.5 8.5h.01" />
        </svg>
      );
    case 'knowledge':
      return (
        <svg {...common}>
          <path d="M5 5.8A2.8 2.8 0 0 1 7.8 3H19v15H8a3 3 0 0 0-3 3z" />
          <path d="M5 5.8V21" />
          <path d="M9 7h6M9 11h7M9 15h5" />
        </svg>
      );
    case 'model':
      return (
        <svg {...common}>
          <rect x="7" y="7" width="10" height="10" rx="2" />
          <path d="M9 3v4M15 3v4M9 17v4M15 17v4M3 9h4M3 15h4M17 9h4M17 15h4" />
          <path d="M10 12h4" />
        </svg>
      );
    case 'mode':
      return (
        <svg {...common}>
          <path d="M5 7h8M17 7h2M5 12h2M11 12h8M5 17h10M19 17h0" />
          <path d="M13 5v4M9 10v4M15 15v4" />
        </svg>
      );
    case 'permission':
      return (
        <svg {...common}>
          <path d="M12 3 5 6v5c0 4.4 2.8 8.4 7 10 4.2-1.6 7-5.6 7-10V6z" />
          <path d="m9.5 12 1.7 1.7 3.6-4" />
        </svg>
      );
    case 'pause':
      return (
        <svg {...common}>
          <rect x="7" y="5" width="3.5" height="14" rx="1" />
          <rect x="13.5" y="5" width="3.5" height="14" rx="1" />
        </svg>
      );
    case 'plan':
      return (
        <svg {...common}>
          <path d="M7 4h10a2 2 0 0 1 2 2v14H5V6a2 2 0 0 1 2-2z" />
          <path d="M9 8h6M9 12h6M9 16h3" />
          <path d="m15 16 1.2 1.2L19 14.4" />
        </svg>
      );
    case 'play':
      return (
        <svg {...common}>
          <path d="M8 5v14l11-7z" />
        </svg>
      );
    case 'plus':
      return (
        <svg {...common}>
          <path d="M12 5v14M5 12h14" />
        </svg>
      );
    case 'research':
      return (
        <svg {...common}>
          <path d="M10.5 18a7.5 7.5 0 1 1 5.3-2.2L21 21" />
          <path d="M8 10h5M8 13h3" />
        </svg>
      );
    case 'restore':
      return (
        <svg {...common}>
          <path d="M4 12a8 8 0 1 0 2.7-6" />
          <path d="M4 4.5v5h5" />
          <path d="M12 8v4l3 2" />
        </svg>
      );
    case 'send':
      return (
        <svg {...common}>
          <path d="M4 12 20 4l-5 16-3-7z" />
          <path d="m12 13 4-5" />
        </svg>
      );
    case 'sound':
      return (
        <svg {...common}>
          <path d="M4 10v4h4l5 4V6L8 10z" />
          <path d="M16 9.5a4 4 0 0 1 0 5M19 7a8 8 0 0 1 0 10" />
        </svg>
      );
    case 'spark':
      return (
        <svg {...common}>
          <path d="m12 3 1.6 5.2L19 10l-5.4 1.8L12 17l-1.6-5.2L5 10l5.4-1.8z" />
          <path d="M19 16v4M17 18h4" />
        </svg>
      );
    case 'stop':
      return (
        <svg {...common}>
          <rect x="7" y="7" width="10" height="10" rx="2" />
        </svg>
      );
    case 'trash':
      return (
        <svg {...common}>
          <path d="M4 7h16M9 7V5h6v2M8 10v8M12 10v8M16 10v8" />
          <path d="M6.5 7 7.4 21h9.2l.9-14" />
        </svg>
      );
    case 'video':
      return (
        <svg {...common}>
          <path d="M5 7h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5z" />
          <path d="m17 10 4-2.5v9L17 14" />
        </svg>
      );
    default:
      return (
        <svg {...common}>
          <path d="M12 3v18M3 12h18" />
        </svg>
      );
  }
}
