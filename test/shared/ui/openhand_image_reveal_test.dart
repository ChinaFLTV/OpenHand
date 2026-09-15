import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_image_reveal.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 120, height: 120, child: child)),
    ),
  );
}

void main() {
  testWidgets('倒序消息列表的内容自适应宽度兼容图片切换', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            children: const [
              Align(
                alignment: Alignment.centerRight,
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Wrap(
                        children: [
                          OpenHandImageRevealSwitcher(
                            stateKey: '图片',
                            child: SizedBox(
                              width: 190,
                              height: 142,
                              child: Text('图片内容'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(OpenHandImageRevealSwitcher)),
      const Size(190, 142),
    );
  });

  testWidgets('消息图片快速切换加载、完成与失败状态后仍可滚动', (tester) async {
    var state = '加载';
    var disableAnimations = false;
    late StateSetter update;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disableAnimations),
              child: Scaffold(
                body: SizedBox(
                  width: 320,
                  child: ListView.builder(
                    controller: controller,
                    reverse: true,
                    itemCount: 8,
                    itemBuilder: (context, index) => Align(
                      alignment: Alignment.centerRight,
                      child: IntrinsicWidth(
                        child: Wrap(
                          children: [
                            OpenHandImageRevealSwitcher(
                              stateKey: state,
                              child: SizedBox(
                                width: 190,
                                height: 142,
                                child: Builder(
                                  builder: (context) =>
                                      openHandImageRevealFrameBuilder(
                                        context,
                                        Text('$state：$index'),
                                        state == '加载' ? null : 0,
                                        false,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final disabled in [false, true]) {
      for (final next in ['完成', '加载', '失败', '加载', '完成']) {
        update(() {
          state = next;
          disableAnimations = disabled;
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pump(kOpenHandImageRevealDuration);
    expect(controller.position.hasContentDimensions, isTrue);
    expect(controller.position.maxScrollExtent.isFinite, isTrue);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(kOpenHandImageRevealDuration);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同步解码时直接显示内容，不插骨架', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => openHandImageRevealFrameBuilder(
            context,
            const Text('ready'),
            0,
            true,
          ),
        ),
      ),
    );
    expect(find.text('ready'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

  testWidgets('首帧未就绪时显示骨架，就绪后切到内容', (tester) async {
    int? frame;
    late VoidCallback rebuild;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = () => setState(() {});
            return openHandImageRevealFrameBuilder(
              context,
              const Text('photo'),
              frame,
              false,
            );
          },
        ),
      ),
    );
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    frame = 0;
    rebuild();
    await tester.pump();
    await tester.pump(kOpenHandImageRevealDuration);
    expect(find.text('photo'), findsOneWidget);
  });

  testWidgets('关闭系统动画时切换器直接显示目标子树', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          );
        },
        home: const Scaffold(
          body: Center(
            child: OpenHandImageRevealSwitcher(
              stateKey: 'a',
              child: Text('shown'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('shown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧约束下首帧显现铺满父级，避免按原图比例留边', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 190,
            height: 142,
            child: Builder(
              builder: (context) => openHandImageRevealFrameBuilder(
                context,
                const ColoredBox(
                  key: ValueKey<String>('cover-fill'),
                  color: Color(0xFFFF0000),
                ),
                0,
                false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(kOpenHandImageRevealDuration);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('cover-fill'))),
      const Size(190, 142),
    );
  });

  testWidgets('横向无界时切换器按内容收缩，不撑破布局', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            OpenHandImageRevealSwitcher(stateKey: 'row', child: Text('chip')),
          ],
        ),
      ),
    );
    expect(find.text('chip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑模式骨架使用更小的占位图标', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => openHandCompactImageRevealFrameBuilder(
            context,
            const Text('avatar'),
            null,
            false,
          ),
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.image_outlined));
    expect(icon.size, 18);
  });
}
