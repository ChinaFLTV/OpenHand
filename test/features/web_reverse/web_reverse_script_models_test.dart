import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

void main() {
  test('snippet and hook parsing normalize metadata without trimming code', () {
    final snippet = WebReverseSnippet.fromJson(<String, Object?>{
      'id': ' snip-1 ',
      'name': '  ',
      'code': '  console.log(1);  ',
      'updated_ms': '1700000000000.0',
    });
    final hook = WebReverseHook.fromJson(<String, Object?>{
      'id': ' hook-1 ',
      'name': ' Hook ',
      'code': '\nwindow.__x = true;\n',
      'enabled': 'off',
      'updated_ms': double.nan,
    });

    expect(snippet.id, 'snip-1');
    expect(snippet.name, 'untitled');
    expect(snippet.code, '  console.log(1);  ');
    expect(
      snippet.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(hook.id, 'hook-1');
    expect(hook.name, 'Hook');
    expect(hook.code, '\nwindow.__x = true;\n');
    expect(hook.enabled, isFalse);
    expect(hook.updatedAt, isNull);
  });

  test(
    'cron parsing rejects unsafe intervals while accepting loose booleans',
    () {
      final cron = WebReverseCron.fromJson(<String, Object?>{
        'id': ' cron-1 ',
        'name': ' Cron ',
        'code': ' run(); ',
        'interval_s': '1.5',
        'enabled': 'yes',
        'updated_ms': '1700000000000',
      });

      expect(cron.id, 'cron-1');
      expect(cron.intervalSeconds, 60);
      expect(cron.enabled, isTrue);
      expect(cron.code, ' run(); ');
      expect(
        cron.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    },
  );

  test('request breakpoint parsing preserves eval expression text', () {
    final breakpoint = WebReverseRequestBreakpoint.fromJson(<String, Object?>{
      'id': ' bp-1 ',
      'name': ' Breakpoint ',
      'enabled': 'disabled',
      'method': ' post ',
      'url_contains': ' /api ',
      'body_contains': ' token ',
      'eval': '  console.log(request);  ',
    });

    expect(breakpoint.id, 'bp-1');
    expect(breakpoint.name, 'Breakpoint');
    expect(breakpoint.enabled, isFalse);
    expect(breakpoint.methodFilter, 'post');
    expect(breakpoint.urlContains, '/api');
    expect(breakpoint.bodyContains, 'token');
    expect(breakpoint.evalExpression, '  console.log(request);  ');
  });
}
