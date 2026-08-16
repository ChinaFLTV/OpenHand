import '../../l10n/app_localizations.dart';
import '../net/http_redirect_utils.dart';

class ReaderFileType {
  const ReaderFileType._();

  static final RegExp _leadingDotPattern = RegExp(r'^\.');
  static final RegExp _separatorPattern = RegExp(r'[\s_-]+');

  static const markdown = 'markdown';
  static const text = 'text';
  static const html = 'html';
  static const json = 'json';
  static const jsonl = 'jsonl';
  static const yaml = 'yaml';
  static const toml = 'toml';
  static const xml = 'xml';
  static const csv = 'csv';
  static const tsv = 'tsv';
  static const code = 'code';
  static const latex = 'latex';
  static const rtf = 'rtf';
  static const docx = 'docx';
  static const xlsx = 'xlsx';
  static const pptx = 'pptx';
  static const pdf = 'pdf';

  static const sourceTypes = <String>[
    html,
    markdown,
    text,
    json,
    jsonl,
    yaml,
    toml,
    xml,
    csv,
    tsv,
    code,
    latex,
    rtf,
    docx,
    xlsx,
    pptx,
    pdf,
  ];

  static const targetTypes = <String>[
    markdown,
    json,
    jsonl,
    text,
    html,
    yaml,
    csv,
    tsv,
    xml,
  ];

  static const textLikeSourceTypes = <String>{
    html,
    markdown,
    text,
    json,
    jsonl,
    yaml,
    toml,
    xml,
    csv,
    tsv,
    code,
    latex,
    rtf,
  };

  static const textLikeExtensions = <String>{
    '.txt',
    '.text',
    '.md',
    '.markdown',
    '.json',
    '.yaml',
    '.yml',
    '.toml',
    '.xml',
    '.html',
    '.htm',
    '.css',
    '.scss',
    '.sass',
    '.less',
    '.js',
    '.jsx',
    '.ts',
    '.tsx',
    '.dart',
    '.go',
    '.py',
    '.java',
    '.kt',
    '.kts',
    '.swift',
    '.rb',
    '.rs',
    '.c',
    '.cc',
    '.cpp',
    '.h',
    '.hpp',
    '.cs',
    '.php',
    '.sh',
    '.zsh',
    '.bash',
    '.fish',
    '.sql',
    '.csv',
    '.tsv',
    '.env',
    '.ini',
    '.cfg',
    '.conf',
    '.log',
    '.svg',
    '.vue',
  };

  static const Map<String, String> _normalizedAliases = <String, String>{
    'plaintext': text,
    kTextPlainMimeType: text,
    kTextMarkdownMimeType: markdown,
    'text/xmarkdown': markdown,
    kApplicationJsonMimeType: json,
    'application/jsonl': jsonl,
    'application/xjsonl': jsonl,
    'application/ndjson': jsonl,
    'application/xndjson': jsonl,
    kApplicationYamlMimeType: yaml,
    'application/xyaml': yaml,
    'text/yaml': yaml,
    'text/xyaml': yaml,
    kApplicationTomlMimeType: toml,
    kApplicationXmlMimeType: xml,
    'text/xml': xml,
    kImageSvgXmlMimeType: xml,
    kTextCsvMimeType: csv,
    'text/tabseparatedvalues': tsv,
    'application/xlatex': latex,
    'application/rtf': rtf,
    'text/rtf': rtf,
    kApplicationPdfMimeType: pdf,
    'application/vnd.openxmlformatsofficedocument.wordprocessingml.document':
        docx,
    'application/vnd.openxmlformatsofficedocument.spreadsheetml.sheet': xlsx,
    'application/vnd.openxmlformatsofficedocument.presentationml.presentation':
        pptx,
    'javascript': code,
    'typescript': code,
    'python': code,
    'kotlin': code,
    'shell': code,
    'shellscript': code,
    'cplusplus': code,
    'csharp': code,
  };

  static String normalize(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceFirst(_leadingDotPattern, '')
        .replaceAll(_separatorPattern, '');
    final aliased = _normalizedAliases[normalized];
    if (aliased != null) return aliased;
    return switch (normalized) {
      'md' || 'markdown' => markdown,
      'txt' || 'text' || 'log' => text,
      'htm' || 'html' => html,
      'json' => json,
      'jsonl' || 'ndjson' => jsonl,
      'yaml' || 'yml' => yaml,
      'toml' => toml,
      'xml' || 'svg' => xml,
      'csv' => csv,
      'tsv' || 'tabseparatedvalues' => tsv,
      'tex' || 'latex' => latex,
      'rtf' => rtf,
      'docx' => docx,
      'xlsx' => xlsx,
      'pptx' => pptx,
      'pdf' => pdf,
      'dart' ||
      'js' ||
      'jsx' ||
      'ts' ||
      'tsx' ||
      'py' ||
      'java' ||
      'kt' ||
      'kts' ||
      'swift' ||
      'go' ||
      'rs' ||
      'c' ||
      'cc' ||
      'cpp' ||
      'h' ||
      'hpp' ||
      'cs' ||
      'php' ||
      'rb' ||
      'sh' ||
      'bash' ||
      'zsh' ||
      'fish' ||
      'sql' ||
      'css' ||
      'scss' ||
      'sass' ||
      'less' ||
      'env' ||
      'ini' ||
      'cfg' ||
      'conf' ||
      'vue' => code,
      _ => normalized,
    };
  }

  static List<String> normalizeList(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final normalized = normalize(value);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(normalized);
    }
    return result.toList(growable: false);
  }

  static bool isTextLikeSource(String value) {
    return textLikeSourceTypes.contains(normalize(value));
  }

  static bool isTextLikeExtension(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final extension = normalized.startsWith('.') ? normalized : '.$normalized';
    return textLikeExtensions.contains(extension);
  }

  static String label(String value, AppLocalizations l10n) {
    return switch (normalize(value)) {
      markdown => 'Markdown',
      text => l10n.readerFileTypeText,
      html => 'HTML',
      json => 'JSON',
      jsonl => 'JSONL',
      yaml => 'YAML',
      toml => 'TOML',
      xml => 'XML',
      csv => 'CSV',
      tsv => 'TSV',
      code => l10n.readerFileTypeCode,
      latex => 'LaTeX',
      rtf => 'RTF',
      docx => 'Word DOCX',
      xlsx => 'Excel XLSX',
      pptx => 'PowerPoint PPTX',
      pdf => 'PDF',
      final other => other.toUpperCase(),
    };
  }

  static String mimeType(String value) {
    return switch (normalize(value)) {
      markdown => kTextMarkdownMimeType,
      text => kTextPlainMimeType,
      html => kTextHtmlMimeType,
      json => kApplicationJsonMimeType,
      jsonl => kApplicationNdjsonMimeType,
      yaml => kApplicationYamlMimeType,
      toml => kApplicationTomlMimeType,
      xml => kApplicationXmlMimeType,
      csv => kTextCsvMimeType,
      tsv => kTextTsvMimeType,
      code => kTextPlainMimeType,
      latex => 'application/x-latex',
      rtf => 'application/rtf',
      docx =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      xlsx =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      pptx =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      pdf => kApplicationPdfMimeType,
      _ => kTextPlainMimeType,
    };
  }
}
