import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/qdrant_admin_service.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, Object?>{'result': true}));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('operation log honors retention setting and keeps newest entries', () async {
    final service = QdrantAdminService();
    final settings = KnowledgeBaseSettings(
      qdrantHost: InternetAddress.loopbackIPv4.address,
      qdrantRestPort: server.port,
      qdrantLogRetainLines: 2,
    );

    await service.scroll(settings, collection: 'test');
    await service.pointsByIds(
      settings,
      collection: 'test',
      ids: const <String>['one'],
    );
    await service.searchRawVector(
      settings,
      collection: 'test',
      vector: const <double>[1],
    );

    expect(
      service.logs.map((entry) => entry.action),
      orderedEquals(const <String>['points_by_ids', 'raw_vector_search']),
    );
  });

  test('trimLogs applies a lower retention limit immediately', () async {
    final service = QdrantAdminService();
    final settings = KnowledgeBaseSettings(
      qdrantHost: InternetAddress.loopbackIPv4.address,
      qdrantRestPort: server.port,
      qdrantLogRetainLines: 3,
    );

    await service.scroll(settings, collection: 'test');
    await service.pointsByIds(
      settings,
      collection: 'test',
      ids: const <String>['one'],
    );
    service.trimLogs(1);

    expect(service.logs, hasLength(1));
    expect(service.logs.single.action, 'points_by_ids');
  });
}
