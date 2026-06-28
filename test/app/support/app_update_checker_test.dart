import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_update_checker.dart';

void main() {
  test('parseGitHubReleaseInfo normalizes dirty release payloads', () {
    final release = parseGitHubReleaseInfo(<Object?, Object?>{
      'tag_name': ' v1.2.3 ',
      'name': ' OpenHand 1.2.3 ',
      'body': '  notes  ',
      'published_at': '2026-06-28T08:00:00Z',
      'prerelease': 'yes',
      'assets': <Object?>[
        <Object?, Object?>{
          'name': 'OpenHand-linux.AppImage',
          'browser_download_url': ' https://example.test/linux ',
          'size': '42',
        },
        <Object?, Object?>{
          'name': 'OpenHand-macos.dmg',
          'browser_download_url': ' https://example.test/macos ',
          'size': double.nan,
        },
        'noise',
      ],
    }, platformAssetSuffix: 'macos');

    expect(release, isNotNull);
    expect(release!.version, '1.2.3');
    expect(release.tagName, 'v1.2.3');
    expect(release.releaseName, 'OpenHand 1.2.3');
    expect(release.releaseNotes, 'notes');
    expect(release.publishedAt.toUtc(), DateTime.utc(2026, 6, 28, 8));
    expect(release.isPreRelease, isTrue);
    expect(release.downloadUrl, 'https://example.test/macos');
    expect(release.downloadSize, 0);
  });

  test(
    'parseGitHubReleaseInfo falls back to first asset and rejects bad roots',
    () {
      expect(parseGitHubReleaseInfo(<String, Object?>{}), isNull);
      expect(parseGitHubReleaseInfo(<Object?>[]), isNull);

      final release = parseGitHubReleaseInfo(<String, Object?>{
        'tag_name': 'v2.0.0',
        'assets': <Object?>[
          <Object?, Object?>{
            'name': 'OpenHand.zip',
            'browser_download_url': 'https://example.test/app.zip',
            'size': -1,
          },
        ],
      });

      expect(release, isNotNull);
      expect(release!.downloadUrl, 'https://example.test/app.zip');
      expect(release.downloadSize, 0);
    },
  );
}
