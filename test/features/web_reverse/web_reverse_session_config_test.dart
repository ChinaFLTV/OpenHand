import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_browser_kind.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_config.dart';

void main() {
  test('fromJson normalizes persisted scalar and list fields', () {
    final config = WebReverseSessionConfig.fromJson(<String, Object?>{
      'target_url': ' https://example.test ',
      'objective': '  find token flow ',
      'cdp_port': '9222',
      'user_data_dir': ' /tmp/openhand ',
      'browser_kind': 'chromium',
      'trigger_actions': 123,
      'login_mode': 'manual',
      'proxy': ' http://127.0.0.1:7890 ',
      'keywords': <Object?>[' alpha ', null, 42, '', ' beta '],
      'har_path': '   ',
      'cdp_mcp_enabled': 'yes',
    });

    expect(config, isNotNull);
    expect(config!.targetUrl, 'https://example.test');
    expect(config.objective, 'find token flow');
    expect(config.cdpPort, 9222);
    expect(config.userDataDir, '/tmp/openhand');
    expect(config.browserKind, WebReverseBrowserKind.chromium);
    expect(config.triggerActions, '123');
    expect(config.loginMode, WebReverseLoginMode.manual);
    expect(config.proxy, 'http://127.0.0.1:7890');
    expect(config.keywords, <String>['alpha', '42', 'beta']);
    expect(config.harPath, isNull);
    expect(config.cdpMcpEnabled, isTrue);
  });

  test('fromJson rejects unsafe CDP ports without throwing', () {
    expect(
      WebReverseSessionConfig.fromJson(<String, Object?>{
        'target_url': 'https://example.test',
        'cdp_port': double.infinity,
        'browser_kind': 'chromium',
      }),
      isNull,
    );
    expect(
      WebReverseSessionConfig.fromJson(<String, Object?>{
        'target_url': 'https://example.test',
        'cdp_port': '9222.5',
        'browser_kind': 'chromium',
      }),
      isNull,
    );
  });

  test('fromJson normalizes loose map keys without throwing', () {
    final config = WebReverseSessionConfig.fromJson(<Object?, Object?>{
      'target_url': 'https://example.test',
      'cdp_port': '9222',
      'browser_kind': 'chromium',
      42: 'ignored',
      'trigger_actions': '  click login  ',
    });

    expect(config, isNotNull);
    expect(config!.targetUrl, 'https://example.test');
    expect(config.cdpPort, 9222);
    expect(config.triggerActions, 'click login');
  });
}
