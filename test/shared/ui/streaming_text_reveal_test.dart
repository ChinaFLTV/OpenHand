import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';
import 'package:openhand/shared/ui/streaming_text_reveal.dart';

void main() {
  testWidgets(
    'reveals complete grapheme clusters and disposes active tickers',
    (tester) async {
      const family = '👨‍👩‍👧‍👦';
      await tester.pumpWidget(
        _app(
          StreamingTextRevealText(
            text: 'A${family}B',
            streaming: true,
            builder: (_, visibleText) =>
                Text(visibleText, key: const ValueKey<String>('visible-text')),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 17));
      expect(_textData(tester, 'visible-text'), 'A');
      await tester.pump(const Duration(milliseconds: 17));
      expect(_textData(tester, 'visible-text'), 'A$family');
      await tester.pump(const Duration(milliseconds: 17));
      expect(_textData(tester, 'visible-text'), 'A${family}B');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bypasses animation for reduced motion and disabled TickerMode', (
    tester,
  ) async {
    Widget reveal() => StreamingTextRevealText(
      text: '完整正文',
      streaming: true,
      builder: (_, visibleText) =>
          Text(visibleText, key: const ValueKey<String>('motion-text')),
    );

    await tester.pumpWidget(_app(reveal(), disableAnimations: true));
    expect(_textData(tester, 'motion-text'), '完整正文');

    await tester.pumpWidget(_app(reveal(), tickerEnabled: false));
    expect(_textData(tester, 'motion-text'), '完整正文');
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('settles and can restart when streaming resumes', (tester) async {
    final key = GlobalKey<_RevealHarnessState>();
    await tester.pumpWidget(_app(_RevealHarness(key: key)));

    await tester.pump(const Duration(milliseconds: 17));
    await tester.pump(const Duration(milliseconds: 17));
    expect(_textData(tester, 'reveal-state'), 'active:ab');

    key.currentState!.update(text: 'ab', streaming: false);
    await tester.pump();
    expect(_textData(tester, 'reveal-state'), 'settled:ab');

    key.currentState!.update(text: 'abc', streaming: true);
    await tester.pump();
    expect(_textData(tester, 'reveal-state'), 'active:ab');
    await tester.pump(const Duration(milliseconds: 17));
    expect(_textData(tester, 'reveal-state'), 'active:abc');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders over-limit streaming text without incremental work', (
    tester,
  ) async {
    final text = List<String>.filled(32 * 1024 + 1, 'x').join();
    await tester.pumpWidget(
      _app(
        StreamingTextRevealText(
          text: text,
          streaming: true,
          builder: (_, visibleText) => Text(
            '${visibleText.length}',
            key: const ValueKey<String>('long-text-length'),
          ),
        ),
      ),
    );

    expect(_textData(tester, 'long-text-length'), '${text.length}');
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reverse Sliver keeps a coherent topology during streaming churn',
    (tester) async {
      _nextProbeToken = 0;
      final key = GlobalKey<_StreamingMessageListState>();
      final base = DateTime.utc(2026, 9, 2, 13);
      final localEcho = _message(
        id: 'assistant-source-1',
        content: '正在生成第一段内容',
        createdAt: base.add(const Duration(minutes: 1)),
        sourceId: 'source-1',
      );
      await tester.pumpWidget(
        _app(
          _StreamingMessageList(
            key: key,
            messages: <DingTalkGatewayMessage>[
              _message(
                id: 'user-1',
                content: '问题',
                createdAt: base,
                role: DingTalkGatewayMessageRole.user,
              ),
              localEcho,
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 17));
      final tokenBeforeBinding = _textData(tester, 'probe:ai:source-1');

      key.currentState!.replaceMessages(<DingTalkGatewayMessage>[
        _message(
          id: 'user-1',
          content: '问题',
          createdAt: base,
          role: DingTalkGatewayMessageRole.user,
        ),
        localEcho.copyWith(id: 'remote-source-1', content: '正在生成第一段内容，并继续追加'),
      ]);
      await tester.pump();
      expect(_textData(tester, 'probe:ai:source-1'), tokenBeforeBinding);
      await tester.pump(const Duration(milliseconds: 17));
      expect(tester.takeException(), isNull);

      // 注入旧快照可能产生的重复 source；两个 row 必须退回各自物理 ID。
      key.currentState!.replaceMessages(<DingTalkGatewayMessage>[
        _message(
          id: 'older-1',
          content: '更早历史',
          createdAt: base.subtract(const Duration(minutes: 1)),
          role: DingTalkGatewayMessageRole.user,
        ),
        _message(
          id: 'user-1',
          content: '问题',
          createdAt: base,
          role: DingTalkGatewayMessageRole.user,
        ),
        localEcho.copyWith(id: 'remote-source-1', content: '第一条冲突回显仍在流式更新'),
        _message(
          id: 'remote-source-2',
          content: '第二条冲突回显也在流式更新',
          createdAt: base.add(const Duration(minutes: 2)),
          sourceId: 'source-1',
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 17));
      expect(
        find.byKey(const ValueKey<String>('probe:message:remote-source-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('probe:message:remote-source-2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // 快速追加并触发滚动回收，旧 delegate 也只能读取自己的不可变快照。
      for (var round = 0; round < 6; round++) {
        key.currentState!.replaceMessages(<DingTalkGatewayMessage>[
          for (var index = 0; index < 36; index++)
            _message(
              id: 'history-$index',
              content: '历史消息 $index',
              createdAt: base.subtract(Duration(minutes: 40 - index)),
              role: DingTalkGatewayMessageRole.user,
            ),
          localEcho.copyWith(
            id: 'remote-source-1',
            content: '持续流式更新 ${List<String>.filled(round + 1, '内容').join()}',
          ),
        ]);
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.drag(
        find.byKey(const ValueKey<String>('streaming-message-list')),
        const Offset(0, 800),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(
  Widget child, {
  bool disableAnimations = false,
  bool tickerEnabled = true,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: TickerMode(
        enabled: tickerEnabled,
        child: Scaffold(body: child),
      ),
    ),
  );
}

String _textData(WidgetTester tester, String key) {
  return tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;
}

class _RevealHarness extends StatefulWidget {
  const _RevealHarness({super.key});

  @override
  State<_RevealHarness> createState() => _RevealHarnessState();
}

class _RevealHarnessState extends State<_RevealHarness> {
  String _text = 'ab';
  bool _streaming = true;

  void update({required String text, required bool streaming}) {
    setState(() {
      _text = text;
      _streaming = streaming;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamingTextRevealText(
      text: _text,
      streaming: _streaming,
      builder: (_, visibleText) => Text(
        'active:$visibleText',
        key: const ValueKey<String>('reveal-state'),
      ),
      settledBuilder: (_, visibleText) => Text(
        'settled:$visibleText',
        key: const ValueKey<String>('reveal-state'),
      ),
    );
  }
}

class _StreamingMessageList extends StatefulWidget {
  const _StreamingMessageList({super.key, required this.messages});

  final List<DingTalkGatewayMessage> messages;

  @override
  State<_StreamingMessageList> createState() => _StreamingMessageListState();
}

class _StreamingMessageListState extends State<_StreamingMessageList> {
  late List<DingTalkGatewayMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = widget.messages;
  }

  void replaceMessages(List<DingTalkGatewayMessage> messages) {
    setState(() => _messages = messages);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = List<DingTalkGatewayMessage>.unmodifiable(_messages);
    final topology = DingTalkMessageRenderTopology(snapshot);
    return SizedBox(
      height: 220,
      child: ListView.builder(
        key: const ValueKey<String>('streaming-message-list'),
        reverse: true,
        itemCount: snapshot.length,
        findChildIndexCallback: (key) {
          if (key case ValueKey<String>(value: final identity)) {
            return topology.reverseIndexOf(identity);
          }
          return null;
        },
        itemBuilder: (_, index) {
          final messageIndex = snapshot.length - index - 1;
          final message = snapshot[messageIndex];
          final identity = topology.identityAt(messageIndex);
          return RepaintBoundary(
            key: ValueKey<String>(identity),
            child: _ProbeMessageRow(identity: identity, message: message),
          );
        },
      ),
    );
  }
}

var _nextProbeToken = 0;

class _ProbeMessageRow extends StatefulWidget {
  const _ProbeMessageRow({required this.identity, required this.message});

  final String identity;
  final DingTalkGatewayMessage message;

  @override
  State<_ProbeMessageRow> createState() => _ProbeMessageRowState();
}

class _ProbeMessageRowState extends State<_ProbeMessageRow> {
  late final int _token = ++_nextProbeToken;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'probe:$_token',
          key: ValueKey<String>('probe:${widget.identity}'),
        ),
        StreamingTextRevealText(
          text: widget.message.content,
          streaming: widget.message.sourceAiMessageId.isNotEmpty,
          animateSize: false,
          builder: (_, visibleText) => Text(visibleText),
        ),
      ],
    );
  }
}

DingTalkGatewayMessage _message({
  required String id,
  required String content,
  required DateTime createdAt,
  String sourceId = '',
  DingTalkGatewayMessageRole role = DingTalkGatewayMessageRole.assistant,
}) {
  return DingTalkGatewayMessage(
    id: id,
    conversationId: 'conversation',
    conversationType: DingTalkConversationType.direct,
    role: role,
    content: content,
    createdAt: createdAt,
    sourceAiMessageId: sourceId,
  );
}
