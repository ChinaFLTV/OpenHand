import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/skills/data/skill_market_client.dart';

void main() {
  group('SkillMarketClient', () {
    test('searchSkills parses results and caches identical pages', () async {
      var requestCount = 0;
      final client = SkillMarketClient(
        httpClient: MockClient((request) async {
          requestCount++;
          expect(request.url.host, 'api.skillhub.cn');
          expect(request.url.path, '/api/skills');
          expect(request.url.queryParameters['page'], '1');
          expect(request.url.queryParameters['pageSize'], '24');
          expect(request.url.queryParameters['sortBy'], 'score');
          expect(request.url.queryParameters['order'], 'desc');
          expect(request.url.queryParameters['keyword'], 'pdf');
          return _jsonResponse(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'skills': <Object?>[
                <String, Object?>{
                  'category': 'ai-intelligence',
                  'description': 'Extract text from PDF files',
                  'description_zh': '从PDF文件中提取文本',
                  'downloads': 24970,
                  'homepage': 'https://api.skillhub.cn/xejrax/pdf-extract',
                  'iconUrl': null,
                  'installs': 8590,
                  'name': 'Pdf Extract',
                  'ownerName': 'xejrax',
                  'requires_api_key': false,
                  'score': 61582.3,
                  'slug': 'pdf-extract',
                  'source': 'clawhub',
                  'stars': 14,
                  'tags': null,
                  'version': '1.0.0',
                },
              ],
              'total': 616,
            },
            'message': 'success',
          });
        }),
      );
      addTearDown(client.close);

      final first = await client.searchSkills(keyword: ' pdf ', page: 1);
      final second = await client.searchSkills(keyword: 'pdf', page: 1);

      expect(requestCount, 1);
      expect(identical(first, second), isTrue);
      expect(first.total, 616);
      expect(first.totalPages, 26);
      expect(first.skills.single.slug, 'pdf-extract');
      expect(first.skills.single.descriptionZh, '从PDF文件中提取文本');
    });

    test(
      'loadSkillBundle fetches detail, versions, files and SKILL.md once',
      () async {
        final requestCounts = <String, int>{};
        final client = SkillMarketClient(
          httpClient: MockClient((request) async {
            requestCounts.update(
              request.url.path,
              (value) => value + 1,
              ifAbsent: () => 1,
            );
            switch (request.url.path) {
              case '/api/v1/skills/pdf-extract':
                return _jsonResponse(<String, Object?>{
                  'latestVersion': <String, Object?>{
                    'changelog': 'Synced by skillhub pipeline',
                    'createdAt': 1774625037186,
                    'version': '1.0.0',
                  },
                  'owner': <String, Object?>{
                    'displayName': 'xejrax',
                    'handle': 'xejrax',
                    'image': null,
                  },
                  'securityReports': <String, Object?>{
                    'keen': <String, Object?>{
                      'status': 'benign',
                      'statusText': '安全，无风险',
                      'reportUrl': 'https://example.com/report',
                    },
                  },
                  'skill': <String, Object?>{
                    'category': 'ai-intelligence',
                    'createdAt': 1772740045955,
                    'displayName': 'Pdf Extract',
                    'iconUrl': null,
                    'requiresApiKey': false,
                    'slug': 'pdf-extract',
                    'source': 'clawhub',
                    'stats': <String, Object?>{
                      'comments': 0,
                      'downloads': 24973,
                      'installs': 8592,
                      'stars': 14,
                      'versions': 1,
                    },
                    'summary': 'Extract text from PDF files for LLM processing',
                    'summary_zh': '从PDF文件中提取文本供大模型处理',
                    'tags': <String, Object?>{'latest': '1.0.0'},
                    'updatedAt': 1777193299536,
                  },
                });
              case '/api/v1/skills/pdf-extract/versions':
                return _jsonResponse(<String, Object?>{
                  'slug': 'pdf-extract',
                  'source': 'clawhub',
                  'versions': <Object?>[
                    <String, Object?>{
                      'changelog': 'Synced by skillhub pipeline',
                      'createdAt': 1774625037186,
                      'version': '1.0.0',
                      'versionId': 229,
                    },
                    <String, Object?>{
                      'changelog': 'Previous release',
                      'createdAt': 1773625037186,
                      'version': '0.9.0',
                      'versionId': 198,
                    },
                  ],
                });
              case '/api/v1/skills/pdf-extract/files':
                final version = request.url.queryParameters['version'];
                expect(<String>['1.0.0', '0.9.0'], contains(version));
                return _jsonResponse(<String, Object?>{
                  'count': 2,
                  'files': <Object?>[
                    <String, Object?>{
                      'path': 'SKILL.md',
                      'sha256': 'abc',
                      'size': 42,
                    },
                  ],
                  'version': version,
                });
              case '/api/v1/skills/pdf-extract/file':
                expect(request.url.queryParameters['path'], 'SKILL.md');
                final version = request.url.queryParameters['version'];
                expect(<String>['1.0.0', '0.9.0'], contains(version));
                return http.Response('# Pdf Extract $version\n\nUse it.', 200);
            }
            return http.Response('missing', 404);
          }),
        );
        addTearDown(client.close);

        final first = await client.loadSkillBundle('pdf-extract');
        final second = await client.loadSkillBundle('pdf-extract');

        expect(identical(first, second), isTrue);
        expect(first.resolvedVersion, '1.0.0');
        expect(first.detail.skill.summaryZh, '从PDF文件中提取文本供大模型处理');
        expect(first.files!.files.single.path, 'SKILL.md');
        expect(first.skillMarkdown, contains('Pdf Extract'));
        expect(requestCounts['/api/v1/skills/pdf-extract'], 1);
        expect(requestCounts['/api/v1/skills/pdf-extract/versions'], 1);
        expect(requestCounts['/api/v1/skills/pdf-extract/files'], 1);
        expect(requestCounts['/api/v1/skills/pdf-extract/file'], 1);

        final historical = await client.loadSkillBundle(
          'pdf-extract',
          version: '0.9.0',
        );
        final historicalAgain = await client.loadSkillBundle(
          'pdf-extract',
          version: '0.9.0',
        );

        expect(identical(historical, historicalAgain), isTrue);
        expect(historical.resolvedVersion, '0.9.0');
        expect(historical.skillMarkdown, contains('0.9.0'));
        expect(requestCounts['/api/v1/skills/pdf-extract'], 1);
        expect(requestCounts['/api/v1/skills/pdf-extract/versions'], 1);
        expect(requestCounts['/api/v1/skills/pdf-extract/files'], 2);
        expect(requestCounts['/api/v1/skills/pdf-extract/file'], 2);
      },
    );
  });
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}
