// WebReverseSessionConfig 的序列化往返测试 + request_template 输出。

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_browser_kind.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_config.dart';

void main() {
  test('toJson / fromJson 往返一致', () {
    const original = WebReverseSessionConfig(
      targetUrl: 'https://example.com/page',
      objective: '复现 sign 字段',
      cdpPort: 9224,
      userDataDir: '/tmp/oh-profile',
      browserKind: WebReverseBrowserKind.edge,
      triggerActions: '点击下载',
      loginMode: WebReverseLoginMode.manual,
      proxy: 'http://127.0.0.1:7890',
      keywords: ['sign', 'token'],
      harPath: '/tmp/x.har',
    );
    final json = original.toJson();
    final restored = WebReverseSessionConfig.fromJson(json);
    expect(restored, isNotNull);
    expect(restored!.targetUrl, original.targetUrl);
    expect(restored.objective, original.objective);
    expect(restored.cdpPort, original.cdpPort);
    expect(restored.userDataDir, original.userDataDir);
    expect(restored.browserKind, original.browserKind);
    expect(restored.triggerActions, original.triggerActions);
    expect(restored.loginMode, original.loginMode);
    expect(restored.proxy, original.proxy);
    expect(restored.keywords, original.keywords);
    expect(restored.harPath, original.harPath);
  });

  test('fromJson 容错：缺字段返回 null', () {
    expect(WebReverseSessionConfig.fromJson(null), isNull);
    expect(WebReverseSessionConfig.fromJson(<String, Object?>{}), isNull);
    expect(
      WebReverseSessionConfig.fromJson(<String, Object?>{
        'target_url': 'https://x',
        // 缺 cdp_port / browser_kind
      }),
      isNull,
    );
  });

  test('toRequestTemplate 含全部关键字段', () {
    const cfg = WebReverseSessionConfig(
      targetUrl: 'https://example.com',
      objective: '复现下载',
      cdpPort: 9222,
      userDataDir: '/p',
      browserKind: WebReverseBrowserKind.chrome,
      keywords: ['sign'],
    );
    final tpl = cfg.toRequestTemplate();
    expect(tpl, contains('<request_template>'));
    expect(tpl, contains('https://example.com'));
    expect(tpl, contains('复现下载'));
    expect(tpl, contains('9222'));
    expect(tpl, contains('Google Chrome'));
    expect(tpl, contains('sign'));
    expect(tpl, contains('</request_template>'));
  });

  test('WebReverseLoginMode.fromId 命中并兜底 none', () {
    expect(WebReverseLoginMode.fromId('manual'), WebReverseLoginMode.manual);
    expect(
      WebReverseLoginMode.fromId('storage_state'),
      WebReverseLoginMode.storageState,
    );
    expect(WebReverseLoginMode.fromId(''), WebReverseLoginMode.none);
    expect(WebReverseLoginMode.fromId('?'), WebReverseLoginMode.none);
  });
}
