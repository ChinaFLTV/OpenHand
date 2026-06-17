part of '../openhand_home_page.dart';

class _HeAnnotation {
  const _HeAnnotation({
    required this.agentRole,
    required this.agentId,
    required this.phase,
    required this.strippedContent,
  });

  final String? agentRole;
  final String? agentId;
  final String? phase;
  final String strippedContent;

  bool get hasAnnotations => agentRole != null || phase != null;
}

_HeAnnotation? _parseHeAnnotation(String content) {
  final agentMatch = _heAgentPattern.firstMatch(content);
  final phaseMatch = _hePhasePattern.firstMatch(content);
  if (agentMatch == null && phaseMatch == null) return null;
  final stripped = content
      .replaceAll(_heAgentPattern, '')
      .replaceAll(_hePhasePattern, '')
      .replaceAll(RegExp(r'^\s+'), '')
      .trim();
  return _HeAnnotation(
    agentRole: agentMatch?.group(1),
    agentId: agentMatch?.group(2),
    phase: phaseMatch?.group(1),
    strippedContent: stripped,
  );
}

// ── Harness Engineering capsule row widget ───────────────────────────────────

class _HardnessAnnotationCapsuleRow extends StatelessWidget {
  const _HardnessAnnotationCapsuleRow({required this.annotation});

  final _HeAnnotation annotation;

  static const Map<String, String> _roleDisplayZh = {
    'reader': '调查者',
    'planner': '规划者',
    'implementer': '实施者',
    'reviewer': '验收者',
  };

  static const Map<String, String> _roleDisplayEn = {
    'reader': 'Reader',
    'planner': 'Planner',
    'implementer': 'Implementer',
    'reviewer': 'Reviewer',
  };

  static const Map<String, String> _phaseDisplayZh = {
    'meta_collection': '元数据采集',
    'reading': '调查',
    'planning': '规划',
    'implementing': '实施',
    'reviewing': '验收',
  };

  static const Map<String, String> _phaseDisplayEn = {
    'meta_collection': 'Meta Collection',
    'reading': 'Reading',
    'planning': 'Planning',
    'implementing': 'Implementing',
    'reviewing': 'Reviewing',
  };

  static const Map<String, IconData> _phaseIcons = {
    'meta_collection': Icons.manage_search_rounded,
    'reading': Icons.menu_book_rounded,
    'planning': Icons.route_rounded,
    'implementing': Icons.code_rounded,
    'reviewing': Icons.fact_check_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final capsules = <Widget>[];

    if (annotation.agentRole != null) {
      final roleName = isZh
          ? (_roleDisplayZh[annotation.agentRole] ?? annotation.agentRole!)
          : (_roleDisplayEn[annotation.agentRole] ?? annotation.agentRole!);
      final label = annotation.agentId != null
          ? '$roleName · ${annotation.agentId}'
          : roleName;
      capsules.add(
        _Capsule(
          icon: Icons.person_pin_rounded,
          label: label,
          color: colorScheme.secondary,
          onColor: colorScheme.onSecondary,
        ),
      );
    }

    if (annotation.phase != null) {
      final phaseName = isZh
          ? (_phaseDisplayZh[annotation.phase] ?? annotation.phase!)
          : (_phaseDisplayEn[annotation.phase] ?? annotation.phase!);
      final icon = _phaseIcons[annotation.phase] ?? Icons.timelapse_rounded;
      capsules.add(
        _Capsule(
          icon: icon,
          label: phaseName,
          color: colorScheme.tertiary,
          onColor: colorScheme.onTertiary,
        ),
      );
    }

    if (capsules.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 6, runSpacing: 6, children: capsules),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
