import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

void main() {
  test('fromJson normalizes dirty persisted mock rule fields', () {
    final rule = WebReverseMockRule.fromJson(<String, Object?>{
      'id': ' rule-1 ',
      'name': ' API mock ',
      'urlPattern': ' https://api.example.test/* ',
      'enabled': 'off',
      'method': ' post ',
      'status': '999',
      'contentType': '  ',
      'body': null,
      'headers': <Object?, Object?>{
        ' X-Test ': ' value ',
        '': 'drop',
        42: true,
      },
    });

    expect(rule.id, 'rule-1');
    expect(rule.name, 'API mock');
    expect(rule.urlPattern, 'https://api.example.test/*');
    expect(rule.enabled, isFalse);
    expect(rule.methodFilter, 'post');
    expect(rule.statusCode, 599);
    expect(rule.contentType, 'application/json; charset=utf-8');
    expect(rule.body, isEmpty);
    expect(rule.extraHeaders, <String, String>{
      'X-Test': 'value',
      '42': 'true',
    });
  });

  test('fromJson clamps invalid status codes to safe fallbacks', () {
    expect(
      WebReverseMockRule.fromJson(<String, Object?>{'status': '42'}).statusCode,
      100,
    );
    expect(
      WebReverseMockRule.fromJson(<String, Object?>{
        'status': double.nan,
      }).statusCode,
      200,
    );
  });
}
