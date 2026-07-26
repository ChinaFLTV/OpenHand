/// 全局排版 token —— 收敛散落在各处的字体族字面量。
///
/// 约定：代码、日志、终端、报文、哈希等一切需要等宽对齐的文本，一律使用
/// [kOpenHandMonospaceFontFamily]，不再逐处书写具体字体名。
///
/// 为什么不写 `'SF Mono'` / `'Menlo'` / `'JetBrains Mono'` 这类具体族名：
/// Flutter 的 `TextStyle.fontFamily` 只接受**单个**族名，既不解析 CSS 风格的
/// 逗号列表，也不会在族名缺失时回退到等宽族——具体族名在缺少该字体的平台上会
/// 静默退回默认比例字体，直接破坏列对齐。`'monospace'` 是各平台字体管理器都
/// 认识的通用族名，由系统解析到本机最合适的等宽字体。
///
/// 确需按序指定候选族时使用 [kOpenHandMonospaceFontFamilyFallback]，它是
/// `TextStyle.fontFamilyFallback` 期望的列表形式。
library;

const String kOpenHandMonospaceFontFamily = 'monospace';

/// 等宽字体回退链：仅在通用族名解析失败时按序生效。
const List<String> kOpenHandMonospaceFontFamilyFallback = <String>[
  'SF Mono',
  'JetBrains Mono',
  'Menlo',
  'Consolas',
  'DejaVu Sans Mono',
];
