import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_video_player_web_styles.dart';

void main() {
  test('macOS 视频 WebView 跳过未实现的背景接口', () {
    expect(openHandCanSetWebViewBackgroundColor(TargetPlatform.macOS), isFalse);
  });

  test('其他支持平台保留视频 WebView 背景设置', () {
    for (final platform in <TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    }) {
      expect(openHandCanSetWebViewBackgroundColor(platform), isTrue);
    }
  });
}
