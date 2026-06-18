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

const Map<String, String> _heRoleDisplayZh = {
  'reader': '调查者',
  'planner': '规划者',
  'implementer': '实施者',
  'reviewer': '验收者',
};

const Map<String, String> _heRoleDisplayEn = {
  'reader': 'Reader',
  'planner': 'Planner',
  'implementer': 'Implementer',
  'reviewer': 'Reviewer',
};

const Map<String, String> _hePhaseDisplayZh = {
  'meta_collection': '元数据采集',
  'reading': '调查',
  'planning': '规划',
  'implementing': '实施',
  'reviewing': '验收',
};

const Map<String, String> _hePhaseDisplayEn = {
  'meta_collection': 'Meta Collection',
  'reading': 'Reading',
  'planning': 'Planning',
  'implementing': 'Implementing',
  'reviewing': 'Reviewing',
};

const Map<String, IconData> _hePhaseIcons = {
  'meta_collection': Icons.manage_search_rounded,
  'reading': Icons.menu_book_rounded,
  'planning': Icons.route_rounded,
  'implementing': Icons.code_rounded,
  'reviewing': Icons.fact_check_rounded,
};
