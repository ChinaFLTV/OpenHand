import '../../../shared/util/input_value_parsing.dart';
import '../model/skill_market.dart';

abstract final class SkillHubSkillMapper {
  static SkillMarketSearchResult skillMarketSearchResult(
    Map<String, Object?> json, {
    required int page,
    required int pageSize,
  }) {
    final data = json['data'];
    if (data is! Map) {
      throw const FormatException('技能市场搜索数据格式不正确。');
    }
    final dataMap = stringKeyedMapFromValue(data);
    final skills = stringKeyedMapListFromValue(
      dataMap['skills'],
    ).map(SkillHubSkillMapper.skillMarketSummary).toList(growable: false);
    return SkillMarketSearchResult(
      skills: skills,
      total: _readInt(dataMap['total']),
      page: page,
      pageSize: pageSize,
    );
  }

  static SkillMarketSummary skillMarketSummary(Map<Object?, Object?> json) {
    return SkillMarketSummary(
      category: _readString(json['category']),
      createdAt: _readInt(json['created_at']),
      description: _readString(json['description']),
      descriptionZh: _readString(json['description_zh']),
      downloads: _readInt(json['downloads']),
      iconUrl: _readNullableString(json['iconUrl']),
      installs: _readInt(json['installs']),
      name: _readString(json['name']),
      ownerName: _readString(json['ownerName']),
      publisherName: _readPublisherName(json['publisher']),
      requiresApiKey: _readRequiresApiKey(json),
      score: _readDouble(json['score']),
      slug: _readString(json['slug']),
      source: _readString(json['source']),
      stars: _readInt(json['stars']),
      subCategories: _readSubCategories(json['subCategories']),
      tags: stringListFromValue(json['tags']),
      updatedAt: _readInt(json['updated_at']),
      version: _readString(json['version']),
    );
  }

  static SkillMarketDetail skillMarketDetail(Map<String, Object?> json) {
    return SkillMarketDetail(
      skill: SkillHubSkillMapper.skillMarketDetailSkill(
        _readMap(json['skill']),
      ),
      owner: SkillHubSkillMapper.skillMarketOwner(_readMap(json['owner'])),
      publisherName: _readPublisherName(json['publisher']),
      latestVersion: SkillHubSkillMapper.skillMarketVersionOrNull(
        optionalStringKeyedMapFromValue(json['latestVersion']),
      ),
      securityReports: _readSecurityReports(json['securityReports']),
    );
  }

  static SkillMarketDetailSkill skillMarketDetailSkill(
    Map<String, Object?> json,
  ) {
    return SkillMarketDetailSkill(
      category: _readString(json['category']),
      createdAt: _readInt(json['createdAt']),
      displayName: _readString(json['displayName']),
      iconUrl: _readNullableString(json['iconUrl']),
      requiresApiKey: _readRequiresApiKey(json),
      slug: _readString(json['slug']),
      source: _readString(json['source']),
      stats: SkillHubSkillMapper.skillMarketStats(_readMap(json['stats'])),
      summary: _readString(json['summary']),
      summaryZh: _readString(json['summary_zh']),
      subCategories: _readSubCategories(json['subCategories']),
      tags: _readStringMap(json['tags']),
      updatedAt: _readInt(json['updatedAt']),
    );
  }

  static SkillMarketSubCategory skillMarketSubCategory(
    Map<Object?, Object?> json,
  ) {
    return SkillMarketSubCategory(
      key: _readString(json['key']),
      name: _readString(json['name']),
    );
  }

  static SkillMarketOwner skillMarketOwner(Map<String, Object?> json) {
    return SkillMarketOwner(
      displayName: _readString(json['displayName']),
      handle: _readString(json['handle']),
      image: _readNullableString(json['image']),
    );
  }

  static SkillMarketStats skillMarketStats(Map<String, Object?> json) {
    return SkillMarketStats(
      downloads: _readInt(json['downloads']),
      installs: _readInt(json['installs']),
      stars: _readInt(json['stars']),
      versions: _readInt(json['versions']),
    );
  }

  static SkillMarketSecurityReport skillMarketSecurityReport(
    Map<Object?, Object?> json,
  ) {
    return SkillMarketSecurityReport(
      status: _readString(json['status']),
      statusText: _readString(json['statusText']),
    );
  }

  static SkillMarketFilesResult skillMarketFilesResult(
    Map<String, Object?> json,
  ) {
    final rawFiles = json['files'];
    return SkillMarketFilesResult(
      count: _readInt(json['count']),
      files: stringKeyedMapListFromValue(
        rawFiles,
      ).map(SkillHubSkillMapper.skillMarketFileEntry).toList(growable: false),
      version: _readString(json['version']),
    );
  }

  static SkillMarketFileEntry skillMarketFileEntry(Map<Object?, Object?> json) {
    return SkillMarketFileEntry(
      path: _readString(json['path']),
      sha256: _readString(json['sha256']),
      size: _readInt(json['size']),
    );
  }

  static SkillMarketVersionsResult skillMarketVersionsResult(
    Map<String, Object?> json,
  ) {
    final rawVersions = json['versions'];
    return SkillMarketVersionsResult(
      slug: _readString(json['slug']),
      source: _readString(json['source']),
      versions: stringKeyedMapListFromValue(
        rawVersions,
      ).map(SkillHubSkillMapper.skillMarketVersion).toList(growable: false),
    );
  }

  static SkillMarketVersion skillMarketVersion(Map<Object?, Object?> json) {
    return SkillMarketVersion(
      changelog: _readString(json['changelog']),
      createdAt: _readInt(json['createdAt']),
      version: _readString(json['version']),
      versionId: _readInt(json['versionId']),
      securityReports: _readSecurityReports(json['securityReports']),
    );
  }

  static SkillMarketVersion? skillMarketVersionOrNull(
    Map<String, Object?>? json,
  ) {
    if (json == null) {
      return null;
    }
    return SkillHubSkillMapper.skillMarketVersion(json);
  }
}

String _readPublisherName(Object? value) {
  return _readString(_readMap(value)['name']);
}

bool _readRequiresApiKey(Map json) {
  if (boolFromValue(json['requires_api_key']) ||
      boolFromValue(json['requiresApiKey'])) {
    return true;
  }
  final labels = json['labels'];
  if (labels is! Map) {
    return false;
  }
  return boolFromValue(labels['requires_api_key'] ?? labels['requiresApiKey']);
}

List<SkillMarketSubCategory> _readSubCategories(Object? value) {
  return stringKeyedMapListFromValue(value)
      .map(SkillHubSkillMapper.skillMarketSubCategory)
      .where((item) => item.key.isNotEmpty || item.name.isNotEmpty)
      .toList(growable: false);
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
    reports[entry.key] = SkillHubSkillMapper.skillMarketSecurityReport(report);
  }
  return Map<String, SkillMarketSecurityReport>.unmodifiable(reports);
}
