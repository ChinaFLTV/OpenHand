import 'dart:typed_data';

import '../../../shared/market/market_provider.dart';
import 'skill_market.dart';

abstract interface class SkillMarketProvider implements MarketProvider {
  static const defaultPageSize = 24;
  static const maxPageSize = 200;
  void clearSearchCache();
  Future<SkillMarketSearchResult> searchSkills({
    required String keyword,
    required int page,
    int pageSize = defaultPageSize,
  });
  Future<SkillMarketBundle> loadSkillBundle(String slug, {String? version});
  Future<String> fetchSkillFileContent({
    required String slug,
    required String path,
    required String version,
  });
  Future<Uint8List> downloadSkillArchive(String slug);
}

class SkillMarketException implements Exception {
  const SkillMarketException(this.message);
  final String message;
  @override
  String toString() => message;
}
