import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;
import 'package:yaml/yaml.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/bounded_zip_archive.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_normalization.dart';
import '../model/knowledge_base_settings.dart';

const int _knowledgeBytesPerMiB = kBytesPerMiB;
const int _maxKnowledgeDocumentBytes = 256 * _knowledgeBytesPerMiB;
const int _maxKnowledgeArchiveEntries = 4096;
const int _maxKnowledgeArchiveEntryBytes = 32 * _knowledgeBytesPerMiB;
const int _maxKnowledgeArchiveXmlBytes = 128 * _knowledgeBytesPerMiB;
const int _maxKnowledgeExtractedTextChars = 64 * _knowledgeBytesPerMiB;
const int _maxKnowledgePdfDecodedStreamBytes = 16 * _knowledgeBytesPerMiB;
const int _maxKnowledgePdfDecodedTotalBytes = 64 * _knowledgeBytesPerMiB;
const Duration _knowledgeFileReadIdleTimeout = Duration(seconds: 30);
const Duration _knowledgeFileReadTotalTimeout = Duration(minutes: 5);
const Duration _knowledgePdfDecodeIdleTimeout = Duration(seconds: 10);
const Duration _knowledgePdfDecodeTotalTimeout = Duration(seconds: 30);

final RegExp _knowledgeLineBreakPattern = RegExp(r'[\r\n]');
final RegExp _knowledgeExcessiveBlankLinesPattern = kExcessiveNewlinesPattern;
final RegExp _xlsxWorksheetFilePattern = RegExp(
  r'^xl/worksheets/sheet\d+\.xml$',
);
final RegExp _pptxSlideFilePattern = RegExp(r'^ppt/slides/slide\d+\.xml$');
final RegExp _xlsxColumnReferencePattern = RegExp(r'^[A-Za-z]+');
final RegExp _naturalIndexPattern = RegExp(r'(\d+)');
final RegExp _htmlScriptPattern = RegExp(
  r'<script\b[^>]*>.*?</script>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _htmlStylePattern = RegExp(
  r'<style\b[^>]*>.*?</style>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _htmlCommentPattern = RegExp(r'<!--.*?-->', dotAll: true);
final RegExp _htmlBlockClosePattern = RegExp(
  r'</(p|div|section|article|header|footer|li|tr)>',
  caseSensitive: false,
);
final RegExp _htmlBreakPattern = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _htmlTableCellClosePattern = RegExp(
  r'</t[dh]>',
  caseSensitive: false,
);
final RegExp _htmlTitlePattern = RegExp(
  r'<title\b[^>]*>(.*?)</title>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _htmlDecimalEntityPattern = RegExp(r'&#(\d+);');
final RegExp _htmlHexEntityPattern = RegExp(r'&#x([0-9a-fA-F]+);');
final RegExp _tomlSectionPattern = RegExp(r'^\[(.+)]$');
final RegExp _tomlAssignmentPattern = RegExp(r'^([^=]+)=(.*)$');
final RegExp _pdfStreamStartPattern = RegExp(r'stream(?:\r\n|\n|\r)');
final RegExp _pdfTextBlockPattern = RegExp(r'BT(.*?)ET', dotAll: true);
final RegExp _pdfOctalEscapePattern = RegExp(r'^[0-7]{1,3}');

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

/// 解析器与文件选择器共用的代码文件后缀。
const Set<String> kCodeKnowledgeDocumentExtensions = <String>{
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
    ...kCodeKnowledgeDocumentExtensions,
  ];

  static const String supportedFilesLabelZh =
      'Markdown、TXT、代码、HTML、PDF、Word DOCX、Excel XLSX、PowerPoint PPTX、CSV/TSV、JSON/JSONL、TOML、YAML、XML、RTF、LaTeX';
  static const String supportedFilesLabelEn =
      'Markdown, TXT, code, HTML, PDF, Word DOCX, Excel XLSX, PowerPoint PPTX, CSV/TSV, JSON/JSONL, TOML, YAML, XML, RTF, LaTeX';

  final List<KnowledgeDocumentParser> parsers;

  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    _validateDocumentSize(request, request.stat.size);
    final extension = _extension(request.file.path);
    final parser = _parserFor(extension);
    final result = await parser.parse(request);
    final text = _compactBlankLines(result.text);
    if (text.trim().isEmpty) {
      throw StateError('未能从 ${p.basename(request.file.path)} 提取可索引文本。');
    }
    if (text.length > _maxKnowledgeExtractedTextChars) {
      throw StateError(
        '文档解析文本超过约 ${_maxKnowledgeExtractedTextChars ~/ _knowledgeBytesPerMiB} Mi 字符安全上限：'
        '${p.basename(request.file.path)}。',
      );
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

int _documentByteLimit(KnowledgeBaseSettings settings) {
  return math.min(
    KnowledgeBaseSettingRanges.maxFileSizeMb.normalize(settings.maxFileSizeMb) *
        _knowledgeBytesPerMiB,
    _maxKnowledgeDocumentBytes,
  );
}

void _validateDocumentSize(KnowledgeDocumentParseRequest request, int size) {
  final maxBytes = _documentByteLimit(request.settings);
  if (size < 0 || size > maxBytes) {
    throw StateError(
      '文件超过知识库最大单文件大小 ${maxBytes ~/ _knowledgeBytesPerMiB} MiB：'
      '${p.basename(request.file.path)}。',
    );
  }
}

Future<Uint8List> _readDocumentBytes(
  KnowledgeDocumentParseRequest request,
) async {
  try {
    return await readBoundedFileBytes(
      request.file,
      maxBytes: _documentByteLimit(request.settings),
      idleTimeout: _knowledgeFileReadIdleTimeout,
      totalTimeout: _knowledgeFileReadTotalTimeout,
    );
  } on BoundedFileReadException catch (error) {
    final detail = error.failure == BoundedFileReadFailure.tooLarge
        ? '文件超过知识库安全上限'
        : '读取期间文件发生变化';
    throw StateError('$detail：${p.basename(request.file.path)}。');
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
    final text = _decodeText(await _readDocumentBytes(request));
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'markdown',
      mimeType: kTextMarkdownMimeType,
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
    final text = _decodeText(await _readDocumentBytes(request));
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'text',
      mimeType: kTextPlainMimeType,
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
  Set<String> get extensions => kCodeKnowledgeDocumentExtensions;

  @override
  Future<KnowledgeDocumentParseResult> parse(
    KnowledgeDocumentParseRequest request,
  ) async {
    final extension = _extension(request.file.path);
    final text = _decodeText(await _readDocumentBytes(request));
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
    final raw = _decodeText(await _readDocumentBytes(request));
    final title = nonBlankStringOr(
      _htmlTitle(raw),
      p.basename(request.file.path),
    );
    final text = request.settings.htmlParsingMode == 'plain_text'
        ? _compactBlankLines(
            '# $title\n\n${_htmlEntitiesToText(_stripTags(raw))}',
          )
        : _htmlToReadableMarkdown(raw, title);
    return KnowledgeDocumentParseResult(
      text: text,
      kind: 'html',
      mimeType: kTextHtmlMimeType,
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
      _decodeText(await _readDocumentBytes(request)),
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
    final raw = _decodeText(await _readDocumentBytes(request));
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return KnowledgeDocumentParseResult(
        text: raw,
        kind: 'structured',
        mimeType: kApplicationJsonMimeType,
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
      mimeType: kApplicationJsonMimeType,
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
    final raw = _decodeText(await _readDocumentBytes(request));
    final Object? decoded;
    try {
      decoded = _yamlToPlain(loadYaml(raw));
    } catch (_) {
      return KnowledgeDocumentParseResult(
        text: raw,
        kind: 'structured',
        mimeType: kApplicationYamlMimeType,
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
      mimeType: kApplicationYamlMimeType,
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
    final raw = _decodeText(await _readDocumentBytes(request));
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
    final archive = _zip(await _readDocumentBytes(request), request.file.path);
    final document = _xmlArchiveFile(archive, 'word/document.xml');
    final title = nonBlankStringOr(
      _corePropertyTitle(archive),
      p.basename(request.file.path),
    );
    final buffer = StringBuffer()..writeln('# $title\n');
    final body = _firstElement(document.rootElement, 'body');
    final children =
        body?.children.whereType<xml.XmlElement>() ??
        document.rootElement.children.whereType<xml.XmlElement>();
    for (final child in children) {
      if (_isElement(child, 'p')) {
        final paragraph = _trimmedOoxmlText(child);
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
    final archive = _zip(await _readDocumentBytes(request), request.file.path);
    final title = nonBlankStringOr(
      _corePropertyTitle(archive),
      p.basename(request.file.path),
    );
    final sharedStrings = _xlsxSharedStrings(archive);
    final sheetNames = _xlsxSheetNames(archive);
    final sheetFiles =
        archive.files
            .where(
              (file) =>
                  file.isFile && _xlsxWorksheetFilePattern.hasMatch(file.name),
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
      final xmlDoc = xml.XmlDocument.parse(_archiveFileText(sheetFiles[index]));
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
    final archive = _zip(await _readDocumentBytes(request), request.file.path);
    final title = nonBlankStringOr(
      _corePropertyTitle(archive),
      p.basename(request.file.path),
    );
    final slideFiles =
        archive.files
            .where(
              (file) =>
                  file.isFile && _pptxSlideFilePattern.hasMatch(file.name),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => _naturalSheetIndex(
              a.name,
            ).compareTo(_naturalSheetIndex(b.name)),
          );
    final buffer = StringBuffer()..writeln('# $title\n');
    for (var index = 0; index < slideFiles.length; index++) {
      final xmlDoc = xml.XmlDocument.parse(_archiveFileText(slideFiles[index]));
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
    final bytes = await _readDocumentBytes(request);
    final text = await _extractPdfText(bytes);
    final header = latin1
        .decode(bytes.take(24).toList(growable: false), allowInvalid: true)
        .split(_knowledgeLineBreakPattern)
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

BoundedZipArchive _zip(Uint8List bytes, String path) {
  try {
    final archive = BoundedZipArchive.decode(
      bytes,
      maxEntries: _maxKnowledgeArchiveEntries,
      maxReadBytes: _maxKnowledgeArchiveXmlBytes,
    );
    var xmlBytes = 0;
    for (final file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.xml')) {
        continue;
      }
      if (file.size < 0 || file.size > _maxKnowledgeArchiveEntryBytes) {
        throw FormatException('压缩文档 XML 条目过大：${file.name}。');
      }
      xmlBytes += file.size;
      if (xmlBytes > _maxKnowledgeArchiveXmlBytes) {
        throw const FormatException('压缩文档 XML 展开总量超过安全上限。');
      }
    }
    return archive;
  } catch (error, stack) {
    silentLog('knowledge_document_parser', '解析压缩文档', error, stack);
    final detail = error is FormatException
        ? collapseInlineWhitespace(error.message)
        : '';
    throw FormatException(
      detail.isEmpty
          ? '无法解析压缩文档：${p.basename(path)}。'
          : '无法解析压缩文档：${p.basename(path)}。$detail',
    );
  }
}

xml.XmlDocument _xmlArchiveFile(BoundedZipArchive archive, String path) {
  final file = archive.findFile(path);
  if (file == null || !file.isFile) {
    throw FormatException('文档缺少必要结构：$path');
  }
  return xml.XmlDocument.parse(_archiveFileText(file));
}

String _corePropertyTitle(BoundedZipArchive archive) {
  final file = archive.findFile('docProps/core.xml');
  if (file == null || !file.isFile) return '';
  try {
    final doc = xml.XmlDocument.parse(_archiveFileText(file));
    for (final title in _elements(doc.rootElement, 'title')) {
      final text = title.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  } catch (_) {
    return '';
  }
}

List<String> _xlsxSharedStrings(BoundedZipArchive archive) {
  final file = archive.findFile('xl/sharedStrings.xml');
  if (file == null || !file.isFile) return const <String>[];
  final doc = xml.XmlDocument.parse(_archiveFileText(file));
  return _elements(
    doc.rootElement,
    'si',
  ).map(_trimmedOoxmlText).toList(growable: false);
}

List<String> _xlsxSheetNames(BoundedZipArchive archive) {
  final file = archive.findFile('xl/workbook.xml');
  if (file == null || !file.isFile) return const <String>[];
  try {
    final doc = xml.XmlDocument.parse(_archiveFileText(file));
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

String _archiveFileText(BoundedZipEntry file) {
  if (file.size < 0 || file.size > _maxKnowledgeArchiveEntryBytes) {
    throw FormatException('压缩文档条目超过安全上限：${file.name}。');
  }
  return _decodeText(file.readBytes(maxBytes: _maxKnowledgeArchiveEntryBytes));
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
    if (_rowHasContent(values)) rows.add(values);
  }
  return rows;
}

String _xlsxCellValue(xml.XmlElement cell, List<String> sharedStrings) {
  final type = cell.getAttribute('t');
  if (type == 'inlineStr') return _trimmedOoxmlText(cell);
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
  final letters = _xlsxColumnReferencePattern.stringMatch(reference) ?? '';
  if (letters.isEmpty) return 0;
  var result = 0;
  for (final codeUnit in letters.toUpperCase().codeUnits) {
    result = result * 26 + (codeUnit - 64);
  }
  return math.max(0, result - 1);
}

int _naturalSheetIndex(String name) {
  final match = _naturalIndexPattern.firstMatch(name);
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
        .map(_trimmedOoxmlText)
        .toList(growable: false);
    if (_rowHasContent(cells)) rows.add(cells);
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

bool _rowHasContent(List<String> row) {
  return row.any((cell) => nullIfBlank(cell) != null);
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

String _trimmedOoxmlText(xml.XmlElement element) => _ooxmlText(element).trim();

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
      .replaceAll(_htmlScriptPattern, '\n')
      .replaceAll(_htmlStylePattern, '\n')
      .replaceAll(_htmlCommentPattern, '\n');
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
      .replaceAll(_htmlBlockClosePattern, '\n')
      .replaceAll(_htmlBreakPattern, '\n')
      .replaceAll(_htmlTableCellClosePattern, ' | ');
  final body = _htmlEntitiesToText(_stripTags(html));
  return _compactBlankLines('# $title\n\n$body');
}

String _htmlTitle(String raw) {
  final match = _htmlTitlePattern.firstMatch(raw);
  if (match == null) return '';
  return _htmlEntitiesToText(_stripTags(match.group(1) ?? '')).trim();
}

String _stripTags(String value) {
  return stripHtmlTags(value);
}

String _htmlEntitiesToText(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(_htmlDecimalEntityPattern, (match) {
        final code = optionalIntFromText(match.group(1));
        return code == null ? match.group(0)! : String.fromCharCode(code);
      })
      .replaceAllMapped(_htmlHexEntityPattern, (match) {
        final code = optionalIntFromText(match.group(1), radix: 16);
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
  return rows.where(_rowHasContent).toList(growable: false);
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
    ..writeln(prettyPrintJson(plain))
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
      '${rawText ?? prettyPrintJson(_jsonSafe(value))}\n'
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
    final section = _tomlSectionPattern.firstMatch(trimmed);
    if (section != null) {
      buffer.writeln('\n## ${section.group(1)!.trim()}\n');
      continue;
    }
    final assignment = _tomlAssignmentPattern.firstMatch(trimmed);
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

Future<String> _extractPdfText(Uint8List bytes) async {
  final latin = latin1.decode(bytes, allowInvalid: true);
  final buffer = StringBuffer();
  var decodedTotalBytes = 0;
  for (final match in _pdfStreamStartPattern.allMatches(latin)) {
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
    final raw = Uint8List.sublistView(bytes, match.end, contentEnd);
    final decoded = await _decodePdfStream(raw, dictionary);
    if (decoded == null || decoded.isEmpty) continue;
    decodedTotalBytes += decoded.length;
    if (decodedTotalBytes > _maxKnowledgePdfDecodedTotalBytes) {
      throw const FormatException('PDF 解压文本流累计大小超过安全上限。');
    }
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

Future<Uint8List?> _decodePdfStream(Uint8List bytes, String dictionary) async {
  if (!dictionary.contains('/FlateDecode')) {
    if (bytes.length > _maxKnowledgePdfDecodedStreamBytes) {
      throw const FormatException('PDF 文本流大小超过安全上限。');
    }
    return bytes;
  }
  try {
    return await readBoundedByteStream(
      ZLibDecoder().bind(Stream<List<int>>.value(bytes)),
      maxBytes: _maxKnowledgePdfDecodedStreamBytes,
      idleTimeout: _knowledgePdfDecodeIdleTimeout,
      totalTimeout: _knowledgePdfDecodeTotalTimeout,
    );
  } on HttpException {
    throw const FormatException('PDF 解压文本流大小超过安全上限。');
  } on TimeoutException {
    throw const FormatException('PDF 解压文本流处理超时。');
  } catch (_) {
    return null;
  }
}

String _extractPdfContentText(String stream) {
  final buffer = StringBuffer();
  for (final block in _pdfTextBlockPattern.allMatches(stream)) {
    final strings = _extractPdfStrings(block.group(1) ?? '')
        .map(collapseInlineWhitespace)
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
      .where((value) => nullIfBlank(value) != null)
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
          final octal = _pdfOctalEscapePattern.stringMatch(
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
  final clean = removeInlineWhitespace(hex);
  final bytes = <int>[];
  for (var index = 0; index < clean.length; index += 2) {
    final chunk = index + 1 < clean.length
        ? clean.substring(index, index + 2)
        : '${clean[index]}0';
    final byte = optionalIntFromText(chunk, radix: 16);
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
      .replaceAll(_knowledgeExcessiveBlankLinesPattern, '\n\n')
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
    _ => kTextPlainMimeType,
  };
}
