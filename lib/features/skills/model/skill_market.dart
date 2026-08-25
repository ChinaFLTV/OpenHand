import '../../../shared/util/input_value_parsing.dart';

class SkillMarketSearchResult {
  const SkillMarketSearchResult({
    required this.skills,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory SkillMarketSearchResult.fromJson(
    Map<String, Object?> json, {
    required int page,
    required int pageSize,
  }) {
    final data = json['data'];
    if (data is! Map) {
      throw const FormatException('Skill market search data is invalid.');
    }
    final dataMap = stringKeyedMapFromValue(data);
    final skills = stringKeyedMapListFromValue(
      dataMap['skills'],
    ).map(SkillMarketSummary.fromJson).toList(growable: false);
    return SkillMarketSearchResult(
      skills: skills,
      total: _readInt(dataMap['total']),
      page: page,
      pageSize: pageSize,
    );
  }

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
    required this.homepage,
    required this.iconUrl,
    required this.installs,
    required this.name,
    required this.ownerName,
    required this.requiresApiKey,
    required this.score,
    required this.slug,
    required this.source,
    required this.stars,
    required this.tags,
    required this.updatedAt,
    required this.version,
  });

  factory SkillMarketSummary.fromJson(Map<Object?, Object?> json) {
    return SkillMarketSummary(
      category: _readString(json['category']),
      createdAt: _readInt(json['created_at']),
      description: _readString(json['description']),
      descriptionZh: _readString(json['description_zh']),
      downloads: _readInt(json['downloads']),
      homepage: _readString(json['homepage']),
      iconUrl: _readNullableString(json['iconUrl']),
      installs: _readInt(json['installs']),
      name: _readString(json['name']),
      ownerName: _readString(json['ownerName']),
      requiresApiKey: _readBool(json['requires_api_key']),
      score: _readDouble(json['score']),
      slug: _readString(json['slug']),
      source: _readString(json['source']),
      stars: _readInt(json['stars']),
      tags: stringListFromValue(json['tags']),
      updatedAt: _readInt(json['updated_at']),
      version: _readString(json['version']),
    );
  }

  final String category;
  final int createdAt;
  final String description;
  final String descriptionZh;
  final int downloads;
  final String homepage;
  final String? iconUrl;
  final int installs;
  final String name;
  final String ownerName;
  final bool requiresApiKey;
  final double score;
  final String slug;
  final String source;
  final int stars;
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
    required this.latestVersion,
    required this.securityReports,
  });

  factory SkillMarketDetail.fromJson(Map<String, Object?> json) {
    return SkillMarketDetail(
      skill: SkillMarketDetailSkill.fromJson(_readMap(json['skill'])),
      owner: SkillMarketOwner.fromJson(_readMap(json['owner'])),
      latestVersion: SkillMarketVersion.fromJsonOrNull(
        optionalStringKeyedMapFromValue(json['latestVersion']),
      ),
      securityReports: _readSecurityReports(json['securityReports']),
    );
  }

  final SkillMarketDetailSkill skill;
  final SkillMarketOwner owner;
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
    required this.tags,
    required this.updatedAt,
  });

  factory SkillMarketDetailSkill.fromJson(Map<String, Object?> json) {
    return SkillMarketDetailSkill(
      category: _readString(json['category']),
      createdAt: _readInt(json['createdAt']),
      displayName: _readString(json['displayName']),
      iconUrl: _readNullableString(json['iconUrl']),
      requiresApiKey: _readBool(json['requiresApiKey']),
      slug: _readString(json['slug']),
      source: _readString(json['source']),
      stats: SkillMarketStats.fromJson(_readMap(json['stats'])),
      summary: _readString(json['summary']),
      summaryZh: _readString(json['summary_zh']),
      tags: _readStringMap(json['tags']),
      updatedAt: _readInt(json['updatedAt']),
    );
  }

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
  final Map<String, String> tags;
  final int updatedAt;

  String get latestTag => tags['latest'] ?? '';
}

class SkillMarketOwner {
  const SkillMarketOwner({
    required this.displayName,
    required this.handle,
    required this.image,
  });

  factory SkillMarketOwner.fromJson(Map<String, Object?> json) {
    return SkillMarketOwner(
      displayName: _readString(json['displayName']),
      handle: _readString(json['handle']),
      image: _readNullableString(json['image']),
    );
  }

  final String displayName;
  final String handle;
  final String? image;
}

class SkillMarketStats {
  const SkillMarketStats({
    required this.comments,
    required this.downloads,
    required this.installs,
    required this.stars,
    required this.versions,
  });

  factory SkillMarketStats.fromJson(Map<String, Object?> json) {
    return SkillMarketStats(
      comments: _readInt(json['comments']),
      downloads: _readInt(json['downloads']),
      installs: _readInt(json['installs']),
      stars: _readInt(json['stars']),
      versions: _readInt(json['versions']),
    );
  }

  final int comments;
  final int downloads;
  final int installs;
  final int stars;
  final int versions;
}

class SkillMarketSecurityReport {
  const SkillMarketSecurityReport({
    required this.status,
    required this.statusText,
    required this.reportUrl,
  });

  factory SkillMarketSecurityReport.fromJson(Map<Object?, Object?> json) {
    return SkillMarketSecurityReport(
      status: _readString(json['status']),
      statusText: _readString(json['statusText']),
      reportUrl: _readString(json['reportUrl']),
    );
  }

  final String status;
  final String statusText;
  final String reportUrl;
}

class SkillMarketFilesResult {
  const SkillMarketFilesResult({
    required this.count,
    required this.files,
    required this.version,
  });

  factory SkillMarketFilesResult.fromJson(Map<String, Object?> json) {
    final rawFiles = json['files'];
    return SkillMarketFilesResult(
      count: _readInt(json['count']),
      files: stringKeyedMapListFromValue(
        rawFiles,
      ).map(SkillMarketFileEntry.fromJson).toList(growable: false),
      version: _readString(json['version']),
    );
  }

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

  factory SkillMarketFileEntry.fromJson(Map<Object?, Object?> json) {
    return SkillMarketFileEntry(
      path: _readString(json['path']),
      sha256: _readString(json['sha256']),
      size: _readInt(json['size']),
    );
  }

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

  factory SkillMarketVersionsResult.fromJson(Map<String, Object?> json) {
    final rawVersions = json['versions'];
    return SkillMarketVersionsResult(
      slug: _readString(json['slug']),
      source: _readString(json['source']),
      versions: stringKeyedMapListFromValue(
        rawVersions,
      ).map(SkillMarketVersion.fromJson).toList(growable: false),
    );
  }

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

  factory SkillMarketVersion.fromJson(Map<Object?, Object?> json) {
    return SkillMarketVersion(
      changelog: _readString(json['changelog']),
      createdAt: _readInt(json['createdAt']),
      version: _readString(json['version']),
      versionId: _readInt(json['versionId']),
      securityReports: _readSecurityReports(json['securityReports']),
    );
  }

  static SkillMarketVersion? fromJsonOrNull(Map<String, Object?>? json) {
    if (json == null) {
      return null;
    }
    return SkillMarketVersion.fromJson(json);
  }

  final String changelog;
  final int createdAt;
  final String version;
  final int versionId;
  final Map<String, SkillMarketSecurityReport> securityReports;
}

String _readString(Object? value) => _readNullableString(value) ?? '';

String? _readNullableString(Object? value) {
  return nullIfBlank(value == null ? null : '$value');
}

int _readInt(Object? value) {
  return nonNegativeRoundedIntFromValue(value, fallback: 0);
}

double _readDouble(Object? value) {
  return doubleFromValue(value, fallback: 0);
}

bool _readBool(Object? value) {
  return boolFromValue(value);
}

Map<String, String> _readStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return Map<String, String>.unmodifiable(
    value.map((key, value) => MapEntry('$key', _readString(value))),
  );
}

Map<String, Object?> _readMap(Object? value) {
  final map = optionalStringKeyedMapFromValue(value);
  if (map == null) {
    return const <String, Object?>{};
  }
  return map;
}

Map<String, SkillMarketSecurityReport> _readSecurityReports(Object? value) {
  final reports = <String, SkillMarketSecurityReport>{};
  final rawReports = stringKeyedMapFromValue(value);
  for (final entry in rawReports.entries) {
    final report = stringKeyedMapFromValue(entry.value);
    if (report.isEmpty) continue;
    reports[entry.key] = SkillMarketSecurityReport.fromJson(report);
  }
  return Map<String, SkillMarketSecurityReport>.unmodifiable(reports);
}
