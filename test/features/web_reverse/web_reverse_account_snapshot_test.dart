import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

void main() {
  test(
    'fromJson normalizes dirty snapshot rows without trimming storage values',
    () {
      final snapshot = WebReverseAccountSnapshot.fromJson(<String, Object?>{
        'id': ' snap-1 ',
        'name': ' account A ',
        'origin': ' https://example.test ',
        'captured_ms': '1700000000000.0',
        'cookies': <Object?>[
          <Object?, Object?>{'name': 'sid', 'value': 'abc'},
          'noise',
        ],
        'localStorage': <Object?, Object?>{
          42: true,
          'token': '  keep whitespace  ',
        },
        'sessionStorage': <Object?, Object?>{'empty': null},
      });

      expect(snapshot.id, 'snap-1');
      expect(snapshot.name, 'account A');
      expect(snapshot.origin, 'https://example.test');
      expect(
        snapshot.capturedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(snapshot.cookies, <Map<String, Object?>>[
        <String, Object?>{'name': 'sid', 'value': 'abc'},
      ]);
      expect(snapshot.localStorage, <String, String>{
        '42': 'true',
        'token': '  keep whitespace  ',
      });
      expect(snapshot.sessionStorage, <String, String>{'empty': ''});
    },
  );

  test('fromJson falls back for invalid snapshot timestamps', () {
    final before = DateTime.now();
    final snapshot = WebReverseAccountSnapshot.fromJson(<String, Object?>{
      'captured_ms': double.nan,
    });
    final after = DateTime.now();

    expect(snapshot.capturedAt.isBefore(before), isFalse);
    expect(snapshot.capturedAt.isAfter(after), isFalse);
  });
}
