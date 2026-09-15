class SkillMarketSearchResult {
  const SkillMarketSearchResult({
    required this.skills,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<SkillMarketSummary> skills;
  final int total;
  final int page;
  final int pageSize;
}

class SkillMarketSummary {
  const SkillMarketSummary({
    required this.category,
    required this.createdAt,
    required this.description,
    required this.descriptionZh,
    required this.downloads,
    required this.iconUrl,
    required this.installs,
    required this.name,
    required this.ownerName,
    required this.publisherName,
    required this.requiresApiKey,
    required this.score,
    required this.slug,
    required this.source,
    required this.stars,
    required this.subCategories,
    required this.tags,
    required this.updatedAt,
    required this.version,
  });

  final String category;
  final int createdAt;
  final String description;
  final String descriptionZh;
  final int downloads;
  final String? iconUrl;
  final int installs;
  final String name;
  final String ownerName;
  final String publisherName;
  final bool requiresApiKey;
  final double score;
  final String slug;
  final String source;
  final int stars;
  final List<SkillMarketSubCategory> subCategories;
  final List<String> tags;
  final int updatedAt;
  final String version;

  String get displayName => name.isNotEmpty ? name : slug;
}

class SkillMarketBundle {
  const SkillMarketBundle({
    required this.detail,
    required this.files,
    required this.versions,
    required this.skillMarkdown,
    required this.resolvedVersion,
  });

  final SkillMarketDetail detail;
  final SkillMarketFilesResult? files;
  final List<SkillMarketVersion> versions;
  final String? skillMarkdown;
  final String resolvedVersion;
}

class SkillMarketDetail {
  const SkillMarketDetail({
    required this.skill,
    required this.owner,
    required this.publisherName,
    required this.latestVersion,
    required this.securityReports,
  });

  final SkillMarketDetailSkill skill;
  final SkillMarketOwner owner;
  final String publisherName;
  final SkillMarketVersion? latestVersion;
  final Map<String, SkillMarketSecurityReport> securityReports;
}

class SkillMarketDetailSkill {
  const SkillMarketDetailSkill({
    required this.category,
    required this.createdAt,
    required this.displayName,
    required this.iconUrl,
    required this.requiresApiKey,
    required this.slug,
    required this.source,
    required this.stats,
    required this.summary,
    required this.summaryZh,
    required this.subCategories,
    required this.tags,
    required this.updatedAt,
  });

  final String category;
  final int createdAt;
  final String displayName;
  final String? iconUrl;
  final bool requiresApiKey;
  final String slug;
  final String source;
  final SkillMarketStats stats;
  final String summary;
  final String summaryZh;
  final List<SkillMarketSubCategory> subCategories;
  final Map<String, String> tags;
  final int updatedAt;

  String get latestTag => tags['latest'] ?? '';
}

class SkillMarketSubCategory {
  const SkillMarketSubCategory({required this.key, required this.name});

  final String key;
  final String name;
}

class SkillMarketOwner {
  const SkillMarketOwner({
    required this.displayName,
    required this.handle,
    required this.image,
  });

  final String displayName;
  final String handle;
  final String? image;
}

class SkillMarketStats {
  const SkillMarketStats({
    required this.downloads,
    required this.installs,
    required this.stars,
    required this.versions,
  });

  final int downloads;
  final int installs;
  final int stars;
  final int versions;
}

class SkillMarketSecurityReport {
  const SkillMarketSecurityReport({
    required this.status,
    required this.statusText,
  });

  final String status;
  final String statusText;
}

class SkillMarketFilesResult {
  const SkillMarketFilesResult({
    required this.count,
    required this.files,
    required this.version,
  });

  final int count;
  final List<SkillMarketFileEntry> files;
  final String version;
}

class SkillMarketFileEntry {
  const SkillMarketFileEntry({
    required this.path,
    required this.sha256,
    required this.size,
  });

  final String path;
  final String sha256;
  final int size;
}

class SkillMarketVersionsResult {
  const SkillMarketVersionsResult({
    required this.slug,
    required this.source,
    required this.versions,
  });

  final String slug;
  final String source;
  final List<SkillMarketVersion> versions;
}

class SkillMarketVersion {
  const SkillMarketVersion({
    required this.changelog,
    required this.createdAt,
    required this.version,
    required this.versionId,
    required this.securityReports,
  });

  final String changelog;
  final int createdAt;
  final String version;
  final int versionId;
  final Map<String, SkillMarketSecurityReport> securityReports;
}
