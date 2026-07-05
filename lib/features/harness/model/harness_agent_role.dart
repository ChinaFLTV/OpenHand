import '../../../shared/util/input_value_parsing.dart';

enum HarnessAgentRole {
  /// 探档者 — first run only: scans project structure and writes meta files.
  profiler('profiler'),
  reader('reader'),
  planner('planner'),
  implementer('implementer'),
  reviewer('reviewer');

  const HarnessAgentRole(this.storageValue);

  final String storageValue;

  String get displayNameZh => switch (this) {
    HarnessAgentRole.profiler => '探档者',
    HarnessAgentRole.reader => '调查者',
    HarnessAgentRole.planner => '规划者',
    HarnessAgentRole.implementer => '实施者',
    HarnessAgentRole.reviewer => '验收者',
  };

  String get displayNameEn => switch (this) {
    HarnessAgentRole.profiler => 'Profiler',
    HarnessAgentRole.reader => 'Reader',
    HarnessAgentRole.planner => 'Planner',
    HarnessAgentRole.implementer => 'Implementer',
    HarnessAgentRole.reviewer => 'Reviewer',
  };

  static HarnessAgentRole? fromStorageValue(String value) {
    return enumByStorageValue(values, value, (role) => role.storageValue);
  }
}
