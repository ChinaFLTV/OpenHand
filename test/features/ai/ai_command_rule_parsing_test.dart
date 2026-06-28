import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('allow command rule parses JSON text and trims scalar fields', () {
    final rule = AiAllowCommandRule.fromJson('''
      {
        "id": " allow-1 ",
        "pattern": " git status* ",
        "match_mode": "simple",
        "note": " developer workflow "
      }
    ''');

    expect(rule.id, 'allow-1');
    expect(rule.pattern, 'git status*');
    expect(rule.matchMode, AiDenyCommandMatchMode.simple);
    expect(rule.note, 'developer workflow');
    expect(rule.matches('git status --short'), isTrue);
    expect(rule.matches('git diff'), isFalse);
  });

  test('deny command rule parses loose map keys and regex mode', () {
    final rule = AiDenyCommandRule.fromJson(<Object?, Object?>{
      1: 'ignored',
      'id': 42,
      'pattern': r'\brm\s+-rf\b',
      'match_mode': 'regex',
      'note': ' destructive ',
    });

    expect(rule.id, '42');
    expect(rule.pattern, r'\brm\s+-rf\b');
    expect(rule.matchMode, AiDenyCommandMatchMode.regex);
    expect(rule.note, 'destructive');
    expect(rule.matches('sudo rm -rf /tmp/demo'), isTrue);
    expect(rule.matches('rm -r /tmp/demo'), isFalse);
  });

  test('invalid regex rules fail closed without throwing', () {
    final rule = AiDenyCommandRule.fromJson(<String, Object?>{
      'pattern': '[',
      'match_mode': 'regex',
    });

    expect(rule.matches('anything'), isFalse);
  });
}
