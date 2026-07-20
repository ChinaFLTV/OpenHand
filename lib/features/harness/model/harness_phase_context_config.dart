import 'harness_phase.dart';

/// 阶段提示词包含经验教训的方式。
enum HarnessLessonInclusionMode {
  /// 不包含。
  none,

  /// 仅包含摘要。
  summary,

  /// 包含完整内容。
  full,
}

/// 阶段提示词的上下文配置。
class HarnessPhaseContextConfig {
  const HarnessPhaseContextConfig({
    this.includeArchitecture = true,
    this.includeConventions = true,
    this.includePlan = false,
    this.includeFeedback = false,
    this.lessonsMode = HarnessLessonInclusionMode.none,
    this.includeHandoff = true,
  });

  /// 是否包含 architecture.md。
  final bool includeArchitecture;

  /// 是否包含 conventions.md。
  final bool includeConventions;

  /// 是否包含最新执行计划。
  final bool includePlan;

  /// 是否包含最新复核反馈。
  final bool includeFeedback;

  /// 经验教训的包含方式。
  final HarnessLessonInclusionMode lessonsMode;

  /// 是否包含最新交接文档。
  final bool includeHandoff;
}

HarnessPhaseContextConfig getPhaseContextConfig(HarnessPhase phase) {
  return switch (phase) {
    HarnessPhase.metaCollection => const HarnessPhaseContextConfig(
      includeArchitecture: false,
      includeConventions: false,
      includeHandoff: false,
    ),
    HarnessPhase.reading => const HarnessPhaseContextConfig(
      lessonsMode: HarnessLessonInclusionMode.summary,
    ),
    HarnessPhase.planning => const HarnessPhaseContextConfig(
      includeFeedback: true,
      lessonsMode: HarnessLessonInclusionMode.summary,
    ),
    HarnessPhase.implementing => const HarnessPhaseContextConfig(
      includePlan: true,
      includeFeedback: true,
      lessonsMode: HarnessLessonInclusionMode.summary,
      includeHandoff: false,
    ),
    HarnessPhase.reviewing => const HarnessPhaseContextConfig(
      includePlan: true,
      includeHandoff: false,
    ),
  };
}
