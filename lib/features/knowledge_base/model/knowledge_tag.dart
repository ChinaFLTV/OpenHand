class KnowledgeTag {
  const KnowledgeTag({
    required this.id,
    required this.name,
    this.color = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'color': color,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  static KnowledgeTag fromRow(Map<String, Object?> row) {
    return KnowledgeTag(
      id: '${row['id'] ?? ''}',
      name: '${row['name'] ?? ''}',
      color: '${row['color'] ?? ''}',
      createdAt:
          DateTime.tryParse('${row['created_at'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse('${row['updated_at'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}
