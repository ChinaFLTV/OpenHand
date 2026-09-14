class McpMarketServer {
  McpMarketServer.fromJson(Map<String, Object?> json)
    : slug = _text(json['slug']),
      name = _text(json['name']),
      publisher = _text(json['publisher']),
      category = _text(json['category']),
      summary = _text(json['summaryZh']).isNotEmpty
          ? _text(json['summaryZh'])
          : _text(json['summary']),
      iconUrl = _text(json['iconUrl']),
      repoUrl = _text(json['repoUrl']),
      homepage = _text(json['homepage']),
      sourceUrl = _text(json['sourceUrl']),
      banned = json['banned'] == true,
      visible = json['status'] == 'visible',
      tags = (json['tags'] as List? ?? const [])
          .whereType<String>()
          .where((tag) => tag.trim().isNotEmpty)
          .take(12)
          .toList(growable: false),
      downloads = _count((json['stats'] as Map?)?['downloads']),
      installs = _count((json['stats'] as Map?)?['installs']);

  final String slug, name, publisher, category, summary, iconUrl;
  final String repoUrl, homepage, sourceUrl;
  final bool banned, visible;
  final List<String> tags;
  final int downloads, installs;

  bool get canConfigure => !banned && visible && slug.isNotEmpty;
  String get displayName => name.isEmpty ? slug : name;

  static String _text(Object? value) => value is String ? value.trim() : '';
  static int _count(Object? value) =>
      value is num ? value.toInt().clamp(0, 1 << 53) : 0;
}

class McpMarketPage {
  McpMarketPage.fromJson(Map<String, Object?> json)
    : items = (json['items'] as List)
          .map(
            (item) => McpMarketServer.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .where((item) => item.slug.isNotEmpty)
          .toList(growable: false),
      total = McpMarketServer._count(json['total']);

  final List<McpMarketServer> items;
  final int total;
}
