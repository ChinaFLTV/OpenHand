import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/widgets/message_gateway_view.dart';

void main() {
  test('趋势绘图区为折线完整描边保留四周空间', () {
    const chart = Rect.fromLTWH(50, 8, 320, 80);

    final plot = webGatewayTrendPlotRect(chart);

    expect(plot, const Rect.fromLTRB(54, 14, 366, 82));
  });

  test('极小绘图区仍保持有效尺寸', () {
    const chart = Rect.fromLTWH(0, 0, 2, 2);

    final plot = webGatewayTrendPlotRect(chart);

    expect(plot.width, 1);
    expect(plot.height, 1);
    expect(chart.contains(plot.topLeft), isTrue);
    expect(chart.contains(plot.bottomRight), isTrue);
  });
}
