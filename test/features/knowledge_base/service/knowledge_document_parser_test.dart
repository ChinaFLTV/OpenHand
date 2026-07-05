import 'dart:io';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_document_parser.dart';

void main() {
  group('KnowledgeDocumentParserRegistry', () {
    test('parses xlsx archive text through shared archive reader', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_knowledge_document_parser_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}/report.xlsx');
      await file.writeAsBytes(_minimalXlsxBytes());

      final result = await const KnowledgeDocumentParserRegistry().parse(
        KnowledgeDocumentParseRequest(
          file: file,
          settings: const KnowledgeBaseSettings(),
          stat: await file.stat(),
        ),
      );

      expect(result.kind, 'spreadsheet');
      expect(result.title, 'Quarterly Plan');
      expect(result.metadata['file_extension'], 'xlsx');
      expect(result.metadata['sheet_count'], 1);
      expect(result.text, contains('# Quarterly Plan'));
      expect(result.text, contains('## Budget'));
      expect(result.text, contains('| Name | Amount |'));
      expect(result.text, contains('| Alice | 42 |'));
    });
  });
}

List<int> _minimalXlsxBytes() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('docProps/core.xml', '''
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>Quarterly Plan</dc:title>
</cp:coreProperties>
'''),
    )
    ..addFile(
      ArchiveFile.string('xl/workbook.xml', '''
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheets>
    <sheet name="Budget" sheetId="1" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
  </sheets>
</workbook>
'''),
    )
    ..addFile(
      ArchiveFile.string('xl/sharedStrings.xml', '''
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Name</t></si>
  <si><t>Alice</t></si>
</sst>
'''),
    )
    ..addFile(
      ArchiveFile.string('xl/worksheets/sheet1.xml', '''
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1" t="inlineStr"><is><t>Amount</t></is></c>
    </row>
    <row r="2">
      <c r="A2" t="s"><v>1</v></c>
      <c r="B2"><v>42</v></c>
    </row>
  </sheetData>
</worksheet>
'''),
    );
  return ZipEncoder().encode(archive);
}
