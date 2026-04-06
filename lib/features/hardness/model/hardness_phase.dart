enum HardnessPhase {
  metaCollection('meta_collection'),
  reading('reading'),
  planning('planning'),
  implementing('implementing'),
  reviewing('reviewing');

  const HardnessPhase(this.storageValue);

  final String storageValue;

  String get displayNameZh => switch (this) {
    HardnessPhase.metaCollection => '元数据采集',
    HardnessPhase.reading => '调查',
    HardnessPhase.planning => '规划',
    HardnessPhase.implementing => '实施',
    HardnessPhase.reviewing => '验收',
  };

  String get displayNameEn => switch (this) {
    HardnessPhase.metaCollection => 'Meta Collection',
    HardnessPhase.reading => 'Reading',
    HardnessPhase.planning => 'Planning',
    HardnessPhase.implementing => 'Implementing',
    HardnessPhase.reviewing => 'Reviewing',
  };

  static HardnessPhase? fromStorageValue(String value) {
    for (final phase in HardnessPhase.values) {
      if (phase.storageValue == value) return phase;
    }
    return null;
  }
}
