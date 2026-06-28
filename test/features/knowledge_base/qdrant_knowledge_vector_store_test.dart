import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/qdrant_knowledge_vector_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('qdrant point id is a stable uuid for chunk ids', () {
    const chunkId = 'f9a59f62-f0c1-431a-8fc5-15d60edae123_chunk_0';

    final first = qdrantPointIdForStableId(chunkId);
    final second = qdrantPointIdForStableId(chunkId);

    expect(first, second);
    expect(first, isA<String>());
    expect(Uuid.isValidUUID(fromString: first as String), isTrue);
  });

  test('qdrant point id preserves existing uuid and unsigned integer ids', () {
    const uuid = 'f9a59f62-f0c1-431a-8fc5-15d60edae123';

    expect(qdrantPointIdForStableId(uuid), uuid);
    expect(qdrantPointIdForStableId('42'), 42);
  });

  test('search normalizes response values and skips unsafe requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestBodies = <Map<String, Object?>>[];
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body);
      requestBodies.add(
        decoded is Map
            ? Map<String, Object?>.from(decoded)
            : const <String, Object?>{},
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'result': <Object?>[
            <String, Object?>{
              'id': 'point-a',
              'score': '0.75',
              'payload': <String, Object?>{'chunk_id': 'chunk-a'},
            },
            <String, Object?>{
              'id': 'point-b',
              'score': 'NaN',
              'payload': <Object?>[],
            },
            <String, Object?>{'id': '', 'score': 0.25},
          ],
        }),
      );
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final store = QdrantKnowledgeVectorStore(
      settings: KnowledgeBaseSettings(
        qdrantHost: server.address.address,
        qdrantRestPort: server.port,
        requestTimeoutSeconds: 3,
      ),
    );

    final skipped = await store.search(
      collectionName: 'docs',
      vector: <double>[double.nan],
      limit: 3,
    );
    expect(skipped, isEmpty);
    expect(requestBodies, isEmpty);

    final skippedLimit = await store.search(
      collectionName: 'docs',
      vector: const <double>[0.1, 0.2],
      limit: 0,
    );
    expect(skippedLimit, isEmpty);
    expect(requestBodies, isEmpty);

    final hits = await store.search(
      collectionName: 'docs',
      vector: const <double>[0.1, 0.2],
      limit: 3,
      scoreThreshold: double.infinity,
    );

    expect(requestBodies, hasLength(1));
    expect(requestBodies.single.containsKey('score_threshold'), isFalse);
    expect(requestBodies.single['with_vector'], isFalse);
    expect(hits, hasLength(2));
    expect(hits.first.id, 'point-a');
    expect(hits.first.score, 0.75);
    expect(hits.first.payload['chunk_id'], 'chunk-a');
    expect(hits.last.id, 'point-b');
    expect(hits.last.score, 0);
    expect(hits.last.payload, isEmpty);
  });

  test('sample scrolls points with vectors and next offset', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, Object?> requestBody = const <String, Object?>{};
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body);
      requestBody = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'result': <String, Object?>{
            'points': <Object?>[
              <String, Object?>{
                'id': 'point-a',
                'vector': <Object?>[0.1, '0.2', 'bad'],
                'payload': <String, Object?>{'chunk_id': 'chunk-a'},
              },
              <String, Object?>{
                'id': 'point-b',
                'vector': <String, Object?>{
                  'default': <Object?>[0.3, 0.4],
                },
                'payload': <String, Object?>{'chunk_id': 'chunk-b'},
              },
            ],
            'next_page_offset': 'point-c',
          },
        }),
      );
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final store = QdrantKnowledgeVectorStore(
      settings: KnowledgeBaseSettings(
        qdrantHost: server.address.address,
        qdrantRestPort: server.port,
        requestTimeoutSeconds: 3,
      ),
    );

    final page = await store.sample(
      collectionName: 'docs',
      limit: 2,
      offset: 'point-a',
    );

    expect(requestBody['with_vector'], isTrue);
    expect(requestBody['offset'], 'point-a');
    expect(page.nextPageOffset, 'point-c');
    expect(page.points, hasLength(2));
    expect(page.points.first.vector, <double>[0.1, 0.2]);
    expect(page.points.last.vector, <double>[0.3, 0.4]);
  });
}
