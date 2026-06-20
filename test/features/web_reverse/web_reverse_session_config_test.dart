import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_browser_kind.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_config.dart';

void main() {
  group('WebReverseSessionConfig', () {
    test('request template makes CDP-first capture explicit', () {
      const config = WebReverseSessionConfig(
        targetUrl: 'https://linux.do/t/topic/2401043/5',
        objective: '抓取帖子评论',
        cdpPort: 9223,
        userDataDir: '/tmp/openhand-web-reverse',
        browserKind: WebReverseBrowserKind.chrome,
        keywords: <String>['post_stream'],
      );

      final template = config.toRequestTemplate();

      expect(template, contains('- 关键字：【post_stream】'));
      expect(template, isNot(contains('关键关键字')));
      expect(template, contains('先用 CDP MCP / 本地 jsonl/HAR'));
      expect(template, contains('禁止 WebFetch/WebSearch/Bash/curl 直接抓目标源'));
      expect(template, contains('可在 curl / Dart / Python 中独立复现'));
    });
  });
}
