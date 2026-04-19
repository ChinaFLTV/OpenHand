// Hardness Engineering phase context configuration.
//
// This module defines which context elements (architecture, conventions,
// plan, feedback, lessons, handoff) should be included in each phase's
// prompt, enabling context-aware loading to reduce token overhead.

import 'hardness_phase.dart';

/// Controls how experience lessons are included in a phase prompt.
enum HardnessLessonInclusionMode {
  /// Do not include lessons.
  none,

  /// Include a compressed summary of lessons (top 3-5 most relevant points).
  summary,

  /// Include all lessons in full.
  full,
}

/// Configuration for what context elements to include in a phase prompt.
class HardnessPhaseContextConfig {
  const HardnessPhaseContextConfig({
    this.includeArchitecture = true,
    this.includeConventions = true,
    this.includePlan = false,
    this.includeFeedback = false,
    this.lessonsMode = HardnessLessonInclusionMode.none,
    this.includeHandoff = true,
  });

  /// Whether to include architecture.md content.
  final bool includeArchitecture;

  /// Whether to include conventions.md content.
  final bool includeConventions;

  /// Whether to include the latest execution plan.
  final bool includePlan;

  /// Whether to include the latest reviewer feedback.
  final bool includeFeedback;

  /// How to include experience lessons.
  final HardnessLessonInclusionMode lessonsMode;

  /// Whether to include the latest handoff document.
  final bool includeHandoff;
}

/// Maps each phase to its context configuration.
///
/// This follows the context dependency matrix from the refactoring proposal:
/// - metaCollection: minimal context (scanning fresh project)
/// - reading: architecture + conventions + lessons + handoff
/// - planning: architecture + conventions + lessons + handoff
/// - implementing: full context except handoff (uses plan + feedback)
/// - reviewing: architecture + conventions + plan (verifying implementation)
const Map<HardnessPhase, HardnessPhaseContextConfig>
    kHardnessPhaseContextConfigs = {
  HardnessPhase.metaCollection: HardnessPhaseContextConfig(
    includeArchitecture: false,
    includeConventions: false,
    includeHandoff: false,
  ),
  HardnessPhase.reading: HardnessPhaseContextConfig(
    lessonsMode: HardnessLessonInclusionMode.summary,
  ),
  HardnessPhase.planning: HardnessPhaseContextConfig(
    includeFeedback: true, // Include feedback during retry cycles
    lessonsMode: HardnessLessonInclusionMode.summary,
  ),
  HardnessPhase.implementing: HardnessPhaseContextConfig(
    includePlan: true,
    includeFeedback: true,
    lessonsMode: HardnessLessonInclusionMode.summary,
    includeHandoff: false,
  ),
  HardnessPhase.reviewing: HardnessPhaseContextConfig(
    includePlan: true,
    includeHandoff: false,
  ),
};

/// Gets the context config for a phase.
HardnessPhaseContextConfig getPhaseContextConfig(HardnessPhase phase) {
  return kHardnessPhaseContextConfigs[phase] ??
      const HardnessPhaseContextConfig();
}
