import 'dart:io';

import 'support/flutter_widget_check.dart';

/// 合并真实页面及其 part 后执行私有组件回归，不给生产代码添加测试接口。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final page = File('${root.path}/lib/features/home/openhand_home_page.dart');
  final libUri = Directory('${root.path}/lib/').uri;
  var source = await page.readAsString();
  source = source.replaceAllMapped(RegExp("(import|export) '([^']+)'"), (
    match,
  ) {
    if (match[2]!.contains(':')) return match[0]!;
    final uri = page.uri.resolve(match[2]!);
    final relative = uri.path.substring(libUri.path.length);
    return "${match[1]} 'package:openhand/$relative'";
  });
  source = source.replaceAllMapped(RegExp("part '([^']+)';"), (match) {
    return File.fromUri(
      page.uri.resolve(match[1]!),
    ).readAsStringSync().replaceFirst(RegExp('^part of [^;]+;'), '');
  });
  await runFlutterWidgetCheck(
    root: root,
    name: 'transcript',
    source:
        "import 'package:flutter_test/flutter_test.dart' hide isEmpty, isNotEmpty;\n"
        "import 'package:openhand/app/state/settings_store.dart';\n"
        "import 'package:openhand/app/theme/openhand_theme.dart';\n"
        "import 'dart:ui' as ui;\n"
        '$source\n$_widgetTests',
  );
}

const _widgetTests = r'''
// 仅替换平台视图边界；消息格式分发与延迟加载仍执行生产实现。
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
  _ProbeSettingsStore(this.animated);
  final bool animated;
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(
    snapshot: AppSettingsSnapshot.defaults().copyWith(
      pageAnimationSettings: animated
          ? OpenHandMotionDefaults.page
          : OpenHandMotionDefaults.disabled,
      showSelfLearningMessages: false,
    ),
    canPersist: false,
  );
}

class _ProbeAiController extends ChangeNotifier implements AiSessionController {
  Future<AiSession?> Function(String)? loadOlder;
  int loadCount = 0;
  @override
  AiSession? get currentSession => null;
  @override
  Future<AiSession?> loadOlderSessionMessages(String id) {
    loadCount += 1;
    return loadOlder?.call(id) ?? Future.value();
  }

  @override
  bool isSessionMessagesHydrating(String id) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _TranscriptProbe {
  _TranscriptProbe(this.tester, this.session);
  final WidgetTester tester;
  AiSession session;
  final key = GlobalKey<_SessionTranscriptState>();
  final controller = OpenHandStableScrollController();
  final activity = TranscriptScrollActivity();
  final ai = _ProbeAiController();
  final tts = _ProbeTts();
  late SettingsController settings;
  late StateSetter rebuild;
  int manualReveals = 0;
  VoidCallback? onLayoutChanged;
  _SessionTranscriptState get state => key.currentState!;

  Future<void> mount({
    Size size = const Size(1400, 900),
    bool animated = false,
    bool paused = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = await SettingsController.create(
      store: _ProbeSettingsStore(animated),
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return _SessionTranscript(
                  key: key,
                  controller: controller,
                  onScrollNotification: (_) => false,
                  session: session,
                  sendPhase: AiSendPhase.idle,
                  onLayoutChanged: () => onLayoutChanged?.call(),
                  onMessageExpansionChanged: (_) {},
                  preserveViewportAfterUserScroll: true,
                  onRevealOlderMessages: () => manualReveals += 1,
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

  void update(AiSession value) => rebuild(() => session = value);

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
    await store.save(session.copyWith(messages: [
      ...session.messages.take(session.messages.length - 1), tail,
    ]));
    final window = (await store.loadSessionTailWindow(session.id, limit: 8))!;
    expect(window.messages.length, 8);
    expect(window.messageWindowStartIndex, 992);
    expect(window.messageTotalCount, 1000);
    expect(window.messages.last.content.length, 4096);
    expect(window.messages.last.metadata[aiSessionMessageContentPreviewMetadataKey], true);
    expect(window.messages.last.metadata['tool_execution_stdout'], largeMetadata);
    expect(window.messages.last.metadata.containsKey('request_payload'), false);
    final full = (await store.loadMessage(session.id, tail.id))!;
    expect(full.content, longContent);
    expect(full.metadata['request_payload'], {'内部遥测': '按需恢复'});
    expect(full.metadata.containsKey(aiSessionMessageContentPreviewMetadataKey), false);
    // 损坏单行不能让后台队列丢失后续正常消息。
    await database.database.update('messages', {'metadata_json': '{损坏'},
      where: 'id = ?', whereArgs: ['history-998']);
    final page = await store.loadMessages(session.id, offset: 998, limit: 2);
    expect(page.messages.map((message) => message.id), ['history-998', 'history-999']);
    expect(page.messages.first.metadata, const <String, Object?>{});
    expect(page.messages.last.metadata['tool_execution_stdout'], largeMetadata);
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

  testWidgets('前方布局收缩后富文本进入视口，无滚动也能继续渲染', (tester) async {
    final spacer = ValueNotifier<double>(1200);
    addTearDown(spacer.dispose);
    var built = 0;
    final deferred = DeferredRichContent(
      placeholder: const SizedBox(height: 60),
      builder: (_) { built++; return const Text('已渲染正文'); },
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
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

  testWidgets('富文本等待解析时不暴露 Markdown 源码', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SafeMarkdownBody(
      data: '**待渲染正文**', styleSheet: MarkdownStyleSheet(),
    ))));
    expect(find.text('**待渲染正文**'), findsNothing);
    for (var frame = 0; frame < 6; frame++) await tester.pump();
    expect(find.byType(_RichContentPendingPreview), findsNothing);
  });

  for (final html in [false, true]) {
    testWidgets('离屏真实富文本进入视口后才解析，HTML=$html', (tester) async {
      final controller = ScrollController();
      var richBuildCount = 0;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
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
  for (final animated in [false, true]) {
    testWidgets('首次打开和切换短会话按视口填充，动画=$animated', (tester) async {
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
    testWidgets('首帧耗时超过揭示上限仍定位到最终回复，动画=$animated', (tester) async {
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

  testWidgets('慢首帧揭示后用户开始阅读，剩余定位帧不得抢占滚动', (tester) async {
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

  testWidgets('没有追底请求时首次打开仍显示最新消息并填满视口', (tester) async {
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

  testWidgets('历史加载无进展时停止自动重试，允许手动重试', (tester) async {
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

  testWidgets('异步历史加载返回前切换会话，不污染新窗口', (tester) async {
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

  testWidgets('连续不可见历史有自动分页上限', (tester) async {
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

  testWidgets('历史请求完成前卸载组件不遗留任务', (tester) async {
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
          reason: '加载历史应保持当前阅读位置',
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
    final settings = await SettingsController.create(store: _ProbeSettingsStore(true));
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
    var collapsed = false;
    var sendCount = 0;
    var textScale = 1.0;
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
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: _WorkspaceView(
              draftController: controller,
              messageScrollController: scroll,
              onMessageScrollNotification: (_) => false,
              onMessagePointerSignal: (_) {},
              currentSession: _probeSession('布局回归', 0),
              liveRuntimeToolPreview: null,
              transcriptHydrating: false,
              transcriptLoadError: null,
              onRetryTranscriptLoad: () async {},
              selectedModel: AiModelConfig(
                id: '布局模型', baseUrl: 'https://example.invalid/v1',
                authScheme: AiAuthScheme.bearer, token: '',
                modelId: modelId, protocolType: AiProtocolType.openai,
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
      await tester.tap(find.text(mode));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectActionsVisible();
      await tester.pumpAndSettle();
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
    rebuild(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    rebuild(() { collapsed = false; modelId = 'gpt-4o'; });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(_DecisionComposerForm), findsNothing);
    expect(find.byWidgetPredicate((widget) => widget is TextField && widget.controller == controller), findsOneWidget);
    expectActionsVisible();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
''';
