import 'dart:async';
import 'dart:isolate';

import 'package:markdown/markdown.dart' as md;

import '../util/serial_task_queue.dart';
import 'markdown_ast_sanitizer.dart';

/// 长正文串行解析，失效任务在启动前丢弃，不把组件状态传入工作线程。
final _parseQueue = SerialTaskQueue(maxPendingTasks: 16);
const _parseTimeout = Duration(seconds: 10);

Future<List<md.Node>?> parseOpenHandMarkdownOffThread(
  String source, {
  required List<md.InlineSyntax> inlineSyntaxes,
  required bool Function() isValid,
}) => _parseQueue.enqueue(() {
  if (!isValid()) return Future<List<md.Node>?>.value();
  return _parseInIsolate(source, inlineSyntaxes);
});

Future<List<md.Node>> _parseInIsolate(
  String source,
  List<md.InlineSyntax> inlineSyntaxes,
) async {
  final results = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn(
      _parseMessage,
      (source: source, syntaxes: inlineSyntaxes, reply: results.sendPort),
      onError: results.sendPort,
      onExit: results.sendPort,
      debugName: '消息正文解析',
    );
    final result = await results.first.timeout(_parseTimeout);
    if (result is List<md.Node>) return result;
    if (result is List && result.length == 2) {
      throw RemoteError('${result[0]}', '${result[1]}');
    }
    throw StateError('后台 Markdown 解析未返回结果。');
  } finally {
    // 超时也终止实际任务，不能只超时 Future 后继续占用后台计算资源。
    worker?.kill(priority: Isolate.immediate);
    results.close();
  }
}

void _parseMessage(
  ({String source, List<md.InlineSyntax> syntaxes, SendPort reply}) input,
) => Isolate.exit(
  input.reply,
  parseOpenHandMarkdown(input.source, inlineSyntaxes: input.syntaxes),
);
