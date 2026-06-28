import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/skills/model/skill_market.dart';

void main() {
  test('search result parser normalizes dirty skill rows', () {
    final result = SkillMarketSearchResult.fromJson(
      <String, Object?>{
        'data': <Object?, Object?>{
          'total': '7',
          'skills': <Object?>[
            <Object?, Object?>{
              'slug': 'skill-a',
              'name': ' Skill A ',
              'score': double.infinity,
              'requires_api_key': 'yes',
              'downloads': double.nan,
              'stars': '12',
              'tags': 'coding, ai',
            },
            'noise',
          ],
        },
      },
      page: 2,
      pageSize: 3,
    );

    expect(result.total, 7);
    expect(result.totalPages, 3);
    expect(result.skills, hasLength(1));
    expect(result.skills.single.slug, 'skill-a');
    expect(result.skills.single.displayName, 'Skill A');
    expect(result.skills.single.score, 0);
    expect(result.skills.single.downloads, 0);
    expect(result.skills.single.stars, 12);
    expect(result.skills.single.requiresApiKey, isTrue);
    expect(result.skills.single.tags, <String>['coding', 'ai']);
  });

  test('files and versions parsers skip malformed rows safely', () {
    final files = SkillMarketFilesResult.fromJson(<String, Object?>{
      'count': '2',
      'version': '1.0.0',
      'files': <Object?>[
        <Object?, Object?>{'path': 'skill.md', 'sha256': 'abc', 'size': '42'},
        null,
      ],
    });
    expect(files.files, hasLength(1));
    expect(files.files.single.path, 'skill.md');
    expect(files.files.single.size, 42);

    final versions = SkillMarketVersionsResult.fromJson(<String, Object?>{
      'slug': 'skill-a',
      'source': 'market',
      'versions': <Object?>[
        <Object?, Object?>{
          'version': '1.0.0',
          'versionId': '5',
          'securityReports': <Object?, Object?>{
            'scan': <Object?, Object?>{
              'status': 'passed',
              'statusText': 'OK',
              'reportUrl': 'https://example.test/report',
            },
            'bad': 'noise',
          },
        },
      ],
    });

    expect(versions.versions, hasLength(1));
    final version = versions.versions.single;
    expect(version.versionId, 5);
    expect(version.securityReports.keys, <String>['scan']);
    expect(version.securityReports['scan']!.status, 'passed');
  });
}
