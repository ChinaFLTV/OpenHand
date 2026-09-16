import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/openhand_home_page.dart';
import 'package:openhand/shared/ui/openhand_safe_markdown_body.dart';

void main() {
  testWidgets('反复展开折叠及动效启停不能重新挂载正文', (tester) async {
    var mounts = 0;
    var disposals = 0;
    var height = 90.0;
    var duration = Duration.zero;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ListView(
              children: [
                maybeAnimatedSize(
                  duration: duration,
                  curve: kCardMotionCurve,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: height,
                    child: _BodyProbe(
                      onMount: () => mounts++,
                      onDispose: () => disposals++,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    final originalBody = tester.state(find.byType(_BodyProbe));
    for (var cycle = 0; cycle < 12; cycle++) {
      update(() {
        height = cycle.isEven ? 240 : 90;
        duration = kCardMotionDurationExpand;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.state(find.byType(_BodyProbe)), same(originalBody));
      update(() => duration = Duration.zero);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SizedBox).first).height, height);
      expect(tester.takeException(), isNull);
      expect(mounts, 1, reason: '动画开始和结束均须沿用正文实例');
      expect(disposals, 0);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposals, 1);
  });

  testWidgets('长 Markdown 首次展开后折叠保留完整正文与渲染状态', (tester) async {
    var collapsed = true;
    late StateSetter update;
    final data =
        '${List.filled(80, '正文 **格式** 与 `代码`。\n\n').join()}\n\n**尾部完整正文标记**';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ListView(
              children: [
                maybeAnimatedSize(
                  duration: collapsed
                      ? Duration.zero
                      : kCardMotionDurationExpand,
                  curve: kCardMotionCurve,
                  alignment: Alignment.topLeft,
                  child: buildCollapsibleMessageBodyForTesting(
                    context,
                    data: data,
                    collapsed: collapsed,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tail = find.textContaining('尾部完整正文标记', findRichText: true);
    expect(tail, findsNothing);
    update(() => collapsed = false);
    await tester.pumpAndSettle();
    expect(tail, findsOneWidget);
    final original = tester.element(tail);
    for (var cycle = 0; cycle < 12; cycle++) {
      update(() => collapsed = !collapsed);
      await tester.pumpAndSettle();
      expect(tester.element(tail), same(original), reason: '折叠只裁剪正文，保留已经构建的全文');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('大型 HTML 展开后折叠不销毁平台视图，卸载仍释放资源', (tester) async {
    final platform = _WebViewPlatformProbe();
    iaw.InAppWebViewPlatform.instance = platform;
    var collapsed = true;
    late StateSetter update;
    final data =
        '<article>${List.filled(60, '<p>保留 HTML 正文和交互状态</p>').join()}</article>';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ListView(
              children: [
                maybeAnimatedSize(
                  duration: collapsed
                      ? Duration.zero
                      : kCardMotionDurationExpand,
                  curve: kCardMotionCurve,
                  alignment: Alignment.topLeft,
                  child: buildCollapsibleMessageBodyForTesting(
                    context,
                    data: data,
                    collapsed: collapsed,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(platform.mounts, 0, reason: '初始折叠不创建平台视图');
    update(() => collapsed = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(platform.mounts, 1);
    final original = tester.state(find.byType(iaw.InAppWebView));
    for (var cycle = 0; cycle < 12; cycle++) {
      update(() => collapsed = !collapsed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.state(find.byType(iaw.InAppWebView)), same(original));
      expect(platform.mounts, 1);
      expect(platform.disposals, 0);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(platform.disposals, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

class _WebViewPlatformProbe extends iaw.InAppWebViewPlatform {
  var mounts = 0;
  var disposals = 0;

  @override
  iaw.PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    iaw.PlatformInAppWebViewWidgetCreationParams params,
  ) {
    mounts++;
    return _WebViewProbe(params, () => disposals++);
  }
}

class _WebViewProbe extends iaw.PlatformInAppWebViewWidget {
  _WebViewProbe(super.params, this.onDispose) : super.implementation();

  final VoidCallback onDispose;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(iaw.PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() => onDispose();
}

class _BodyProbe extends StatefulWidget {
  const _BodyProbe({required this.onMount, required this.onDispose});

  final VoidCallback onMount;
  final VoidCallback onDispose;

  @override
  State<_BodyProbe> createState() => _BodyProbeState();
}

class _BodyProbeState extends State<_BodyProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const OpenHandThemedMarkdownBody(
      data: '### 已渲染正文\n\n反复切换保留 **格式** 与 `代码`。',
    );
  }
}
