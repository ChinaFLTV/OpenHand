// 浏览器枚举的稳态字段验证 + fromId 的边界。
// 核心目标：避免误改了 enum 的字段名（id / displayName 都被 metadata
// 序列化用），导致旧会话恢复时拿不到对应 kind 而退化到 chrome。

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_browser_kind.dart';

void main() {
  test('每个 kind 都有非空 id / displayName / macBundleId / macAppPath', () {
    for (final k in WebReverseBrowserKind.values) {
      expect(k.id, isNotEmpty, reason: 'kind ${k.name} 缺 id');
      expect(k.displayName, isNotEmpty, reason: 'kind ${k.name} 缺 displayName');
      expect(k.macBundleId, isNotEmpty, reason: 'kind ${k.name} 缺 bundle id');
      expect(k.macAppPath, contains('/Applications/'),
          reason: 'kind ${k.name} 默认安装路径异常');
    }
  });

  test('id 全局唯一', () {
    final ids = WebReverseBrowserKind.values.map((k) => k.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'id 出现重复');
  });

  test('fromId 命中已知值，未知输入返回 null', () {
    expect(WebReverseBrowserKind.fromId('chrome'), WebReverseBrowserKind.chrome);
    expect(WebReverseBrowserKind.fromId('edge'), WebReverseBrowserKind.edge);
    expect(WebReverseBrowserKind.fromId(''), isNull);
    expect(WebReverseBrowserKind.fromId(null), isNull);
    expect(WebReverseBrowserKind.fromId('unknown'), isNull);
  });

  test('cliCandidates / windowsExecutableCandidates 非空（至少 chrome）', () {
    expect(WebReverseBrowserKind.chrome.cliCandidates, isNotEmpty);
    expect(WebReverseBrowserKind.chrome.windowsExecutableCandidates, isNotEmpty);
    expect(
      WebReverseBrowserKind.chrome.windowsExecutableCandidates.first,
      contains('chrome.exe'),
    );
  });
}
