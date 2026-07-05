// Harness Engineering phase context configuration.
// This module defines which context elements (architecture, conventions,
// plan, feedback, lessons, handoff) should be included in each phase's
// prompt, enabling context-aware loading to reduce token overhead.

import 'harness_phase.dart';

/// Controls how experience lessons are included in a phase prompt.
enum HarnessLessonInclusionMode {
  /// Do not include lessons.
  none,

  /// Include a compressed summary of lessons (top 3-5 most relevant points).
  summary,

  /// Include all lessons in full.
  full,
}

/// Configuration for what context elements to include in a phase prompt.
class HarnessPhaseContextConfig {
  const HarnessPhaseContextConfig({
    this.includeArchitecture = true,
    this.includeConventions = true,
    this.includePlan = false,
    this.includeFeedback = false,
    this.lessonsMode = HarnessLessonInclusionMode.none,
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
  final HarnessLessonInclusionMode lessonsMode;

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
const Map<HarnessPhase, HarnessPhaseContextConfig> kHarnessPhaseContextConfigs =
    {
      HarnessPhase.metaCollection: HarnessPhaseContextConfig(
        includeArchitecture: false,
        includeConventions: false,
        includeHandoff: false,
      ),
      HarnessPhase.reading: HarnessPhaseContextConfig(
        lessonsMode: HarnessLessonInclusionMode.summary,
      ),
      HarnessPhase.planning: HarnessPhaseContextConfig(
        includeFeedback: true, // Include feedback during retry cycles
        lessonsMode: HarnessLessonInclusionMode.summary,
      ),
      HarnessPhase.implementing: HarnessPhaseContextConfig(
        includePlan: true,
        includeFeedback: true,
        lessonsMode: HarnessLessonInclusionMode.summary,
        includeHandoff: false,
      ),
      HarnessPhase.reviewing: HarnessPhaseContextConfig(
        includePlan: true,
        includeHandoff: false,
      ),
    };

/// Gets the context config for a phase.
HarnessPhaseContextConfig getPhaseContextConfig(HarnessPhase phase) {
  return kHarnessPhaseContextConfigs[phase] ??
      const HarnessPhaseContextConfig();
}
