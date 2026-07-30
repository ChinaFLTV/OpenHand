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

// 进程级 HE 注解解析结果缓存。气泡每次 build 都会对整条 message.content
// 跑 2 次 firstMatch + 3 次 replaceAll 全串正则，长会话下反复重扫是主线程
// 负担。按内容指纹缓存结果（含未命中的 null），transcript 与 bubble 共用。
// 值用 _HeAnnotationCacheEntry 包裹以区分「已算得 null」与「未缓存」。
final RegExp _heLeadingWhitespacePattern = RegExp(r'^\s+');

class _HeAnnotationCacheEntry {
  const _HeAnnotationCacheEntry(this.value);
  final _HeAnnotation? value;
}

class _HeAnnotationCache {
  static const int _maxEntries = 256;
  final LinkedHashMap<int, _HeAnnotationCacheEntry> _entries =
      LinkedHashMap<int, _HeAnnotationCacheEntry>();

  _HeAnnotationCacheEntry? get(int key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry;
    }
    return entry;
  }

  void put(int key, _HeAnnotationCacheEntry entry) {
    _entries.remove(key);
    _entries[key] = entry;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

final _HeAnnotationCache _heAnnotationCache = _HeAnnotationCache();

_HeAnnotation? _parseHeAnnotation(String content) {
  if (content.isEmpty) return null;
  final cacheKey = Object.hash(content.length, boundedTextFingerprint(content));
  final cached = _heAnnotationCache.get(cacheKey);
  if (cached != null) {
    return cached.value;
  }
  final result = _computeHeAnnotation(content);
  _heAnnotationCache.put(cacheKey, _HeAnnotationCacheEntry(result));
  return result;
}

_HeAnnotation? _computeHeAnnotation(String content) {
  final agentMatch = _heAgentPattern.firstMatch(content);
  final phaseMatch = _hePhasePattern.firstMatch(content);
  if (agentMatch == null && phaseMatch == null) return null;
  final stripped = content
      .replaceAll(_heAgentPattern, '')
      .replaceAll(_hePhasePattern, '')
      .replaceAll(_heLeadingWhitespacePattern, '')
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
