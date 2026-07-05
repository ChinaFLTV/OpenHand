import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/skills/model/skill_market.dart';

void main() {
  group('SkillMarketStats', () {
    test('normalizes malformed numeric counters safely', () {
      final stats = SkillMarketStats.fromJson(<String, Object?>{
        'comments': -2,
        'downloads': '12.6',
        'installs': double.nan,
        'stars': 4.4,
        'versions': 'bad',
      });

      expect(stats.comments, 0);
      expect(stats.downloads, 13);
      expect(stats.installs, 0);
      expect(stats.stars, 4);
      expect(stats.versions, 0);
    });
  });

  group('SkillMarketFileEntry', () {
    test('does not keep negative file sizes from market payloads', () {
      final entry = SkillMarketFileEntry.fromJson(<String, Object?>{
        'path': 'skill.md',
        'sha256': 'abc',
        'size': -100,
      });

      expect(entry.size, 0);
    });
  });
}
