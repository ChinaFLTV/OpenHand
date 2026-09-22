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
        "import 'package:flutter/rendering.dart' show RenderRepaintBoundary;\n"
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
  AiProtocolType protocol = AiProtocolType.jev,
  AiModelConfig? provider,
  Locale locale = const Locale('zh'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = await SettingsController.create(store: _EditorSettings(motion));
  addTearDown(settings.dispose);
  const id = 'typesafe-ai/jev';
  final health = AiModelHealthController();
  addTearDown(health.dispose);
  final captureFont = Platform.environment['OPENHAND_LAYOUT_FONT'];
  if (captureFont != null) {
    await tester.runAsync(() async {
      final loader = FontLoader('配置截图字体');
      loader.addFont(File(captureFont).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
      final monoFont = Platform.environment['OPENHAND_LAYOUT_MONO_FONT'];
      if (monoFont != null) {
        final mono = FontLoader(kOpenHandMonospaceFontFamily);
        mono.addFont(File(monoFont).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await mono.load();
      }
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
  }
  final theme = brightness == Brightness.light
      ? OpenHandTheme.light(OpenHandThemePreset.tundraGreen)
      : OpenHandTheme.dark(OpenHandThemePreset.tundraGreen);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: health),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: captureFont == null ? theme : theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: '配置截图字体'),
        chipTheme: theme.chipTheme.copyWith(labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: '配置截图字体')),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        child: const Text('打开配置'),
        onPressed: () async {
          if (provider != null) {
            await showAnimatedDialog<void>(context: context,
              builder: (_) => _AiModelEditorDialog(initialModel: provider));
            return;
          }
          final result = await showAnimatedDialog<_ModelProfileEditorResult>(
            context: context,
            builder: (_) => _ModelProfileEditorDialog(
              modelId: id,
              existingModelIds: const [id, 'existing-model'],
              initialProfile: const AiModelProfile(),
              effectiveProfile: AiModelCatalog.lookup(id, protocol)!,
              protocolType: protocol,
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

Future<void> _captureEditor(WidgetTester tester, Finder dialog, String name) async {
  final directory = Platform.environment['OPENHAND_LAYOUT_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.ancestor(of: dialog, matching: find.byType(RepaintBoundary)).first);
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final tts in [false, true]) {
    testWidgets('${tts ? 'TTS' : '翻译'} 优先级拖放只保存一次并清理悬停状态', (tester) async {
      final translation = AiTranslationSettings.defaults();
      final speech = AiTtsSettings.defaults();
      final playback = AiTtsPlaybackService();
      addTearDown(playback.dispose);
      final original = tts ? speech.providerPriority : translation.providerPriority;
      final updates = <List<Object>>[];
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: tts
          ? _AiTtsProviderDeck(settings: speech, playbackService: playback,
              availableModels: const [], recentModelSelections: const [],
              onChanged: (next) async { updates.add(next.providerPriority); return true; })
          : _AiTranslationProviderDeck(settings: translation,
              availableModels: const [], recentModelSelections: const [],
              onChanged: (next) async { updates.add(next.providerPriority); return true; }))),
      ));
      final dynamic state = tester.state(find.byType(tts ? _AiTtsProviderDeck : _AiTranslationProviderDeck));
      final dynamic details = tts
        ? DragTargetDetails<AiTtsProvider>(data: speech.providerPriority.first, offset: const Offset(0, 100000))
        : DragTargetDetails<AiTranslationProvider>(data: translation.providerPriority.first, offset: const Offset(0, 100000));
      state._updateHoverInsertIndex(details);
      await tester.pump();
      state._acceptProviderDrop(details);
      state._completeProviderDrag(original.first, DraggableDetails(wasAccepted: true, velocity: Velocity.zero, offset: Offset.zero));
      await tester.pump();
      expect(updates, [<Object>[...original.skip(1), original.first]]);
      expect(state._hoverInsertIndex, isNull);
      expect(state._draggingProvider, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('模型配置动作和元数据按当前语言展示 $locale', (tester) async {
      await _openEditor(tester, locale: locale);
      final context = tester.element(_editor);
      final l10n = AppLocalizations.of(context)!;
      expect(find.text(l10n.mdlEdDecisionSummary), findsOneWidget);
      final actions = tester.widgetList<OpenHandDialogActionButton>(find.byType(OpenHandDialogActionButton));
      expect(actions.where((button) => button.label == l10n.mdlEdOk).single.icon, isNull);
      final cancel = tester.widget<FilledButton>(find.descendant(
        of: find.widgetWithText(OpenHandDialogActionButton, l10n.mdlEdCancel),
        matching: find.byType(FilledButton)));
      final confirm = tester.widget<FilledButton>(find.descendant(
        of: find.widgetWithText(OpenHandDialogActionButton, l10n.mdlEdOk),
        matching: find.byType(FilledButton)));
      expect(cancel.themeStyleOf(context)?.backgroundColor?.resolve({}),
        confirm.themeStyleOf(context)?.backgroundColor?.resolve({}));
      final state = tester.state<_ModelProfileEditorDialogState>(_editor);
      state._profileScrollController.jumpTo(state._profileScrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.mdlEdOpenRouterRawMetadata));
      await tester.pumpAndSettle();
      state._profileScrollController.jumpTo(state._profileScrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byType(OpenHandJsonTreeView), findsOneWidget);
      expect(tester.widget<OpenHandJsonTreeView>(find.byType(OpenHandJsonTreeView)).text,
        contains('supported_parameters'));
      expect(_modelConfigurationValueLabel(context, 'experimental'), l10n.mdlEdValueExperimental);
      expect(tester.takeException(), isNull);
      await _captureEditor(tester, _editor, 'metadata-$locale');
      await tester.tap(find.text(l10n.mdlEdCancel));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('请求头删除按钮与输入框等高且可用，放大文字不溢出', (tester) async {
    await _openEditor(tester, size: const Size(440, 760), textScale: 1.4,
      provider: const AiModelConfig(id: '请求头', baseUrl: 'https://example.invalid',
        token: '', authScheme: AiAuthScheme.none, modelId: 'custom',
        protocolType: AiProtocolType.openai, customHeaders: {'X-Test': 'value'}));
    final dialog = find.byType(_AiModelEditorDialog);
    final field = find.widgetWithText(TextField, '请求头名称');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    final remove = find.descendant(of: dialog, matching: find.byTooltip('删除'));
    final add = find.ancestor(
      of: find.descendant(of: dialog, matching: find.byIcon(Icons.add_rounded)),
      matching: find.byType(FilledButton),
    ).first;
    expect(tester.getSize(remove).height, closeTo(tester.getSize(field).height, 1));
    expect(tester.getSize(remove).width, closeTo(tester.getSize(field).height, 1));
    expect(tester.getRect(add).right, closeTo(tester.getRect(remove).right, 1));
    expect(tester.takeException(), isNull);
    await _captureEditor(tester, dialog, 'headers-narrow');
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(find.text('暂无自定义请求头。点击「添加」按钮来添加。'), findsOneWidget);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '请求头名称'), findsOneWidget);
  });

  testWidgets('宽屏自定义请求头添加与删除右缘对齐', (tester) async {
    await _openEditor(tester,
      provider: const AiModelConfig(id: '请求头宽屏', baseUrl: 'https://example.invalid',
        token: '', authScheme: AiAuthScheme.none, modelId: 'custom',
        protocolType: AiProtocolType.openai,
        customHeaders: {'X-Test': 'value', 'X-Trace': '1'}));
    final dialog = find.byType(_AiModelEditorDialog);
    final nameField = find.widgetWithText(TextField, '请求头名称').first;
    await tester.ensureVisible(nameField);
    await tester.pumpAndSettle();
    final remove = find.descendant(of: dialog, matching: find.byTooltip('删除'));
    final add = find.ancestor(
      of: find.descendant(of: dialog, matching: find.byIcon(Icons.add_rounded)),
      matching: find.byType(FilledButton),
    ).first;
    expect(remove, findsNWidgets(2));
    expect(tester.getRect(add).right, closeTo(tester.getRect(remove.first).right, 1));
    expect(tester.getRect(remove.first).right, closeTo(tester.getRect(remove.at(1)).right, 1));
    expect(tester.getSize(remove.first).height, closeTo(tester.getSize(nameField).height, 1));
    expect(tester.takeException(), isNull);
    await _captureEditor(tester, dialog, 'headers-wide');
  });

  testWidgets('提供商协议切换同步端点和高级配置，模型 ID 不参与判断', (tester) async {
    await _openEditor(tester, provider: const AiModelConfig(
      id: '配置', name: '自定义决策服务', baseUrl: 'https://decision.example',
      token: '', authScheme: AiAuthScheme.none, modelId: 'custom-router',
      protocolType: AiProtocolType.openai,
    ));
    final dialog = find.byType(_AiModelEditorDialog);
    final dropdown = find.byType(AnimatedDropdownButtonFormField<AiProtocolType>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jev').last);
    await tester.pumpAndSettle();
    final state = tester.state<_AiModelEditorDialogState>(dialog);
    expect(state._apiDialect, AiApiDialect.jevNative);
    expect(state._previewChatEndpoints(), (responses: '', chat: 'https://decision.example/v1/systemone'));
    expect(find.textContaining('Jev 协议 · 文本输入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.descendant(of: dialog, matching: find.byType(TextFormField)).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.ancestor(of: dialog, matching: find.byType(RepaintBoundary)).first);
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/openhand-jev-provider.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    state._handleProtocolChanged(AiProtocolType.openai);
    await tester.pumpAndSettle();
    expect(state._previewChatEndpoints().chat, 'https://decision.example/v1/chat/completions');
    expect(state._apiDialect, AiApiDialect.openAiCompat);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('Jev 协议修改模型 ID 后仍保持决策限制', (tester) async {
    _ModelProfileEditorResult? result;
    await _openEditor(tester, onResult: (value) => result = value);
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNull);
    await tester.enterText(_idField, 'custom-router');
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNull);
    expect(tester.widget<Switch>(_titleSwitch).value, isFalse);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result?.modelId, 'custom-router');
    expect(result?.profile.isGlobalDefaultTitleModel, isFalse);
    expect(result?.profile.supportedParameters, ['model', 'state', 'questions']);
    expect(result?.profile.capabilities.isEmpty, isTrue);
    expect(_editor, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('普通协议不因 Jev 模型名称启用决策界面', (tester) async {
    await _openEditor(tester, protocol: AiProtocolType.openai);
    expect(find.textContaining('Jev 协议 · 文本输入'), findsNothing);
    await tester.enterText(_idField, 'gpt-4o-mini');
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNotNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
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
        await _captureEditor(tester, _editor, 'layout-${brightness.name}-${size.width.toInt()}');
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
    expect(tester.widget<Switch>(_titleSwitch).onChanged, isNull);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(_editor, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
''';
