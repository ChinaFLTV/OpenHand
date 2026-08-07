import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_ops_charts.dart';

void main() {
  const blue = Color(0xff1565c0);
  const orange = Color(0xffef6c00);

  test('line and donut painters tolerate nonfinite and mismatched inputs', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    expect(
      () => const OpenHandSmoothLineChartPainter(
        series: [
          OpenHandChartSeries(
            label: 'sample',
            values: [double.nan, double.infinity, -3, 0],
            color: blue,
          ),
        ],
        gridColor: Colors.grey,
        labelColor: Colors.black,
        emptyLabel: 'empty',
        valueSuffix: 'ms',
        textDirection: TextDirection.ltr,
      ).paint(canvas, const Size(1, 1)),
      returnsNormally,
    );
    expect(
      () => const OpenHandDonutChartPainter(
        values: [double.nan, double.infinity, -1, 1, 2],
        colors: [blue],
        trackColor: Colors.grey,
      ).paint(canvas, const Size(2, 2)),
      returnsNormally,
    );
    recorder.endRecording().dispose();
  });

  test('圆环在矩形画布中保持居中的正圆', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const OpenHandDonutChartPainter(
      values: [0],
      colors: [orange],
      trackColor: blue,
    ).paint(canvas, const Size(200, 100));
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 100);
    final bytes = await image.toByteData();
    int alphaAt(int x, int y) => bytes!.getUint8((y * 200 + x) * 4 + 3);

    expect(alphaAt(4, 50), 0);
    expect(alphaAt(54, 50), greaterThan(0));
    image.dispose();
    picture.dispose();
  });

  testWidgets('operational trend selects only an actual plotted point', (
    tester,
  ) async {
    OpenHandOperationalTrendSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: OpenHandOperationalTrendChart(
              series: const [
                OpenHandChartSeries(
                  label: 'requests',
                  values: [0, 10],
                  color: blue,
                ),
              ],
              valueSuffix: 'r/s',
              height: 180,
              onSelectionChanged: (value) => selection = value,
            ),
          ),
        ),
      ),
    );

    final paint = find.descendant(
      of: find.byType(OpenHandOperationalTrendChart),
      matching: find.byType(CustomPaint),
    );
    final renderBox = tester.renderObject<RenderBox>(paint);
    final origin = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    await tester.tapAt(origin + Offset(size.width / 2, size.height - 16));
    expect(selection, isNull);

    await tester.tapAt(
      origin +
          Offset(size.width - 8, size.height - 16 - (size.height - 24) / 1.14),
    );
    expect(selection, isNotNull);
    expect(selection!.series.label, 'requests');
    expect(selection!.pointIndex, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(selection!.pointIndex, 0);
  });

  testWidgets('operational donut selects a segment through ring hit testing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    OpenHandOperationalDonutSelection? selection;
    OpenHandOperationalDonutSelection? activated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: OpenHandOperationalDonutChart(
              segments: const [
                OpenHandChartSegment(label: 'first', value: 1, color: blue),
                OpenHandChartSegment(label: 'second', value: 1, color: orange),
              ],
              trackColor: Colors.grey,
              showLegend: false,
              height: 200,
              onSelectionChanged: (value) => selection = value,
              onSegmentTap: (value) => activated = value,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(190, 100));
    expect(selection, isNotNull);
    expect(selection!.segment.label, 'first');
    expect(activated, isNotNull);
    expect(activated!.segment.label, 'first');

    final chartSemantics = find
        .descendant(
          of: find.byType(OpenHandOperationalDonutChart),
          matching: find.byType(Semantics),
        )
        .first;
    final semantics = tester.getSemantics(chartSemantics).getSemanticsData();
    expect(semantics.label, '运维占比环图');
    expect(semantics.hasAction(SemanticsAction.increase), isTrue);
    handle.dispose();
  });

  testWidgets('交互圆环在矩形父布局中使用正方形画布', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 180,
            child: OpenHandOperationalDonutChart(
              segments: [
                OpenHandChartSegment(label: 'sample', value: 1, color: blue),
              ],
              trackColor: Colors.grey,
              showLegend: false,
              height: 180,
              onSelectionChanged: null,
            ),
          ),
        ),
      ),
    );

    final paint = find.descendant(
      of: find.byType(OpenHandOperationalDonutChart),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(paint).aspectRatio, closeTo(1, 0.001));
  });

  testWidgets('donut keyboard activation invokes segment action', (
    tester,
  ) async {
    OpenHandOperationalDonutSelection? activated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenHandOperationalDonutChart(
            segments: const [
              OpenHandChartSegment(label: 'first', value: 1, color: blue),
              OpenHandChartSegment(label: 'second', value: 1, color: orange),
            ],
            trackColor: Colors.grey,
            showLegend: false,
            height: 180,
            onSelectionChanged: (_) {},
            onSegmentTap: (selection) => activated = selection,
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, isNotNull);
    expect(activated!.segment.label, 'first');
  });

  testWidgets('live chart updates rehydrate selected snapshots', (
    tester,
  ) async {
    final trendSeries = ValueNotifier<List<OpenHandChartSeries>>(const [
      OpenHandChartSeries(label: 'requests', values: [1], color: blue),
    ]);
    final donutSegments = ValueNotifier<List<OpenHandChartSegment>>(const [
      OpenHandChartSegment(label: 'first', value: 1, color: blue),
    ]);
    addTearDown(trendSeries.dispose);
    addTearDown(donutSegments.dispose);
    OpenHandOperationalTrendSelection? trendSelection;
    OpenHandOperationalDonutSelection? donutSelection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ValueListenableBuilder(
                valueListenable: trendSeries,
                builder: (context, series, _) => OpenHandOperationalTrendChart(
                  series: series,
                  valueSuffix: '',
                  height: 160,
                  onSelectionChanged: (value) => trendSelection = value,
                ),
              ),
              ValueListenableBuilder(
                valueListenable: donutSegments,
                builder: (context, segments, _) =>
                    OpenHandOperationalDonutChart(
                      segments: segments,
                      trackColor: Colors.grey,
                      showLegend: false,
                      height: 160,
                      onSelectionChanged: (value) => donutSelection = value,
                    ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(trendSelection, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(donutSelection, isNotNull);

    trendSeries.value = const [
      OpenHandChartSeries(label: 'requests', values: [9], color: orange),
    ];
    donutSegments.value = const [
      OpenHandChartSegment(label: 'updated', value: 9, color: orange),
    ];
    await tester.pump();

    expect(trendSelection?.value, 9);
    expect(trendSelection?.series.color, orange);
    expect(donutSelection?.segment.label, 'updated');
    expect(donutSelection?.segment.value, 9);
  });

  testWidgets(
    'nonfinite trend samples are unavailable, not selectable zeroes',
    (tester) async {
      OpenHandOperationalTrendSelection? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpenHandOperationalTrendChart(
              series: const [
                OpenHandChartSeries(
                  label: 'samples',
                  values: [1, double.nan, 3],
                  color: blue,
                ),
              ],
              valueSuffix: '',
              onSelectionChanged: (value) => selection = value,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(selection?.pointIndex, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(selection?.pointIndex, 2);
    },
  );

  testWidgets('generic components expose empty states', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              OpenHandOperationalComparisonBars(
                segments: [],
                orientation: OpenHandComparisonBarOrientation.horizontal,
                emptyLabel: 'no comparisons',
              ),
              OpenHandOperationalLatencyRange(
                segments: [],
                emptyLabel: 'no latency',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('no comparisons'), findsOneWidget);
    expect(find.text('no latency'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('no comparisons')).getSemanticsData().label,
      'no comparisons',
    );
    expect(
      tester.getSemantics(find.text('no latency')).getSemanticsData().label,
      'no latency',
    );
    handle.dispose();
  });
}
