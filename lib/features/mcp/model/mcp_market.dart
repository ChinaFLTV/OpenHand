class McpMarketServer {
  const McpMarketServer({
    this.slug = '',
    this.name = '',
    this.nameEn = '',
    this.publisher = '',
    this.category = '',
    this.summary = '',
    this.summaryZh = '',
    this.iconUrl = '',
    this.repoUrl = '',
    this.homepage = '',
    this.sourceUrl = '',
    this.banned = false,
    this.visible = true,
    this.tags = const [],
    this.downloads = 0,
    this.installs = 0,
  });

  final String slug;
  final String name;
  final String nameEn;
  final String publisher;
  final String category;
  final String summary;
  final String summaryZh;
  final String iconUrl;
  final String repoUrl;
  final String homepage;
  final String sourceUrl;
  final bool banned;
  final bool visible;
  final List<String> tags;
  final int downloads;
  final int installs;

  bool get canConfigure => !banned && visible && slug.isNotEmpty;
  String get displayName => name.isEmpty ? slug : name;
}

class McpMarketPage {
  const McpMarketPage({required this.items, required this.total});
  final List<McpMarketServer> items;
  final int total;
}
