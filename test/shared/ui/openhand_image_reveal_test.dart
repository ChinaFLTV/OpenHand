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
