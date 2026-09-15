import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_studio_cutout_portrait.dart';

Uint8List _rgba(int width, int height, void Function(Uint8List pixels) paint) {
  final pixels = Uint8List(width * height * 4);
  paint(pixels);
  return pixels;
}

void _fill(
  Uint8List pixels,
  int width,
  int height,
  int r,
  int g,
  int b, [
  int a = 255,
]) {
  for (var i = 0; i < width * height; i++) {
    pixels[i * 4] = r;
    pixels[i * 4 + 1] = g;
    pixels[i * 4 + 2] = b;
    pixels[i * 4 + 3] = a;
  }
}

void _rect(
  Uint8List pixels,
  int width,
  int x0,
  int y0,
  int x1,
  int y1,
  int r,
  int g,
  int b,
) {
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final offset = (y * width + x) * 4;
      pixels[offset] = r;
      pixels[offset + 1] = g;
      pixels[offset + 2] = b;
      pixels[offset + 3] = 255;
    }
  }
}

void main() {
  test('抠掉边缘浅色纸底，保留闭合色块', () {
    const width = 16;
    const height = 16;
    final pixels = _rgba(width, height, (buffer) {
      _fill(buffer, width, height, 248, 236, 220);
      _rect(buffer, width, 5, 5, 10, 10, 30, 90, 210);
    });
    final frame = OpenHandStudioCutout.processRgba(
      rgba: pixels,
      width: width,
      height: height,
    );
    expect(frame, isNotNull);
    var kept = 0;
    var ink = 0;
    var cleared = 0;
    for (var i = 0; i < frame!.width * frame.height; i++) {
      final offset = i * 4;
      if (frame.bytes[offset + 3] <= 16) {
        cleared++;
        continue;
      }
      kept++;
      if (frame.bytes[offset] < 80 && frame.bytes[offset + 2] > 150) ink++;
    }
    expect(cleared, greaterThan(kept));
    expect(ink, greaterThan(16));
  });

  test('描边闭合的白色填充不会被当成纸底挖空', () {
    const width = 14;
    const height = 14;
    final pixels = _rgba(width, height, (buffer) {
      _fill(buffer, width, height, 236, 241, 255);
      _rect(buffer, width, 3, 3, 10, 10, 16, 16, 16);
      _rect(buffer, width, 4, 4, 9, 9, 255, 255, 255);
    });
    final frame = OpenHandStudioCutout.processRgba(
      rgba: pixels,
      width: width,
      height: height,
    );
    expect(frame, isNotNull);
    var white = 0;
    for (var i = 0; i < frame!.width * frame.height; i++) {
      final offset = i * 4;
      if (frame.bytes[offset + 3] <= 16) continue;
      if (frame.bytes[offset] > 240 &&
          frame.bytes[offset + 1] > 240 &&
          frame.bytes[offset + 2] > 240) {
        white++;
      }
    }
    expect(white, greaterThanOrEqualTo(16));
  });

  test('整张纸底或非法尺寸时放弃抠图', () {
    final paper = _rgba(8, 8, (buffer) => _fill(buffer, 8, 8, 250, 244, 230));
    expect(
      OpenHandStudioCutout.processRgba(rgba: paper, width: 8, height: 8),
      isNull,
    );
    expect(
      OpenHandStudioCutout.processRgba(
        rgba: Uint8List(4),
        width: 0,
        height: 10,
      ),
      isNull,
    );
  });

  testWidgets('立绘壳层带左侧溶边，失败时不抛出', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 140,
          height: 120,
          child: OpenHandStudioCutoutPortrait(
            url: 'https://example.invalid/portrait.png',
            duration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OpenHandStudioCutoutPortrait), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
