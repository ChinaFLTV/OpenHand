import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/generated_media_result_card.dart';

void main() {
  testWidgets('音频结果卡展示统一信息并响应点击', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeneratedMediaResultCard(
            kind: GeneratedMediaResultKind.audio,
            title: '夏夜电台',
            detail: 'audio_20260826.mp3',
            identity: 'audio-result-card-test',
            textColor: Colors.black87,
            backgroundColor: Colors.white,
            onTap: () => tapCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('夏夜电台'), findsOneWidget);
    expect(find.text('AI 音频 · 生成音频'), findsOneWidget);

    await tester.tap(find.text('夏夜电台'));
    await tester.pump();
    expect(tapCount, 1);
  });

  testWidgets('音频结果卡悬停抬升始终保留完整边框空间', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeneratedMediaResultCard(
            kind: GeneratedMediaResultKind.audio,
            title: '夏夜电台',
            detail: 'audio_20260826.mp3',
            identity: 'audio-hover-boundary-test',
            textColor: Colors.black87,
            backgroundColor: Colors.white,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byType(GeneratedMediaResultCard);
    final boundary = find.descendant(
      of: card,
      matching: find.byType(RepaintBoundary),
    );
    final surface = find.descendant(
      of: card,
      matching: find.byType(GestureDetector),
    );
    final boundaryTop = tester.getTopLeft(boundary.first).dy;
    expect(tester.getTopLeft(surface).dy - boundaryTop, closeTo(2, 0.01));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(surface));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(surface).dy, greaterThanOrEqualTo(boundaryTop));
    expect(
      tester.getSize(boundary.first).height - tester.getSize(surface).height,
      closeTo(2, 0.01),
    );
    await mouse.removePointer();
  });

  testWidgets('视频结果卡展示统一封面结构并响应点击', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeneratedMediaResultCard(
            kind: GeneratedMediaResultKind.video,
            title: '城市延时摄影',
            detail: 'city_timelapse.mp4',
            identity: 'video-result-card-test',
            textColor: Colors.black87,
            backgroundColor: Colors.white,
            onTap: () => tapCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('城市延时摄影'), findsOneWidget);
    expect(find.text('city_timelapse.mp4'), findsOneWidget);
    expect(find.text('VIDEO'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.text('城市延时摄影'));
    await tester.pump();
    expect(tapCount, 1);
  });
}
