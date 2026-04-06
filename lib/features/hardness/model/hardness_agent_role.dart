enum HardnessAgentRole {
  /// 探档者 — first run only: scans project structure and writes meta files.
  profiler('profiler'),
  reader('reader'),
  planner('planner'),
  implementer('implementer'),
  reviewer('reviewer');

  const HardnessAgentRole(this.storageValue);

  final String storageValue;

  String get displayNameZh => switch (this) {
    HardnessAgentRole.profiler => '探档者',
    HardnessAgentRole.reader => '调查者',
    HardnessAgentRole.planner => '规划者',
    HardnessAgentRole.implementer => '实施者',
    HardnessAgentRole.reviewer => '验收者',
  };

  String get displayNameEn => switch (this) {
    HardnessAgentRole.profiler => 'Profiler',
    HardnessAgentRole.reader => 'Reader',
    HardnessAgentRole.planner => 'Planner',
    HardnessAgentRole.implementer => 'Implementer',
    HardnessAgentRole.reviewer => 'Reviewer',
  };

  static HardnessAgentRole? fromStorageValue(String value) {
    for (final role in HardnessAgentRole.values) {
      if (role.storageValue == value) return role;
    }
    return null;
  }
}
