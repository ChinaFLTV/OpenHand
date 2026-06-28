import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/qdrant_admin_service.dart';

void main() {
  test('qdrant collection parser normalizes loose maps and skips noise', () {
    final collections = qdrantCollectionsFromResponse(<Object?, Object?>{
      'result': <Object?, Object?>{
        'collections': <Object?>[
          <Object?, Object?>{1: 'numeric-key', 'name': 'docs'},
          'bad',
          <Object?, Object?>{'name': 'archive'},
        ],
      },
    });

    expect(collections, <Map<String, Object?>>[
      <String, Object?>{'1': 'numeric-key', 'name': 'docs'},
      <String, Object?>{'name': 'archive'},
    ]);
  });

  test(
    'listCollections falls back to empty list for malformed success body',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.write('not-json');
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final service = QdrantAdminService();
      final collections = await service.listCollections(
        KnowledgeBaseSettings(
          qdrantHost: server.address.address,
          qdrantRestPort: server.port,
        ),
      );

      expect(collections, isEmpty);
    },
  );
}
