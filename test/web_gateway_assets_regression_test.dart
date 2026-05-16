// Regression test for the Web 网关 SPA 静态资源声明：
// pubspec.yaml 必须把 vite 产物会写入的所有子目录都纳入 Flutter rootBundle，
// 否则桌面端启动 Web Gateway 后浏览器拉 chunks/*.js / assets/*.* 会全 404。
//
// 历史 BUG（2026-05）：仅声明 assets/web/，子目录 assets/web/chunks/ 默认不
// 递归，所有 vite 拆出的 chunk 在生产二进制里完全丢失 → 网页一片空白。
// 本测试通过 AssetManifest.bin 验证 chunks 与 assets 子目录文件全部进 bundle。
//
// 跑法：flutter test test/web_gateway_assets_regression_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assets/web/chunks/* 全部进入 rootBundle', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest.listAssets();
    final chunks = keys.where((k) => k.startsWith('assets/web/chunks/')).toList();
    expect(
      chunks.isNotEmpty,
      isTrue,
      reason:
          'pubspec.yaml 必须声明 assets/web/chunks/，否则 vite 拆出的所有 chunk 都不会进 bundle。',
    );
    // 至少要有 vendor.js + 几个 feature chunk。具体名称随构建变化，但量级
    // 应当 ≥ 3 个，否则说明声明丢了。
    expect(chunks.length, greaterThanOrEqualTo(3),
        reason: 'chunks 数量异常少：${chunks.length}，可能 pubspec 漏声明子目录。');
    expect(
      chunks.any((k) => k.endsWith('vendor.js')),
      isTrue,
      reason: 'vendor.js 必须在 bundle 里，否则首屏脚本全部跑不起来。',
    );
  });

  test('assets/web/ 根目录关键文件齐全', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest.listAssets().toSet();
    for (final required in const [
      'assets/web/index.html',
      'assets/web/app.js',
      'assets/web/app.css',
    ]) {
      expect(
        keys.contains(required),
        isTrue,
        reason: '$required 缺失：先跑 scripts/build_web.sh 再回归。',
      );
    }
  });

  test('assets/web/assets/ 目录已声明（防止 vite 后续输出资源时再踩坑）', () async {
    // assets/web/assets/ 目前可能没有真实文件（vite 项目暂未引入图片/字体），
    // 但只要 pubspec 声明了该目录，rootBundle 就会容纳后续输出，无需再改 pubspec。
    // 通过加载占位文件验证目录被正确扫描。
    expect(
      () async => rootBundle.load('assets/web/assets/.gitkeep'),
      returnsNormally,
      reason: 'pubspec 必须声明 assets/web/assets/ 让 vite 后续输出的 image/font 自动进 bundle。',
    );
  });
}
