import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'image_resources',
  source: _checks,
);

const _checks = r'''
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_screenshot_markup.dart';
import 'package:openhand/features/workflows/service/workflow_portability_service.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/shared/util/path_safety.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/image_rasterization.dart';
import 'package:openhand/shared/ui/natural_image_size_resolver.dart';

class _ImageCompleter extends ImageStreamCompleter {}

class _ImageProvider extends ImageProvider<_ImageProvider> {
  _ImageProvider(this.completer);
  final ImageStreamCompleter completer;
  @override
  Future<_ImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);
  @override
  void resolveStreamForKey(ImageConfiguration configuration, ImageStream stream,
      _ImageProvider key, ImageErrorListener handleError) {
    stream.setCompleter(completer);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('栅格化释放绘图指令，首帧解码结果可独立使用', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await rasterizePicture(picture, 8, 6);
    expect(picture.debugDisposed, isTrue);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final decoded = await decodeFirstImageFrame(data.buffer.asUint8List());
      expect(Size(decoded.width.toDouble(), decoded.height.toDouble()), const Size(8, 6));
      decoded.dispose();
    } finally {
      image.dispose();
    }
    await expectLater(decodeFirstImageFrame(Uint8List(0)), throwsA(isA<Exception>()));
  });

  test('同步与异步图片尺寸解析只持有首帧且释放克隆引用', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final image = await rasterizePicture(recorder.endRecording(), 8, 6);
    try {
      for (final synchronous in [true, false]) {
        final completer = _ImageCompleter();
        final keepAlive = completer.keepAlive();
        var notifications = 0;
        final resolver = NaturalImageSizeResolver(onResolved: () => notifications++);
        if (synchronous) completer.setImage(ImageInfo(image: image.clone()));
        resolver.resolve(_ImageProvider(completer));
        if (!synchronous) completer.setImage(ImageInfo(image: image.clone()));
        expect(resolver.size, const Size(8, 6));
        expect(notifications, synchronous ? 0 : 1);
        expect(completer.hasListeners, isFalse);
        expect(image.debugGetOpenHandleStackTraces()!.length, 2);
        resolver.dispose();
        keepAlive.dispose();
        expect(image.debugGetOpenHandleStackTraces()!.length, 1);
      }
    } finally {
      image.dispose();
    }
  });

  test('工作流导出导入保持一致，文件名兼容跨平台边界', () {
    final date = DateTime.utc(2026, 9, 18);
    final workflow = WorkflowDefinition(id: '工作流', name: '流程演示', createdAt: date, updatedAt: date);
    expect(decodeWorkflowYaml(encodeWorkflowYaml(workflow)).toJson(), workflow.toJson());
    for (final name in ['CON', 'NUL.yaml', '..', '流程. ', '流程/导出', '😀' * 120]) {
      for (final format in WorkflowExportFormat.values) {
        final fileName = workflowExportFileName(workflow.copyWith(name: name), format);
        expect(isPortableFileNamePart(fileName), isTrue, reason: fileName);
        expect(fileName.endsWith('.${format.extension}'), isTrue);
      }
    }
  });

  test('工作流图片导出成功或编码前异常均释放栅格图像', () async {
    final date = DateTime.utc(2026, 9, 18);
    final workflow = WorkflowDefinition(id: '工作流', name: '流程演示', createdAt: date, updatedAt: date);
    final previous = ui.Image.onCreate;
    final created = <ui.Image>[];
    ui.Image.onCreate = (image) {
      previous?.call(image);
      created.add(image);
    };
    try {
      for (final format in [WorkflowExportFormat.png, WorkflowExportFormat.jpeg]) {
        final artifact = await buildWorkflowExportArtifact(workflow, format);
        expect(artifact.bytes, isNotEmpty);
        expect(created, isNotEmpty);
        expect(created.every((image) => image.debugDisposed), isTrue);
        created.clear();
        final failure = StateError('模拟编码前进度回调失败');
        await expectLater(buildWorkflowExportArtifact(workflow, format, onProgress: (progress, _) {
          if (progress > 0.7) throw failure;
        }), throwsA(same(failure)));
        expect(created, isNotEmpty);
        expect(created.every((image) => image.debugDisposed), isTrue);
        created.clear();
      }
    } finally {
      ui.Image.onCreate = previous;
    }
  });

  test('无效工作流版本与非字符串键不能被隐式修正后导入', () {
    for (final version in ['1.5', '.nan', '.inf', 'true', '"1"']) {
      expect(() => decodeWorkflowYaml('format: openhand-workflow\nversion: $version\nworkflow: {}'),
        throwsA(isA<WorkflowPortabilityException>().having((error) => error.message, '错误原因', startsWith('不支持的工作流配置版本'))));
    }
    expect(() => decodeWorkflowYaml('format: openhand-workflow\nversion: 1\nworkflow:\n  1: 数值键\n  "1": 字符串键'),
      throwsA(isA<WorkflowPortabilityException>().having((error) => error.message, '错误原因', contains('键必须为字符串'))));
  });

  testWidgets('损坏截图停止加载，显示失败状态并允许关闭', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (value) {
        context = value;
        return const Scaffold();
      }),
    ));
    final result = showScreenshotMarkupDialog(context, image: Uint8List(0));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizations.of(context)!.imageEditorLoadFailed), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(tester.takeException(), isNull);
  });
}
''';
