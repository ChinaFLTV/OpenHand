import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart' show Archive, ZipDecoder;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;
import 'package:yaml/yaml.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../model/knowledge_base_settings.dart';

class KnowledgeDocumentParseRequest {
  const KnowledgeDocumentParseRequest({
    required this.file,
    required this.settings,
    required this.stat,
    this.tags = const <String>[],
  });

  final File file;
  final KnowledgeBaseSettings settings;
  final FileStat stat;
  final List<String> tags;
}

class KnowledgeDocumentParseResult {
  const KnowledgeDocumentParseResult({
    required this.text,
    required this.kind,
    required this.mimeType,
    required this.parserId,
    this.title,
    this.metadata = const <String, Object?>{},
  });

  final String text;
  final String kind;
  final String mimeType;
  final String parserId;
  final String? title;
  final Map<String, Object?> metadata;
}

abstract class KnowledgeDocumentParser {
  const KnowledgeDocumentParser();

  String get id;
  Set<String> get extensions;

  bool supports(String extension) => extensions.contains(extension);

  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  );
}

class KnowledgeDocumentParserRegistry {
  const KnowledgeDocumentParserRegistry({
    this.parsers = const <KnowledgeDocumentParser>[
      MarkdownKnowledgeDocumentParser(),
      PlainTextKnowledgeDocumentParser(),
      CodeKnowledgeDocumentParser(),
      HtmlKnowledgeDocumentParser(),
      CsvKnowledgeDocumentParser(),
      JsonKnowledgeDocumentParser(),
      YamlKnowledgeDocumentParser(),
      TomlKnowledgeDocumentParser(),
      DocxKnowledgeDocumentParser(),
      XlsxKnowledgeDocumentParser(),
      PptxKnowledgeDocumentParser(),
      PdfKnowledgeDocumentParser(),
    ],
  });

  static const List<String> supportedExtensions = <String>[
    'md',
    'markdown',
    'txt',
    'text',
    'log',
    'html',
    'htm',
    'csv',
    'tsv',
    'json',
    'jsonl',
    'ndjson',
    'toml',
    'yaml',
    'yml',
    'rtf',
    'tex',
    'latex',
    'docx',
    'xlsx',
    'pptx',
    'pdf',
    'dart',
    'js',
    'jsx',
    'ts',
    'tsx',
    'py',
    'java',
    'kt',
    'kts',
    'swift',
    'go',
    'rs',
    'c',
    'cc',
    'cpp',
    'h',
    'hpp',
    'cs',
    'php',
    'rb',
    'sh',
    'bash',
    'zsh',
    'fish',
    'sql',
    'xml',
    'css',
    'scss',
    'less',
  ];

  static const String supportedFilesLabelZh =
      'Markdown、TXT、代码、HTML、PDF、Word DOCX、Excel XLSX、PowerPoint PPTX、CSV/TSV、JSON/JSONL、TOML、YAML、XML、RTF、LaTeX';
  static const String supportedFilesLabelEn =
      'Markdown, TXT, code, HTML, PDF, Word DOCX, Excel XLSX, PowerPoint PPTX, CSV/TSV, JSON/JSONL, TOML, YAML, XML, RTF, LaTeX';

  final List<KnowledgeDocumentParser> parsers;

  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final extension = _extension(request.file.path);
    final parser = _parserFor(extension);
    final result = await parser.parse(request);
    final text = _compactBlankLines(result.text);
    if (text.trim().isEmpty) {
      throw StateError('未能从 ${p.basename(request.file.path)} 提取可索引文本。');
    }
    return KnowledgeDocumentParseResult(
      text: text,
      kind: result.kind,
      mimeType: result.mimeType,
      parserId: result.parserId,
      title: result.title,
      metadata: <String, Object?>{
        ...result.metadata,
        'file_extension': extension,
      },
    );
  }

  KnowledgeDocumentParser _parserFor(String extension) {
    for (final parser in parsers) {
      if (parser.supports(extension)) return parser;
    }
    throw UnsupportedError('不支持的知识库文档类型：.$extension');
  }
}

class MarkdownKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const MarkdownKnowledgeDocumentParser();

  @override
  String get id => 'markdown_text';

  @override
  Set<String> get extensions => const <String>{'md', 'markdown'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final text = _decodeText(await request.file.readAsBytes());
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'markdown',
      mimeType: 'text/markdown',
      parserId: id,
      title: p.basename(request.file.path),
      metadata: _strategyMetadata(request.settings),
    );
  }
}

class PlainTextKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const PlainTextKnowledgeDocumentParser();

  @override
  String get id => 'plain_text';

  @override
  Set<String> get extensions => const <String>{
    'txt',
    'text',
    'log',
    'jsonl',
    'ndjson',
    'rtf',
    'tex',
    'latex',
  };

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final text = _decodeText(await request.file.readAsBytes());
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'text',
      mimeType: 'text/plain',
      parserId: id,
      title: p.basename(request.file.path),
      metadata: _strategyMetadata(request.settings),
    );
  }
}

class CodeKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const CodeKnowledgeDocumentParser();

  @override
  String get id => 'code_text';

  @override
  Set<String> get extensions => const <String>{
    'dart',
    'js',
    'jsx',
    'ts',
    'tsx',
    'py',
    'java',
    'kt',
    'kts',
    'swift',
    'go',
    'rs',
    'c',
    'cc',
    'cpp',
    'h',
    'hpp',
    'cs',
    'php',
    'rb',
    'sh',
    'bash',
    'zsh',
    'fish',
    'sql',
    'xml',
    'css',
    'scss',
    'less',
  };

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final extension = _extension(request.file.path);
    final text = _decodeText(await request.file.readAsBytes());
    return KnowledgeDocumentParseResult(
      text: '```$extension\n${text.trimRight()}\n```',
      kind: 'code',
      mimeType: _mimeForExtension(extension),
      parserId: id,
      title: p.basename(request.file.path),
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'language': extension,
      },
    );
  }
}

class HtmlKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const HtmlKnowledgeDocumentParser();

  @override
  String get id => 'html_readable_text';

  @override
  Set<String> get extensions => const <String>{'html', 'htm'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final raw = _decodeText(await request.file.readAsBytes());
    final title = _htmlTitle(raw).ifEmpty(p.basename(request.file.path));
    final text = request.settings.htmlParsingMode == 'plain_text'
        ? _compactBlankLines(
            '# $title\n\n${_htmlEntitiesToText(_stripTags(raw))}',
          )
        : _htmlToReadableMarkdown(raw, title);
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'html',
      mimeType: 'text/html',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'html_parsing_mode': request.settings.htmlParsingMode,
      },
    );
  }
}

class CsvKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const CsvKnowledgeDocumentParser();

  @override
  String get id => 'csv_markdown_table';

  @override
  Set<String> get extensions => const <String>{'csv', 'tsv'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final extension = _extension(request.file.path);
    final rows = _parseDelimitedRows(
      _decodeText(await request.file.readAsBytes()),
      delimiter: extension == 'tsv' ? '\t' : ',',
    );
    final title = p.basename(request.file.path);
    return KnowledgeDocumentParseResult(
      text: _tableToMarkdown(title, rows),
      kind: 'table',
      mimeType: extension == 'tsv' ? 'text/tab-separated-values' : 'text/csv',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'row_count': rows.length,
        'structured_data_parsing_mode':
            request.settings.structuredDataParsingMode,
      },
    );
  }
}

class JsonKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const JsonKnowledgeDocumentParser();

  @override
  String get id => 'json_structured_markdown';

  @override
  Set<String> get extensions => const <String>{'json'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final raw = _decodeText(await request.file.readAsBytes());
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return KnowledgeDocumentParseResult(
        text: raw,
        kind: 'structured',
        mimeType: 'application/json',
        parserId: 'json_text_fallback',
        title: p.basename(request.file.path),
        metadata: _strategyMetadata(request.settings),
      );
    }
    final title = p.basename(request.file.path);
    final text = request.settings.structuredDataParsingMode == 'raw_fenced'
        ? _rawFencedBlock(title: title, value: decoded, codeLanguage: 'json')
        : _structuredDataToMarkdown(
            title: title,
            value: decoded,
            codeLanguage: 'json',
          );
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'structured',
      mimeType: 'application/json',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'structured_data_parsing_mode':
            request.settings.structuredDataParsingMode,
      },
    );
  }
}

class YamlKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const YamlKnowledgeDocumentParser();

  @override
  String get id => 'yaml_structured_markdown';

  @override
  Set<String> get extensions => const <String>{'yaml', 'yml'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final raw = _decodeText(await request.file.readAsBytes());
    final Object? decoded;
    try {
      decoded = _yamlToPlain(loadYaml(raw));
    } catch (_) {
      return KnowledgeDocumentParseResult(
        text: raw,
        kind: 'structured',
        mimeType: 'application/yaml',
        parserId: 'yaml_text_fallback',
        title: p.basename(request.file.path),
        metadata: _strategyMetadata(request.settings),
      );
    }
    final title = p.basename(request.file.path);
    final text = request.settings.structuredDataParsingMode == 'raw_fenced'
        ? _rawFencedBlock(
            title: title,
            value: decoded,
            codeLanguage: 'yaml',
            rawText: raw,
          )
        : _structuredDataToMarkdown(
            title: title,
            value: decoded,
            codeLanguage: 'yaml',
          );
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'structured',
      mimeType: 'application/yaml',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'structured_data_parsing_mode':
            request.settings.structuredDataParsingMode,
      },
    );
  }
}

class TomlKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const TomlKnowledgeDocumentParser();

  @override
  String get id => 'toml_section_markdown';

  @override
  Set<String> get extensions => const <String>{'toml'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final raw = _decodeText(await request.file.readAsBytes());
    final title = p.basename(request.file.path);
    return KnowledgeDocumentParseResult(
      text: _tomlToMarkdown(title, raw),
      kind: 'structured',
      mimeType: 'application/toml',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'structured_data_parsing_mode':
            request.settings.structuredDataParsingMode,
      },
    );
  }
}

class DocxKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const DocxKnowledgeDocumentParser();

  @override
  String get id => 'docx_open_xml';

  @override
  Set<String> get extensions => const <String>{'docx'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final archive = _zip(await request.file.readAsBytes(), request.file.path);
    final document = _xmlArchiveFile(archive, 'word/document.xml');
    final title = _corePropertyTitle(
      archive,
    ).ifEmpty(p.basename(request.file.path));
    final buffer = StringBuffer()..writeln('# $title\n');
    final body = _firstElement(document.rootElement, 'body');
    final children =
        body?.children.whereType<xml.XmlElement>() ??
        document.rootElement.children.whereType<xml.XmlElement>();
    for (final child in children) {
      if (_isElement(child, 'p')) {
        final paragraph = _ooxmlText(child).trim();
        if (paragraph.isNotEmpty) buffer.writeln('$paragraph\n');
      } else if (_isElement(child, 'tbl')) {
        final table = _wordTableToMarkdown(child);
        if (table.trim().isNotEmpty) buffer.writeln('$table\n');
      }
    }
    return KnowledgeDocumentParseResult(
      text: buffer.toString(),
      kind: 'docx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'office_parsing_engine': request.settings.officeParsingEngine,
      },
    );
  }
}

class XlsxKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const XlsxKnowledgeDocumentParser();

  @override
  String get id => 'xlsx_open_xml';

  @override
  Set<String> get extensions => const <String>{'xlsx'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final archive = _zip(await request.file.readAsBytes(), request.file.path);
    final title = _corePropertyTitle(
      archive,
    ).ifEmpty(p.basename(request.file.path));
    final sharedStrings = _xlsxSharedStrings(archive);
    final sheetNames = _xlsxSheetNames(archive);
    final sheetFiles =
        archive.files
            .where(
              (file) =>
                  file.isFile &&
                  RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => _naturalSheetIndex(
              a.name,
            ).compareTo(_naturalSheetIndex(b.name)),
          );
    final buffer = StringBuffer()..writeln('# $title\n');
    for (var index = 0; index < sheetFiles.length; index++) {
      final sheetName = index < sheetNames.length
          ? sheetNames[index]
          : 'Sheet ${index + 1}';
      final xmlDoc = xml.XmlDocument.parse(
        _decodeText(sheetFiles[index].readBytes() ?? const <int>[]),
      );
      final rows = _xlsxRows(xmlDoc, sharedStrings);
      if (rows.isEmpty) continue;
      buffer
        ..writeln('## $sheetName\n')
        ..writeln(
          request.settings.spreadsheetParsingMode == 'row_blocks'
              ? _rowsToBlocks(rows)
              : _rowsToMarkdown(rows),
        )
        ..writeln();
    }
    return KnowledgeDocumentParseResult(
      text: buffer.toString(),
      kind: 'spreadsheet',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'office_parsing_engine': request.settings.officeParsingEngine,
        'spreadsheet_parsing_mode': request.settings.spreadsheetParsingMode,
        'sheet_count': sheetFiles.length,
      },
    );
  }
}

class PptxKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const PptxKnowledgeDocumentParser();

  @override
  String get id => 'pptx_open_xml';

  @override
  Set<String> get extensions => const <String>{'pptx'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final archive = _zip(await request.file.readAsBytes(), request.file.path);
    final title = _corePropertyTitle(
      archive,
    ).ifEmpty(p.basename(request.file.path));
    final slideFiles =
        archive.files
            .where(
              (file) =>
                  file.isFile &&
                  RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => _naturalSheetIndex(
              a.name,
            ).compareTo(_naturalSheetIndex(b.name)),
          );
    final buffer = StringBuffer()..writeln('# $title\n');
    for (var index = 0; index < slideFiles.length; index++) {
      final xmlDoc = xml.XmlDocument.parse(
        _decodeText(slideFiles[index].readBytes() ?? const <int>[]),
      );
      final paragraphs = trimmedNonEmptyStrings(
        _elements(xmlDoc.rootElement, 'p').map(_ooxmlText),
      );
      if (paragraphs.isEmpty) continue;
      buffer
        ..writeln('## Slide ${index + 1}\n')
        ..writeln(
          request.settings.presentationParsingMode == 'outline'
              ? paragraphs.map((paragraph) => '- $paragraph').join('\n')
              : paragraphs.join('\n\n'),
        )
        ..writeln();
    }
    return KnowledgeDocumentParseResult(
      text: buffer.toString(),
      kind: 'presentation',
      mimeType:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'office_parsing_engine': request.settings.officeParsingEngine,
        'presentation_parsing_mode': request.settings.presentationParsingMode,
        'slide_count': slideFiles.length,
      },
    );
  }
}

class PdfKnowledgeDocumentParser extends KnowledgeDocumentParser {
  const PdfKnowledgeDocumentParser();

  @override
  String get id => 'pdf_basic_text_stream';

  @override
  Set<String> get extensions => const <String>{'pdf'};

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final bytes = await request.file.readAsBytes();
    final text = _extractPdfText(bytes);
    final header = latin1
        .decode(bytes.take(24).toList(growable: false), allowInvalid: true)
        .split(RegExp(r'[\r\n]'))
        .first
        .trim();
    final title = p.basename(request.file.path);
    return KnowledgeDocumentParseResult(
      text: '# $title\n\n$text',
      kind: 'pdf',
      mimeType: 'application/pdf',
      parserId: id,
      title: title,
      metadata: <String, Object?>{
        ..._strategyMetadata(request.settings),
        'pdf_parsing_engine': request.settings.pdfParsingEngine,
        'pdf_header': header,
      },
    );
  }
}

Archive _zip(List<int> bytes, String path) {
  try {
    return ZipDecoder().decodeBytes(bytes);
  } catch (error) {
    throw FormatException('无法解析压缩文档：${p.basename(path)}。$error');
  }
}

xml.XmlDocument _xmlArchiveFile(Archive archive, String path) {
  final file = archive.findFile(path);
  if (file == null || !file.isFile) {
    throw FormatException('文档缺少必要结构：$path');
  }
  return xml.XmlDocument.parse(_decodeText(file.readBytes() ?? const <int>[]));
}

String _corePropertyTitle(Archive archive) {
  final file = archive.findFile('docProps/core.xml');
  if (file == null || !file.isFile) return '';
  try {
    final doc = xml.XmlDocument.parse(
      _decodeText(file.readBytes() ?? const <int>[]),
    );
    for (final title in _elements(doc.rootElement, 'title')) {
      final text = title.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  } catch (_) {
    return '';
  }
}

List<String> _xlsxSharedStrings(Archive archive) {
  final file = archive.findFile('xl/sharedStrings.xml');
  if (file == null || !file.isFile) return const <String>[];
  final doc = xml.XmlDocument.parse(_decodeText(file.readBytes() ?? const []));
  return _elements(
    doc.rootElement,
    'si',
  ).map(_ooxmlText).map((value) => value.trim()).toList(growable: false);
}

List<String> _xlsxSheetNames(Archive archive) {
  final file = archive.findFile('xl/workbook.xml');
  if (file == null || !file.isFile) return const <String>[];
  try {
    final doc = xml.XmlDocument.parse(
      _decodeText(file.readBytes() ?? const []),
    );
    return trimmedNonEmptyStrings(
      _elements(
        doc.rootElement,
        'sheet',
      ).map((sheet) => sheet.getAttribute('name') ?? ''),
    );
  } catch (_) {
    return const <String>[];
  }
}

List<List<String>> _xlsxRows(xml.XmlDocument doc, List<String> sharedStrings) {
  final rows = <List<String>>[];
  for (final row in _elements(doc.rootElement, 'row')) {
    final values = <String>[];
    for (final cell in row.children.whereType<xml.XmlElement>().where(
      (child) => _isElement(child, 'c'),
    )) {
      final reference = cell.getAttribute('r') ?? '';
      final columnIndex = _xlsxColumnIndex(reference);
      while (values.length < columnIndex) {
        values.add('');
      }
      values.add(_xlsxCellValue(cell, sharedStrings));
    }
    while (values.isNotEmpty && values.last.trim().isEmpty) {
      values.removeLast();
    }
    if (values.any((value) => value.trim().isNotEmpty)) rows.add(values);
  }
  return rows;
}

String _xlsxCellValue(xml.XmlElement cell, List<String> sharedStrings) {
  final type = cell.getAttribute('t');
  if (type == 'inlineStr') return _ooxmlText(cell).trim();
  final value = _firstElement(cell, 'v')?.innerText.trim() ?? '';
  if (type == 's') {
    final index = optionalNonNegativeIntFromValue(value);
    if (index != null && index < sharedStrings.length) {
      return sharedStrings[index];
    }
  }
  if (type == 'b') return value == '1' ? 'TRUE' : 'FALSE';
  return value;
}

int _xlsxColumnIndex(String reference) {
  final letters = RegExp(r'^[A-Za-z]+').stringMatch(reference) ?? '';
  if (letters.isEmpty) return 0;
  var result = 0;
  for (final codeUnit in letters.toUpperCase().codeUnits) {
    result = result * 26 + (codeUnit - 64);
  }
  return math.max(0, result - 1);
}

int _naturalSheetIndex(String name) {
  final match = RegExp(r'(\d+)').firstMatch(name);
  return optionalNonNegativeIntFromValue(match?.group(1)) ?? 0;
}

String _wordTableToMarkdown(xml.XmlElement table) {
  final rows = <List<String>>[];
  for (final row in table.children.whereType<xml.XmlElement>().where(
    (child) => _isElement(child, 'tr'),
  )) {
    final cells = row.children
        .whereType<xml.XmlElement>()
        .where((child) => _isElement(child, 'tc'))
        .map(_ooxmlText)
        .map((value) => value.trim())
        .toList(growable: false);
    if (cells.any((cell) => cell.isNotEmpty)) rows.add(cells);
  }
  return _rowsToMarkdown(rows);
}

String _rowsToMarkdown(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final width = rows.fold<int>(0, (max, row) => math.max(max, row.length));
  final normalized = rows
      .map(
        (row) => <String>[
          for (var index = 0; index < width; index++)
            index < row.length ? row[index] : '',
        ],
      )
      .toList(growable: false);
  final buffer = StringBuffer();
  buffer.writeln('| ${normalized.first.map(_markdownCell).join(' | ')} |');
  buffer.writeln('| ${List<String>.filled(width, '---').join(' | ')} |');
  for (final row in normalized.skip(1)) {
    buffer.writeln('| ${row.map(_markdownCell).join(' | ')} |');
  }
  return buffer.toString().trimRight();
}

String _rowsToBlocks(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final buffer = StringBuffer();
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final values = trimmedNonEmptyStrings(rows[rowIndex]);
    if (values.isEmpty) continue;
    buffer.writeln('- Row ${rowIndex + 1}: ${values.join(' | ')}');
  }
  return buffer.toString().trimRight();
}

String _tableToMarkdown(String title, List<List<String>> rows) {
  final table = _rowsToMarkdown(rows);
  return table.isEmpty ? '# $title' : '# $title\n\n$table';
}

String _markdownCell(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '<br>')
      .replaceAll('|', r'\|')
      .trim();
}

String _ooxmlText(xml.XmlElement element) {
  final buffer = StringBuffer();
  for (final node in element.descendants) {
    if (node is! xml.XmlElement) continue;
    if (_isElement(node, 't')) {
      buffer.write(node.innerText);
    } else if (_isElement(node, 'tab')) {
      buffer.write('\t');
    } else if (_isElement(node, 'br')) {
      buffer.write('\n');
    }
  }
  return buffer.toString();
}

Iterable<xml.XmlElement> _elements(xml.XmlElement element, String localName) {
  return element.descendants.whereType<xml.XmlElement>().where(
    (child) => _isElement(child, localName),
  );
}

xml.XmlElement? _firstElement(xml.XmlElement element, String localName) {
  for (final child in element.descendants.whereType<xml.XmlElement>()) {
    if (_isElement(child, localName)) return child;
  }
  return null;
}

bool _isElement(xml.XmlElement element, String localName) {
  final local = element.name.local;
  final qualified = element.name.qualified;
  return local == localName ||
      qualified == localName ||
      local.endsWith(':$localName') ||
      qualified.endsWith(':$localName');
}

String _htmlToReadableMarkdown(String raw, String title) {
  var html = raw
      .replaceAll(
        RegExp(
          r'<script\b[^>]*>.*?</script>',
          caseSensitive: false,
          dotAll: true,
        ),
        '\n',
      )
      .replaceAll(
        RegExp(
          r'<style\b[^>]*>.*?</style>',
          caseSensitive: false,
          dotAll: true,
        ),
        '\n',
      )
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '\n');
  for (var level = 1; level <= 6; level++) {
    html = html.replaceAllMapped(
      RegExp(
        '<h$level\\b[^>]*>(.*?)</h$level>',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) =>
          '\n${'#' * level} ${_htmlEntitiesToText(_stripTags(match.group(1) ?? '')).trim()}\n',
    );
  }
  html = html
      .replaceAll(
        RegExp(
          r'</(p|div|section|article|header|footer|li|tr)>',
          caseSensitive: false,
        ),
        '\n',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' | ');
  final body = _htmlEntitiesToText(_stripTags(html));
  return _compactBlankLines('# $title\n\n$body');
}

String _htmlTitle(String raw) {
  final match = RegExp(
    r'<title\b[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(raw);
  if (match == null) return '';
  return _htmlEntitiesToText(_stripTags(match.group(1) ?? '')).trim();
}

String _stripTags(String value) {
  return value.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
}

String _htmlEntitiesToText(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
        final code = int.tryParse(match.group(1) ?? '');
        return code == null ? match.group(0)! : String.fromCharCode(code);
      })
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
        final code = int.tryParse(match.group(1) ?? '', radix: 16);
        return code == null ? match.group(0)! : String.fromCharCode(code);
      });
}

List<List<String>> _parseDelimitedRows(
  String input, {
  required String delimiter,
}) {
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var index = 0; index < input.length; index++) {
    final char = input[index];
    if (quoted) {
      if (char == '"') {
        final hasEscapedQuote =
            index + 1 < input.length && input[index + 1] == '"';
        if (hasEscapedQuote) {
          cell.write('"');
          index += 1;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
      continue;
    }
    if (char == '"') {
      quoted = true;
    } else if (char == delimiter) {
      row.add(cell.toString());
      cell.clear();
    } else if (char == '\n') {
      row.add(cell.toString());
      rows.add(List<String>.from(row));
      row.clear();
      cell.clear();
    } else if (char != '\r') {
      cell.write(char);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(List<String>.from(row));
  }
  return rows
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .toList(growable: false);
}

String _structuredDataToMarkdown({
  required String title,
  required Object? value,
  required String codeLanguage,
}) {
  final plain = _jsonSafe(value);
  final buffer = StringBuffer()..writeln('# $title\n');
  _writeStructuredNode(buffer, plain, level: 2);
  buffer
    ..writeln()
    ..writeln('```$codeLanguage')
    ..writeln(const JsonEncoder.withIndent('  ').convert(plain))
    ..writeln('```');
  return buffer.toString();
}

String _rawFencedBlock({
  required String title,
  required Object? value,
  required String codeLanguage,
  String? rawText,
}) {
  return '# $title\n\n```$codeLanguage\n'
      '${rawText ?? const JsonEncoder.withIndent('  ').convert(_jsonSafe(value))}\n'
      '```';
}

void _writeStructuredNode(
  StringBuffer buffer,
  Object? value, {
  required int level,
}) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = '${entry.key}'.trim();
      if (_isScalar(entry.value)) {
        buffer.writeln('- $key: ${entry.value}');
      } else {
        buffer.writeln('${'#' * level} $key\n');
        _writeStructuredNode(
          buffer,
          entry.value,
          level: math.min(level + 1, 6),
        );
      }
    }
  } else if (value is List) {
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (_isScalar(item)) {
        buffer.writeln('- $item');
      } else {
        buffer.writeln('${'#' * level} Item ${index + 1}\n');
        _writeStructuredNode(buffer, item, level: math.min(level + 1, 6));
      }
    }
  } else if (value != null) {
    buffer.writeln('$value');
  }
}

Object? _jsonSafe(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': _jsonSafe(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_jsonSafe).toList(growable: false);
  }
  return '$value';
}

Object? _yamlToPlain(Object? value) {
  if (value is YamlMap) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _yamlToPlain(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_yamlToPlain).toList(growable: false);
  }
  return value;
}

bool _isScalar(Object? value) {
  return value == null || value is num || value is bool || value is String;
}

String _tomlToMarkdown(String title, String raw) {
  final buffer = StringBuffer()..writeln('# $title\n');
  for (final line in raw.replaceAll('\r\n', '\n').split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final section = RegExp(r'^\[(.+)]$').firstMatch(trimmed);
    if (section != null) {
      buffer.writeln('\n## ${section.group(1)!.trim()}\n');
      continue;
    }
    final assignment = RegExp(r'^([^=]+)=(.*)$').firstMatch(trimmed);
    if (assignment != null) {
      buffer.writeln(
        '- ${assignment.group(1)!.trim()}: ${assignment.group(2)!.trim()}',
      );
    } else {
      buffer.writeln(trimmed);
    }
  }
  buffer
    ..writeln()
    ..writeln('```toml')
    ..writeln(raw.trimRight())
    ..writeln('```');
  return buffer.toString();
}

String _extractPdfText(List<int> bytes) {
  final latin = latin1.decode(bytes, allowInvalid: true);
  final buffer = StringBuffer();
  final streamPattern = RegExp(r'stream(?:\r\n|\n|\r)');
  for (final match in streamPattern.allMatches(latin)) {
    final end = latin.indexOf('endstream', match.end);
    if (end <= match.end) continue;
    var contentEnd = end;
    while (contentEnd > match.end) {
      final code = latin.codeUnitAt(contentEnd - 1);
      if (code != 10 && code != 13) break;
      contentEnd -= 1;
    }
    final dictionaryStart = math.max(0, match.start - 900);
    final dictionary = latin.substring(dictionaryStart, match.start);
    final raw = bytes.sublist(match.end, contentEnd);
    final decoded = _decodePdfStream(raw, dictionary);
    if (decoded == null || decoded.isEmpty) continue;
    final extracted = _extractPdfContentText(
      latin1.decode(decoded, allowInvalid: true),
    );
    if (extracted.trim().isNotEmpty) {
      buffer
        ..writeln(extracted.trim())
        ..writeln();
    }
  }
  return _compactBlankLines(buffer.toString());
}

List<int>? _decodePdfStream(List<int> bytes, String dictionary) {
  if (!dictionary.contains('/FlateDecode')) return bytes;
  try {
    return ZLibDecoder().convert(bytes);
  } catch (_) {
    return null;
  }
}

String _extractPdfContentText(String stream) {
  final buffer = StringBuffer();
  final textBlocks = RegExp(r'BT(.*?)ET', dotAll: true).allMatches(stream);
  for (final block in textBlocks) {
    final strings = _extractPdfStrings(block.group(1) ?? '')
        .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((value) => value.length > 1)
        .toList(growable: false);
    if (strings.isNotEmpty) buffer.writeln(strings.join(' '));
  }
  return buffer.toString();
}

List<String> _extractPdfStrings(String block) {
  final values = <String>[];
  var index = 0;
  while (index < block.length) {
    final char = block[index];
    if (char == '(') {
      final parsed = _parsePdfLiteral(block, index);
      if (parsed != null) {
        values.add(parsed.value);
        index = parsed.nextIndex;
        continue;
      }
    } else if (char == '<' &&
        index + 1 < block.length &&
        block[index + 1] != '<') {
      final end = block.indexOf('>', index + 1);
      if (end > index) {
        values.add(_decodePdfHex(block.substring(index + 1, end)));
        index = end + 1;
        continue;
      }
    }
    index += 1;
  }
  return values
      .where((value) => value.trim().isNotEmpty)
      .toList(growable: false);
}

_PdfLiteral? _parsePdfLiteral(String input, int start) {
  final bytes = <int>[];
  var depth = 1;
  var index = start + 1;
  while (index < input.length) {
    final char = input[index];
    if (char == r'\') {
      if (index + 1 >= input.length) break;
      final next = input[index + 1];
      switch (next) {
        case 'n':
          bytes.add(10);
          index += 2;
        case 'r':
          bytes.add(13);
          index += 2;
        case 't':
          bytes.add(9);
          index += 2;
        case 'b':
          bytes.add(8);
          index += 2;
        case 'f':
          bytes.add(12);
          index += 2;
        case '(':
        case ')':
        case r'\':
          bytes.add(next.codeUnitAt(0));
          index += 2;
        case '\r':
          index += input.startsWith('\r\n', index + 1) ? 3 : 2;
        case '\n':
          index += 2;
        default:
          final octal = RegExp(r'^[0-7]{1,3}').stringMatch(
            input.substring(index + 1, math.min(input.length, index + 4)),
          );
          if (octal != null && octal.isNotEmpty) {
            bytes.add(int.parse(octal, radix: 8).clamp(0, 255));
            index += 1 + octal.length;
          } else {
            bytes.add(next.codeUnitAt(0));
            index += 2;
          }
      }
      continue;
    }
    if (char == '(') {
      depth += 1;
      bytes.add(char.codeUnitAt(0));
      index += 1;
      continue;
    }
    if (char == ')') {
      depth -= 1;
      if (depth == 0) {
        return _PdfLiteral(_decodePdfStringBytes(bytes), index + 1);
      }
      bytes.add(char.codeUnitAt(0));
      index += 1;
      continue;
    }
    bytes.add(char.codeUnitAt(0) & 0xff);
    index += 1;
  }
  return null;
}

String _decodePdfHex(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s+'), '');
  final bytes = <int>[];
  for (var index = 0; index < clean.length; index += 2) {
    final chunk = index + 1 < clean.length
        ? clean.substring(index, index + 2)
        : '${clean[index]}0';
    final byte = int.tryParse(chunk, radix: 16);
    if (byte != null) bytes.add(byte);
  }
  return _decodePdfStringBytes(bytes);
}

String _decodePdfStringBytes(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    final units = <int>[];
    for (var index = 2; index + 1 < bytes.length; index += 2) {
      units.add((bytes[index] << 8) | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }
  return latin1.decode(bytes, allowInvalid: true);
}

class _PdfLiteral {
  const _PdfLiteral(this.value, this.nextIndex);

  final String value;
  final int nextIndex;
}

Map<String, Object?> _strategyMetadata(KnowledgeBaseSettings settings) {
  return <String, Object?>{
    'document_parsing_engine': settings.documentParsingEngine,
    'chunk_strategy': settings.chunkStrategy,
  };
}

String _decodeText(List<int> bytes) {
  final decoded = utf8.decode(bytes, allowMalformed: true);
  return decoded.startsWith('\ufeff') ? decoded.substring(1) : decoded;
}

String _compactBlankLines(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _extension(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension.startsWith('.') ? extension.substring(1) : extension;
}

String _mimeForExtension(String extension) {
  return switch (extension) {
    'dart' => 'text/x-dart',
    'js' || 'jsx' => 'text/javascript',
    'ts' || 'tsx' => 'text/typescript',
    'py' => 'text/x-python',
    'java' => 'text/x-java-source',
    'kt' || 'kts' => 'text/x-kotlin',
    'swift' => 'text/x-swift',
    'go' => 'text/x-go',
    'rs' => 'text/x-rust',
    'sql' => 'application/sql',
    'xml' => 'application/xml',
    'css' || 'scss' || 'less' => 'text/css',
    _ => 'text/plain',
  };
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : trim();
}
