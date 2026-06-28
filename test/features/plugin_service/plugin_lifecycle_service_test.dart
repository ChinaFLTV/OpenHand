import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/service/plugin_lifecycle_service.dart';

void main() {
  test('homebrew stable version parser normalizes loose formula maps', () {
    final version = homebrewStableVersionFromDecoded(<Object?, Object?>{
      'formulae': <Object?>[
        <Object?, Object?>{
          'name': 'python',
          'versions': <Object?, Object?>{'stable': ' 3.13.5 '},
        },
      ],
    });

    expect(version, '3.13.5');
  });

  test('homebrew stable version parser rejects malformed roots', () {
    expect(homebrewStableVersionFromDecoded(null), isNull);
    expect(homebrewStableVersionFromDecoded(<Object?>[]), isNull);
    expect(
      homebrewStableVersionFromDecoded(<String, Object?>{
        'formulae': <Object?>[
          <String, Object?>{
            'versions': <String, Object?>{'stable': '   '},
          },
        ],
      }),
      isNull,
    );
  });
}
