class ReaderFileType {
  const ReaderFileType._();

  static const markdown = 'markdown';
  static const text = 'text';
  static const html = 'html';
  static const json = 'json';
  static const yaml = 'yaml';
  static const toml = 'toml';
  static const csv = 'csv';
  static const code = 'code';
  static const docx = 'docx';
  static const xlsx = 'xlsx';
  static const pptx = 'pptx';
  static const pdf = 'pdf';

  static const sourceTypes = <String>[
    html,
    markdown,
    text,
    json,
    yaml,
    toml,
    csv,
    code,
    docx,
    xlsx,
    pptx,
    pdf,
  ];

  static const targetTypes = <String>[markdown, json, text];

  static const textLikeSourceTypes = <String>{
    html,
    markdown,
    text,
    json,
    yaml,
    toml,
    csv,
    code,
  };

  static String normalize(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.'), '')
        .replaceAll(RegExp(r'[\s_-]+'), '');
    return switch (normalized) {
      'md' || 'markdown' => markdown,
      'txt' || 'text' || 'log' => text,
      'htm' || 'html' => html,
      'json' => json,
      'yaml' || 'yml' => yaml,
      'toml' => toml,
      'csv' => csv,
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
      'xml' ||
      'css' ||
      'scss' ||
      'less' => code,
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

  static String label(String value, {required bool isZh}) {
    return switch (normalize(value)) {
      markdown => 'Markdown',
      text => isZh ? '纯文本' : 'Text',
      html => 'HTML',
      json => 'JSON',
      yaml => 'YAML',
      toml => 'TOML',
      csv => 'CSV',
      code => isZh ? '代码' : 'Code',
      docx => 'Word DOCX',
      xlsx => 'Excel XLSX',
      pptx => 'PowerPoint PPTX',
      pdf => 'PDF',
      final other => other.toUpperCase(),
    };
  }

  static String mimeType(String value) {
    return switch (normalize(value)) {
      markdown => 'text/markdown',
      text => 'text/plain',
      html => 'text/html',
      json => 'application/json',
      yaml => 'application/yaml',
      toml => 'application/toml',
      csv => 'text/csv',
      code => 'text/plain',
      docx =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      xlsx =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      pptx =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      pdf => 'application/pdf',
      _ => 'text/plain',
    };
  }
}
