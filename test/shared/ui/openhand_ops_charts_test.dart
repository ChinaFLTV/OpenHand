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
