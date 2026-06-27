import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_document_parser.dart';

void main() {
  group('KnowledgeDocumentParserRegistry', () {
    late Directory tempDir;
    const registry = KnowledgeDocumentParserRegistry();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('openhand_kb_parser_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'extracts DOCX paragraphs and tables through the Open XML parser',
      () async {
        final file = File('${tempDir.path}/runbook.docx');
        await _writeZip(file, <String, String>{
          'docProps/core.xml':
              '<cp:coreProperties xmlns:cp="cp" xmlns:dc="dc"><dc:title>Runbook</dc:title></cp:coreProperties>',
          'word/document.xml': '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Deploy checklist</w:t></w:r></w:p>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>Step</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Owner</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>Verify health</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>SRE</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
  </w:body>
</w:document>
''',
        });

        final result = await _parse(registry, file);

        expect(result.kind, 'docx');
        expect(result.title, 'Runbook');
        expect(result.text, contains('Deploy checklist'));
        expect(result.text, contains('| Step | Owner |'));
        expect(result.text, contains('| Verify health | SRE |'));
        expect(result.metadata['parser_id'], isNull);
        expect(result.parserId, 'docx_open_xml');
      },
    );

    test('extracts XLSX shared strings into markdown tables', () async {
      final file = File('${tempDir.path}/inventory.xlsx');
      await _writeZip(file, <String, String>{
        'docProps/core.xml':
            '<cp:coreProperties xmlns:cp="cp" xmlns:dc="dc"><dc:title>Inventory</dc:title></cp:coreProperties>',
        'xl/workbook.xml':
            '<workbook xmlns="main"><sheets><sheet name="Servers" sheetId="1"/></sheets></workbook>',
        'xl/sharedStrings.xml': '''
<sst xmlns="main">
  <si><t>Name</t></si>
  <si><t>Status</t></si>
  <si><t>api-01</t></si>
  <si><t>healthy</t></si>
</sst>
''',
        'xl/worksheets/sheet1.xml': '''
<worksheet xmlns="main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
    <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="s"><v>3</v></c></row>
  </sheetData>
</worksheet>
''',
      });

      final result = await _parse(registry, file);

      expect(result.kind, 'spreadsheet');
      expect(result.text, contains('## Servers'));
      expect(result.text, contains('| Name | Status |'));
      expect(result.text, contains('| api-01 | healthy |'));
    });

    test('extracts PPTX slide text in slide order', () async {
      final file = File('${tempDir.path}/briefing.pptx');
      await _writeZip(file, <String, String>{
        'docProps/core.xml':
            '<cp:coreProperties xmlns:cp="cp" xmlns:dc="dc"><dc:title>Briefing</dc:title></cp:coreProperties>',
        'ppt/slides/slide1.xml': '''
<p:sld xmlns:p="presentation" xmlns:a="drawing">
  <p:cSld><p:spTree><p:sp><p:txBody>
    <a:p><a:r><a:t>Quarterly plan</a:t></a:r></a:p>
    <a:p><a:r><a:t>Reduce incident response time</a:t></a:r></a:p>
  </p:txBody></p:sp></p:spTree></p:cSld>
</p:sld>
''',
      });

      final result = await _parse(registry, file);

      expect(result.kind, 'presentation');
      expect(result.text, contains('## Slide 1'));
      expect(result.text, contains('Quarterly plan'));
      expect(result.text, contains('Reduce incident response time'));
    });

    test('extracts basic compressed PDF text streams', () async {
      final file = File('${tempDir.path}/note.pdf');
      final contentStream = latin1.encode(
        'BT /F1 12 Tf 72 712 Td (Hello PDF knowledge) Tj ET',
      );
      final compressed = ZLibCodec().encoder.convert(contentStream);
      await file.writeAsBytes(<int>[
        ...latin1.encode('''
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /Contents 4 0 R >> endobj
4 0 obj << /Length ${compressed.length} /Filter /FlateDecode >>
stream
'''),
        ...compressed,
        ...latin1.encode('''

endstream
endobj
trailer << /Root 1 0 R >>
%%EOF
'''),
      ], flush: true);

      final result = await _parse(registry, file);

      expect(result.kind, 'pdf');
      expect(result.text, contains('Hello PDF knowledge'));
      expect(result.parserId, 'pdf_basic_text_stream');
    });

    test('normalizes CSV, JSON, and YAML into knowledge text', () async {
      final csv = File('${tempDir.path}/data.csv')
        ..writeAsStringSync('name,status\napi,healthy\n');
      final json = File('${tempDir.path}/config.json')
        ..writeAsStringSync('{"service":{"name":"api","replicas":2}}');
      final yaml = File('${tempDir.path}/config.yaml')
        ..writeAsStringSync('service:\n  name: api\n  replicas: 2\n');

      final csvResult = await _parse(registry, csv);
      final jsonResult = await _parse(registry, json);
      final yamlResult = await _parse(registry, yaml);

      expect(csvResult.kind, 'table');
      expect(csvResult.text, contains('| name | status |'));
      expect(jsonResult.kind, 'structured');
      expect(jsonResult.text, contains('## service'));
      expect(jsonResult.text, contains('- name: api'));
      expect(yamlResult.kind, 'structured');
      expect(yamlResult.text, contains('## service'));
      expect(yamlResult.text, contains('- replicas: 2'));
    });
  });
}

Future<KnowledgeDocumentParseResult> _parse(
  KnowledgeDocumentParserRegistry registry,
  File file, {
  KnowledgeBaseSettings settings = const KnowledgeBaseSettings(),
}) async {
  return registry.parse(
    KnowledgeDocumentParseRequest(
      file: file,
      settings: settings,
      stat: await file.stat(),
    ),
  );
}

Future<void> _writeZip(File file, Map<String, String> entries) async {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
}
