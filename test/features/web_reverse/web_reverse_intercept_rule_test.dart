import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

void main() {
  test('fromJson normalizes dirty persisted intercept rule fields', () {
    final rule = WebReverseInterceptRule.fromJson(<String, Object?>{
      'urlPattern': ' https://api.example.test/* ',
      'enabled': 'no',
      'block': 'enabled',
      'replaceUrl': '   ',
      'headerOverrides': <Object?, Object?>{
        ' X-Debug ': ' 1 ',
        '': 'drop',
        42: true,
      },
    });

    expect(rule.urlPattern, 'https://api.example.test/*');
    expect(rule.enabled, isFalse);
    expect(rule.block, isTrue);
    expect(rule.replaceUrl, isNull);
    expect(rule.headerOverrides, <String, String>{
      'X-Debug': '1',
      '42': 'true',
    });
    expect(rule.matches('https://api.example.test/v1/users'), isTrue);
  });

  test('fromJson keeps safe defaults for malformed intercept rule fields', () {
    final rule = WebReverseInterceptRule.fromJson(<String, Object?>{
      'enabled': double.nan,
      'block': 2,
      'headerOverrides': 'bad',
    });

    expect(rule.enabled, isTrue);
    expect(rule.block, isFalse);
    expect(rule.headerOverrides, isEmpty);
    expect(rule.matches('https://api.example.test'), isFalse);
  });
}
