import 'dart:io';

import 'support/flutter_widget_check.dart';

/// 合并真实设置页，直接检查私有模型编辑弹窗，不增加生产测试接口。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final page = File(
    '${root.path}/lib/features/settings/widgets/settings_view.dart',
  );
  final libUri = Directory('${root.path}/lib/').uri;
  var source = await page.readAsString();
  source = source.replaceAllMapped(RegExp("(import|export) '([^']+)'"), (
    match,
  ) {
    if (match[2]!.contains(':')) return match[0]!;
    final uri = page.uri.resolve(match[2]!);
    return "${match[1]} 'package:openhand/${uri.path.substring(libUri.path.length)}'";
  });
  source = source.replaceAllMapped(RegExp("part '([^']+)';"), (match) {
    return File.fromUri(page.uri.resolve(match[1]!))
        .readAsStringSync()
        .replaceFirst(RegExp('^part of [^;]+;', multiLine: true), '');
  });
  await runFlutterWidgetCheck(
    root: root,
    name: 'model_editor',
    source:
        "import 'package:flutter_test/flutter_test.dart' hide isEmpty, isNotEmpty;\n"
        '$source\n$_checks',
  );
}

const _checks = r'''
class _EditorSettings extends SettingsStore {
  _EditorSettings(this.motion);
  final DialogAnimationSettings motion;
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(
    snapshot: AppSettingsSnapshot.defaults().copyWith(dialogAnimationSettings: motion),
    canPersist: false,
  );
}

Future<void> _openEditor(
  WidgetTester tester, {
  Size size = const Size(1100, 900),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  DialogAnimationSettings motion = OpenHandMotionDefaults.dialog,
  ValueChanged<_ModelProfileEditorResult?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = await SettingsController.create(store: _EditorSettings(motion));
  addTearDown(settings.dispose);
  const id = 'typesafe-ai/jev';
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: settings,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: brightness == Brightness.light
          ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen)
          : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        child: const Text('打开配置'),
        onPressed: () async {
          final result = await showAnimatedDialog<_ModelProfileEditorResult>(
            context: context,
            builder: (_) => _ModelProfileEditorDialog(
              modelId: id,
              existingModelIds: const [id, 'existing-model'],
              initialProfile: const AiModelProfile(),
              effectiveProfile: AiModelCatalog.lookup(id, AiProtocolType.openai)!,
              protocolType: AiProtocolType.openai,
              onDuplicate: (id, profile) => '$id-copy',
            ),
          );
          onResult?.call(result);
        },
      ))),
    ),
  ));
  await tester.tap(find.text('打开配置'));
  await tester.pumpAndSettle();
}

Finder get _editor => find.byType(_ModelProfileEditorDialog);
Finder get _idField => find.descendant(of: _editor, matching: find.byType(TextField)).first;
Finder get _titleSwitch => find.descendant(of: _editor, matching: find.byType(Switch)).first;

void main() {
  testWidgets('模型 ID 输入即时刷新决策限制，保存时禁止决策模型用于标题', (tester) async {
    _ModelProfileEditorResult? result;
    await _openEditor(tester, onResult: (value) => result = value);
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNull);
    await tester.enterText(_idField, 'gpt-4o-mini');
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNotNull);
    await tester.ensureVisible(_titleSwitch);
    await tester.tap(_titleSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_titleSwitch).value, isTrue);
    await tester.ensureVisible(_idField);
    await tester.enterText(_idField, 'typesafe-ai/jev');
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNull);
    expect(tester.widget<Switch>(_titleSwitch).value, isFalse);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result?.modelId, 'typesafe-ai/jev');
    expect(result?.profile.isGlobalDefaultTitleModel, isFalse);
    expect(_editor, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长表单底部提交错误始终可见，修正 ID 后可以保存', (tester) async {
    _ModelProfileEditorResult? result;
    await _openEditor(tester, onResult: (value) => result = value);
    await tester.enterText(_idField, 'existing-model');
    await tester.pumpAndSettle();
    final state = tester.state<_ModelProfileEditorDialogState>(_editor);
    state._profileScrollController.jumpTo(state._profileScrollController.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final error = find.text('模型 ID 已存在，请换一个唯一 ID。');
    expect(error.hitTestable(), findsOneWidget);
    expect(_editor, findsOneWidget);
    await tester.ensureVisible(_idField);
    await tester.enterText(_idField, 'my-model');
    await tester.pumpAndSettle();
    expect(error, findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result?.modelId, 'my-model');
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(1100, 900), const Size(390, 720)]) {
      testWidgets('纯色弹窗布局适配 ${brightness.name} $size', (tester) async {
        await _openEditor(tester, size: size, brightness: brightness, textScale: 1.2);
        expect(tester.takeException(), isNull);
        expect(find.text('确定').hitTestable(), findsOneWidget);
        final decorations = tester.widgetList<DecoratedBox>(find.descendant(
          of: _editor, matching: find.byType(DecoratedBox),
        ));
        expect(decorations.where((item) => item.decoration is BoxDecoration &&
            (item.decoration as BoxDecoration).gradient != null).isEmpty, isTrue);
        final state = tester.state<_ModelProfileEditorDialogState>(_editor);
        state._profileScrollController.jumpTo(state._profileScrollController.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('确定').hitTestable(), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(_editor, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('关闭全局弹窗动画后开关和退场可正常完成', (tester) async {
    await _openEditor(tester, motion: OpenHandMotionDefaults.disabled);
    await tester.enterText(_idField, 'gpt-4o-mini');
    await tester.pump();
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNotNull);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(_editor, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
''';
