class KnowledgeVectorPoint {
  const KnowledgeVectorPoint({
    required this.id,
    required this.vector,
    required this.payload,
  });

  final String id;
  final List<double> vector;
  final Map<String, Object?> payload;
}

class KnowledgeVectorSearchHit {
  const KnowledgeVectorSearchHit({
    required this.id,
    required this.score,
    required this.payload,
  });

  final String id;
  final double score;
  final Map<String, Object?> payload;
}

abstract class KnowledgeVectorStore {
  Future<void> ensureCollection({
    required String collectionName,
    required int dimensions,
    required String distance,
  });

  Future<void> upsert({
    required String collectionName,
    required List<KnowledgeVectorPoint> points,
  });

  Future<List<KnowledgeVectorSearchHit>> search({
    required String collectionName,
    required List<double> vector,
    required int limit,
    double? scoreThreshold,
    Map<String, Object?>? filter,
  });

  Future<void> deleteBySource({
    required String collectionName,
    required String sourceId,
  });
}
