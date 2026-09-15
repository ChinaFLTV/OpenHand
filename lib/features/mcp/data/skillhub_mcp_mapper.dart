import '../model/mcp_market.dart';

abstract final class SkillHubMcpMapper {
  static McpMarketServer server(Map<String, Object?> json) => McpMarketServer(
    slug: _text(json['slug']),
    name: _text(json['name']),
    nameEn: _text(json['nameEn']),
    publisher: _text(json['publisher']),
    category: _text(json['category']),
    summary: _text(json['summary']),
    summaryZh: _text(json['summaryZh']),
    iconUrl: _text(json['iconUrl']),
    repoUrl: _text(json['repoUrl']),
    homepage: _text(json['homepage']),
    sourceUrl: _text(json['sourceUrl']),
    banned: json['banned'] == true,
    visible: json['status'] == 'visible',
    tags: (json['tags'] as List? ?? const [])
        .whereType<String>()
        .where((tag) => tag.trim().isNotEmpty)
        .take(12)
        .toList(growable: false),
    downloads: _count((json['stats'] as Map?)?['downloads']),
    installs: _count((json['stats'] as Map?)?['installs']),
  );

  static McpMarketPage page(Map<String, Object?> json) => McpMarketPage(
    items: (json['items'] as List)
        .map((item) => server(Map<String, Object?>.from(item as Map)))
        .where((item) => item.slug.isNotEmpty)
        .toList(growable: false),
    total: _count(json['total']),
  );

  static String _text(Object? value) => value is String ? value.trim() : '';
  static int _count(Object? value) =>
      value is num ? value.toInt().clamp(0, 1 << 53) : 0;
}
