import 'dart:io';

import 'support/flutter_widget_check.dart';

/// 合并真实页面及其 part 后执行私有组件回归，不给生产代码添加测试接口。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final page = File('${root.path}/lib/features/home/openhand_home_page.dart');
  final source = await readFlutterCheckSource(
    page,
    root: root,
    inlineParts: true,
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'transcript',
    source:
        "import 'package:flutter_test/flutter_test.dart' hide isEmpty, isNotEmpty;\n"
        "import 'package:openhand/app/state/settings_store.dart';\n"
        "import 'package:openhand/app/theme/openhand_theme.dart';\n"
        "import 'dart:ui' as ui;\n"
        "import 'dart:isolate' show RemoteError;\n"
        '$source\n$_widgetTests',
  );
}

const _widgetTests = r'''
// 仅替换平台视图边界；消息格式分发与延迟加载仍执行生产实现。
class _FailingMarkdownSyntax extends md.InlineSyntax {
  _FailingMarkdownSyntax() : super('@解析失败');
  @override
  bool onMatch(md.InlineParser parser, Match match) =>
      throw const FormatException('模拟正文解析失败');
}

class _ProbeWebViewPlatform extends iaw.InAppWebViewPlatform {
  @override
  iaw.PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    iaw.PlatformInAppWebViewWidgetCreationParams params,
  ) => _ProbeWebView(params);
}

class _ProbeWebView extends iaw.PlatformInAppWebViewWidget {
  _ProbeWebView(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  T controllerFromPlatform<T>(iaw.PlatformInAppWebViewController controller) =>
      throw UnimplementedError('本用例不调用平台控制器');
  @override
  void dispose() {}
}

class _ProbeSettingsStore extends SettingsStore {
  _ProbeSettingsStore(this.animated, {this.writable = false, this.textActions = false});
  final bool animated;
  final bool writable;
  final bool textActions;
  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {}
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(
    snapshot: AppSettingsSnapshot.defaults().copyWith(
      pageAnimationSettings: animated
          ? OpenHandMotionDefaults.page
          : OpenHandMotionDefaults.disabled,
      showSelfLearningMessages: false,
      aiTtsSettings: AiTtsSettings.defaults().copyWith(enabled: textActions),
      aiTranslationSettings: AiTranslationSettings.defaults().copyWith(enabled: textActions),
    ),
    canPersist: writable,
  );
}

class _ProbeAiController extends ChangeNotifier implements AiSessionController {
  Future<AiSession?> Function(String)? loadOlder;
  Future<AiSessionMessage?> Function(String, String)? loadFull;
  int loadCount = 0;
  @override
  AiSession? get currentSession => null;
  @override
  Future<AiSession?> loadOlderSessionMessages(String id) {
    loadCount += 1;
    return loadOlder?.call(id) ?? Future.value();
  }

  @override
  Future<AiSessionMessage?> loadFullSessionMessageContent(String sessionId, String messageId) =>
      loadFull?.call(sessionId, messageId) ?? Future.value();

  @override
  String? lastErrorMessageForSession(String? id) => null;

  @override
  bool isSessionMessagesHydrating(String id) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryStore extends AiSessionStore {
  _HistoryStore(this.session, String path) : super(sessionsDirectoryPath: path);
  AiSession session;
  final requests = <Completer<AiSessionMessagePage>>[];
  @override
  Future<AiSessionLoadResult> loadAllHeaders({bool includeArchived = false}) async =>
      AiSessionLoadResult(sessions: [session], issues: const []);
  @override
  Future<AiSessionMessagePage> loadMessages(String sessionId, {
    int limit = 50, int offset = 0, bool deferTelemetryMetadata = false,
    int? contentPreviewChars, int? knownTotalCount,
    bool includeToolCallContext = true,
  }) {
    final request = Completer<AiSessionMessagePage>();
    requests.add(request);
    return request.future;
  }
}

class _HistoryRuntime implements AiToolRuntimeService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ComposerRoutingProbe extends _OpenHandHomePageState {
  static Future<_ComposerRoutingProbe> create(WidgetTester tester) async {
    const recorderChannel = MethodChannel('com.llfbandit.record/messages');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(recorderChannel, (_) async => null);
    // 主页构造会探测本机语音能力，避免把系统进程计时器放入组件的虚拟时钟。
    final home = (await tester.runAsync(() async => _ComposerRoutingProbe()))!;
    addTearDown(home._composerController.dispose);
    addTearDown(home._composerFocusNode.dispose);
    addTearDown(home._globalShortcutFocusNode.dispose);
    addTearDown(() async {
      await tester.runAsync(() async {
        home._voiceConversationService.dispose();
        await home._ttsPlaybackService.dispose();
        await Future<void>.delayed(Duration.zero);
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(recorderChannel, null);
    });
    addTearDown(home._translationService.dispose);
    addTearDown(home._webReverseCdpMcpBridge.dispose);
    addTearDown(home._transcriptScrollActivity.dispose);
    addTearDown(home._navigationWidthNotifier.dispose);
    addTearDown(home._userScrollGraceDebouncer.dispose);
    addTearDown(home._messageScrollController.dispose);
    return home;
  }
  @override
  bool get mounted => true;
  @override
  void setState(VoidCallback fn) => fn();
  @override
  void _syncVoiceConversationVisibility(String? currentSessionId) {}
}

class _WorkspaceProbeAi extends _ProbeAiController {
  @override
  bool sessionWasInitiallyThrottled(String id) => false;
  @override
  bool sessionStreamThrottleDurationExpired(String id) => false;
  @override
  int sessionStreamCardBacklog(String id) => 0;
  @override
  AiStreamThrottleOverride? sessionStreamThrottleOverride(String id) => null;
  @override
  final ValueNotifier<int> streamThrottleOverrideSignal = ValueNotifier<int>(0);
  @override
  void dispose() {
    streamThrottleOverrideSignal.dispose();
    super.dispose();
  }
}

class _ProbeInstructions extends ChangeNotifier implements InstructionsController {
  @override
  List<UserInstructionEntry> get enabledEntries => [
    UserInstructionEntry(id: '布局指令', name: '响应文本语言约束', body: '使用简体中文',
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026), sortOrder: 0),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeVoice extends ChangeNotifier implements AiVoiceConversationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeTts implements AiTtsPlaybackService {
  @override
  final state = ValueNotifier<AiTtsPlaybackSnapshot>(
    const AiTtsPlaybackSnapshot(),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeTranslation implements AiTranslationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AiSession _probeSession(
  String id,
  int count, {
  bool mixed = false,
  int hidden = 0,
  int filtered = 0,
}) {
  final date = DateTime.utc(2026, 9, 16);
  return AiSession(
    id: id,
    title: id,
    templateId: 'chat',
    templateName: '对话',
    templateIconName: 'chat',
    templateInternalVersion: '1',
    createdAt: date,
    updatedAt: date,
    environment: AiSessionEnvironment.fromJson({}),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
    messageLoadState: hidden > 0
        ? AiSessionMessageLoadState.windowed
        : AiSessionMessageLoadState.complete,
    messageWindowStartIndex: hidden,
    messageTotalCount: count + filtered + hidden,
    messages: [
      for (var index = 0; index < count + filtered; index++)
        if (index >= count - 2 && index < count - 2 + filtered)
          AiSessionMessage.selfLearning(
            id: '$id-$index',
            content: '过滤的内部消息',
            createdAt: date,
            metadata: const {},
          )
        else
          AiSessionMessage.assistant(
            id: '$id-$index',
            createdAt: date.add(Duration(seconds: index)),
            content: mixed && index != count - 1
                ? '历史消息$index\n\n${List.filled(index % 5 + 2, '这是一段用于检查变高消息滚动的历史内容。').join('\n\n')}'
                : '短消息$index',
          ),
    ],
  );
}

class _ProbeTranscriptScrollController extends OpenHandStableScrollController {
  int maxAttachedPositions = 0;

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    maxAttachedPositions = math.max(maxAttachedPositions, positions.length);
  }
}

class _TranscriptProbe {
  _TranscriptProbe(this.tester, this.session);
  final WidgetTester tester;
  AiSession session;
  var key = GlobalKey<_SessionTranscriptState>();
  var controller = _ProbeTranscriptScrollController();
  bool _workspaceSwitcher = false;
  final activity = TranscriptScrollActivity();
  final ai = _ProbeAiController();
  final tts = _ProbeTts();
  late SettingsController settings;
  late StateSetter rebuild;
  int manualReveals = 0;
  AiSendPhase sendPhase = AiSendPhase.idle;
  bool preserveViewportAfterUserScroll = true;
  bool tickerEnabled = true;
  VoidCallback? onLayoutChanged;
  VoidCallback? onRevealOlderMessages;
  _SessionTranscriptState get state => key.currentState!;

  Future<void> mount({
    Size size = const Size(1400, 900),
    bool animated = false,
    bool paused = false,
    bool textActions = false,
    bool writable = false,
    bool workspaceSwitcher = false,
  }) async {
    _workspaceSwitcher = workspaceSwitcher;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = await SettingsController.create(
      store: _ProbeSettingsStore(animated, textActions: textActions, writable: writable),
    );
    activity.value = paused;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AiSessionController>.value(value: ai),
          ChangeNotifierProvider<TranscriptScrollActivity>.value(
            value: activity,
          ),
        ],
        child: MaterialApp(
          scrollBehavior: const OpenHandImplicitScrollbarBehavior(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                final transcript = _SessionTranscript(
                  key: key,
                  controller: controller,
                  onScrollNotification: (_) => false,
                  session: session,
                  sendPhase: sendPhase,
                  onLayoutChanged: () => onLayoutChanged?.call(),
                  onMessageExpansionChanged: (_) {},
                  preserveViewportAfterUserScroll: preserveViewportAfterUserScroll,
                  onRevealOlderMessages: () {
                    manualReveals += 1;
                    onRevealOlderMessages?.call();
                  },
                  onProgrammaticScrollCorrection: (correction) => correction(),
                  messageActions: _MessageActions(
                    onEdit: (_) async {},
                    onCopy: (_) async {},
                    onDelete: (_) async => false,
                    onDeleteFromHere: (_) async => false,
                    onFork: (_) async {},
                    onSetFeedback: (_, _) async {},
                    onRegenerate: (_) async {},
                    onSelectResponseVariant: (_, _) async {},
                  ),
                  ttsPlaybackService: tts,
                  translationService: _ProbeTranslation(),
                  onDismissError: (_) async {},
                );
                return TickerMode(enabled: tickerEnabled, child: workspaceSwitcher
                    ? _WorkspacePrimarySwitcher(child: KeyedSubtree(
                        key: ValueKey('session-${session.id}'), child: transcript))
                    : transcript);
              },
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      controller.dispose();
      activity.dispose();
      settings.dispose();
      ai.dispose();
      tts.state.dispose();
    });
  }

  Future<void> settle() async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(tester.takeException(), isNull);
  }

  void update(AiSession value) => rebuild(() {
    if (_workspaceSwitcher && value.id != session.id) {
      key = GlobalKey<_SessionTranscriptState>();
    }
    session = value;
  });

  void expectFilled() {
    expect(state._initialRevealPhase, _TranscriptInitialRevealPhase.ready);
    expect(
      controller.position.extentAfter,
      lessThan(1),
      reason: '首次打开必须停在最新尾部',
    );
    expect(
      state._renderEntries.map((e) => e.id),
      session.displayMessages.skip(state._windowStartIndex).map((m) => m.id),
      reason: '渲染序列必须完整对应历史数据',
    );
    final top = state._bubbleRegistry._contexts.keys
        .map(state._viewportOffsetForMessage)
        .whereType<double>()
        .fold(double.infinity, math.min);
    final allExpanded =
        state._windowStartIndex == 0 && !session.hasMoreHistoricalMessages;
    expect(allExpanded || top <= 1, true, reason: '有历史可展示时，视口顶部不得留下空白：顶部=$top，起点=${state._windowStartIndex}，条数=${state._renderEntries.length}，剩余额度=${state._viewportFillMessagesRemaining}');
    if (allExpanded && controller.position.maxScrollExtent == 0) {
      expect(top, closeTo(0, 1), reason: '不足一屏的消息必须从视口顶部开始排列');
    }
    final last = state._bubbleRegistry.contextOf(
      session.displayMessages.last.id,
    );
    expect(last, isNotNull, reason: '最新消息必须实际挂载');
    final offset = state._viewportOffsetForMessage(
      session.displayMessages.last.id,
    )!;
    final box = last!.findRenderObject()! as RenderBox;
    expect(offset, lessThan(controller.position.viewportDimension));
    expect(
      offset + box.size.height,
      lessThanOrEqualTo(controller.position.viewportDimension),
    );
    expect(state._staggerFillActive, false);
  }
}

void main() {
  iaw.InAppWebViewPlatform.instance = _ProbeWebViewPlatform();
  testWidgets('消息控件：六语窄屏、大字号与长输出保持可用', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await SettingsController.create(store: _ProbeSettingsStore(false));
    addTearDown(settings.dispose);
    final output = List.filled(24, '服务运行正常，任务已完成。').join('\n');
    for (final locale in AppLocalizations.supportedLocales) {
      for (final brightness in Brightness.values) {
        final l10n = lookupAppLocalizations(locale);
        final message = AiSessionMessage.toolCall(
          id: '${locale.toLanguageTag()}-${brightness.name}',
          content: '', createdAt: DateTime.utc(2026),
          metadata: {
            'tool_name': 'MachineTerminalExec', 'tool_execution_status': 'success',
            'tool_execution_working_directory': '/workspace/${'很长的项目目录/' * 15}',
            'tool_arguments': '{"command":"systemctl status"}',
            'tool_execution_stdout': output, 'tool_execution_exit_code': 0,
            'websearch_cache': 'hit',
          },
        );
        await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(
          value: settings,
          child: MaterialApp(
            theme: OpenHandTheme.light(settings.themePreset), darkTheme: OpenHandTheme.dark(settings.themePreset),
            themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
            locale: locale, supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.6), disableAnimations: true),
              child: SingleChildScrollView(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _ToolCallMetaRow(message: message, color: (brightness == Brightness.dark ? OpenHandTheme.dark(settings.themePreset) : OpenHandTheme.light(settings.themePreset)).colorScheme.onSecondaryContainer),
                  const SizedBox(height: 10),
                  KeyedSubtree(key: ValueKey(message.id), child: _ToolCallBody(message: message, sessionId: '布局检查', selectable: false)),
                  const SizedBox(height: 10),
                  OpenHandMessageActionChip(onPressed: () {}, icon: Icons.unfold_more_rounded, label: l10n.messageLoadFullContent),
                ]),
              )),
            )),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.textContaining(l10n.messageToolNameMachineTerminalExec), findsNWidgets(2));
        expect(find.text('MachineTerminalExec'), findsNothing);
        expect(find.text(l10n.messageCacheHit), findsOneWidget);
        await tester.tap(find.text(l10n.tlCallToolOutput));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(l10n.tlCallViewFullContent));
        await tester.tap(find.text(l10n.tlCallViewFullContent));
        await tester.pumpAndSettle();
        expect(find.text(l10n.tlCallViewInDialog), findsOneWidget);
        expect(find.byTooltip(l10n.codeBlockDownload), findsWidgets);
        expect(tester.takeException(), isNull, reason: '${locale.toLanguageTag()} / ${brightness.name} 不得溢出');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('完整内容弹窗：短内容收缩、长内容限高且窄屏大字号可用', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final width in [320.0, 960.0]) {
      tester.view.physicalSize = Size(width, 780);
      for (final scale in [1.0, 1.6]) {
        for (final locale in AppLocalizations.supportedLocales) {
          for (final count in [0, 1, 25, 200]) {
            final text = List.generate(count, (index) => '日志 $index：任务完成').join('\n');
            await tester.pumpWidget(MaterialApp(
              locale: locale, supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true), child: child!),
              home: Scaffold(body: _ToolContentFullDialog(label: '结果', content: _FormattedToolContent(text: text))),
            ));
            await tester.pumpAndSettle();
            final surface = find.byWidgetPredicate((widget) => widget is Material && widget.type == MaterialType.card).first;
            final height = tester.getSize(surface).height;
            expect(height, lessThanOrEqualTo(780 * .9 + 1));
            if (count <= 1) expect(height, lessThan(780 * .9 - 120), reason: '短内容不能铺满高度上限');
            if (count == 200) {
              final scroll = tester.widget<SingleChildScrollView>(find.descendant(
                of: find.byType(_ToolContentFullDialogBody), matching: find.byType(SingleChildScrollView)).first).controller!;
              expect(scroll.position.maxScrollExtent, greaterThan(0));
              scroll.jumpTo(scroll.position.maxScrollExtent);
              await tester.pump();
            }
            expect(tester.takeException(), isNull, reason: '$width / $scale / ${locale.toLanguageTag()} / $count 不得溢出');
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('完整内容弹窗：换行与内容更新平滑改变尺寸并遵守全局动效', (tester) async {
    tester.view.physicalSize = const Size(960, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await SettingsController.create(store: _ProbeSettingsStore(true, writable: true));
    addTearDown(settings.dispose);
    var source = '短内容';
    var reducedMotion = false;
    late StateSetter update;
    await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(value: settings,
      child: MaterialApp(locale: const Locale('zh'), supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
            child: _ToolContentFullDialog(label: '结果', content: _FormattedToolContent(text: source)));
        })),
      ),
    ));
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate((widget) => widget is Material && widget.type == MaterialType.card).first;
    final state = tester.state(find.byType(_ToolContentFullDialog));
    final shortHeight = tester.getSize(surface).height;
    update(() => source = List.filled(100, '长日志内容').join('\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final middleHeight = tester.getSize(surface).height;
    expect(middleHeight, greaterThan(shortHeight));
    expect(middleHeight, lessThan(780 * .9));
    await settings.updateDialogAnimationSettings(OpenHandMotionDefaults.disabled);
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, closeTo(780 * .9, 1));
    expect(tester.state(find.byType(_ToolContentFullDialog)), same(state));
    update(() => source = '换行检查：${'很长的内容 ' * 180}');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消换行'));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, lessThan(780 * .9 - 120));
    await settings.updateDialogAnimationSettings(OpenHandMotionDefaults.dialog.copyWith(durationMs: 640));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSize>(find.byType(AnimatedSize).first).duration, const Duration(milliseconds: 640));
    await tester.tap(find.byTooltip('自动换行'));
    await tester.pump(const Duration(milliseconds: 30));
    update(() => reducedMotion = true);
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.state(find.byType(_ToolContentFullDialog)), same(state));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('完整内容弹窗：文件切换取消加载时回退内容且拒绝迟到结果', (tester) async {
    final directory = Directory.systemTemp.createTempSync('tool-dialog-content-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/output.txt')..writeAsStringSync('文件内容');
    late StateSetter update;
    String? path = file.path;
    await tester.pumpWidget(MaterialApp(locale: const Locale('zh'), supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return _ToolContentFullDialog(label: '结果', content: const _FormattedToolContent(text: '回退正文'), fullContentFile: path);
      })),
    ));
    final state = tester.state<_ToolContentFullDialogState>(find.byType(_ToolContentFullDialog));
    expect(state._loadingFile, isTrue);
    update(() => path = null);
    await tester.pump();
    expect(state._loadingFile, isFalse);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(state._fileContent, isNull);
    expect(find.textContaining('回退正文'), findsWidgets);
    update(() => path = '${directory.path}/missing.txt');
    await tester.pump();
    for (var index = 0; index < 20 && state._loadingFile; index++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(state._loadingFile, isFalse);
    expect(state._fileContent, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('工具子板块：折叠复制原文、正文点击与工具栏尺寸', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    expect(_getFileExtensionForLanguage('../../异常路径'), '.txt');
    expect(_getFileExtensionForLanguage('patch'), '.patch');
    final source = List.generate(40, (index) => '日志第 $index 行：服务运行正常').join('\n');
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copiedText = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    var toggles = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'), supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Builder(builder: (context) => SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(12), child: _ExpandableToolSection(
          title: AppLocalizations.of(context)!.tlCallToolOutput,
          preview: '', expanded: true, onToggle: () => toggles++,
          expandedBuilder: (context) => _ToolOutputPanel(
            label: AppLocalizations.of(context)!.tlCallStdout,
            content: _FormattedToolContent(text: source, language: 'text'),
            theme: Theme.of(context), selectable: false,
          ),
        )),
      ))),
    ));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('fr'));
    expect(find.byTooltip(l10n.codeBlockDownload), findsOneWidget);
    expect(find.textContaining('Texte brut'), findsOneWidget);
    final panel = tester.widget<_HighlightedCodePanel>(find.byType(_HighlightedCodePanel));
    expect(panel.content.length, lessThan(source.length));
    await tester.tap(find.byTooltip('Copier'));
    await tester.pumpAndSettle();
    expect(copiedText, source, reason: '折叠复制必须保留后续日志');
    final actions = find.byType(_CodeBlockToolbarAction);
    final sizes = List.generate(actions.evaluate().length, (index) => tester.getSize(actions.at(index)));
    expect(sizes.every((size) => size.height == sizes.first.height), isTrue);
    expect(sizes.first.height, 28);
    final body = find.descendant(of: find.byType(_HighlightedCodePanel), matching: find.byType(RichText)).last;
    await tester.tap(body);
    expect(toggles, 0, reason: '正文点击不能传递给分区折叠操作');
    await tester.ensureVisible(find.text(l10n.tlCallToolOutput));
    await tester.tap(find.text(l10n.tlCallToolOutput));
    expect(toggles, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('消息控件：忙碌态阻止重复点击，外部工具保留原名', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'), supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Builder(builder: (context) {
        expect(openHandToolDisplayName(context, 'MachineTerminalExec'), '执行终端命令');
        expect(openHandToolDisplayName(context, 'mcp__server__Read'), 'mcp__server__Read');
        final external = AiSessionMessage.toolCall(id: '外部工具', content: '', createdAt: DateTime.utc(2026),
          metadata: {'tool_name': 'Read', 'tool_source': 'mcp', 'mcp_server_name': '自定义服务', 'mcp_tool_name': 'Read'});
        expect(_toolCallPresentation(context, external).displayName, '自定义服务 / Read');
        return OpenHandMessageActionChip(onPressed: () => taps++, busy: true, icon: Icons.copy, label: '加载中');
      })),
    ));
    await tester.tap(find.byType(OutlinedButton));
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox());
  });

  test('同长历史正文的局部差异不能串用 Markdown 缓存', () {
    final first = '${'前' * 300}甲${'后' * 800}';
    final second = '${'前' * 300}乙${'后' * 800}';
    expect(boundedTextFingerprint(first), boundedTextFingerprint(second));
    final cache = _MarkdownAstCache();
    final firstKey = _markdownAstCacheKeyForInputs(
      normalizedSource: first, parseKey: '历史', inlineSyntaxes: const [],
    );
    final secondKey = _markdownAstCacheKeyForInputs(
      normalizedSource: second, parseKey: '历史', inlineSyntaxes: const [],
    );
    final nodes = <md.Node>[md.Text(first)];
    cache.put(firstKey, nodes);
    expect(cache.get(secondKey), isNull);
    expect(cache.get(firstKey), same(nodes));
  });
  testWidgets('折叠渐隐：明暗主题尾部连续淡出并保持点击与退场', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      final background = dark ? const Color(0xff18181b) : const Color(0xffe3e5ef);
      final foreground = dark ? Colors.white : Colors.black;
      final captureKey = GlobalKey();
      var visible = true;
      var taps = 0;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return RepaintBoundary(key: captureKey, child: SizedBox(width: 200, height: 100,
            child: Stack(children: [
              Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque,
                onTap: () => taps++, child: ColoredBox(color: foreground))),
              _CollapsedPreviewFade(visible: visible, fadeColor: background),
            ])));
        },
      )))));
      await tester.pumpAndSettle();
      Future<List<double>> sampleFade() async {
        final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            final start = image.height - _collapsedMessageFadeHeight.round();
            return [for (final fraction in [0.0, .25, .6, .98])
              (bytes!.getUint8(((start + (_collapsedMessageFadeHeight * fraction).floor()) * image.width + image.width ~/ 2) * 4) / 255 - foreground.r) /
                (background.r - foreground.r)];
          } finally {
            image.dispose();
          }
        }))!;
      }
      final samples = await sampleFade();
      expect(samples.first, lessThan(.05), reason: '渐隐顶部不能出现半透明色块边界');
      for (var index = 1; index < samples.length; index++) {
        expect(samples[index], greaterThan(samples[index - 1] + .1), reason: '尾部必须连续过渡，不能整块等透明度遮挡');
      }
      expect(samples.last, inInclusiveRange(.65, .8));
      final rect = tester.getRect(find.byKey(captureKey));
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 8));
      expect(taps, 1, reason: '渐隐层不能拦截正文点击');
      update(() => visible = false);
      await tester.pumpAndSettle();
      expect((await sampleFade()).every((value) => value.abs() < .02), true,
        reason: '触底或展开后渐隐必须完整退场');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final plain in [false, true]) {
    for (final animated in [false, true]) {
      testWidgets('折叠预览同尺寸更新后仍能内部滚动，纯文本=$plain，动画=$animated', (tester) async {
        final original = _probeSession('折叠滚动-$plain', 1);
        final message = AiSessionMessage.reasoning(id: original.messages.first.id,
          createdAt: original.createdAt, content: List.filled(24, '甲：检查折叠内容的内部滚动。').join('\n\n'));
        final probe = _TranscriptProbe(tester, original.copyWith(messages: [message]));
        await probe.mount(size: const Size(800, 700), animated: animated);
        await probe.settle();
        if (plain) {
          final bubble = tester.state<_MessageBubbleState>(find.byType(_MessageBubble));
          bubble.setState(() => bubble._showRawContent = true);
          await probe.settle();
        }
        final previewFinder = find.byType(plain ? _PlainTextPreviewBody : _MarkdownPreviewBody);
        expect(previewFinder, findsOneWidget);
        final preview = tester.state(previewFinder) as _CollapsedPreviewBodyState;
        probe.update(original.copyWith(messages: [message.copyWith(content: message.content.replaceAll('甲', '乙'))]));
        await probe.settle();
        expect(preview._scrollController.position.maxScrollExtent, greaterThan(0));
        expect(tester.widget<_CollapsedPreviewFade>(find.descendant(of: previewFinder,
          matching: find.byType(_CollapsedPreviewFade))).visible, true);
        final outerOffset = probe.controller.offset;
        await tester.sendEventToBinding(PointerScrollEvent(
          position: tester.getCenter(previewFinder),
          scrollDelta: const Offset(0, 50),
        ));
        await probe.settle();
        expect(preview._scrollController.offset, greaterThan(0), reason: '滚轮必须能滚动折叠正文');
        preview._scrollController.jumpTo(0);
        await probe.settle();
        await tester.drag(previewFinder, const Offset(0, -65));
        await probe.settle();
        expect(preview._scrollController.offset, greaterThan(0), reason: '不能因测高缓存失效而禁止内部滚动');
        expect(probe.controller.offset, closeTo(outerOffset, 1), reason: '内部阅读不能拖动整条会话');
        for (var cycle = 0; cycle < 3; cycle++) {
          await tester.sendEventToBinding(PointerScrollEvent(
            position: tester.getCenter(previewFinder), scrollDelta: const Offset(0, 10000)));
          await probe.settle();
          final bottom = preview._scrollController.position.maxScrollExtent;
          expect(preview._scrollController.offset, closeTo(bottom, 1));
          expect(tester.widget<_CollapsedPreviewFade>(find.descendant(of: previewFinder,
            matching: find.byType(_CollapsedPreviewFade))).visible, false, reason: '触底后尾行不能被渐隐遮挡');
          await tester.sendEventToBinding(PointerScrollEvent(
            position: tester.getCenter(previewFinder), scrollDelta: const Offset(0, -60)));
          await probe.settle();
          expect(preview._scrollController.offset, lessThan(bottom - 30), reason: '触底后滚轮必须能反向滚动');
          expect(tester.widget<_CollapsedPreviewFade>(find.descendant(of: previewFinder,
            matching: find.byType(_CollapsedPreviewFade))).visible, true, reason: '反向滚动后恢复尾部渐隐');
          await tester.drag(previewFinder, const Offset(0, -2000));
          await probe.settle();
          expect(preview._scrollController.offset, closeTo(bottom, 1));
          await tester.drag(previewFinder, const Offset(0, 70));
          await probe.settle();
          expect(preview._scrollController.offset, lessThan(bottom - 30), reason: '触底后拖动必须能反向滚动');
        }
        final capsule = find.byType(_ReasoningMetaRow);
        for (var cycle = 0; cycle < 3; cycle++) {
          await tester.tap(capsule);
          await probe.settle();
          expect(preview._previewExpanded, true, reason: '胶囊必须驱动实际正文展开');
          probe.controller.jumpTo(probe.controller.position.minScrollExtent);
          await probe.settle();
          await tester.tap(capsule);
          await probe.settle();
          expect(preview._previewExpanded, false);
          await tester.drag(previewFinder, const Offset(0, -65));
          await probe.settle();
          expect(preview._scrollController.offset, greaterThan(0), reason: '重新折叠后仍能内部滚动');
        }
      });
    }
  }

  for (final plain in [false, true]) {
    testWidgets('折叠卡片：边界剩余滚轮继续推动会话，纯文本=$plain', (tester) async {
      final original = _probeSession('嵌套触底-$plain', 3);
      final message = AiSessionMessage.reasoning(id: original.messages.first.id,
        createdAt: original.createdAt,
        content: List.filled(24, '检查卡片滚到边界后仍能反向阅读。').join('\n\n'));
      final probe = _TranscriptProbe(tester, original.copyWith(messages: [message,
        for (final tail in original.messages.skip(1)) tail.copyWith(
          content: List.filled(30, '会话下方仍有其他消息。').join('\n\n'))]));
      await probe.mount(size: const Size(800, 500));
      await probe.settle();
      probe.controller.jumpTo(probe.controller.position.minScrollExtent);
      await probe.settle();
      if (plain) {
        final bubble = tester.state<_MessageBubbleState>(find.byType(_MessageBubble).first);
        bubble.setState(() => bubble._showRawContent = true);
        await probe.settle();
      }
      final previewFinder = find.byType(plain ? _PlainTextPreviewBody : _MarkdownPreviewBody).first;
      final preview = tester.state(previewFinder) as _CollapsedPreviewBodyState;
      final outerOffset = probe.controller.offset;
      final bottom = preview._scrollController.position.maxScrollExtent;
      expect(probe.controller.position.extentAfter, greaterThan(100));
      expect(bottom, greaterThan(60));
      preview._scrollController.jumpTo(bottom - 10);
      await probe.settle();
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(previewFinder), scrollDelta: const Offset(0, 40)));
      await probe.settle();
      expect(preview._scrollController.offset, closeTo(bottom, 1));
      expect(probe.controller.offset, closeTo(outerOffset + 30, 1),
        reason: '内部消费 10，剩余 30 必须继续滚动会话，不能丢失或重复');
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(previewFinder), scrollDelta: const Offset(0, -60)));
      await probe.settle();
      expect(preview._scrollController.offset, closeTo(bottom - 60, 1));
      expect(probe.controller.offset, closeTo(outerOffset + 30, 1),
        reason: '反向阅读仍先移动正文');
      probe.controller.jumpTo(probe.controller.position.minScrollExtent + 50);
      preview._scrollController.jumpTo(10);
      await probe.settle();
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(previewFinder), scrollDelta: const Offset(0, -40)));
      await probe.settle();
      expect(preview._scrollController.offset, 0);
      expect(probe.controller.offset, closeTo(probe.controller.position.minScrollExtent + 20, 1),
        reason: '触顶剩余位移也必须继续移动会话');
    }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
  }

  testWidgets('折叠卡片：同一次触控板手势跨过缓存区仍能到达会话尾部', (tester) async {
    final original = _probeSession('触控板跨越卡片', 30);
    final message = AiSessionMessage.reasoning(id: original.messages.first.id,
      createdAt: original.createdAt,
      content: List.filled(24, '读取思考正文后继续浏览后续消息。').join('\n\n'));
    final probe = _TranscriptProbe(tester, original.copyWith(messages: [message,
      ...original.messages.skip(1)]));
    probe.preserveViewportAfterUserScroll = false;
    await probe.mount(size: const Size(800, 500));
    await probe.settle();
    probe.state.setState(() {
      probe.state._windowStartIndex = 0;
      probe.state._syncRenderEntries();
    });
    await probe.settle();
    probe.controller.jumpTo(probe.controller.position.minScrollExtent);
    await probe.settle();
    probe.controller.jumpTo(probe.controller.position.minScrollExtent);
    await probe.settle();
    final previewFinder = find.byType(_MarkdownPreviewBody).first;
    expect(previewFinder.hitTestable(), findsOneWidget);
    final preview = tester.state(previewFinder) as _CollapsedPreviewBodyState;
    final point = tester.getCenter(previewFinder);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await gesture.panZoomStart(point);
    for (var step = 1; step <= 60; step++) {
      await gesture.panZoomUpdate(point, pan: Offset(0, -100.0 * step),
        timeStamp: Duration(milliseconds: 16 * step));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(probe.controller.position.extentAfter, lessThanOrEqualTo(1),
      reason: '内部触底后的手势不能因原卡片离开缓存区而中断');
    expect(preview.mounted, true, reason: '手势结束前保留原命中的滚动域');
    await gesture.panZoomUpdate(point, pan: const Offset(0, -5920),
      timeStamp: const Duration(milliseconds: 976));
    expect(preview._scrollController.position.extentAfter, greaterThan(30),
      reason: '同一次手势反向时仍能阅读原正文');
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 992));
    await probe.settle();
    expect(preview.mounted, false, reason: '手势结束后正常回收离屏卡片');
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  for (final kind in [AiSessionMessageKind.assistant, AiSessionMessageKind.user,
      AiSessionMessageKind.tool, AiSessionMessageKind.mcp, AiSessionMessageKind.skill,
      AiSessionMessageKind.compressionPoint]) {
    for (final format in kind == AiSessionMessageKind.compressionPoint
        ? ['markdown'] : ['markdown', 'plain_text', 'html']) {
      testWidgets('多类型折叠消息触边后可反向滚动，类型=$kind，格式=$format', (tester) async {
        final original = _probeSession('多类型-$kind-$format', 3);
        final content = format == 'html'
          ? '<article>${List.filled(120, '<p>甲：折叠内容需要保持滚动能力。</p>').join()}</article>'
          : List.filled(60, '甲：折叠内容需要保持滚动能力。').join('\n\n');
        final message = original.messages.first.copyWith(kind: kind,
          role: kind == AiSessionMessageKind.user ? AiSessionMessageRole.user : AiSessionMessageRole.assistant,
          content: content, metadata: {aiSessionMessageContentFormatKey: format});
        final session = original.copyWith(messages: [message,
          for (final tail in original.messages.skip(1)) tail.copyWith(
            content: List.filled(60, '会话下方的其他消息。').join('\n\n'))]);
        final probe = _TranscriptProbe(tester, session);
        await probe.mount(size: const Size(800, 500));
        await probe.settle();
        probe.controller.jumpTo(probe.controller.position.minScrollExtent);
        await probe.settle();
        final previewFinder = find.descendant(
          of: find.byWidgetPredicate((widget) => widget is _MessageBubble && widget.message.id == message.id),
          matching: find.byWidgetPredicate((widget) => widget is _PlainTextPreviewBody ||
            widget is _MarkdownPreviewBody || widget is _ProgressiveHtmlMessageBody));
        expect(previewFinder, findsOneWidget);
        probe.update(session.copyWith(messages: [message.copyWith(content: content.replaceAll('甲', '乙')),
          ...session.messages.skip(1)]));
        await probe.settle();
        final preview = tester.state(previewFinder) as _CollapsedPreviewBodyState;
        final outerOffset = probe.controller.offset;
        expect(probe.controller.position.extentAfter, greaterThan(60));
        expect(preview._scrollController.position.maxScrollExtent, greaterThan(0));
        for (var cycle = 0; cycle < 2; cycle++) {
          probe.controller.jumpTo(outerOffset);
          final bottom = preview._scrollController.position.maxScrollExtent;
          preview._scrollController.jumpTo(bottom - 10);
          await probe.settle();
          final point = tester.getCenter(previewFinder);
          final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await gesture.panZoomStart(point);
          await gesture.panZoomUpdate(point, pan: const Offset(0, -20),
            timeStamp: const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
          await gesture.panZoomUpdate(point, pan: const Offset(0, -60),
            timeStamp: const Duration(milliseconds: 32));
          await tester.pump(const Duration(milliseconds: 16));
          expect(preview._scrollController.offset, closeTo(bottom, 1));
          expect(probe.controller.offset, closeTo(outerOffset + 30, 1),
            reason: '各类型正文触边后都应只转交剩余位移');
          probe.rebuild(() {});
          await tester.pump(const Duration(milliseconds: 16));
          await gesture.panZoomUpdate(point, pan: const Offset(0, 20),
            timeStamp: const Duration(milliseconds: 48));
          expect(preview._scrollController.offset, lessThan(bottom - 30),
            reason: '父级重建后同一次触控板手势仍能反向阅读正文');
          await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 64));
          await probe.settle();
          probe.controller.jumpTo(outerOffset);
          preview._scrollController.jumpTo(bottom);
          await probe.settle();
          final up = await tester.createGesture(kind: PointerDeviceKind.trackpad);
          final upPoint = tester.getCenter(previewFinder);
          await up.panZoomStart(upPoint);
          await up.panZoomUpdate(upPoint, pan: const Offset(0, 80),
            timeStamp: const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
          await up.panZoomUpdate(upPoint, pan: const Offset(0, 160),
            timeStamp: const Duration(milliseconds: 32));
          expect(preview._scrollController.offset, lessThan(bottom - 30),
            reason: '抬手后从正文开始的新触控板手势必须能反向滚动');
          await up.panZoomEnd(timeStamp: const Duration(milliseconds: 48));
          await probe.settle();
          expect(probe.controller.offset, closeTo(outerOffset, 1),
            reason: '正文仍有可滚动内容时，外层会话保持位置');
        }
      }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
    }
  }

  test('长消息复用已有字符数，预览的元数据更新不覆盖全文统计', () {
    final message = _probeSession('字符统计', 1).messages.single.copyWith(
      content: '预览正文', characterCount: 300000,
      metadata: {aiSessionMessageContentPreviewMetadataKey: true},
    );
    expect(AiSessionMessage.fromJson(message.toJson()).characterCount, 300000);
    expect(message.copyWith(metadata: {'message_feedback': 'positive'}).characterCount, 300000);
    expect(message.copyWith(content: message.content).characterCount, 300000);
    expect(message.copyWith(content: '👨‍👩‍👧‍👦🇨🇳').characterCount, 2);
    expect(message.copyWith(characterCount: 0).characterCount, 0);
    for (final invalid in [null, -1, '无效']) {
      expect(AiSessionMessage.fromJson({
        ...message.toJson(), 'content': '👨‍👩‍👧‍👦🇨🇳', 'character_count': invalid,
      }).characterCount, 2);
    }
  });
  test('千条历史按窗口解码，大元数据后台加载保留正文与标记', () async {
    final directory = await Directory.systemTemp.createTemp('openhand_history_');
    final database = await DatabaseService.initialize(
      databasePath: '${directory.path}/history.db',
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    final store = AiSessionStore(sessionsDirectoryPath: directory.path);
    final session = _probeSession('history', 1000);
    final longContent = List.filled(3000, '**历史正文**\n').join();
    final largeMetadata = List.filled(30000, '工具输出').join();
    final tail = session.messages.last.copyWith(
      content: longContent,
      characterCount: longContent.length,
      metadata: {
        'tool_execution_stdout': largeMetadata,
        'request_payload': {'内部遥测': '按需恢复'},
      },
    );
    await store.save(session.copyWith(
      lastPromptMetadata: {'历史提示词': largeMetadata},
      metadata: {'会话审计': largeMetadata},
      messages: [
        ...session.messages.take(session.messages.length - 1), tail,
      ],
    ));
    final header = (await store.loadHeader(session.id))!;
    expect(header.messages.isEmpty, true);
    expect(header.messageTotalCount, 1000);
    expect(header.messageLoadState, AiSessionMessageLoadState.header);
    expect(header.lastPromptMetadata['历史提示词'], largeMetadata);
    expect(header.metadata['会话审计'], largeMetadata);
    final headers = await store.loadAllHeaders();
    expect(headers.issues.isEmpty, true);
    expect(headers.sessions.single.lastPromptMetadata, header.lastPromptMetadata);
    final window = (await store.loadSessionTailWindow(session.id, limit: 8))!;
    expect(window.lastPromptMetadata, header.lastPromptMetadata);
    expect(window.metadata, header.metadata);
    expect(window.messages.length, 8);
    expect(window.messageWindowStartIndex, 992);
    expect(window.messageTotalCount, 1000);
    expect(window.messages.last.content.length, 4096);
    expect(window.messages.last.metadata[aiSessionMessageContentPreviewMetadataKey], true);
    expect(window.messages.last.metadata.containsKey('tool_execution_stdout'), false);
    expect(window.messages.last.metadata[aiSessionMessageDeferredDisplayMetadataKey], true);
    expect(window.messages.last.metadata.containsKey('request_payload'), false);
    final full = (await store.loadMessage(session.id, tail.id))!;
    expect(full.content, longContent);
    expect(full.metadata['request_payload'], {'内部遥测': '按需恢复'});
    expect(full.metadata.containsKey(aiSessionMessageContentPreviewMetadataKey), false);
    // 预览上的轻量操作不能把数据库里的完整工具输出覆盖掉。
    await store.updateMessageMetadata(sessionId: session.id, messageId: tail.id,
      metadata: {...window.messages.last.metadata, 'message_feedback': 'like'});
    final persisted = (await store.loadMessage(session.id, tail.id))!;
    expect(persisted.metadata['tool_execution_stdout'], largeMetadata);
    expect(persisted.metadata['request_payload'], {'内部遥测': '按需恢复'});
    expect(persisted.metadata['message_feedback'], 'like');
    expect(persisted.metadata.containsKey(aiSessionMessageDeferredDisplayMetadataKey), false);

    final shortMessage = tail.copyWith(content: '短正文', characterCount: 3);
    final shortSession = _probeSession('short-metadata', 1).copyWith(messages: [shortMessage.copyWith(id: 'short-message')]);
    await store.save(shortSession);
    final shortWindow = (await store.loadSessionTailWindow(shortSession.id, limit: 6))!;
    expect(shortWindow.messageLoadState, AiSessionMessageLoadState.windowed);
    expect(shortWindow.messages.single.content, '短正文');
    expect(shortWindow.messages.single.metadata[aiSessionMessageContentPreviewMetadataKey], true);
    expect(shortWindow.messages.single.copyWith(content: '').isTranscriptRenderable, true);
    final previewPage = await store.loadMessages(shortSession.id, contentPreviewChars: 4096);
    expect(previewPage.messages.single.metadata.containsKey('tool_execution_stdout'), false);
    expect(previewPage.messages.single.metadata[aiSessionMessageDeferredTelemetryMetadataKey], true);

    final usage = AiToolUsagePromotionStore(filePath: '${directory.path}/usage.json');
    final controller = await AiSessionController.create(
      store: store, toolRuntimeService: _HistoryRuntime(), toolUsagePromotionStore: usage,
    );
    addTearDown(() async {
      await controller.shutdown();
      controller.dispose();
      await usage.shutdown();
    });
    await controller.selectSession(shortSession.id);
    await controller.ensureSessionMessageWindowHydrated(shortSession.id);
    final audited = await controller.loadFullSessionMessageMetadata(shortSession.id, 'short-message');
    expect(audited['tool_execution_stdout'], largeMetadata);
    expect(audited['request_payload'], {'内部遥测': '按需恢复'});
    expect(audited.containsKey(aiSessionMessageDeferredDisplayMetadataKey), false);
    final hydrated = await controller.loadFullSessionMessageContent(shortSession.id, 'short-message');
    expect(hydrated!.metadata['tool_execution_stdout'], largeMetadata);
    expect(hydrated.metadata.containsKey(aiSessionMessageContentPreviewMetadataKey), false);
    final nested = <String, Object?>{'tool_arguments': {'输出': largeMetadata}, 'tool_call_id': '配对标识'};
    final previewMetadata = aiSessionMessagePreviewMetadata(nested);
    expect(previewMetadata.containsKey('tool_arguments'), false);
    expect(previewMetadata['tool_call_id'], '配对标识');
    expect(previewMetadata[aiSessionMessageContentPreviewMetadataKey], true);
    final small = <String, Object?>{'tool_arguments': {'路径': '/tmp'}};
    expect(identical(aiSessionMessagePreviewMetadata(small), small), true);
    // 损坏单行不能让后台队列丢失后续正常消息。
    await database.database.update('messages', {'metadata_json': '{损坏'},
      where: 'id = ?', whereArgs: ['history-998']);
    final page = await store.loadMessages(session.id, offset: 998, limit: 2);
    expect(page.messages.map((message) => message.id), ['history-998', 'history-999']);
    expect(page.messages.first.metadata, const <String, Object?>{});
    expect(page.messages.last.metadata['tool_execution_stdout'], largeMetadata);
  });

  testWidgets('历史加载：读取超时释放状态，迟到页不回写，重试共享任务', (tester) async {
    late Directory directory;
    late AiSessionController controller;
    late AiToolUsagePromotionStore usage;
    final complete = _probeSession('分页回归', 30);
    late _HistoryStore store;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('openhand_history_timeout_');
      store = _HistoryStore(complete.copyWith(
        messages: complete.messages.sublist(20),
        messageLoadState: AiSessionMessageLoadState.windowed,
        messageWindowStartIndex: 20,
        messageTotalCount: 30,
      ), directory.path);
      usage = AiToolUsagePromotionStore(filePath: '${directory.path}/usage.json');
      controller = await AiSessionController.create(
        store: store, toolRuntimeService: _HistoryRuntime(),
        toolUsagePromotionStore: usage,
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await controller.shutdown();
        controller.dispose();
        await usage.shutdown();
        await directory.delete(recursive: true);
      });
    });
    Future<AiSession?>? reentrant;
    controller.addListener(() {
      if (controller.isSessionMessagesHydrating(complete.id)) {
        reentrant = controller.loadOlderSessionMessages(complete.id);
      }
    });
    final first = controller.loadOlderSessionMessages(complete.id);
    await tester.pump();
    expect(reentrant, same(first), reason: '同步监听器重入也必须共享请求');
    expect(store.requests.length, 1);
    await tester.pump(const Duration(seconds: 16));
    expect(await first, isNull);
    expect(controller.isSessionMessagesHydrating(complete.id), false);
    expect(controller.sessions.single.messageWindowStartIndex, 20);

    final retry = controller.loadOlderSessionMessages(complete.id);
    expect(controller.loadOlderSessionMessages(complete.id), same(retry));
    await tester.pump();
    expect(store.requests.length, 2);
    final page = AiSessionMessagePage(messages: complete.messages.sublist(8, 21),
      offset: 8, totalCount: 30, hasMore: true);
    store.requests.first.complete(page);
    await tester.pump();
    expect(controller.sessions.single.messageWindowStartIndex, 20,
      reason: '超时后的迟到响应不能更新消息');
    expect(controller.isSessionMessagesHydrating(complete.id), true,
      reason: '旧请求不能清除新请求的忙碌状态');
    store.requests.last.complete(page);
    await tester.pump();
    final loaded = await retry;
    expect(loaded!.messageWindowStartIndex, 8);
    expect(loaded.messages.map((message) => message.id),
      complete.messages.skip(8).map((message) => message.id));
    expect(controller.isSessionMessagesHydrating(complete.id), false);

    final broken = controller.loadOlderSessionMessages(complete.id);
    await tester.pump();
    store.requests.last.complete(AiSessionMessagePage(
      messages: complete.messages.take(3).toList(), offset: 0,
      totalCount: 30, hasMore: true,
    ));
    await tester.pump();
    expect(await broken, isNull, reason: '不相接的分页必须拒绝');
    expect(controller.sessions.single.messageWindowStartIndex, 8);
    expect(controller.isSessionMessagesHydrating(complete.id), false);

    final previousReads = store.requests.length;
    for (var i = 0; i < 4; i++) {
      final stalled = controller.loadOlderSessionMessages(complete.id);
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      expect(await stalled, isNull);
    }
    final queued = controller.loadOlderSessionMessages(complete.id);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(await queued, isNull);
    expect(store.requests.length - previousReads, 4,
      reason: '连续超时重试不能突破底层读取并发上限');
    for (final request in store.requests.skip(previousReads)) {
      request.complete(AiSessionMessagePage(
        messages: complete.messages.take(9).toList(), offset: 0,
        totalCount: 30, hasMore: true,
      ));
    }
    await tester.pump();
    expect(store.requests.length - previousReads, 4,
      reason: '超时的排队任务不能重新启动读取');
    expect(controller.sessions.single.messageWindowStartIndex, 8);
  });

  test('密集 Markdown 缓存同时限制单条与总节点数', () {
    final cache = _MarkdownAstCache();
    _MarkdownAstKey key(String source) => (source: source, parseKey: '', syntaxSignature: 0);
    final nodes = List<md.Node>.generate(1500, (_) => md.Element.text('p', '内容'));
    for (var index = 0; index < 9; index++) cache.put(key('正文-$index'), nodes);
    expect(cache._astNodes, lessThanOrEqualTo(_MarkdownAstCache._maxAstNodes));
    expect(cache.get(key('正文-0')), isNull, reason: '总节点超限时淘汰最旧正文');
    expect(cache.get(key('正文-8')), same(nodes));
    cache.put(key('过密表格'), List<md.Node>.generate(6001, (_) => md.Text('单元格')));
    expect(cache.get(key('过密表格')), isNull, reason: '单条节点超限时不长期保留语法树');
    cache.put(key('正文-8'), [md.Text('精简正文')]);
    expect(cache._astNodes, 21001, reason: '覆盖旧条目时释放旧节点预算');
  });

  test('后台 Markdown 保留表格、公式、路径及媒体语法，失效任务不启动', () async {
    final source = normalizeOpenHandMarkdownSource(
      '| 名称 | 数值 |\n| --- | --- |\n| **内容** | 42 |\n\n'
      r'$x^2$ /tmp/openhand-check.txt [音频](/tmp/openhand-check.mp3)',
    );
    final syntaxes = withOpenHandMarkdownMathInlineSyntaxes([
      MessagePathCodeSyntax(candidateRoots: const ['/tmp']),
      MessageFilePathSyntax(candidateRoots: const ['/tmp']),
      _GeneratedMediaLinkSyntax.byExtension(pathRoots: const ['/tmp']),
    ]);
    String describe(List<md.Node> nodes) => nodes.map((node) => node is md.Element
      ? '${node.tag}:${node.attributes}:${describe(node.children ?? [])}'
      : node.textContent).join('|');
    final expected = parseOpenHandMarkdown(source, inlineSyntaxes: syntaxes);
    final actual = await parseOpenHandMarkdownOffThread(source,
      inlineSyntaxes: syntaxes, isValid: () => true);
    expect(describe(actual!), describe(expected));
    expect(await parseOpenHandMarkdownOffThread(source,
      inlineSyntaxes: syntaxes, isValid: () => false), isNull);
  });

  test('后台解析错误释放队列，后续消息仍可完成', () async {
    await expectLater(parseOpenHandMarkdownOffThread('@解析失败',
      inlineSyntaxes: [_FailingMarkdownSyntax()], isValid: () => true),
      throwsA(isA<RemoteError>()));
    final nodes = await parseOpenHandMarkdownOffThread('**后续正文**',
      inlineSyntaxes: const [], isValid: () => true);
    expect(nodes!.single.textContent, '后续正文');
  });

  testWidgets('长正文冷解析移出界面线程，更新与卸载不接收旧结果', (tester) async {
    final initial = '**旧正文** ${'正文 ' * 3000}';
    final latest = '**最新正文** ${'新内容 ' * 2500}';
    late StateSetter rebuild;
    var content = initial;
    await tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(
      child: StatefulBuilder(builder: (_, setState) {
        rebuild = setState;
        return _SafeMarkdownRichBody(_SafeMarkdownBody(data: content,
          styleSheet: MarkdownStyleSheet(), deferInitialParse: false));
      }),
    ))));
    final state = tester.state<_SafeMarkdownBodyState>(find.byType(_SafeMarkdownRichBody));
    expect(state._lastData, isNull, reason: '关闭首次延迟也不能同步解析长正文');
    rebuild(() => content = latest);
    for (var frame = 0; frame < 100 && state._lastData != latest; frame++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(state._lastData, latest);
    expect(state._workerAst, isNotNull, reason: '必须使用真实后台解析结果');
    expect(state._workerFailedKey, isNull);
    rebuild(() => content = '**卸载前正文** ${'更多内容 ' * 2000}');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('失效富文本任务立即取消', (tester) async {
    final scheduler = RichContentFrameScheduler();
    var executed = 0;
    final cancellations = <VoidCallback>[
      for (var index = 0; index < 1000; index++)
        scheduler.schedule(() => executed += 1),
    ];
    for (final cancel in cancellations) {
      cancel();
    }
    scheduler.schedule(() => executed += 1);
    await tester.pump();
    expect(executed, 1);
    scheduler.clear();
  });

  testWidgets('淘汰回调同步入队仍遵守容量上限', (tester) async {
    final scheduler = RichContentFrameScheduler(maxPending: 1);
    final executed = <String>[];
    var dropped = 0;
    scheduler.schedule(() => executed.add('旧任务'), onDropped: () {
      scheduler.schedule(() => executed.add('回调新任务'));
    });
    scheduler.schedule(() => executed.add('超限任务'), onDropped: () => dropped++);
    await tester.pump();
    await tester.pump();
    expect(executed, ['回调新任务']);
    expect(dropped, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    scheduler.clear();
  });

  testWidgets('淘汰回调失败不遗留空队列或导致逐帧错误', (tester) async {
    final scheduler = RichContentFrameScheduler(maxPending: 1);
    scheduler.schedule(() {}, onDropped: () => throw StateError('模拟淘汰失败'));
    expect(() => scheduler.schedule(() {}), throwsStateError);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    var executed = 0;
    final cancel = scheduler.schedule(() => executed++);
    await tester.pump();
    cancel();
    cancel();
    expect(executed, 1, reason: '任务完成后的重复取消不能影响后续调度');
    scheduler.clear();
  });

  testWidgets('滚动静默期富文本队列不逐帧空转，静默结束后继续执行', (tester) async {
    final activity = TranscriptScrollActivity();
    addTearDown(activity.dispose);
    final scheduler = RichContentFrameScheduler(isPaused: () => activity.value);
    var executed = 0;
    activity.markActive();
    scheduler.schedule(() => executed += 1);
    await tester.pump();
    expect(executed, 0);
    expect(tester.binding.hasScheduledFrame, false, reason: '暂停期间不能逐帧空转');
    await tester.pump(TranscriptScrollActivity.settleDelay);
    await tester.pump();
    expect(executed, 1);
  });

  testWidgets('前方布局收缩后富文本进入视口，无滚动也能继续渲染', (tester) async {
    final spacer = ValueNotifier<double>(1200);
    addTearDown(spacer.dispose);
    var built = 0;
    final deferred = DeferredRichContent(
      placeholder: const SizedBox(height: 60),
      builder: (_) { built++; return const Text('已渲染正文'); },
    );
    await tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(
      child: Column(children: [
        ValueListenableBuilder<double>(valueListenable: spacer,
          builder: (_, height, _) => SizedBox(height: height)),
        deferred,
      ]),
    ))));
    await tester.pump();
    expect(built, 0);
    spacer.value = 0;
    for (var frame = 0; frame < 6; frame++) await tester.pump();
    expect(built, 1);
    expect(find.text('已渲染正文'), findsOneWidget);
  });

  for (final shortContent in [false, true]) {
    testWidgets('已挂载历史正文批量补齐时逐帧解析，短正文=$shortContent', (tester) async {
      var revision = 0;
      late StateSetter rebuild;
      String source(int index) => '**历史-$index-$revision** ${'正文 ' * (shortContent ? 30 : 300)}';
      await tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: StatefulBuilder(
        builder: (_, setState) {
          rebuild = setState;
          return SingleChildScrollView(child: Column(children: [
            for (var index = 0; index < 4; index++)
              _SafeMarkdownRichBody(_SafeMarkdownBody(
                data: source(index), styleSheet: MarkdownStyleSheet(),
                deferInitialParse: shortContent,
              )),
          ]));
        },
      ))));
      await tester.pumpAndSettle();
      final states = tester.stateList<_SafeMarkdownBodyState>(
        find.byType(_SafeMarkdownRichBody)).toList();
      final oldTrees = states.map((state) => state._children).toList();
      rebuild(() => revision++);
      await tester.pump();
      expect(states.where((state) => state._lastData == state.config.data).length, 1);
      for (var index = 1; index < states.length; index++) {
        expect(identical(states[index]._children, oldTrees[index]), true);
      }
      for (var completed = 2; completed <= states.length; completed++) {
        await tester.pump();
        expect(states.where((state) => state._lastData == state.config.data).length, completed);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('消息 Markdown 的本地 SVG 保持矢量渲染，图片加载器切换与关闭不接收迟到结果', (tester) async {
    final folder=Directory.systemTemp.createTempSync('openhand-svg-check-');
    addTearDown(()=>folder.deleteSync(recursive:true));
    final file=File('${folder.path}/image.svg')..writeAsStringSync(
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16"/></svg>');
    await tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home:Scaffold(body:_SafeMarkdownBody(
      data:'![本地矢量图](${file.uri})',styleSheet:MarkdownStyleSheet(),
    ))));
    for (var frame=0;frame<3;frame++) {
      await tester.pump();
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));
    }
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture),findsOneWidget);
    expect(tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader,isA<SvgFileLoader>());
    expect(find.byType(Image),findsNothing);
    await tester.pumpWidget(const SizedBox());
    final settings=await SettingsController.create(store:_ProbeSettingsStore(false));
    addTearDown(settings.dispose);
    final pending=Completer<Uint8List>();
    final loaded=Completer<Uint8List>();
    var loads=0;
    final images=[
      OpenHandGalleryImage(uri:Uri.parse('https://example.invalid/old.png'),title:'旧图片',loadBytes:(){loads++;return pending.future;}),
      OpenHandGalleryImage(uri:Uri.parse('https://example.invalid/new.png'),title:'新图片',loadBytes:(){loads++;return loaded.future;}),
    ];
    await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(value:settings,
      child:MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home:Scaffold(body:_ImagePreviewDialog.gallery(images:images,initialIndex:0,canLocate:false)))));
    await tester.pump();
    final state=tester.state<_ImagePreviewDialogState>(find.byType(_ImagePreviewDialog));
    state._navigate(1);await tester.pump();
    pending.complete(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
    await tester.pump();
    expect(state._imageSize.size,isNull);
    expect(state._index,1);expect(loads,2);
    expect(find.byType(Image),findsNothing);
    await tester.pumpWidget(const SizedBox());
    loaded.completeError(const FormatException('模拟关闭后加载失败'));
    await tester.pump();
    expect(tester.takeException(),isNull);
  });

  testWidgets('富文本等待解析时不暴露 Markdown 源码', (tester) async {
    await tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _SafeMarkdownBody(
      data: '**待渲染正文**', styleSheet: MarkdownStyleSheet(),
    ))));
    expect(find.text('**待渲染正文**'), findsNothing);
    for (var frame = 0; frame < 6; frame++) await tester.pump();
    expect(find.byType(_RichContentPendingPreview), findsNothing);
  });

  for (final kind in [AiSessionMessageKind.toolCall, AiSessionMessageKind.hook]) {
    for (final inputFirst in [false, true]) {
      testWidgets('工具完整内容：$kind 子板块按需读取、去重并支持重试，入参优先=$inputFirst', (tester) async {
        final original = _probeSession('工具按需读取', 1);
        final output = '${List.filled(24, '完整输出记录${'内容' * 400}').join('\n')}\n输出末尾标记';
        final full = original.messages.single.copyWith(kind: kind, metadata: {
          'tool_name': 'MachineTerminalExec', 'tool_execution_status': 'success',
          'tool_arguments': '{"command":"systemctl status"}',
          'tool_execution_stdout': output,
        });
        final preview = full.copyWith(metadata: aiSessionMessagePreviewMetadata(full.metadata));
        expect(preview.metadata.containsKey('tool_execution_stdout'), false);
        final probe = _TranscriptProbe(tester, original.copyWith(messages: [preview]));
        final requests = <Completer<AiSessionMessage?>>[];
        probe.ai.loadFull = (sessionId, messageId) {
          expect(sessionId, original.id);
          expect(messageId, full.id);
          final request = Completer<AiSessionMessage?>();
          requests.add(request);
          return request.future;
        };
        await probe.mount(animated: true);
        await probe.settle();
        final l10n = AppLocalizations.of(tester.element(find.byType(_ToolCallBody)))!;
        expect(find.text(l10n.messageLoadFullContent), findsNothing);
        expect(requests.isEmpty, true, reason: '默认折叠不能提前读取完整记录');
        final titles = inputFirst
            ? [l10n.tlCallToolInput, l10n.tlCallToolOutput]
            : [l10n.tlCallToolOutput, l10n.tlCallToolInput];
        await tester.tap(find.text(titles.first));
        await probe.settle();
        expect(requests.length, 1);
        expect(find.text(l10n.messageLoadingContent), findsOneWidget);
        expect(find.text(l10n.tlCallThereIsNoToolOutputYet), findsNothing);
        await tester.tap(find.text(titles.last));
        await probe.settle();
        expect(requests.length, 1, reason: '两个子板块共享一次正在进行的读取');
        final busyButtons = tester.widgetList<OutlinedButton>(find.ancestor(
          of: find.text(l10n.messageLoadingContent), matching: find.byType(OutlinedButton)));
        expect(busyButtons.length, 2);
        expect(busyButtons.every((button) => button.onPressed == null), true);
        requests.single.complete(null);
        await probe.settle();
        expect(find.text(l10n.messageFullContentFailed), findsNWidgets(2));
        await tester.ensureVisible(find.text(l10n.tlCallViewFullContent).first);
        await tester.tap(find.text(l10n.tlCallViewFullContent).first);
        await probe.settle();
        expect(requests.length, 2, reason: '失败后可以从原子板块重试');
        probe.update(probe.session.copyWith(messages: [full]));
        requests.last.complete(full);
        await probe.settle();
        expect(find.text(l10n.messageLoadFullContent), findsNothing);
        expect(find.text(l10n.messageFullContentFailed), findsNothing);
        final stdout = find.byWidgetPredicate((widget) => widget is _ToolOutputPanel && widget.label == l10n.tlCallStdout);
        expect(tester.widget<_ToolOutputPanel>(stdout).content.text, output);
        final viewFull = find.descendant(of: stdout, matching: find.text(l10n.tlCallViewFullContent));
        await tester.ensureVisible(viewFull);
        await tester.tap(viewFull);
        await probe.settle();
        expect(find.text(l10n.tlCallViewInDialog), findsOneWidget);
        expect(tester.state<_ToolOutputPanelState>(stdout)._isExpanded, true);
      });
    }
  }

  for (final status in ['', 'failed']) {
    testWidgets('工具完整内容：未执行或失败的预览仍保留子板块入口，状态=$status', (tester) async {
      final original = _probeSession('工具状态入口', 1);
      final message = original.messages.single.copyWith(kind: AiSessionMessageKind.toolCall, metadata: {
        'tool_name': 'MachineTerminalExec', 'tool_execution_status': status,
        aiSessionMessageContentPreviewMetadataKey: true,
      });
      final probe = _TranscriptProbe(tester, original.copyWith(messages: [message]));
      await probe.mount();
      await probe.settle();
      expect(find.text('加载完整内容'), findsNothing);
      expect(find.byType(_ExpandableToolSection), findsNWidgets(2));
      if (status.isNotEmpty) {
        await tester.tap(find.text('工具入参'));
        await probe.settle();
      }
      expect(find.text('查看完整内容'), findsWidgets);
    });
  }

  for (final html in [false, true]) {
    testWidgets('离屏真实富文本进入视口后才解析，HTML=$html', (tester) async {
      final controller = ScrollController();
      var richBuildCount = 0;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 320,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    const SizedBox(height: 1200),
                    if (html)
                      _DeferredPreparedHtmlBody(
                        data: '<p>视口测试 <strong>完整富文本</strong></p>',
                        backgroundColor: Colors.white,
                        builder: (prepared) {
                          richBuildCount += 1;
                          return Text(prepared.healedHtml);
                        },
                      )
                    else
                      _SafeMarkdownBody(
                        data: '**视口测试完整富文本**',
                        styleSheet: MarkdownStyleSheet(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(richBuildCount, 0);
      expect(find.byType(_SafeMarkdownRichBody), findsNothing);
      expect(find.byType(_RichContentPendingPreview), findsOneWidget);

      controller.jumpTo(controller.position.maxScrollExtent);
      for (var frame = 0; frame < 6; frame++) await tester.pump();
      if (html) {
        expect(richBuildCount, 1);
      } else {
        final state = tester.state<_SafeMarkdownBodyState>(find.byType(_SafeMarkdownRichBody));
        expect(state._lastData, '**视口测试完整富文本**');
      }
      expect(find.byType(_RichContentPendingPreview), findsNothing);
    });
  }

  for (final creation in [false, true]) {
    for (final unmount in [false, true]) {
      testWidgets('错误卡片退场可取消，创作=$creation，卸载=$unmount', (tester) async {
        final bannerKey = GlobalKey<_SessionErrorBannerState>();
        var dismissed = 0;
        final error = AiSessionErrorRecord(
          id: '动效错误检查', createdAt: DateTime.utc(2026),
          stage: 'chat', message: '请求失败',
        );
        Widget host(bool disabled) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: MediaQuery(
            data: MediaQueryData(disableAnimations: disabled),
            child: creation
                ? _CreationFailureCard(
                    request: const AiCreationRequest(mode: AiCreationMode.image),
                    error: error,
                    onDismiss: () async { dismissed++; },
                  )
                : _SessionErrorBanner(
                    key: bannerKey, error: error,
                    onDismiss: () { dismissed++; },
                  ),
          )),
        );
        await tester.pumpWidget(host(false));
        await tester.pump(const Duration(milliseconds: 220));
        expect(tester.takeException(), isNull);
        var finished = false;
        final closing = creation
            ? tester.state<_CreationFailureCardState>(find.byType(_CreationFailureCard))._handleDismiss()
            : bannerKey.currentState!._handleDismiss();
        unawaited(closing.then((_) { finished = true; }));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpWidget(unmount ? const SizedBox.shrink() : host(true));
        await tester.pump();
        expect(finished, true, reason: '取消 Ticker 后不能永久挂起关闭操作');
        expect(dismissed, unmount ? 0 : 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final phase in [
    _TranscriptInitialRevealPhase.dismissingPlaceholder,
    _TranscriptInitialRevealPhase.revealingContent,
  ]) {
    for (final disableSettings in [false, true]) {
      testWidgets('会话加载：揭示途中禁用动画不会停留在加载界面，阶段=$phase，全局设置=$disableSettings', (tester) async {
        final probe = _TranscriptProbe(tester, _probeSession('暂停揭示', 12, mixed: true));
        await probe.mount(animated: true, writable: disableSettings);
        for (var frame = 0; frame < 80 && probe.state._initialRevealPhase != phase; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(probe.state._initialRevealPhase, phase);
        if (disableSettings) {
          expect(await probe.settings.updatePageAnimationSettings(OpenHandMotionDefaults.disabled), true);
        } else {
          probe.rebuild(() => probe.tickerEnabled = false);
        }
        await probe.settle();
        probe.expectFilled();
        expect(find.byType(_TranscriptHydratingPlaceholder), findsNothing);
        if (disableSettings) {
          expect(await probe.settings.updatePageAnimationSettings(OpenHandMotionDefaults.page), true);
        } else {
          probe.rebuild(() => probe.tickerEnabled = true);
        }
        await probe.settle();
        probe.expectFilled();
      });
    }
  }

  for (final animated in [false, true]) {
    for (final initialPixels in <double?>[0, null]) {
      testWidgets('会话加载：滚动位置尚未就绪时仍完成揭示，动画=$animated，初始位置=$initialPixels', (tester) async {
        final probe = _TranscriptProbe(tester, _probeSession('延迟测量', 12, mixed: true));
        await probe.mount(animated: animated);
        final measured = probe.controller.position;
        // 复现会话切换时已 attach、尚未 applyContentDimensions 的原生位置。
        final pending = ScrollPositionWithSingleContext(
          physics: measured.physics, context: measured.context, keepScrollOffset: false,
          initialPixels: initialPixels,
        );
        probe.controller.detach(measured);
        probe.controller.attach(pending);
        try {
          expect(pending.hasPixels, initialPixels != null);
          expect(pending.hasContentDimensions, false);
          expect(probe.state._capturePrependAnchor(), isNull);
          expect(probe.state._scrollNearRenderEntryIndex(0), false);
          final anchor = _TranscriptViewportAnchor(
            messageId: probe.session.messages.last.id, viewportOffset: 0,
          );
          expect(probe.state._restorePrependAnchorOutcome(anchor), _AnchorRestoreOutcome.unmeasurable);
          probe.state._startPrependAnchorStabilization(anchor, settleFrameCount: 3);
          for (var frame = 0; frame < 80; frame++) {
            await tester.pump(const Duration(milliseconds: 40));
            expect(tester.takeException(), isNull, reason: '未测量的位置不能读取滚动边界，第 $frame 帧');
            if (frame == 0) {
              expect(probe.state._pendingPrependAnchor, isNotNull,
                reason: '缺少尺寸不能被误判为用户滚动并取消锚点恢复');
            }
          }
          expect(probe.state._pendingPrependAnchor, isNull, reason: '不可测量的锚点仍受帧数上限约束');
          expect(probe.state._initialRevealPhase, _TranscriptInitialRevealPhase.ready,
            reason: '测量未就绪不能阻断占位退场和内容揭示');
          expect(find.byType(_TranscriptHydratingPlaceholder), findsNothing);
        } finally {
          probe.controller.detach(pending);
          probe.controller.attach(measured);
          pending.dispose();
        }
        // 新视口完成测量后会发送尺寸通知，继续补齐可见消息。
        tester.view.physicalSize = const Size(1450, 950);
        await probe.settle();
        probe.expectFilled();
        expect(tester.binding.hasScheduledFrame, false, reason: '稳定后不能无限调度定位帧');
      });
    }

    testWidgets('会话加载：首次打开和切换短会话按视口填充，动画=$animated', (tester) async {
      final probe = _TranscriptProbe(tester, _probeSession('首屏', 30));
      await probe.mount(animated: animated);
      await probe.settle();
      probe.expectFilled();
      expect(
        probe.state._renderEntries.length,
        lessThan(30),
        reason: '只补足视口，不一次物化整条会话',
      );
      for (final count in [1, 4, 8, 13]) {
        probe.update(_probeSession('切换$count', count));
        await probe.settle();
        probe.expectFilled();
        if (count <= 4) {
          expect(probe.state._viewportOffsetForMessage('切换$count-0'), closeTo(0, 1));
          expect(probe.controller.position.minScrollExtent, closeTo(0, 1));
          expect(probe.controller.position.maxScrollExtent, closeTo(0, 1));
        }
      }
      final pixels = probe.controller.offset;
      await tester.pump(const Duration(seconds: 2));
      expect(probe.controller.offset, pixels, reason: '稳定后不得继续纠正位置');
    });
  }

  for (final animated in [false, true]) {
    testWidgets('用户消息起排、流式增高及视口变化保持顶部布局，动画=$animated', (tester) async {
      final original = _probeSession('顶部布局', 1);
      final user = AiSessionMessage.user(
        id: '用户请求', content: '检查消息排列', createdAt: original.createdAt,
      );
      final probe = _TranscriptProbe(tester, original.copyWith(messages: [user]));
      await probe.mount(size: const Size(360, 300), animated: animated);
      await probe.settle();
      expect(probe.state._viewportOffsetForMessage(user.id), closeTo(0, 1));
      expect(
        probe.controller.position.minScrollExtent,
        closeTo(0, 1),
        reason: '首条消息上方不得存在负向滚动范围',
      );
      await tester.drag(
        find.byKey(const ValueKey<String>('session-transcript-list')),
        const Offset(0, 180),
      );
      await probe.settle();
      expect(
        probe.controller.offset,
        closeTo(0, 1),
        reason: '只有首条消息时继续上滑不得出现空白区域',
      );
      expect(probe.controller.position.maxScrollExtent, closeTo(0, 1));
      final reply = AiSessionMessage.assistant(
        id: '流式回复', content: '开始处理', createdAt: original.createdAt,
      );
      probe.update(probe.session.copyWithTailMessage(reply, append: true));
      await probe.settle();
      expect(probe.state._viewportOffsetForMessage(user.id), closeTo(0, 1));
      expect(probe.state._viewportOffsetForMessage(reply.id), greaterThan(0));
      probe.update(probe.session.copyWithTailMessage(reply.copyWith(
        content: List.filled(10, '正在逐项核对消息展示与滚动状态。').join('\n\n'),
      ), append: false));
      await probe.settle();
      expect(
        probe.controller.position.minScrollExtent,
        closeTo(0, 1),
        reason: '首条消息增高后仍不得出现负向滚动范围',
      );
      expect(probe.controller.position.maxScrollExtent - probe.controller.position.minScrollExtent,
        greaterThan(0), reason: '内容超出视口后应允许滚动');
      probe.controller.jumpTo(probe.controller.position.maxScrollExtent);
      await probe.settle();
      tester.view.physicalSize = const Size(1200, 1000);
      await probe.settle();
      expect(probe.state._viewportOffsetForMessage(user.id), closeTo(0, 1));
      expect(probe.controller.position.maxScrollExtent, closeTo(0, 1));
      probe.update(probe.session.copyWith(messages: [user]));
      await probe.settle();
      expect(probe.state._viewportOffsetForMessage(user.id), closeTo(0, 1));
      expect(probe.controller.position.minScrollExtent, closeTo(0, 1));
      await tester.drag(find.byKey(const ValueKey<String>('session-transcript-list')), const Offset(0, 180));
      await probe.settle();
      expect(probe.controller.offset, closeTo(0, 1), reason: '短记录不能拖出空白滚动区域');
    });
  }

  for (final count in [3, 4, 8]) {
    testWidgets('超屏会话滚回首条不留下顶部空白，消息数=$count', (tester) async {
      final session = _probeSession('首条边界', count);
      final probe = _TranscriptProbe(tester, session.copyWith(messages: [
        for (final message in session.messages)
          AiSessionMessage.user(
            id: message.id,
            createdAt: message.createdAt,
            content: List.filled(5, '检查消息到达顶部时的实际位置。').join('\n'),
          ),
      ]));
      await probe.mount(size: const Size(800, 500));
      await probe.settle();
      for (var page = 0; page < count && probe.state._windowStartIndex > 0; page++) {
        final reveal = probe.state._revealOlderMessages();
        await probe.settle();
        await reveal;
      }
      expect(probe.state._windowStartIndex, 0);
      for (final height in [500.0, 700.0, 400.0]) {
        tester.view.physicalSize = Size(800, height);
        await probe.settle();
        probe.controller.jumpTo(probe.controller.position.minScrollExtent);
        await probe.settle();
        expect(probe.state._viewportOffsetForMessage(session.messages.first.id),
          closeTo(0, 1), reason: '滚动上界必须对应首条消息顶部，视口高度=$height');
        final top = probe.controller.offset;
        await tester.drag(find.byKey(const ValueKey<String>('session-transcript-list')),
          const Offset(0, 240));
        await probe.settle();
        expect(probe.controller.offset, closeTo(top, 1),
          reason: '到达首条后继续拖动不得滚入空白');
      }
    });
  }

  for (final hidden in [0, 98]) {
    testWidgets('持续滚动及视口变化时顶部当帧收敛，隐藏=$hidden', (tester) async {
      final session = _probeSession('动态顶部边界', 8, hidden: hidden);
      final probe = _TranscriptProbe(tester, session);
      await probe.mount(size: const Size(800, 400));
      await probe.settle();
      for (var page = 0; page < session.messages.length && probe.state._windowStartIndex > 0; page++) {
        final reveal = probe.state._revealOlderMessages();
        await probe.settle();
        await reveal;
      }
      double top() {
        if (hidden == 0) return probe.state._viewportOffsetForMessage(session.messages.first.id)!;
        final viewport = tester.renderObject<RenderViewport>(find.byType(_TranscriptViewport));
        final button = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey<String>(_kTranscriptLoadEarlierKey)));
        return button.localToGlobal(Offset.zero, ancestor: viewport).dy;
      }
      probe.controller.jumpTo(probe.controller.position.minScrollExtent);
      await probe.settle();
      probe.activity.value = true;
      for (final height in [1200.0, 500.0, 900.0]) {
        tester.view.physicalSize = Size(800, height);
        await tester.pump();
        probe.controller.jumpTo(probe.controller.position.minScrollExtent);
        await tester.pump();
        expect(top(), closeTo(0, 1), reason: '滚动期间不能等待空闲后再移除顶部空白');
      }
      await tester.fling(find.byKey(const ValueKey<String>('session-transcript-list')),
        const Offset(0, 1500), 10000);
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(top(), closeTo(0, 1), reason: '持续冲击顶部不能露出空白或拉走历史入口');
      }
      probe.activity.value = false;
      await probe.settle();
      expect(top(), closeTo(0, 1), reason: '滚动停止后不能再次移动顶部内容');
    });
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets('点击可见用户正文不改变阅读位置，平台=$platform', (tester) async {
      final session = _probeSession('点击位置', 4);
      final probe = _TranscriptProbe(tester, session.copyWith(messages: [
        for (final message in session.messages)
          AiSessionMessage.user(id: message.id, createdAt: message.createdAt,
            content: List.filled(5, '点击用户正文时保持当前阅读位置。').join('\n')),
      ]));
      await probe.mount(size: const Size(800, 500));
      await probe.settle();
      final messageId = session.messages[2].id;
      final bubble = find.byKey(ValueKey<String>(messageId));
      final text = find.descendant(of: bubble, matching: find.byType(SelectableText));
      final before = probe.state._viewportOffsetForMessage(messageId)!;
      final pixels = probe.controller.offset;
      await tester.tap(text);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(probe.controller.offset, closeTo(pixels, 1),
        reason: '正文获得焦点不能触发外层会话滚动');
      await probe.settle();
      expect(probe.state._viewportOffsetForMessage(messageId), closeTo(before, 1),
        reason: '选中卡片和显示操作栏不能移动当前消息');
      expect(probe.state._selectedMessageId, messageId);
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      final editable = tester.state<EditableTextState>(
        find.descendant(of: bubble, matching: find.byType(EditableText)));
      expect(editable.textEditingValue.selection.isCollapsed, false,
        reason: '修复焦点滚动后仍应支持键盘全选正文');
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('会话加载：历史段重建与鼠标输入交错不访问未布局节点', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    final centerKey = GlobalKey();
    var showHistory = false;
    var pressed = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const OpenHandImplicitScrollbarBehavior(),
      home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return _TranscriptScrollView(controller: controller,
          center: showHistory ? centerKey : null,
          slivers: [
            if (showHistory) _TranscriptSliverList(anchorsBottom: () => false,
              scrollActive: () => false,
              delegate: SliverChildBuilderDelegate((_, index) =>
                SizedBox(height: 60, child: Text('历史卡片$index')), childCount: 3)),
            SliverPadding(key: centerKey, padding: const EdgeInsets.only(bottom: 12),
              sliver: _TranscriptSliverList(anchorsBottom: () => false,
                scrollActive: () => false,
                delegate: SliverChildBuilderDelegate((_, index) =>
                  SizedBox(height: 80, child: TextButton(onPressed: () => pressed++,
                    child: Text('当前卡片$index'))), childCount: 3))),
          ]);
      },
    ))));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    await tester.pumpAndSettle();
    final viewport = tester.renderObject<RenderViewport>(find.byType(_TranscriptViewport));
    for (var cycle = 0; cycle < 4; cycle++) {
      rebuild(() => showHistory = true);
      // 只完成元素重建，模拟新增 Sliver 尚未布局时平台鼠标数据到达。
      tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
      expect(viewport.firstChild!.geometry, isNull);
      await tester.sendEventToBinding(const PointerHoverEvent(position: Offset(400, 550)));
      await tester.sendEventToBinding(const PointerScrollEvent(
        position: Offset(400, 550), scrollDelta: Offset(0, 40)));
      await tester.tapAt(const Offset(400, 40));
      expect(tester.takeException(), isNull, reason: '新历史段尚未布局时不能空值解引用');
      expect(pressed, cycle * 2 + 1, reason: '已完成布局的当前段仍能点击');
      await tester.pump();
      for (var child = viewport.firstChild; child != null; child = viewport.childAfter(child)) {
        expect(child.geometry, isNotNull);
      }
      await tester.tap(find.text('当前卡片0'));
      expect(tester.takeException(), isNull);
      expect(pressed, cycle * 2 + 2);
      expect(find.text('当前卡片0'), findsOneWidget);
      expect(tester.getRect(find.text('当前卡片0')).overlaps(Offset.zero & viewport.size), true,
        reason: '恢复布局后消息必须真正位于可见视口');
      rebuild(() => showHistory = false);
      await tester.pumpAndSettle();
    }
    expect(tester.binding.hasScheduledFrame, false, reason: '重建结束后不能持续空转');
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  for (final animated in [false, true]) {
    testWidgets('会话加载：真实工作区切换后首帧布局完整且消息不空白，动画=$animated', (tester) async {
      final probe = _TranscriptProbe(tester, _probeSession('工作区切换起点', 12, mixed: true));
      await probe.mount(animated: animated, workspaceSwitcher: true,
        size: const Size(1068, 548));
      await probe.settle();
      probe.expectFilled();
      for (final count in [1, 12, 35, 3, 30]) {
        final previousState = probe.state;
        probe.update(_probeSession('工作区切换$count', count, mixed: true));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: '新旧列表暂时共享控制器时不能中断首帧布局');
        expect(probe.state, isNot(same(previousState)), reason: '必须复现工作区的会话组件销毁与重建');
        final viewport = tester.renderObject<RenderViewport>(find.byType(_TranscriptViewport));
        for (var child = viewport.firstChild; child != null; child = viewport.childAfter(child)) {
          expect(child.geometry, isNotNull, reason: '布局中断会留下空几何并导致整页空白');
        }
        await probe.settle();
        probe.expectFilled();
        expect(find.byType(_TranscriptHydratingPlaceholder), findsNothing);
        final tail = find.text('短消息${count - 1}');
        expect(tail, findsOneWidget);
        expect(tester.getRect(tail).overlaps(tester.getRect(find.byType(_TranscriptViewport))), true,
          reason: '当前会话最新消息必须真正可见');
        await tester.sendEventToBinding(const PointerHoverEvent(position: Offset(500, 300)));
        await tester.tapAt(const Offset(500, 300));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(probe.controller.positions, hasLength(1), reason: '旧列表必须释放滚动位置');
      }
      expect(probe.controller.maxAttachedPositions, greaterThan(1),
        reason: '用例必须覆盖新列表布局早于旧列表卸载的真实窗口');
    }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

    for (final workspaceSwitcher in [false, true]) {
      testWidgets('会话加载：快速切换未完成首屏的会话后消息和鼠标交互恢复，动画=$animated，工作区=$workspaceSwitcher', (tester) async {
        final probe = _TranscriptProbe(tester, _probeSession('快速切换起点', 2));
        await probe.mount(animated: animated, workspaceSwitcher: workspaceSwitcher,
          size: const Size(1000, 600));
        AiSession? latest;
        for (var cycle = 0; cycle < 12; cycle++) {
          final full = _probeSession('快速切换$cycle', 30, mixed: true);
          latest = full;
          probe.update(full.copyWith(messages: const [],
            messageLoadState: AiSessionMessageLoadState.header));
          await tester.pump(const Duration(milliseconds: 16));
          await tester.sendEventToBinding(const PointerHoverEvent(position: Offset(500, 300)));
          probe.update(full.copyWith(messages: full.messages.sublist(24),
            messageLoadState: AiSessionMessageLoadState.windowed, messageWindowStartIndex: 24));
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            await tester.sendEventToBinding(const PointerHoverEvent(position: Offset(500, 300)));
            expect(tester.takeException(), isNull);
          }
        }
        probe.update(latest!);
        await probe.settle();
        probe.expectFilled();
        expect(find.byType(_TranscriptHydratingPlaceholder), findsNothing);
        expect(find.text('短消息29'), findsOneWidget);
        final viewportRect = tester.getRect(find.byType(_TranscriptViewport));
        for (final placeholder in find.byType(_RichContentPendingPreview).evaluate()) {
          expect(tester.getRect(find.byWidget(placeholder.widget)).overlaps(viewportRect), false,
            reason: '可见正文不能一直停留在占位状态');
        }
        await tester.tapAt(const Offset(500, 300));
        await tester.sendEventToBinding(const PointerScrollEvent(
          position: Offset(900, 300), scrollDelta: Offset(0, -120)));
        await probe.settle();
        expect(tester.takeException(), isNull);
        expect(probe.state._initialRevealPhase, _TranscriptInitialRevealPhase.ready);
        // 缓存范围内的占位微光有持续动效，暂停后单独检查加载与定位任务是否结束。
        probe.rebuild(() => probe.tickerEnabled = false);
        await probe.settle();
        expect(probe.state._viewportFillQueued, false);
        expect(tester.binding.hasScheduledFrame, false, reason: '旧会话回调不能让当前窗口无限重建');
      }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
    }
  }

  testWidgets('会话加载：更换首页控制器保持当前位置，卸载后解除全部登记', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('位置生命周期', 12, mixed: true));
    await probe.mount();
    await probe.settle();
    final oldController = probe.controller;
    addTearDown(oldController.dispose);
    final position = oldController.position;
    final offset = position.pixels;
    final state = probe.state;
    final replacement = _ProbeTranscriptScrollController();
    probe.rebuild(() => probe.controller = replacement);
    await tester.pump();
    expect(oldController.positions, hasLength(0));
    expect(replacement.positions.single, same(position));
    expect(state._listController.positions.single, same(position));
    expect(position.pixels, closeTo(offset, 1), reason: '重新登记不能重建原生位置或改变阅读坐标');
    await probe.settle();
    probe.expectFilled();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(replacement.positions, hasLength(0));
    expect(oldController.positions, hasLength(0));
    expect(state.mounted, false);
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, false, reason: '卸载不能遗留位置监听或分帧任务');
  });

  for (final initialPixels in <double?>[null, 420]) {
    testWidgets('会话加载：共享控制器时只测量和滚动当前列表，额外位置=$initialPixels', (tester) async {
      final probe = _TranscriptProbe(tester, _probeSession('位置隔离', 35, mixed: true));
      await probe.mount(size: const Size(1000, 500));
      await probe.settle();
      final ownPosition = probe.controller.position;
      final otherPosition = ScrollPositionWithSingleContext(
        physics: ownPosition.physics, context: ownPosition.context,
        initialPixels: initialPixels, keepScrollOffset: false,
      );
      if (initialPixels != null) {
        otherPosition.applyViewportDimension(500);
        otherPosition.applyContentDimensions(0, 1200);
      }
      probe.controller.attach(otherPosition);
      try {
        expect(probe.controller.positions, hasLength(2));
        expect(probe.state._measuredScrollPosition, same(ownPosition),
          reason: '不能因多位置而跳过自己的测量，也不能使用最后附着的其他位置');
        final anchor = probe.state._capturePrependAnchor();
        expect(anchor, isNotNull);
        final previousOffset = ownPosition.pixels;
        expect(probe.state._scrollNearRenderEntryIndex(0), true);
        expect(ownPosition.pixels, lessThan(previousOffset));
        probe.state._startPrependAnchorStabilization(anchor!, settleFrameCount: 3);
        tester.view.physicalSize = const Size(1080, 540);
        await probe.settle();
        expect(probe.state._pendingPrependAnchor, isNull);
        expect(otherPosition.hasPixels ? otherPosition.pixels : null, initialPixels,
          reason: '定位、锚点恢复与重新布局不能修改其他列表的滚动坐标');
        expect(find.byType(_TranscriptHydratingPlaceholder), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        probe.controller.detach(otherPosition);
        otherPosition.dispose();
      }
      await probe.settle();
      expect(probe.controller.positions, hasLength(1));
    });
  }

  testWidgets('历史段与当前段的显露坐标包含视口锚点', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('显露坐标', 8));
    await probe.mount(size: const Size(800, 500));
    await probe.settle();
    final viewport = tester.renderObject<RenderViewport>(
      find.byType(_TranscriptViewport));
    expect(viewport.anchor, greaterThan(0));
    for (final id in probe.state._bubbleRegistry._contexts.keys) {
      final box = probe.state._bubbleRegistry.contextOf(id)!.findRenderObject()! as RenderBox;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      for (final alignment in [0.0, 0.5, 1.0]) {
        final revealed = viewport.getOffsetToReveal(box, alignment);
        final alignedTop = (viewport.size.height - box.size.height) * alignment;
        expect(revealed.offset, closeTo(probe.controller.offset + top - alignedTop, 0.01));
        expect(revealed.rect.top, closeTo(alignedTop, 0.01));
      }
    }
  });

  testWidgets('缓存只有两条时自动加载历史并保留尾部', (tester) async {
    final full = _probeSession('缓存', 30);
    final probe = _TranscriptProbe(
      tester,
      full.copyWith(
        messages: full.messages.sublist(28),
        messageLoadState: AiSessionMessageLoadState.windowed,
        messageWindowStartIndex: 28,
        messageTotalCount: 30,
      ),
    );
    probe.ai.loadOlder = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      probe.update(full);
      return full;
    };
    await probe.mount();
    await probe.settle();
    probe.expectFilled();
    expect(probe.ai.loadCount, 1);
    expect(probe.manualReveals, 0, reason: '自动补屏不能暂停全局追底');
  });

  testWidgets('窗口扩展与收窄后补屏，过滤消息不占可见高度', (tester) async {
    final probe = _TranscriptProbe(
      tester,
      _probeSession('尺寸', 40, filtered: 8),
    );
    await probe.mount(size: const Size(500, 400));
    await probe.settle();
    probe.expectFilled();
    final previousCount = probe.state._renderEntries.length;
    tester.view.physicalSize = const Size(1600, 1100);
    await probe.settle();
    probe.expectFilled();
    expect(probe.state._renderEntries.length, greaterThan(previousCount));
    tester.view.physicalSize = const Size(400, 500);
    await probe.settle();
    probe.expectFilled();
  });

  for (final animated in [false, true]) {
    testWidgets('会话加载：首帧耗时超过揭示上限仍定位到最终回复，动画=$animated', (tester) async {
      final original = _probeSession('慢首帧', 3, hidden: 320);
      final probe = _TranscriptProbe(tester, original.copyWith(messages: [
        AiSessionMessage.reasoning(
          id: '思考', createdAt: original.createdAt,
          content: List.filled(6, '检查已完成，接下来整理最终交付结果。').join('\n\n'),
        ),
        original.messages[1].copyWith(content: '**检查通过**\n\n## 最终交付\n\n${List.filled(12, '- 已完成验证，结果正常。').join('\n')}'),
        AiSessionMessage.fileMutationSummary(
          id: original.messages.last.id, createdAt: original.createdAt,
          metadata: const {'round_summary_record_count': 9,
            'round_summary_tool_call_ids': ['历史工具调用']},
        ),
      ]));
      // 模拟首帧被复杂卡片或平台视图占用，真实时钟超过揭示时限。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        sleep(_transcriptInitialRevealMaxDuration + const Duration(milliseconds: 20));
      });
      await probe.mount(animated: animated, size: const Size(1100, 550));
      await probe.settle();
      expect(probe.controller.position.extentAfter, lessThan(1),
        reason: '揭示超时只能结束占位，不能跳过首次尾部定位');
      expect(probe.state._viewportOffsetForMessage(original.messages.last.id),
        lessThan(probe.controller.position.viewportDimension));
      expect(find.text('检查通过', findRichText: true), findsOneWidget);
      final pixels = probe.controller.offset;
      await tester.pump(const Duration(seconds: 2));
      expect(probe.controller.offset, pixels, reason: '首次定位完成后不得持续纠偏');
    });
  }

  for (final hydrated in [false, true]) {
    for (final animated in [false, true]) {
      testWidgets('会话加载：复杂正文首次可见的每一帧均贴底，动画=$animated，水合=$hydrated', (tester) async {
        final original = _probeSession('首次可见', 12, mixed: true);
        final probe = _TranscriptProbe(tester, original.copyWith(messages: [
          ...original.messages.take(original.messages.length - 2),
          original.messages[original.messages.length - 2].copyWith(content: List.filled(24,
            '## 验证结果\n\n- **检查通过**：完整展示复杂正文。\n').join('\n')),
          original.messages.last.copyWith(content: '最终回复'),
        ]));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          sleep(_transcriptInitialRevealMaxDuration + const Duration(milliseconds: 20));
        });
        probe.preserveViewportAfterUserScroll = false;
        final loaded = probe.session;
        if (hydrated) {
          probe.session = _probeSession(loaded.id, 0).copyWith(
            messageLoadState: AiSessionMessageLoadState.header,
            messageTotalCount: loaded.messages.length,
          );
        }
        await probe.mount(animated: animated, size: const Size(1100, 550));
        if (hydrated) {
          await probe.settle();
          probe.update(loaded);
        }
        var visibleFrames = 0;
        for (var frame = 0; frame < 120; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final opacity = tester.renderObject<RenderAnimatedOpacity>(
            find.ancestor(of: find.byKey(const ValueKey<String>('session-transcript-list')),
              matching: find.byType(FadeTransition)).first);
          if (opacity.opacity.value <= 0 ||
              probe.controller.position.maxScrollExtent <=
                  probe.controller.position.minScrollExtent + 1) continue;
          visibleFrames++;
          final tail = find.byKey(ValueKey<String>(
            '$_kTranscriptEntryKeyPrefix${original.messages.last.id}'));
          expect(tail, findsOneWidget);
          expect(tester.getBottomLeft(tail).dy, closeTo(550 - 12, 1),
            reason: '第 $frame 帧实际绘制的尾部必须贴底，不能靠下一帧跳转补救');
        }
        expect(visibleFrames, greaterThan(0));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('正文延迟增高在当前帧贴底，用户接管后停止布局修正', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('延迟增高', 12, mixed: true));
    probe.preserveViewportAfterUserScroll = false;
    await probe.mount(size: const Size(1100, 550));
    await probe.settle();
    final messages = probe.session.messages;
    probe.update(probe.session.copyWith(messages: [
      ...messages.take(messages.length - 1),
      messages.last.copyWith(content: List.filled(8, '**延迟加载的正文**\n\n新增内容。').join('\n\n')),
    ]));
    final tail = find.byKey(ValueKey<String>(
      '$_kTranscriptEntryKeyPrefix${messages.last.id}'));
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getBottomLeft(tail).dy, closeTo(550 - 12, 1),
        reason: '正文增高后不能先绘制旧位置再追底');
    }
    probe.activity.value = true;
    probe.controller.jumpTo(probe.controller.offset - 80);
    final readingOffset = probe.controller.offset;
    tester.view.physicalSize = const Size(1100, 450);
    await tester.pump();
    expect(probe.controller.offset, readingOffset,
      reason: '用户阅读期间布局变化不能抢回底部');
    expect(tester.takeException(), isNull);
  });

  for (final trackpad in [true, false]) {
    testWidgets('会话加载：桌面触底后正文先缩后涨仍到达真实尾部，触控板=$trackpad', (tester) async {
      final controller = OpenHandStableScrollController();
      addTearDown(controller.dispose);
      final centerKey = GlobalKey();
      final tailKey = GlobalKey();
      var height = 400.0;
      var reading = false;
      late StateSetter rebuild;
      bool anchorsBottom(ScrollMetrics metrics) =>
          !reading &&
          metrics.hasContentDimensions &&
          !metrics.outOfRange &&
          metrics.extentAfter <= _scrollToBottomSettleTolerance;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const OpenHandImplicitScrollbarBehavior(),
          home: SizedBox(
            height: 550,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent && event.scrollDelta.dy < 0)
                      reading = true;
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification &&
                          notification.dragDetails != null &&
                          (notification.scrollDelta ?? 0) < 0)
                        reading = true;
                      return false;
                    },
                    child: _TranscriptScrollView(
                      controller: controller,
                      center: centerKey,
                      physics: _TranscriptScrollPhysics(
                        shouldAnchorBottom: anchorsBottom,
                      ),
                      slivers: [
                        const SliverToBoxAdapter(child: SizedBox(height: 1200)),
                        _TranscriptSliverList(
                          key: centerKey,
                          anchorsBottom: () =>
                              controller.hasClients &&
                              anchorsBottom(controller.position),
                          scrollActive: () =>
                              controller.hasClients &&
                              controller.position.isScrollingNotifier.value,
                          delegate: SliverChildListDelegate([
                            SizedBox(
                              key: tailKey,
                              height: height,
                              child: const ColoredBox(color: Colors.green),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      controller.jumpTo(controller.position.minScrollExtent);
      await tester.pump();
      final viewport = find.byType(_TranscriptViewport);
      final point = tester.getCenter(viewport);
      final gesture = trackpad
          ? await tester.createGesture(kind: PointerDeviceKind.trackpad)
          : null;
      if (gesture != null) {
        await gesture.panZoomStart(point);
        await gesture.panZoomUpdate(point, pan: const Offset(0, -2400));
      } else {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: const Offset(0, 2400),
          ),
        );
      }
      await tester.pump();
      expect(controller.position.extentAfter, lessThan(1));
      for (final nextHeight in [120.0, 820.0, 90.0, 640.0]) {
        rebuild(() => height = nextHeight);
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          controller.position.outOfRange,
          false,
          reason: '正文收缩必须在当前布局中消除尾部临时越界',
        );
        expect(
          tester.getBottomLeft(find.byKey(tailKey)).dy,
          closeTo(tester.getBottomLeft(viewport).dy, 1),
          reason: '同一次手势中重新测高不能丢失触底意图',
        );
      }
      if (gesture != null) {
        await gesture.panZoomUpdate(point, pan: const Offset(0, -2399.9));
      } else {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: const Offset(0, -.1),
          ),
        );
      }
      final readingOffset = controller.offset;
      rebuild(() => height = 800);
      await tester.pump();
      expect(
        controller.offset,
        closeTo(readingOffset, .01),
        reason: '微小反向输入必须立即停止贴底',
      );
      await gesture?.panZoomEnd();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, false);
    }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
  }

  testWidgets('一次下滑触底后，滚动静默期内连续测高仍停在真实尾部', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('手动触底', 1000));
    probe.preserveViewportAfterUserScroll = false;
    await probe.mount(size: const Size(1100, 550));
    await probe.settle();
    probe.controller.jumpTo(probe.controller.offset - 240);
    await tester.pump();
    probe.activity.value = true;
    await tester.fling(find.byKey(const ValueKey<String>('session-transcript-list')),
      const Offset(0, -600), 1800);
    await tester.pump(const Duration(seconds: 1));
    expect(probe.controller.position.extentAfter, lessThan(1));
    final messages = probe.session.messages;
    final tail = find.byKey(ValueKey<String>(
      '$_kTranscriptEntryKeyPrefix${messages.last.id}'));
    for (final paragraphs in [2, 4]) {
      probe.update(probe.session.copyWith(messages: [
        ...messages.take(messages.length - 1),
        messages.last.copyWith(content: List.filled(paragraphs,
          '**图片与富文本延迟就绪**\n\n新增正文。').join('\n\n')),
      ]));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getBottomLeft(tail).dy, closeTo(550 - 12, 1),
          reason: '同一次向下触底必须跟随连续增高后的真实尾部');
      }
    }
    probe.preserveViewportAfterUserScroll = true;
    probe.controller.jumpTo(probe.controller.offset - 0.1);
    final readingOffset = probe.controller.offset;
    probe.update(probe.session.copyWith(messages: [
      ...messages.take(messages.length - 1),
      messages.last.copyWith(content: List.filled(6,
        '**用户已反向上滑**\n\n新增正文。').join('\n\n')),
    ]));
    await tester.pump(const Duration(milliseconds: 16));
    expect(probe.controller.offset, closeTo(readingOffset, 0.01),
      reason: '微小反向上滑也必须撤销触底跟随');
    probe.activity.value = false;
    await probe.settle();
    expect(probe.controller.position.extentAfter, greaterThan(1));
    expect(tester.binding.hasScheduledFrame, false,
      reason: '完成或撤销触底后不能持续空转');
  });

  for (final hiddenTail in [true, false]) {
    testWidgets('尾部长富文本就绪后贴底，不被回收重建成骨架，尾随隐藏=$hiddenTail', (tester) async {
      final base = _probeSession('尾部富文本', 3);
      final longMarkdown = [
        '## 抓取结果',
        '| 序号 | 标题 |\n| --- | --- |\n'
            '${List.generate(16, (i) => '| $i | 评论标题$i |').join('\n')}',
        '```bash\n${List.generate(12, (i) => 'echo 抓取第$i页').join('\n')}\n```',
        List.filled(8, '这是一段用于撑高最终回复的说明文字。').join(),
      ].join('\n\n');
      final tailId = base.messages.last.id;
      final probe = _TranscriptProbe(tester, base.copyWith(
        messageTotalCount: 4,
        messages: [
          ...base.messages.take(2),
          base.messages.last.copyWith(content: longMarkdown),
          // 尾随记录远矮于长正文，尾部列表按平均高度外推会远超真实底部。
          hiddenTail
              ? AiSessionMessage.selfLearning(id: '尾部富文本-尾随', content: '过滤的内部消息',
                  createdAt: DateTime.utc(2026, 9, 16), metadata: const {})
              : AiSessionMessage.assistant(id: '尾部富文本-尾随', content: '已完成',
                  createdAt: DateTime.utc(2026, 9, 16)),
        ],
      ));
      probe.preserveViewportAfterUserScroll = false;
      await probe.mount(size: const Size(1100, 420));
      await probe.settle();
      final bubble = find.byKey(ValueKey<String>(tailId));
      final element = tester.element(bubble);
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.element(bubble), same(element), reason: '贴底修正不能回收并重建可见的长消息');
      expect(find.byType(_RichContentPendingPreview), findsNothing);
      expect(find.text('抓取结果'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, false, reason: '富文本就绪后不能持续产生帧');
      expect(probe.controller.position.extentAfter, lessThan(1));
    });
  }

  testWidgets('会话加载：慢首帧揭示后用户开始阅读，剩余定位帧不得抢占滚动', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('阅读保护', 30, mixed: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sleep(_transcriptInitialRevealMaxDuration + const Duration(milliseconds: 20));
    });
    await probe.mount();
    probe.activity.value = true;
    probe.controller.jumpTo(probe.controller.position.minScrollExtent);
    final pixels = probe.controller.offset;
    await probe.settle();
    expect(probe.controller.offset, pixels);
    expect(probe.state._initialRevealPhase, _TranscriptInitialRevealPhase.ready);
  });

  testWidgets('会话加载：没有追底请求时首次打开仍显示最新消息并填满视口', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('未请求追底', 30));
    await probe.mount();
    await probe.settle();
    probe.expectFilled();
  });

  for (final html in [false, true]) {
    testWidgets('窗口截断正文按原格式渲染，HTML=$html', (tester) async {
      final original = _probeSession('截断正文', 1);
      final probe = _TranscriptProbe(tester, original.copyWith(messages: [
        original.messages.single.copyWith(
          content: html ? '<p>正文<strong>加粗内容</strong></p>' : '**加粗正文**\n\n- 列表内容',
          metadata: {aiSessionMessageContentPreviewMetadataKey: true,
            aiSessionMessageContentFormatKey: html ? 'html' : 'markdown'},
        ),
      ]));
      await probe.mount();
      await probe.settle();
      expect(find.byType(_PlainTextMessageBody), findsNothing);
      expect(find.byType(html ? _ProgressiveHtmlMessageBody : _SafeMarkdownRichBody), findsWidgets);
      expect(find.text('加载完整内容'), findsOneWidget);
      final loadButton = find.ancestor(of: find.text('加载完整内容'), matching: find.byType(OutlinedButton));
      expect(loadButton, findsOneWidget);
      expect(tester.getSize(loadButton).height, inInclusiveRange(26, 34), reason: '完整内容按钮沿用紧凑操作尺寸');
      final theme = Theme.of(tester.element(loadButton));
      final style = tester.widget<OutlinedButton>(loadButton).style!;
      expect(style.backgroundColor!.resolve({}), theme.colorScheme.surface.withValues(alpha: 0.72));
      expect(style.foregroundColor!.resolve({}), theme.colorScheme.onSurface);
      final full = probe.session.messages.single.copyWith(
        content: html ? '<p>完整<strong>加粗内容</strong></p>' : '**完整加粗内容**',
        metadata: {aiSessionMessageContentFormatKey: html ? 'html' : 'markdown'},
      );
      probe.update(probe.session.copyWith(messages: [full]));
      await probe.settle();
      expect(find.text('加载完整内容'), findsNothing);
      expect(find.byType(_PlainTextMessageBody), findsNothing);
      expect(find.byType(html ? _ProgressiveHtmlMessageBody : _SafeMarkdownRichBody), findsWidgets);
    });
  }

  testWidgets('手动滚动期间停止补屏，恢复空闲后继续', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('暂停', 30));
    await probe.mount(paused: true);
    await probe.settle();
    expect(probe.state._renderEntries.length, lessThanOrEqualTo(4));
    probe.activity.markInactive();
    await probe.settle();
    probe.expectFilled();
    probe.activity.value = true;
    probe.controller.jumpTo(probe.controller.position.minScrollExtent);
    final pixels = probe.controller.offset;
    tester.view.physicalSize = const Size(1400, 1000);
    await probe.settle();
    expect(probe.controller.offset, pixels, reason: '用户滚动时不得强行追底');
  });

  testWidgets('历史加载：同步回调重入共享同一次展开', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('重入', 30, mixed: true));
    await probe.mount(size: const Size(800, 600));
    await probe.settle();
    final previousStart = probe.state._windowStartIndex;
    Future<void>? reentrant;
    probe.onRevealOlderMessages = () {
      if (probe.manualReveals == 1) reentrant = probe.state._revealOlderMessages();
    };
    final first = probe.state._revealOlderMessages();
    await probe.settle();
    await first;
    expect(reentrant, same(first), reason: '回调重入不能重复建立加载任务');
    expect(probe.manualReveals, 1);
    expect(probe.state._windowStartIndex,
      TranscriptListWindowing.revealOlderWindowStart(previousStart));
    expect(probe.state._loadingOlderMessages, false);
    expect(probe.state._activeRevealOlderFuture, isNull);
  });

  testWidgets('历史加载：界面等待超时后可重试，旧请求不能解锁新请求', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('界面超时', 2, hidden: 28));
    final requests = <Completer<AiSession?>>[];
    probe.ai.loadOlder = (_) {
      final request = Completer<AiSession?>();
      requests.add(request);
      return request.future;
    };
    await probe.mount(paused: true);
    await probe.settle();
    final first = probe.state._revealOlderMessages();
    expect(probe.state._revealOlderMessages(), same(first));
    await probe.settle();
    expect(requests.length, 1);
    expect(probe.state._loadingOlderMessages, true);
    await tester.pump(const Duration(seconds: 16));
    await probe.settle();
    expect(probe.state._loadingOlderMessages, false,
      reason: '控制器未返回时界面也必须结束加载');
    expect(probe.state._activeRevealOlderFuture, isNull);
    await first;
    expect(find.text('加载更早消息超时，请重试。'), findsOneWidget);
    final retry = probe.state._revealOlderMessages();
    await probe.settle();
    expect(requests.length, 2);
    requests.first.completeError(StateError('模拟过期读取失败'));
    await probe.settle();
    expect(probe.state._loadingOlderMessages, true);
    expect(probe.state._activeRevealOlderFuture, same(retry));
    requests.last.complete(probe.session);
    await probe.settle();
    await retry;
    expect(probe.state._loadingOlderMessages, false);
    expect(probe.state._activeRevealOlderFuture, isNull);
    expect(probe.manualReveals, 2);
    expect(probe.state._renderEntries.last.id, '界面超时-1');
  });

  testWidgets('历史加载：异常后立即恢复按钮并提示重试', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('加载异常', 2, hidden: 28));
    await probe.mount(paused: true);
    await probe.settle();
    probe.ai.loadOlder = (_) => Future.error(StateError('模拟读取失败'));
    final load = probe.state._revealOlderMessages();
    await probe.settle();
    await load;
    expect(probe.state._loadingOlderMessages, false);
    expect(probe.state._activeRevealOlderFuture, isNull);
    expect(find.text('加载更早消息失败，请重试。'), findsOneWidget);
    expect(find.byType(_TranscriptLoadEarlierButton), findsOneWidget);
  });

  testWidgets('历史加载：同步界面回调失败也能释放状态并重试', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('回调异常', 30, mixed: true));
    await probe.mount(size: const Size(800, 600));
    await probe.settle();
    final previousStart = probe.state._windowStartIndex;
    probe.onRevealOlderMessages = () => throw StateError('模拟界面回调失败');
    final failed = probe.state._revealOlderMessages();
    await probe.settle();
    await failed;
    expect(probe.state._loadingOlderMessages, false);
    expect(probe.state._activeRevealOlderFuture, isNull);
    expect(probe.state._windowStartIndex, previousStart);
    probe.onRevealOlderMessages = null;
    final retry = probe.state._revealOlderMessages();
    await probe.settle();
    await retry;
    expect(probe.state._windowStartIndex, lessThan(previousStart));
    expect(probe.manualReveals, 2);
  });

  testWidgets('历史加载：立即卸载不启动读取', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('启动前卸载', 2, hidden: 28));
    await probe.mount(paused: true);
    await probe.settle();
    final load = probe.state._revealOlderMessages();
    await tester.pumpWidget(const SizedBox());
    await probe.settle();
    await load;
    expect(probe.ai.loadCount, 0);
    expect(probe.manualReveals, 1);
  });

  for (final animated in [false, true]) {
    testWidgets('历史加载：混合工具消息连续点击完整展开，动画=$animated', (tester) async {
      final base = _probeSession('混合分页', 108, mixed: true);
      final messages = <AiSessionMessage>[
        for (var index = 0; index < base.messages.length; index++)
          switch (index % 4) {
            0 => AiSessionMessage.reasoning(id: '混合-$index', content: '正在检查历史记录',
              createdAt: DateTime.utc(2026), metadata: const {aiSessionMessageReasoningElapsedMsKey: 5000}),
            2 => AiSessionMessage.toolCall(id: '混合-$index', content: '调用工具',
              createdAt: DateTime.utc(2026), metadata: {
                'tool_call_id': '调用-$index', 'tool_name': 'MachineTerminalExec',
                'tool_execution_status': 'success', 'tool_arguments': '{"命令":"检查历史"}',
                'tool_execution_stdout': List.filled(20, '模拟工具输出').join('\n'),
              }),
            3 => AiSessionMessage.toolResult(id: '混合-$index', content: '工具执行完成',
              createdAt: DateTime.utc(2026), metadata: {'tool_call_id': '调用-${index - 1}'}),
            _ => base.messages[index],
          },
      ];
      final complete = base.copyWith(messages: messages);
      final probe = _TranscriptProbe(tester, complete.copyWith(
        messages: messages.sublist(96), messageLoadState: AiSessionMessageLoadState.windowed,
        messageWindowStartIndex: 96, messageTotalCount: messages.length));
      probe.ai.loadOlder = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final start = math.max(0, probe.session.messageWindowStartIndex - 12);
        final next = complete.copyWith(messages: messages.sublist(start),
          messageLoadState: start == 0 ? AiSessionMessageLoadState.complete : AiSessionMessageLoadState.windowed,
          messageWindowStartIndex: start, messageTotalCount: messages.length);
        probe.update(next);
        return next;
      };
      await probe.mount(size: const Size(1000, 700), animated: animated);
      await probe.settle();
      for (var page = 0; page < 30; page++) {
        if (probe.state._windowStartIndex == 0 && !probe.session.hasMoreHistoricalMessages) break;
        final button = find.byType(_TranscriptLoadEarlierButton);
        probe.controller.jumpTo(probe.controller.position.minScrollExtent);
        await tester.pump(const Duration(milliseconds: 40));
        expect(button, findsOneWidget, reason: '第$page页滚回顶部必须展示历史入口');
        final anchor = probe.state._capturePrependAnchor();
        await tester.tap(button);
        final first = probe.state._activeRevealOlderFuture!;
        await tester.tap(button);
        expect(probe.state._activeRevealOlderFuture, same(first));
        await probe.settle();
        await first;
        expect(probe.state._loadingOlderMessages, false, reason: '第$page次展开必须结束加载');
        expect(probe.state._activeRevealOlderFuture, isNull);
        if (anchor != null) {
          final offset = probe.state._viewportOffsetForMessage(anchor.messageId)!;
          final position = probe.controller.position;
          final desired = position.pixels + offset - anchor.viewportOffset;
          final target = desired.clamp(position.minScrollExtent, position.maxScrollExtent);
          expect(position.pixels, closeTo(target, 2),
            reason: '第$page次展开必须在滚动边界内保留阅读位置');
        }
      }
      expect(probe.ai.loadCount, 8);
      expect(probe.state._windowStartIndex, 0);
      expect(probe.session.messageWindowStartIndex, 0);
      expect(probe.state._renderEntries.map((entry) => entry.id),
        complete.displayMessages.map((message) => message.id));
      expect(find.byType(_TranscriptLoadEarlierButton), findsNothing);
    });
  }

  testWidgets('历史加载：无进展时停止自动重试，允许手动重试', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('失败', 2, hidden: 28));
    await probe.mount();
    await probe.settle();
    expect(probe.ai.loadCount, 1);
    for (var i = 0; i < 3; i++) {
      tester.view.physicalSize = Size(1400, 950 + i * 10);
      await probe.settle();
    }
    expect(probe.ai.loadCount, 1);
    final retry = probe.state._revealOlderMessages();
    await probe.settle();
    await retry;
    expect(probe.ai.loadCount, 2);
    expect(probe.manualReveals, 1);
  });

  testWidgets('历史加载：返回前切换会话，不污染新窗口', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('旧会话', 2, hidden: 20));
    final pending = Completer<AiSession?>();
    probe.ai.loadOlder = (_) => pending.future;
    await probe.mount();
    await probe.settle();
    expect(probe.ai.loadCount, 1);
    probe.update(_probeSession('新会话', 20));
    await probe.settle();
    final ids = probe.state._renderEntries.map((e) => e.id).toList();
    final pixels = probe.controller.offset;
    pending.complete();
    await probe.settle();
    expect(probe.state._renderEntries.map((e) => e.id), ids);
    expect(probe.controller.offset, pixels);
    probe.expectFilled();
  });

  testWidgets('历史加载：往返切换同一会话，旧请求不能提前解锁新请求', (tester) async {
    final original = _probeSession('往返会话', 2, hidden: 20);
    final probe = _TranscriptProbe(tester, original);
    final requests = <Completer<AiSession?>>[];
    probe.ai.loadOlder = (_) {
      final request = Completer<AiSession?>();
      requests.add(request);
      return request.future;
    };
    await probe.mount();
    await probe.settle();
    probe.update(_probeSession('临时会话', 2));
    await probe.settle();
    probe.update(original);
    await probe.settle();
    expect(requests.length, 2);
    requests.first.complete();
    await probe.settle();
    expect(probe.state._loadingOlderMessages, true);
    requests.last.complete();
    await probe.settle();
    expect(probe.state._loadingOlderMessages, false);
  });

  testWidgets('历史加载：定位不存在的旧消息遇到无进展分页立即结束', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('定位失败', 2, hidden: 200));
    await probe.mount();
    await probe.settle();
    final previousLoads = probe.ai.loadCount;
    final result = probe.state._scrollToMessageId('不存在的消息');
    await probe.settle();
    expect(await result, false);
    expect(probe.ai.loadCount - previousLoads, 1);
    expect(probe.state._loadingOlderMessages, false);
  });

  testWidgets('历史加载：连续不可见记录有自动分页上限', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('上限', 2, hidden: 400));
    probe.ai.loadOlder = (_) async {
      final previous = probe.session;
      final next = previous.copyWith(
        messages: [
          ...List.generate(
            10,
            (index) => AiSessionMessage.selfLearning(
              id: '内部-${previous.messageWindowStartIndex}-$index',
              content: '不可见记录',
              createdAt: DateTime.utc(2026),
              metadata: const {},
            ),
          ),
          ...previous.messages,
        ],
        messageLoadState: AiSessionMessageLoadState.windowed,
        messageWindowStartIndex: previous.messageWindowStartIndex - 10,
        messageTotalCount: 402,
      );
      probe.update(next);
      return next;
    };
    await probe.mount();
    await probe.settle();
    expect(probe.ai.loadCount, 3, reason: '不可见历史不能触发无界自动分页');
    await probe.settle();
    expect(probe.ai.loadCount, 3);
    expect(probe.state._loadingOlderMessages, false);
    expect(probe.state._staggerFillActive, false);
  });

  testWidgets('本地大量过滤记录有分帧补屏上限', (tester) async {
    final probe = _TranscriptProbe(
      tester,
      _probeSession('过滤上限', 2, filtered: 200),
    );
    await probe.mount();
    for (var pass = 0; pass < 4; pass++) {
      await probe.settle();
    }
    expect(probe.state._renderEntries.length, 68);
    expect(probe.state._staggerFillActive, false);
    final count = probe.state._renderEntries.length;
    await probe.settle();
    expect(probe.state._renderEntries.length, count);
  });

  testWidgets('历史加载：请求完成前卸载组件不遗留任务', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('卸载', 2, hidden: 20));
    final pending = Completer<AiSession?>();
    probe.ai.loadOlder = (_) => pending.future;
    await probe.mount();
    await probe.settle();
    expect(probe.ai.loadCount, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await probe.settle();
    expect(probe.key.currentState, isNull);
  });

  testWidgets('千条长正文混排只解析附近预览且不预挂载平台视图', (tester) async {
    final base = _probeSession('rich-history', 1000);
    final markdown = List.filled(1500, '- **历史正文**：消息内容\n').join();
    final html = '<article>${List.filled(500, '<p>历史 HTML 卡片</p>').join()}</article>';
    final session = base.copyWith(messages: [
      for (var index = 0; index < base.messages.length; index++)
        base.messages[index].copyWith(
          content: index.isEven ? html : markdown,
          metadata: {'content_format': index.isEven ? 'html' : 'markdown'},
        ),
    ]);
    final probe = _TranscriptProbe(tester, session);
    var layoutUpdates = 0;
    probe.onLayoutChanged = () {
      layoutUpdates += 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!probe.controller.hasClients) return;
        probe.controller.jumpTo(probe.controller.position.maxScrollExtent);
      });
    };
    await probe.mount();
    expect(probe.state._bubbleRegistry._contexts.length, lessThanOrEqualTo(2));
    await probe.settle();
    final richBodies = tester.stateList<_SafeMarkdownBodyState>(
      find.byType(_SafeMarkdownRichBody),
    ).toList();
    expect(richBodies.length, greaterThan(0));
    expect(richBodies.every((body) => body.config.data.length <= 1200), true);
    expect(probe.state._bubbleRegistry._contexts.length, lessThan(20));
    expect(find.byType(_DeferredHtmlBubbleWebView), findsNothing);
    expect(layoutUpdates, greaterThan(0));
    expect(probe.controller.position.extentAfter, lessThan(1));
  });

  testWidgets('千条消息流式更新只替换尾部并复用索引', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('流式', 1000));
    await probe.mount(size: const Size(800, 600));
    await probe.settle();
    probe.rebuild(() {
      probe.state._windowStartIndex = 0;
      probe.state._replaceRenderEntries(
        probe.session.displayMessages,
        animate: false,
      );
    });
    await tester.pump();

    final firstEntry = probe.state._renderEntries.first;
    final middleEntry = probe.state._renderEntries[500];
    final indexMap = probe.state._cachedVisibleIndexMap!;
    for (var chunk = 0; chunk < 20; chunk++) {
      final tail = probe.session.messages.last.copyWith(
        content: '流式正文$chunk',
      );
      final next = probe.session.copyWithTailMessage(tail, append: false);
      expect(
        next.displayMessageChangeFrom(probe.session),
        AiSessionDisplayMessageChange.tailReplaced,
      );
      probe.update(next);
      await tester.pump();
      expect(identical(probe.state._renderEntries.first, firstEntry), true);
      expect(identical(probe.state._renderEntries[500], middleEntry), true);
      expect(identical(probe.state._cachedVisibleIndexMap, indexMap), true);
      expect(probe.state._renderEntries.last.message.content, '流式正文$chunk');
    }

    final appended = probe.session.copyWithTailMessage(
      AiSessionMessage.assistant(
        id: '流式-追加',
        content: '追加消息',
        createdAt: DateTime.utc(2026, 9, 17),
      ),
      append: true,
    );
    probe.update(appended);
    await tester.pump();
    expect(identical(probe.state._cachedVisibleIndexMap, indexMap), true);
    expect(indexMap['流式-追加'], 1000);
    expect(probe.state._renderEntries.last.id, '流式-追加');

    final changedMessages = List<AiSessionMessage>.of(probe.session.messages);
    changedMessages[500] = changedMessages[500].copyWith(content: '中间消息已更新');
    final middleChanged = probe.session.copyWith(messages: changedMessages);
    expect(middleChanged.displayMessageChangeFrom(probe.session), isNull);
    final previousTailEntry = probe.state._renderEntries.last;
    probe.update(middleChanged);
    await tester.pump();
    expect(probe.state._renderEntries[500].message.content, '中间消息已更新');
    expect(identical(probe.state._renderEntries.last, previousTailEntry), true);
  });

  testWidgets('长会话展开历史与往返滚动保留消息和阅读位置', (tester) async {
    final probe = _TranscriptProbe(
      tester,
      _probeSession('历史', 100, mixed: true),
    );
    await probe.mount(size: const Size(800, 600));
    await probe.settle();
    probe.expectFilled();
    for (var page = 0; page < 8; page++) {
      probe.controller.jumpTo(probe.controller.position.minScrollExtent);
      await tester.pump();
      final anchor = probe.state._capturePrependAnchor();
      final reveal = probe.state._revealOlderMessages();
      await probe.settle();
      await reveal;
      if (anchor != null)
        expect(
          (probe.state._viewportOffsetForMessage(anchor.messageId)! -
                  anchor.viewportOffset)
              .abs(),
          lessThan(2),
          reason: '第 $page 次加载历史应保持当前阅读位置：${anchor.messageId}，原位置=${anchor.viewportOffset}，当前位置=${probe.state._viewportOffsetForMessage(anchor.messageId)}',
        );
      expect(probe.state._renderEntries.last.id, '历史-99');
    }
    final expandedIds = probe.state._renderEntries.map((e) => e.id).toList();
    expect(expandedIds.toSet().length, expandedIds.length);
    for (var pass = 0; pass < 3; pass++) {
      probe.controller.jumpTo(probe.controller.position.minScrollExtent);
      await probe.settle();
      for (var step = 0; step < 20; step++) {
        probe.controller.jumpTo(probe.controller.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await probe.settle();
      expect(probe.state._renderEntries.map((e) => e.id), expandedIds);
      expect(find.text('短消息99'), findsWidgets);
      expect(
        probe.state._bubbleRegistry._contexts.length,
        lessThan(25),
        reason: '离屏普通消息应回收',
      );
    }
    probe.update(
      probe.session.copyWith(
        messages: [
          ...probe.session.messages,
          AiSessionMessage.assistant(
            id: '新回复',
            content: '追加回复',
            createdAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    await probe.settle();
    expect(probe.state._renderEntries.first.id, expandedIds.first);
    expect(probe.state._renderEntries.last.id, '新回复');
    final target = probe.state._scrollToMessageId('历史-60');
    await probe.settle();
    expect(await target, true);
    probe.update(
      probe.session.copyWith(
        messages: probe.session.messages
            .where((m) => m.id != probe.state._listCenterMessageId)
            .toList(),
      ),
    );
    await probe.settle();
    expect(probe.state._renderEntries.last.id, '新回复');
  });

  testWidgets('发送与响应期间视口逐帧变化，跟随底部不出现反向跳动', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('发送抖动', 8));
    probe.preserveViewportAfterUserScroll = false;
    await probe.mount(size: const Size(700, 650));
    await probe.settle();
    probe.controller.jumpTo(probe.controller.position.maxScrollExtent);
    final reply = AiSessionMessage.assistant(id: '持续响应',
      content: '开始处理', createdAt: DateTime.utc(2026));
    probe.update(probe.session.copyWithTailMessage(reply, append: true));
    await probe.settle();
    for (var i = 0; i < 45; i++) {
      final height = i < 15 ? 650.0 - i * 12 : i < 30 ? 470.0 + (i - 15) * 12 : 650.0;
      tester.view.physicalSize = Size(700, height);
      if (i % 3 == 0) {
        probe.update(probe.session.copyWithTailMessage(reply.copyWith(
          content: List.filled(3 + i, '响应内容正在增长，检查滚动稳定性。').join('\n'),
        ), append: false));
      }
      await tester.pump(const Duration(milliseconds: 16));
      final position = probe.controller.position;
      expect(position.extentAfter, lessThanOrEqualTo(1), reason: '第 $i 帧不得掉离底部');
      expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent + 1), reason: '第 $i 帧不得超过底部');
      expect(tester.takeException(), isNull);
    }
    await probe.settle();
  });

  for (final animated in [false, true]) {
  testWidgets('决策历史往返慢速滚动时已可见消息不发生额外位移，动画=$animated', (tester) async {
    final original = _probeSession('决策慢速滚动', 18);
    final content = DecisionPayload.encode(DecisionPayload.resultLanguage, {
      'questions': {
        '分类': {
          'type': 'choice', 'instructions': '评估这项方案的执行方向与预期结果',
          'criteria': {'甲': null, '乙': null, '丙': null, '丁': null},
        },
      },
      'answers': {
        '分类': {
          'type': 'choice', 'choice': '甲',
          'probabilities': {'甲': .4, '乙': .3, '丙': .2, '丁': .1},
        },
      },
    });
    final probe = _TranscriptProbe(tester, original.copyWith(messages: [
      for (var i = 0; i < original.messages.length; i++)
        if (i.isEven) AiSessionMessage.user(id: original.messages[i].id,
          createdAt: original.createdAt,
          content: DecisionPayload.encode(DecisionPayload.requestLanguage, {
            'state': '请评估这项方案的执行方向与预期结果。' * 8,
            'questions': {'分类': {'type': 'choice', 'instructions': '选择最佳方案',
              'criteria': {'甲': null, '乙': null, '丙': null, '丁': null}}},
          }))
        else original.messages[i].copyWith(content: content),
    ]));
    await probe.mount(size: Size(animated ? 700 : 390, 650), animated: animated);
    await probe.settle();
    for (var page = 0; page < 8 && probe.state._windowStartIndex > 0; page++) {
      final reveal = probe.state._revealOlderMessages();
      await probe.settle();
      await reveal;
    }
    expect(probe.state._windowStartIndex, 0);
    probe.controller.jumpTo(probe.controller.position.maxScrollExtent);
    await probe.settle();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    final position = probe.controller.position;
    final drag = position.drag(DragStartDetails(), () {});
    for (var frame = 0; frame < 600; frame++) {
      final delta = frame < 300 ? 16.0 : -16.0;
      final before = <String, double>{
        for (final id in probe.state._bubbleRegistry._contexts.keys)
          if (probe.state._viewportOffsetForMessage(id) case final double offset)
            if (offset < 650 && offset +
                (probe.state._bubbleRegistry.contextOf(id)!.findRenderObject()! as RenderBox).size.height > 0)
              id: offset,
      };
      probe.activity.markActive();
      final oldPixels = position.pixels;
      drag.update(DragUpdateDetails(globalPosition: Offset.zero,
        delta: Offset(0, delta), primaryDelta: delta));
      final requestedShift = oldPixels - position.pixels;
      await tester.pump(const Duration(milliseconds: 32));
      for (final entry in before.entries) {
        final after = probe.state._viewportOffsetForMessage(entry.key);
        if (after == null || entry.value > 650 || after > 650) continue;
        expect(after - entry.value, closeTo(requestedShift, 1),
          reason: '第 $frame 帧 ${entry.key} 出现拖动之外的位移');
      }
      expect(tester.takeException(), isNull);
    }
    drag.cancel();
    await probe.settle();
  });
  }

  for (final history in [false, true]) {
  testWidgets('异步卡片测高保持阅读位置和拖动，历史段=$history', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final centerKey = GlobalKey();
    final rowKeys = List.generate(1000, (_) => GlobalKey());
    final heights = List.generate(1000, (index) => 90.0 + index % 3 * 135);
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      Widget row(int index) => SizedBox(key: rowKeys[index], height: heights[index], child: Text('卡片$index'));
      return _TranscriptScrollView(controller: controller,
        center: history ? centerKey : null,
        scrollCacheExtent: const ScrollCacheExtent.pixels(280),
        physics: const ClampingScrollPhysics(), slivers: [
          if (history) _TranscriptSliverList(anchorsBottom: () => false,
            scrollActive: () => controller.position.isScrollingNotifier.value,
            delegate: SliverChildBuilderDelegate((_, index) => row(499 - index), childCount: 500)),
          _TranscriptSliverList(key: centerKey, anchorsBottom: () => false,
            scrollActive: () => controller.position.isScrollingNotifier.value,
            delegate: SliverChildBuilderDelegate((_, index) => row(history ? 500 + index : index),
              childCount: history ? 500 : 1000)),
        ]);
    })));
    await tester.pump();
    controller.jumpTo(history ? -1800 : 1800);
    await tester.pump();
    final viewport = tester.renderObject<RenderBox>(find.byType(_TranscriptViewport));
    double top(int index) => (rowKeys[index].currentContext!.findRenderObject()! as RenderBox)
      .localToGlobal(Offset.zero, ancestor: viewport).dy;
    int reading() {
      var index = -1;
      var firstTop = double.infinity;
      for (var i = 0; i < rowKeys.length; i++) {
        final box = rowKeys[i].currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached || !box.hasSize) continue;
        final offset = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final rank = offset >= 0 ? offset : 600 + offset.abs();
        if (offset + box.size.height > 0 && offset < 600 && rank < firstTop) {
          firstTop = rank;
          index = i;
        }
      }
      return index;
    }
    final anchor = reading();
    expect(anchor, greaterThanOrEqualTo(0));
    final before = top(anchor);
    final resized = history ? anchor + 1 : anchor - 1;
    expect(rowKeys[resized].currentContext, isNotNull);
    rebuild(() => heights[resized] = 1080);
    await tester.pump();
    expect(top(anchor), closeTo(before, 1), reason: '图片解码或 HTML 测高增高后当帧保持阅读位置');
    rebuild(() => heights[resized] = 90);
    await tester.pump();
    expect(top(anchor), closeTo(before, 1), reason: '多媒体收缩后当帧保持阅读位置');
    final drag = controller.position.drag(DragStartDetails(), () {});
    for (var frame = 0; frame < 120; frame++) {
      final index = reading();
      final before = top(index);
      final oldPixels = controller.offset;
      final delta = frame < 60 ? 18.0 : -18.0;
      drag.update(DragUpdateDetails(globalPosition: Offset.zero, delta: Offset(0, delta), primaryDelta: delta));
      final shift = oldPixels - controller.offset;
      if (frame == 20) rebuild(() => heights[index] = 720);
      if (frame == 80) rebuild(() => heights[index] = 90);
      await tester.pump(const Duration(milliseconds: 16));
      if (rowKeys[index].currentContext != null) {
        expect(top(index) - before, closeTo(shift, 1), reason: '第 $frame 帧不能产生拖动之外的跳动');
      }
      expect(controller.position.isScrollingNotifier.value, true, reason: '布局补偿不能中断拖动');
    }
    drag.cancel();
    (controller.position as ScrollPositionWithSingleContext).goBallistic(history ? -1500 : 1500);
    await tester.pump(const Duration(milliseconds: 16));
    final ballistic = controller.position.activity;
    expect(ballistic, isA<BallisticScrollActivity>());
    final velocity = ballistic!.velocity;
    final current = reading();
    rebuild(() => heights[history ? current + 1 : current - 1] += 600);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.position.activity, isA<BallisticScrollActivity>(), reason: '异步测高不能终止惯性活动');
    expect(controller.position.activity!.velocity / velocity, inInclusiveRange(.8, 1),
      reason: '异步测高后惯性保持方向和自然减速');
    await tester.pumpWidget(const SizedBox());
  });
  }

  testWidgets('完整决策响应不经逐字揭示和结束重挂载改变高度', (tester) async {
    final original = _probeSession('决策响应', 18);
    final probe = _TranscriptProbe(tester, original);
    probe.preserveViewportAfterUserScroll = false;
    await probe.mount(size: const Size(700, 650), animated: true);
    await probe.settle();
    final content = DecisionPayload.encode(DecisionPayload.resultLanguage, {
      'questions': {'判断': {'type': 'noul', 'instructions': '是否成立？'}},
      'answers': {'判断': {'type': 'noul', 'noul': .65}},
    });
    final reply = AiSessionMessage.assistant(id: '决策新响应', content: content,
      createdAt: original.createdAt,
      metadata: {aiSessionMessageMetadataStreamingKey: true});
    probe.sendPhase = AiSendPhase.responding;
    probe.update(probe.session.copyWithTailMessage(reply, append: true));
    for (var frame = 0; frame < 60; frame++) {
      if (frame == 15) {
        probe.sendPhase = AiSendPhase.idle;
        probe.update(probe.session.copyWithTailMessage(reply.copyWith(
          metadata: {aiSessionMessageMetadataStreamingKey: false}), append: false));
      }
      tester.view.physicalSize = Size(700, frame < 30 ? 650 - frame * 4 : 530 + (frame - 30) * 4);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(OpenHandDecisionCard), findsOneWidget,
        reason: '第 $frame 帧完整决策响应不能变成片段或占位');
      expect(probe.controller.position.extentAfter, lessThanOrEqualTo(1),
        reason: '第 $frame 帧视口变化后仍应贴底');
      expect(tester.takeException(), isNull);
    }
    await probe.settle();
    probe.preserveViewportAfterUserScroll = true;
    expect(probe.controller.position.maxScrollExtent - probe.controller.position.minScrollExtent,
      greaterThan(80));
    probe.controller.jumpTo(probe.controller.position.maxScrollExtent - 80);
    await tester.pump();
    final anchor = probe.state._capturePrependAnchor()!;
    probe.activity.markActive();
    for (var turn = 0; turn < 3; turn++) {
      probe.sendPhase = AiSendPhase.responding;
      probe.update(probe.session.copyWithTailMessage(AiSessionMessage.assistant(
        id: '继续响应-$turn', content: content, createdAt: original.createdAt,
        metadata: {aiSessionMessageMetadataStreamingKey: true}), append: true));
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(probe.state._viewportOffsetForMessage(anchor.messageId),
          closeTo(anchor.viewportOffset, 1), reason: '用户阅读历史时连续响应不能抢回底部：轮次=$turn，帧=$frame，消息=${anchor.messageId}，滚动=${probe.controller.position.pixels}');
      }
    }
    await probe.settle();
  });

  testWidgets('慢速滚动间歇不释放布局保护，真正停止后统一恢复', (tester) async {
    final activity = TranscriptScrollActivity();
    addTearDown(activity.dispose);
    final changes = <bool>[];
    activity.addListener(() => changes.add(activity.value));
    for (var i = 0; i < 8; i++) {
      activity.markActive();
      await tester.pump(const Duration(milliseconds: 250));
      expect(activity.value, true);
    }
    expect(changes, [true]);
    await tester.pump(TranscriptScrollActivity.settleDelay);
    expect(changes, [true, false]);
  });

  testWidgets('微小上滑撤销追底，开始结束通知不会重新抢回底部', (tester) async {
    final home = await _ComposerRoutingProbe.create(tester);
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final metrics = FixedScrollMetrics(minScrollExtent: 0, maxScrollExtent: 100,
      pixels: 99.9, viewportDimension: 600, axisDirection: AxisDirection.down, devicePixelRatio: 1);
    home._pendingForcedScrollToBottom = true;
    home._queuedForcedScrollToBottom = true;
    home._messageProgrammaticScrollWindow.begin();
    home._handleMessagePointerSignal(const PointerScrollEvent(scrollDelta: Offset(0, -.01)));
    expect(home._shouldAutoFollowMessages, false);
    expect(home._pendingForcedScrollToBottom, false);
    expect(home._queuedForcedScrollToBottom, false);
    home._handleMessageScrollNotification(ScrollStartNotification(metrics: metrics, context: context));
    expect(home._shouldAutoFollowMessages, false);
    home._handleMessageScrollNotification(ScrollUpdateNotification(metrics: metrics, context: context,
      scrollDelta: -.01, dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, .01))));
    expect(home._shouldAutoFollowMessages, false);
    home._handleMessageScrollNotification(ScrollEndNotification(metrics: metrics, context: context));
    expect(home._shouldAutoFollowMessages, false);
    home._handleMessageScrollNotification(ScrollUpdateNotification(metrics: metrics.copyWith(pixels: 90), context: context,
      scrollDelta: .1, dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, -.1))));
    expect(home._shouldAutoFollowMessages, false, reason: '仅接近底部仍保持用户阅读位置');
    home._handleMessageScrollNotification(ScrollUpdateNotification(metrics: metrics, context: context,
      scrollDelta: .1, dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, -.1))));
    expect(home._shouldAutoFollowMessages, true, reason: '主动下滑回到底部后恢复跟随');
    home._shouldAutoFollowMessages = false;
    home._handleMessageScrollNotification(OverscrollNotification(metrics: metrics, context: context,
      overscroll: 30, dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, -30))));
    expect(home._shouldAutoFollowMessages, true, reason: '拖动已触底时，边界通知也必须恢复跟随');
    home._shouldAutoFollowMessages = false;
    await tester.pumpWidget(MaterialApp(home: ListView(controller: home._messageScrollController,
      children: const [SizedBox(height: 1400)])));
    home._messageScrollController.jumpTo(home._messageScrollController.position.maxScrollExtent);
    home._handleMessagePointerSignal(const PointerScrollEvent(scrollDelta: Offset(0, 30)));
    expect(home._shouldAutoFollowMessages, true, reason: '已在底部的滚轮输入没有位置更新也能保留触底');
    home._handleMessagePointerSignal(const PointerScrollEvent(scrollDelta: Offset(0, -.01)));
    expect(home._shouldAutoFollowMessages, false, reason: '同一边界的微小上滑立即撤销跟随');
    home._messageScrollController.jumpTo(home._messageScrollController.offset - 30);
    home._handleMessagePointerSignal(const PointerScrollEvent(scrollDelta: Offset(0, 1)));
    expect(home._shouldAutoFollowMessages, false, reason: '尚未触底的向下输入不能提前贴底');
    home._autoFollowEnabled = false;
    home._messageScrollController.jumpTo(home._messageScrollController.position.maxScrollExtent);
    home._handleMessagePointerSignal(const PointerScrollEvent(scrollDelta: Offset(0, 30)));
    expect(home._shouldAutoFollowMessages, false, reason: '关闭跟随时边界输入不能重新开启');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('原生拖动期间延迟锚点修正不能改写视口', (tester) async {
    final probe = _TranscriptProbe(tester, _probeSession('拖动保护', 12));
    await probe.mount();
    await probe.settle();
    final anchor = probe.state._capturePrependAnchor()!;
    final stale = _TranscriptViewportAnchor(messageId: anchor.messageId,
      viewportOffset: anchor.viewportOffset - 30);
    final position = probe.controller.position;
    final drag = position.drag(DragStartDetails(), () {});
    drag.update(DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, 1), primaryDelta: 1));
    final before = position.pixels;
    expect(probe.state._restorePrependAnchor(stale), false);
    probe.state._startPrependAnchorStabilization(stale);
    await tester.pump();
    expect(position.pixels, before);
    expect(probe.state._pendingPrependAnchor, isNull);
    drag.cancel();
    await probe.settle();
  });

  for (final animated in [false, true]) {
    testWidgets('决策内容交互不切换消息选中，仅外层留白切换，动画=$animated', (tester) async {
      final original = _probeSession('决策点击隔离', 1);
      final probe = _TranscriptProbe(tester, original);
      await probe.mount(size: const Size(1200, 1400), animated: animated);
      for (final type in ['noul', 'choice', 'score']) {
        final source = DecisionPayload.encode(DecisionPayload.resultLanguage, {
          'questions': {'决策': {'type': type, 'instructions': '判断内容',
            if (type == 'choice') 'criteria': {'甲': null, '乙': null},
            if (type == 'score') 'criteria': ['低', '高'],
          }},
          'answers': {'决策': {'type': type,
            if (type == 'noul') 'noul': .6,
            if (type == 'choice') ...{'choice': '甲', 'probabilities': {'甲': .6, '乙': .4}, 'confidence': .99},
            if (type == 'score') ...{'score': .6, 'probabilities': {'0': .4, '1': .6}, 'confidence': .5},
          }},
        });
        final message = AiSessionMessage.assistant(id: '结果-$type', content: source, createdAt: original.createdAt);
        probe.update(original.copyWith(messages: [message]));
        await probe.settle();
        final bubble = tester.state<_MessageBubbleState>(find.byType(_MessageBubble));
        expect(bubble._embeddedInteractiveRegions.length, 1);
        for (final selected in [false, true]) {
          probe.state.setState(() => probe.state._selectedMessageId = selected ? message.id : null);
          await probe.settle();
          expect(find.byType(OpenHandExpansionTile), findsNothing);
          expect(find.byType(OpenHandDecisionCard), findsOneWidget);
          expect(find.text('判断内容'), findsNothing);
          expect(find.text('Choice'), findsNothing);
          expect(find.text('Score'), findsNothing);
          expect(find.text('Judgement'), findsNothing);
          expect(find.text('Confidence'), findsNothing);
          final typeLabel = type == 'choice' ? '选择' : type == 'score' ? '评分' : '判断';
          if (selected) {
            expect(find.text(typeLabel), findsWidgets);
            if (type == 'choice') {
              expect(find.text('置信度 99.0%'), findsOneWidget);
            } else if (type == 'score') {
              expect(find.text('0.6'), findsWidgets);
              expect(find.text('置信度 50.0%'), findsOneWidget);
            }
          } else {
            expect(find.text(typeLabel), findsNothing);
            expect(find.textContaining('置信度'), findsNothing);
          }
          await tester.tap(find.text('60.0%'));
          await probe.settle();
          expect(probe.state._selectedMessageId, selected ? message.id : null);
          await tester.tap(find.text('60.0%'));
          await probe.settle();
          expect(probe.state._selectedMessageId, selected ? message.id : null);
          await tester.tap(find.text('60.0%'));
          await probe.settle();
          expect(probe.state._selectedMessageId, selected ? message.id : null);
          final margin = tester.getTopLeft(find.byKey(bubble._bubbleInteractionKey)) + const Offset(4, 4);
          expect(bubble._isPointerInsideEmbeddedInteractiveRegion(margin), isFalse);
          await tester.tapAt(margin);
          await probe.settle();
          expect(probe.state._selectedMessageId, selected ? null : message.id);
        }
        probe.state.setState(() => probe.state._selectedMessageId = message.id);
        await probe.settle();
        await tester.tap(find.text('显示原始'));
        await probe.settle();
        expect(bubble._embeddedInteractiveRegions.length, 0, reason: '卸载决策视图须注销交互区域');
        await tester.tap(find.text('显示渲染'));
        await probe.settle();
        expect(bubble._embeddedInteractiveRegions.length, 1);
        final held = await tester.startGesture(tester.getCenter(find.text('60.0%')));
        bubble.setState(() => bubble._showRawContent = true);
        await tester.pump();
        await held.up();
        await probe.settle();
        expect(bubble._embeddedInteractiveRegions.length, 0);
        expect(probe.state._selectedMessageId, message.id, reason: '按下后内容卸载，抬起仍不切换选中');
        await tester.tap(find.text('显示渲染'));
        await probe.settle();
        final requestSource = DecisionPayload.encode(DecisionPayload.requestLanguage, {
          'state': '待评估内容',
          'questions': {'决策': {'type': type, 'instructions': '判断内容',
            if (type == 'choice') 'criteria': {'甲': null, '乙': null},
            if (type == 'score') 'criteria': ['低', '高'],
          }},
        });
        probe.update(original.copyWith(messages: [AiSessionMessage.assistant(
          id: message.id, content: requestSource, createdAt: original.createdAt)]));
        await probe.settle();
        expect(bubble._embeddedInteractiveRegions.length, 1);
        await tester.tap(find.text('待评估内容').last);
        await probe.settle();
        expect(probe.state._selectedMessageId, message.id);
      }
    });
  }

  testWidgets('三类决策请求和结果禁用朗读翻译，原始视图与执行入口一致', (tester) async {
    final original = _probeSession('决策操作限制', 1);
    final probe = _TranscriptProbe(tester, original);
    await probe.mount(size: const Size(1200, 1400), textActions: true);
    for (final type in ['noul', 'choice', 'score']) {
      final source = DecisionPayload.encode(DecisionPayload.resultLanguage, {
        'questions': {'决策': {'type': type, 'instructions': '判断内容',
          if (type == 'choice') 'criteria': {'甲': null, '乙': null},
          if (type == 'score') 'criteria': ['低', '高'],
        }},
        'answers': {'决策': {'type': type,
          if (type == 'noul') 'noul': .6,
          if (type == 'choice') ...{'choice': '甲', 'probabilities': {'甲': .6, '乙': .4}},
          if (type == 'score') ...{'score': .6, 'probabilities': {'0': .4, '1': .6}},
        }},
      });
      final message = AiSessionMessage.assistant(id: '结果', content: source, createdAt: original.createdAt);
      expect(message.isStructuredDecision, isTrue);
      probe.update(original.copyWith(messages: [message]));
      probe.state.setState(() => probe.state._selectedMessageId = message.id);
      await probe.settle();
      expect(probe.state._messageSupportsSpeech(message, probe.settings), isFalse);
      expect(probe.state._isMessageTranslatable(message, probe.settings), isFalse);
      await probe.state._toggleMessageSpeech(message, probe.settings.aiTtsSettings);
      await probe.state._toggleMessageTranslation(message, probe.settings.aiTranslationSettings);
      expect(find.text('朗读'), findsNothing);
      expect(find.text('翻译'), findsNothing);
      expect(find.text('复制'), findsOneWidget);
      await tester.tap(find.text('显示原始'));
      await probe.settle();
      expect(find.text('朗读'), findsNothing);
      expect(find.text('翻译'), findsNothing);
      expect(find.text('显示渲染'), findsOneWidget);
      await tester.tap(find.text('显示渲染'));
      await probe.settle();
      final request = AiSessionMessage.user(id: '用户请求', createdAt: original.createdAt,
        content: DecisionPayload.encode(DecisionPayload.requestLanguage, {
          'state': '待评估内容', 'questions': {'决策': {'type': type, 'instructions': '判断内容',
            if (type == 'choice') 'criteria': {'甲': null, '乙': null},
            if (type == 'score') 'criteria': ['低', '高'],
          }},
        }));
      expect(request.isStructuredDecision, isTrue);
      probe.update(original.copyWith(messages: [request]));
      probe.state.setState(() => probe.state._selectedMessageId = request.id);
      await probe.settle();
      expect(probe.state._messageSupportsSpeech(request, probe.settings), isFalse);
      expect(probe.state._isMessageTranslatable(request, probe.settings), isFalse);
      await probe.state._toggleMessageSpeech(request, probe.settings.aiTtsSettings);
      await probe.state._toggleMessageTranslation(request, probe.settings.aiTranslationSettings);
      expect(find.text('朗读'), findsNothing);
      expect(find.text('翻译'), findsNothing);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      await tester.tap(find.text('显示原始'));
      await probe.settle();
      expect(find.text('朗读'), findsNothing);
      expect(find.text('翻译'), findsNothing);
      await tester.tap(find.text('显示渲染'));
      await probe.settle();
    }
    for (final content in ['普通回复提到 openhand-decision', '```openhand-decision-request\n{}\n```', '```openhand-decision-extra\n{}\n```']) {
      final message = AiSessionMessage.assistant(id: '普通', content: content, createdAt: original.createdAt);
      expect(message.isStructuredDecision, isFalse);
    }
    final normal = AiSessionMessage.assistant(id: '普通', content: '普通助手回复', createdAt: original.createdAt);
    probe.update(original.copyWith(messages: [normal]));
    probe.state.setState(() => probe.state._selectedMessageId = normal.id);
    await probe.settle();
    expect(find.text('朗读'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);
    final normalUser = AiSessionMessage.user(id: '普通用户', content: '普通用户消息提到 openhand-decision-request', createdAt: original.createdAt);
    probe.update(original.copyWith(messages: [normalUser]));
    probe.state.setState(() => probe.state._selectedMessageId = normalUser.id);
    await probe.settle();
    expect(normalUser.isStructuredDecision, isFalse);
    expect(find.text('朗读'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);
    expect(AiSessionMessage.user(id: '用户', content: '```openhand-decision\n{}\n```', createdAt: original.createdAt).isStructuredDecision, isFalse);
    expect(DecisionPayload.containsResult('前文\n  ~~~openhand-decision\r\n{}\r\n~~~'), isTrue);
  });

  testWidgets('用户决策请求复用 Markdown 并支持原始渲染往返切换', (tester) async {
    final original = _probeSession('决策请求展示', 1);
    final source = DecisionPayload.encode(DecisionPayload.requestLanguage, {
      'state': '待评估 <script>内容</script>', 'questions': {
        '判断': {'type': 'noul', 'instructions': '是否成立？', 'criteria': {'真': '有证据'}},
        '选择': {'type': 'choice', 'instructions': '选哪个？', 'criteria': {'甲*': null, '乙|': '详细描述'}},
        '评分': {'type': 'score', 'instructions': {'问题': '评几级？'}, 'criteria': ['低', '高']},
      },
    });
    final message = AiSessionMessage.user(id: '决策请求', content: source, createdAt: original.createdAt);
    final probe = _TranscriptProbe(tester, original.copyWith(messages: [message]));
    await probe.mount(size: const Size(1000, 1800), animated: true);
    await probe.settle();
    final bubble = find.byKey(const ValueKey<String>('决策请求'));
    final state = tester.state<_MessageBubbleState>(bubble);
    final copy = DecisionCopy.of(tester.element(bubble));
    final markdown = decisionRequestToMarkdown(source, copy)!;
    expect(markdown, contains('### 结构化决策'));
    expect(markdown, contains('#### 判断 · 判断'));
    expect(markdown, contains(r'甲\*'));
    expect(markdown, contains(r'乙\|：详细描述'));
    expect(markdown, contains('1. 低\n2. 高'));
    expect(markdown, contains(r'\<script\>'));
    expect(markdown, contains('```json\n'));
    expect(find.descendant(of: bubble, matching: find.byType(_AssistantMessageBodyDispatcher)), findsOneWidget);
    probe.state.setState(() => probe.state._selectedMessageId = message.id);
    await probe.settle();
    await tester.ensureVisible(find.text('显示原始'));
    await tester.tap(find.text('显示原始'));
    await probe.settle();
    expect(state._showRawContent, isTrue);
    expect(find.descendant(of: bubble, matching: find.byType(_PlainTextMessageBody)), findsOneWidget);
    expect(state.widget.message.content, source, reason: '显示转换不改写持久化原文');
    await tester.ensureVisible(find.text('显示渲染'));
    await tester.tap(find.text('显示渲染'));
    await probe.settle();
    expect(state._showRawContent, isFalse);
    expect(find.descendant(of: bubble, matching: find.byType(_AssistantMessageBodyDispatcher)), findsOneWidget);
    for (final invalid in ['普通消息', '```openhand-decision-request\n损坏\n```', '```openhand-decision-request\n{}']) {
      expect(decisionRequestToMarkdown(invalid, copy), isNull);
    }
    final surrounded = decisionRequestToMarkdown('前文\n${source.replaceAll('\n', '\r\n')}\n后文', copy)!;
    expect(surrounded, startsWith('前文'));
    expect(surrounded, endsWith('后文'));
    probe.update(original.copyWith(messages: [AiSessionMessage.user(id: '普通请求', content: '普通消息', createdAt: original.createdAt)]));
    await probe.settle();
    expect(find.text('显示原始'), findsNothing);
  });

  test('草稿允许未完成字段，但发送校验仍拒绝空内容与不完整标准', () {
    for (final type in ['noul', 'choice', 'score']) {
      final encoded = DecisionPayload.encode(DecisionPayload.requestLanguage, {
        'state': '', 'questions': {'决策': {'type': type, 'instructions': '',
          if (type == 'choice') 'criteria': <String, Object?>{},
          if (type == 'score') 'criteria': <String>[],
        }},
      });
      expect(DecisionPayload.request(encoded, allowIncomplete: true)['state'], '');
      expect(() => DecisionPayload.request(encoded), throwsFormatException);
      final draft = DecisionPayload.request(encoded, allowIncomplete: true);
      draft['state'] = '有效正文';
      expect(() => DecisionPayload.request(jsonEncode(draft)), throwsFormatException,
        reason: '正文填写后仍须校验问题内容');
      ((draft['questions'] as Map)['决策'] as Map)['instructions'] = '有效问题';
      if (type != 'noul') {
        expect(() => DecisionPayload.request(jsonEncode(draft)), throwsFormatException,
          reason: '正文和问题填写后仍须校验候选项或评分等级');
      }
    }
  });

  testWidgets('Jev 草稿外部清空、替换与重新挂载不会回填已发送内容', (tester) async {
    final controller = TextEditingController();
    final replacement = TextEditingController(text: '另一会话草稿');
    addTearDown(controller.dispose);
    addTearDown(replacement.dispose);
    var writes = 0;
    controller.addListener(() => writes++);
    Future<void> mount(TextEditingController target, {String locale = 'zh'}) async {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale), supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: SingleChildScrollView(child:
          _DecisionComposerForm(controller: target, enabled: true))),
      ));
      await tester.pumpAndSettle();
    }
    await mount(controller);
    expect(controller.text, '');
    expect(writes, 0, reason: '挂载空表单不能生成决策代码块');
    await mount(controller, locale: 'en');
    expect(writes, 0, reason: '语言切换只更新默认文案');
    var form = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    form._state.selection = const TextSelection.collapsed(offset: 0);
    form._question.selection = const TextSelection.collapsed(offset: 0);
    expect(controller.text, '', reason: '聚焦或移动光标不能生成空请求');
    expect(writes, 0);
    form._state.text = '已经发送的正文';
    expect(DecisionPayload.request(controller.text)['state'], '已经发送的正文');
    controller.clear();
    await tester.pumpAndSettle();
    expect(form._state.text, '');
    expect(controller.text, '', reason: '外部清空后不允许旧表单重新编码');
    form._setType('score');
    form._criteria.first.text = '尚未写完的等级';
    final incomplete = controller.text;
    await tester.pumpWidget(const SizedBox());
    await mount(controller);
    form = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    expect(form._state.text, '', reason: '未完成的决策草稿不能当作普通正文嵌套');
    expect(form._type, 'score');
    expect(form._criteria.first.text, '尚未写完的等级');
    expect(controller.text, incomplete);
    await mount(replacement);
    expect(form._state.text, '另一会话草稿');
    controller.text = '旧控制器迟到内容';
    await tester.pumpAndSettle();
    expect(form._state.text, '另一会话草稿');
    expect(replacement.text, '另一会话草稿');
    replacement.clear();
    await tester.pumpAndSettle();
    expect(form._state.text, '');
    expect(form._retiredCriteria.length, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切入发送中的会话清空上一会话输入，失败恢复副本独立保存', (tester) async {
    final home = await _ComposerRoutingProbe.create(tester);
    home._activeComposerSessionId = '会话甲';
    home._composerController.text = '甲未发送的内容';
    home._storeComposerDraftForSession('会话乙', text: '乙正在发送的恢复副本', isSubmissionBackup: true);
    home._submittingSessionId = '会话乙';
    home._syncComposerDraftForSession('会话乙');
    expect(home._composerController.text, '');
    expect(home._composerDraftsBySessionId['会话甲']!.text, '甲未发送的内容');
    expect(home._composerDraftsBySessionId['会话乙']!.text, '乙正在发送的恢复副本');
    home._syncComposerDraftForSession('会话甲');
    expect(home._composerController.text, '甲未发送的内容');
    home._submittingSessionId = null;
    home._syncComposerDraftForSession('会话乙');
    expect(home._composerController.text, '乙正在发送的恢复副本');
    home._submittingSessionId = '会话乙';
    home._composerController.text = '乙新写的下一条草稿';
    home._syncComposerDraftForSession('会话甲');
    home._syncComposerDraftForSession('会话乙');
    expect(home._composerController.text, '乙新写的下一条草稿');
    home._composerController.clear();
    home._syncComposerDraftForSession('会话甲');
    home._syncComposerDraftForSession('会话乙');
    expect(home._composerController.text, '', reason: '主动清空的新草稿不能恢复');
  });

  testWidgets('内嵌决策类型更新默认问题并同步草稿，自定义问题保持不变', (tester) async {
    final controller = TextEditingController(text: '待评估内容');
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: _DecisionComposerForm(controller: controller, enabled: true)),
    ));
    final form = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    for (final custom in [false, true]) {
      if (custom) form._question.text = '应由哪个团队处理？';
      for (final entry in {'choice': '选择', 'score': '评分', 'noul': '判断'}.entries) {
        await tester.tap(find.text(entry.value));
        await tester.pumpAndSettle();
        for (var i = 0; i < form._criteria.length; i++) {
          form._criteria[i].text = '等级 $i';
        }
        final expected = custom ? '应由哪个团队处理？' : DecisionPayload.defaultQuestionForType(entry.key, const Locale('zh'));
        expect(form._question.text, expected);
        final request = DecisionPayload.request(controller.text);
        final question = (request['questions'] as Map).values.single as Map;
        expect(question['type'], entry.key);
        expect(question['instructions'], expected);
      }
    }
    form._question.clear();
    await tester.tap(find.text('判断'));
    await tester.pumpAndSettle();
    expect(form._question.text, '', reason: '重复点击当前类型不改写编辑内容');
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(form._question.text, DecisionPayload.defaultQuestionForType('choice', const Locale('zh')));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('决策候选项与评分等级独立保留，草稿只包含当前类型', (tester) async {
    final controller = TextEditingController(text: DecisionPayload.encode(
      DecisionPayload.requestLanguage,
      {'state': '待评估内容', 'questions': {'决策': {
        'type': 'choice', 'instructions': DecisionPayload.questionForType('choice'),
        'criteria': {for (var i = 0; i < 30; i++) '候选 $i': null},
      }}},
    ));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: SingleChildScrollView(
      child: _DecisionComposerForm(controller: controller, enabled: true),
    ))));
    final form = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    form._addCriteria();
    final choiceControllers = form._criteria.toList();
    form._setType('score');
    await tester.pumpAndSettle();
    expect(form._criteria.map((item) => item.text), ['', '']);
    form._criteria[0].text = '低';
    form._criteria[1].text = '高';
    form._addCriteria();
    form._criteria[2].text = '最高';
    form._removeCriteria(1);
    Map activeQuestion() => (DecisionPayload.request(controller.text)['questions'] as Map).values.single as Map;
    expect(activeQuestion()['criteria'], ['低', '最高']);
    form._setType('noul');
    await tester.pumpAndSettle();
    expect(activeQuestion().containsKey('criteria'), isFalse);
    form._setType('choice');
    await tester.pumpAndSettle();
    expect(form._criteria, orderedEquals(choiceControllers));
    expect(form._criteria.last.text, '', reason: '未填写的新行也应保留');
    expect((activeQuestion()['criteria'] as Map).keys, hasLength(30));
    form._removeCriteria(0);
    form._setType('score');
    await tester.pumpAndSettle();
    expect(form._criteria.map((item) => item.text), ['低', '最高']);
    expect(activeQuestion()['criteria'], ['低', '最高']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('决策条目等高操作、排序与增删动画保持内容和资源一致', (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: DecisionPayload.encode(
      DecisionPayload.requestLanguage, {'state': '评估内容', 'questions': {'决策': {
        'type': 'score', 'instructions': '评分', 'criteria': ['低', '中', '高'],
      }}},
    ));
    addTearDown(controller.dispose);
    var reduceMotion = false;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'), localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: SingleChildScrollView(child: _DecisionComposerForm(controller: controller, enabled: true))));
      }),
    ));
    await tester.pumpAndSettle();
    final form = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    final original = form._criteria.toList();
    Finder field(TextEditingController value) => find.byWidgetPredicate((widget) => widget is TextField && widget.controller == value);
    List<Object?> payload() => ((DecisionPayload.request(controller.text)['questions'] as Map).values.single as Map)['criteria'] as List;
    final row = find.ancestor(of: field(original[0]), matching: find.byType(Row)).first;
    final remove = find.descendant(of: row, matching: find.byType(IconButton)).last;
    final indexBadge = find.descendant(of: row, matching: find.byType(OpenHandDecisionIndexBadge));
    expect(tester.getSize(remove).height, closeTo(tester.getSize(field(original[0])).height, .1));
    expect(tester.getSize(indexBadge).width, closeTo(tester.getSize(remove).width, .1));
    expect(tester.getSize(indexBadge).height, closeTo(tester.getSize(remove).height, .1));
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == '上移').first).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == '下移').last).onPressed, isNull);
    final before = tester.getTopLeft(field(original[0])).dy;
    await tester.tap(find.byTooltip('下移').first);
    await tester.pump();
    expect(payload(), ['中', '低', '高']);
    expect(tester.getTopLeft(field(original[0])).dy, closeTo(before, 1), reason: '排序首帧从旧位置开始');
    await tester.pump(const Duration(milliseconds: 80));
    final moving = tester.getTopLeft(field(original[0])).dy;
    expect(moving, greaterThan(before));
    form._moveCriteria(1, -1);
    await tester.pump();
    expect(tester.getTopLeft(field(original[0])).dy, closeTo(moving, 1), reason: '反向移动接续当前位置');
    await tester.pumpAndSettle();
    expect(form._criteria, orderedEquals(original));
    form._removeCriteria(1);
    await tester.pump();
    expect(payload(), ['低', '高']);
    expect(field(original[1]), findsOneWidget, reason: '删除视图保留到退场结束');
    expect(form._retiredCriteria, hasLength(1));
    final duringRemoval = tester.getTopLeft(field(original[0])).dy;
    form._moveCriteria(0, 1);
    await tester.pump();
    expect(tester.getTopLeft(field(original[0])).dy, closeTo(duringRemoval, 1), reason: '退场期间排序仍从当前位置衔接');
    expect(payload(), ['高', '低']);
    await tester.pumpAndSettle();
    expect(field(original[1]), findsNothing);
    expect(form._retiredCriteria, hasLength(0));
    form._moveCriteria(0, 1);
    await tester.pumpAndSettle();
    form._addCriteria();
    await tester.pump();
    final added = form._criteria.last;
    final list = find.byType(CustomScrollView);
    final startHeight = tester.getSize(list).height;
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(list).height, greaterThan(startHeight));
    await tester.pumpAndSettle();
    added.text = '最高';
    rebuild(() => reduceMotion = true);
    await tester.pumpAndSettle();
    form._moveCriteria(2, -1);
    await tester.pump();
    expect(payload(), ['低', '最高', '高']);
    form._removeCriteria(1);
    await tester.pumpAndSettle();
    expect(form._retiredCriteria, hasLength(0));
    form._addCriteria();
    form._removeCriteria(2);
    expect(form._retiredCriteria, hasLength(0), reason: '同帧增删未挂载条目直接释放');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test('会话惯性滚动时贴底修正不得改写弹道位置', () {
    final physics = _TranscriptScrollPhysics(
      shouldAnchorBottom: (_) => true,
      parent: const AlwaysScrollableScrollPhysics(),
    );
    ScrollMetrics metrics({
      required double pixels,
      required double max,
    }) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: max,
      pixels: pixels,
      viewportDimension: 200,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final resting = metrics(pixels: 350, max: 400);
    final grown = metrics(pixels: 350, max: 420);
    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: resting,
        newPosition: grown,
        isScrolling: true,
        velocity: 1200,
      ),
      350,
    );
    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: resting,
        newPosition: grown,
        isScrolling: false,
        velocity: 0,
      ),
      420,
    );
    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: metrics(pixels: 424, max: 400),
        newPosition: metrics(pixels: 424, max: 400),
        isScrolling: true,
        velocity: 800,
      ),
      424,
    );
    for (final velocity in [0.0, 1200.0]) {
      expect(physics.adjustPositionForNewDimensions(
        oldPosition: metrics(pixels: 400, max: 400),
        newPosition: metrics(pixels: 400, max: 120),
        isScrolling: true,
        velocity: velocity,
      ), 120, reason: '触底后正文收缩不能留下临时越界');
      expect(physics.adjustPositionForNewDimensions(
        oldPosition: metrics(pixels: 424, max: 400),
        newPosition: metrics(pixels: 424, max: 820),
        isScrolling: true,
        velocity: velocity,
      ), 820, reason: '正文恢复高度必须承接尾部临时越界时的触底意图');
      expect(physics.adjustPositionForNewDimensions(
        oldPosition: metrics(pixels: 400, max: 400),
        newPosition: metrics(pixels: 400, max: 820),
        isScrolling: true,
        velocity: velocity,
      ), 820, reason: '向下触底后，测高增加的尾部必须在布局阶段补齐');
      expect(physics.adjustPositionForNewDimensions(
        oldPosition: metrics(pixels: 350, max: 400),
        newPosition: metrics(pixels: 400, max: 820),
        isScrolling: true,
        velocity: velocity,
      ), 820, reason: '同一帧才滑到旧边界时，必须用当前位置识别触底');
      expect(physics.adjustPositionForNewDimensions(
        oldPosition: metrics(pixels: 400, max: 400),
        newPosition: metrics(pixels: 780, max: 820),
        isScrolling: true,
        velocity: velocity,
      ), 820, reason: '布局正向修正超出旧边界时仍承接底部测高');
    }
    expect(physics.adjustPositionForNewDimensions(
      oldPosition: metrics(pixels: 400, max: 400),
      newPosition: metrics(pixels: 400, max: 820),
      isScrolling: true,
      velocity: -1200,
    ), 400, reason: '反向惯性不能被触底修正抢占');
    expect(physics.adjustPositionForNewDimensions(
      oldPosition: metrics(pixels: 400, max: 400),
      newPosition: metrics(pixels: 399.9, max: 820),
      isScrolling: false,
      velocity: 0,
    ), 399.9, reason: '上一轮布局的触底快照不能覆盖随后微小上滑');
  });

  testWidgets('应用滚动行为在两端使用夹紧物理', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const OpenHandImplicitScrollbarBehavior(),
        home: const SizedBox(),
      ),
    );
    final context = tester.element(find.byType(SizedBox));
    expect(
      ScrollConfiguration.of(context).getScrollPhysics(context),
      isA<ClampingScrollPhysics>(),
    );
  });

  testWidgets('工作区空状态在极小高度下不产生负约束', (tester) async {
    tester.view.physicalSize = const Size(800, 16);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: _WorkspaceEmptyState()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('工作区适应窗口高度和长决策表单，切回普通模型恢复文本输入', (tester) async {
    final captureDirectory = Platform.environment['OPENHAND_LAYOUT_SCREENSHOTS'];
    final captureFont = Platform.environment['OPENHAND_LAYOUT_FONT'];
    if (captureDirectory != null && captureFont != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('布局截图字体');
        loader.addFont(File(captureFont).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final captureKey = GlobalKey();
    Future<void> capture(String name) async {
      if (captureDirectory == null) return;
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captureDirectory/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
    // 硬件探测需要真实异步环境，避免子进程定时器进入组件测试的虚拟时钟。
    await tester.runAsync(() async {
      final service = OfflineSpeechModelService.instance;
      if (service.hardwareProfile != null) return;
      final ready = Completer<void>();
      void onReady() {
        if (service.hardwareProfile != null && !ready.isCompleted) ready.complete();
      }
      service.addListener(onReady);
      try {
        await ready.future.timeout(const Duration(seconds: 30));
      } finally {
        service.removeListener(onReady);
      }
    });
    final controller = TextEditingController(text: DecisionPayload.encode(
      DecisionPayload.requestLanguage,
      {
        'state': '待分类内容',
        'questions': {'分类': {
          'type': 'choice',
          'instructions': '选择候选项',
          'criteria': {for (var i = 0; i < 30; i++) '候选项 $i': null},
        }},
      },
    ));
    final scroll = ScrollController();
    final focus = FocusNode();
    final ai = _WorkspaceProbeAi();
    final instructions = _ProbeInstructions();
    final voice = _ProbeVoice();
    final tts = _ProbeTts();
    final settings = await SettingsController.create(store: _ProbeSettingsStore(true, writable: true));
    addTearDown(() {
      controller.dispose();
      scroll.dispose();
      focus.dispose();
      ai.dispose();
      instructions.dispose();
      voice.dispose();
      tts.state.dispose();
      settings.dispose();
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var modelId = 'jev-latest';
    var composerSessionId = '布局回归';
    var collapsed = false;
    var sendCount = 0;
    var textScale = 1.0;
    var reduceMotion = false;
    final theme = OpenHandTheme.light(settings.themePreset).copyWith(platform: TargetPlatform.macOS);
    late StateSetter rebuild;
    tester.view.physicalSize = const Size(1068, 738);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AiSessionController>.value(value: ai),
          ChangeNotifierProvider<InstructionsController>.value(value: instructions),
        ],
        child: MaterialApp(
          theme: captureFont == null ? theme : theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: '布局截图字体'),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: RepaintBoundary(key: captureKey, child: Scaffold(body: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
              child: _WorkspaceView(
              draftController: controller,
              messageScrollController: scroll,
              onMessageScrollNotification: (_) => false,
              onMessagePointerSignal: (_) {},
              currentSession: _probeSession(composerSessionId, 0),
              liveRuntimeToolPreview: null,
              transcriptHydrating: false,
              transcriptLoadError: null,
              onRetryTranscriptLoad: () async {},
              selectedModel: AiModelConfig(
                id: '布局模型', baseUrl: 'https://example.invalid/v1',
                authScheme: AiAuthScheme.bearer, token: '',
                modelId: modelId, protocolType: modelId == 'jev-latest' ? AiProtocolType.jev : AiProtocolType.openai,
              ),
              availableModels: const [],
              recentModelSelections: const [],
              onModelSelected: (_, _) {},
              composerFocusNode: focus,
              composerCollapsed: collapsed,
              onComposerCollapsedChanged: (value) => rebuild(() => collapsed = value),
              onComposerLayoutChanged: () {},
              onTranscriptLayoutChanged: () {},
              onMessageExpansionChanged: (_) {},
              onRevealOlderMessages: () {},
              onProgrammaticScrollCorrection: (callback) => callback(),
              autoFollowEnabled: true,
              autoFollowPaused: false,
              onToggleAutoFollow: () {},
              sendPhase: AiSendPhase.idle,
              canStopSending: false,
              planTimelineCollapsed: true,
              onPlanTimelineCollapsedChanged: (_) {},
              sessionMode: AiSessionMode.chat,
              onSessionModeChanged: (_) {},
              goalControls: _GoalControls(available: false, suppressedForQueue: false,
                onPause: () async {}, onResume: () async {}, onTerminate: () async {}),
              attachments: _ComposerAttachments(drafts: const [], enabled: false,
                onPick: () async {}, onRemove: (_) {}, onReorder: (_, _) {}),
              onSend: () async { sendCount++; },
              onStop: () async {},
              voiceModeSelected: false,
              voiceConversationSnapshot: () => const AiVoiceConversationSnapshot.idle(),
              voiceConversationService: voice,
              onStartVoiceConversation: () async {},
              onStopVoiceConversation: () async {},
              creationMode: _CreationMode.none,
              onCreationModeChanged: (_) {},
              editingMessageId: null,
              onCancelEditing: () async {},
              messageActions: _MessageActions(onEdit: (_) async {}, onCopy: (_) async {},
                onDelete: (_) async => false, onDeleteFromHere: (_) async => false,
                onFork: (_) async {}, onSetFeedback: (_, _) async {},
                onRegenerate: (_) async {}, onSelectResponseVariant: (_, _) async {}),
              ttsPlaybackService: tts,
              translationService: _ProbeTranslation(),
              onDismissError: (_) async {},
              fullAccessPermission: false,
              onToggleFullAccessPermission: (_) {},
              queuedPanel: _QueuedMessagesPanel(messages: const [], guidanceInProgress: false,
                onRemove: (_) {}, onMove: (_, _) {}, onEdit: (_, _) {}, onGuide: (_) {}),
            ));
          }))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(_DecisionComposerForm), findsOneWidget);
    expect(tester.widget<_ComposerModeButton>(find.byType(_ComposerModeButton)).mode, AiSessionMode.chat);
    expect(tester.widget<_ComposerModeButton>(find.byType(_ComposerModeButton)).enabled, false);
    expect(tester.widget<_ComposerCreationModeButton>(find.byType(_ComposerCreationModeButton)).enabled, false);
    expect(tester.widget<_ComposerInstructionsStrip>(find.byType(_ComposerInstructionsStrip)).disabled, true);
    void expectActionsVisible() {
      final send = find.widgetWithText(FilledButton, '发送');
      expect(send, findsOneWidget);
      final panel = tester.getRect(find.byType(_ComposerPanel));
      final button = tester.getRect(send);
      expect(button.bottom, lessThanOrEqualTo(panel.bottom));
      expect(button.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      expect(send.hitTestable(), findsOneWidget);
    }
    expectActionsVisible();
    await capture('choice-desktop');
    final formScroll = find.ancestor(of: find.byType(_DecisionComposerForm),
      matching: find.byType(SingleChildScrollView)).first;
    await tester.drag(formScroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    final formScrollable = tester.state<ScrollableState>(
      find.descendant(of: formScroll, matching: find.byType(Scrollable)).first);
    expect(formScrollable.position.pixels, greaterThan(0));
    expectActionsVisible();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();
    expect(sendCount, 1);
    for (final height in [400.0, 200.0, 32.0, 0.0, 738.0]) {
      tester.view.physicalSize = Size(1068, height);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '窗口高度 $height');
      if (height >= 200) expectActionsVisible();
    }
    for (final mode in ['判断', '选择', '评分']) {
      formScrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byType(_ComposerPanel)).height;
      final actionBottom = tester.getRect(find.widgetWithText(FilledButton, '发送')).bottom;
      await tester.tap(find.text(mode));
      await tester.pump();
      expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(before, 1),
        reason: '模式切换首帧不能跳到目标高度');
      await tester.pump(const Duration(milliseconds: 100));
      final intermediate = tester.getSize(find.byType(_ComposerPanel)).height;
      expectActionsVisible();
      await capture('motion-${mode == '判断' ? 'judge' : mode == '选择' ? 'choice' : 'score'}-100ms');
      expect(tester.getRect(find.widgetWithText(FilledButton, '发送')).bottom, closeTo(actionBottom, 1));
      await tester.pumpAndSettle();
      final after = tester.getSize(find.byType(_ComposerPanel)).height;
      if ((before - after).abs() > 1) {
        expect(intermediate, greaterThan(math.min(before, after)));
        expect(intermediate, lessThan(math.max(before, after)), reason: '长表单收缩不能在高度上限停顿');
      }
      expect(tester.takeException(), isNull);
      expectActionsVisible();
      await capture('mode-${mode == '判断' ? 'judge' : mode == '选择' ? 'choice' : 'score'}');
    }
    for (final size in [const Size(800, 500), const Size(1068, 400)]) {
      tester.view.physicalSize = size;
      rebuild(() => textScale = 1.5);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectActionsVisible();
      await capture('compact-${size.width.toInt()}');
    }
    tester.view.physicalSize = const Size(1068, 738);
    rebuild(() => textScale = 1);
    await tester.pumpAndSettle();
    final expandedHeight = tester.getSize(find.byType(_ComposerPanel)).height;
    rebuild(() => collapsed = true);
    await tester.pump();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(expandedHeight, 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(_ComposerPanel)).height, lessThan(expandedHeight));
    // 动画中反向展开，从当前高度接续，不能闪回起点。
    final interruptedHeight = tester.getSize(find.byType(_ComposerPanel)).height;
    rebuild(() => collapsed = false);
    await tester.pump();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(interruptedHeight, 1));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(expandedHeight, 1));
    // 面板设置关闭或系统减少动画时，无需推进动画时间即可完成布局。
    final formBeforeSettings = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    final draftBeforeSettings = controller.text;
    formScrollable.position.jumpTo(80);
    await tester.pumpAndSettle();
    final scrollBeforeSettings = formScrollable.position.pixels;
    expect(await settings.updatePanelAnimationSettings(OpenHandMotionDefaults.disabled), isTrue);
    await tester.pumpAndSettle();
    expect(tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm)), same(formBeforeSettings));
    expect(controller.text, draftBeforeSettings);
    expect(formScrollable.position.pixels, closeTo(scrollBeforeSettings, 1));
    rebuild(() => collapsed = true);
    await tester.pump();
    await tester.pump();
    final collapsedHeight = tester.getSize(find.byType(_ComposerPanel)).height;
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, collapsedHeight);
    expect(collapsedHeight, lessThan(expandedHeight));
    expect(await settings.updatePanelAnimationSettings(OpenHandMotionDefaults.panel), isTrue);
    rebuild(() { reduceMotion = true; collapsed = false; });
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(expandedHeight, 1));
    await tester.pumpAndSettle();
    rebuild(() => reduceMotion = false);
    await tester.pumpAndSettle();
    rebuild(() { collapsed = false; modelId = 'gpt-4o'; });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(_DecisionComposerForm), findsNothing);
    expect(find.byWidgetPredicate((widget) => widget is TextField && widget.controller == controller), findsOneWidget);
    expectActionsVisible();
    rebuild(() => modelId = 'jev-latest');
    await tester.pumpAndSettle();
    final form = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    final judgeHeight = tester.getSize(find.byType(_ComposerPanel)).height;
    await tester.tap(find.text('选择'));
    await tester.pump();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(judgeHeight, 1));
    await tester.pump(const Duration(milliseconds: 100));
    final growingHeight = tester.getSize(find.byType(_ComposerPanel)).height;
    await tester.pumpAndSettle();
    final choiceHeight = tester.getSize(find.byType(_ComposerPanel)).height;
    expect(growingHeight, inExclusiveRange(judgeHeight, choiceHeight));
    // 连续增删候选项时保持当前视口尺寸连续，收敛后不遗留动画任务。
    form._addCriteria();
    await tester.pump();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(choiceHeight, 1));
    await tester.pump(const Duration(milliseconds: 80));
    final addingHeight = tester.getSize(find.byType(_ComposerPanel)).height;
    form._removeCriteria(1);
    await tester.pump();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(addingHeight, 1));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(_ComposerPanel)).height, closeTo(choiceHeight, 1));
    expectActionsVisible();
    expect(await settings.updatePanelAnimationSettings(const DialogAnimationSettings(
      durationMs: 400, curve: DialogAnimationCurve.elasticOut,
    )), isTrue);
    await tester.pumpAndSettle();
    for (final value in [true, false]) {
      rebuild(() => collapsed = value);
      await tester.pump();
      for (var frame = 0; frame < 26; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
        expectActionsVisible();
      }
    }
    final targetDraft = DecisionPayload.encode(DecisionPayload.requestLanguage, {
      'state': '目标会话自己保存的代码块',
      'questions': {'决策': {'type': 'noul', 'instructions': '自定义问题'}},
    });
    rebuild(() {
      composerSessionId = '普通会话';
      modelId = 'gpt-4o';
      controller.text = targetDraft;
    });
    await tester.pumpAndSettle();
    expect(controller.text, targetDraft, reason: '跨会话模型变化不能解包目标草稿');
    rebuild(() {
      composerSessionId = '空的决策会话';
      modelId = 'jev-latest';
      controller.clear();
    });
    await tester.pumpAndSettle();
    expect(controller.text, '');
    final emptyForm = tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm));
    expect(emptyForm._state.text, '');
    emptyForm._state.text = '本会话新内容';
    controller.clear();
    rebuild(() { composerSessionId = '另一个空决策会话'; });
    await tester.pumpAndSettle();
    expect(controller.text, '');
    expect(tester.state<_DecisionComposerFormState>(find.byType(_DecisionComposerForm)), isNot(same(emptyForm)));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
''';
