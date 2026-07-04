enum HarnessPhase {
  metaCollection('meta_collection'),
  reading('reading'),
  planning('planning'),
  implementing('implementing'),
  reviewing('reviewing');

  const HarnessPhase(this.storageValue);

  final String storageValue;

  String get displayNameZh => switch (this) {
    HarnessPhase.metaCollection => '元数据采集',
    HarnessPhase.reading => '调查',
    HarnessPhase.planning => '规划',
    HarnessPhase.implementing => '实施',
    HarnessPhase.reviewing => '验收',
  };

  String get displayNameEn => switch (this) {
    HarnessPhase.metaCollection => 'Meta Collection',
    HarnessPhase.reading => 'Reading',
    HarnessPhase.planning => 'Planning',
    HarnessPhase.implementing => 'Implementing',
    HarnessPhase.reviewing => 'Reviewing',
  };

  static HarnessPhase? fromStorageValue(String value) {
    for (final phase in HarnessPhase.values) {
      if (phase.storageValue == value) return phase;
    }
    return null;
  }
}
