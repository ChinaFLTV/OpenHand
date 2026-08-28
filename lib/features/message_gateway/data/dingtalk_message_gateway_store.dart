import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/dingtalk_message_gateway.dart';

class DingTalkGatewayStoreSnapshot {
  const DingTalkGatewayStoreSnapshot({
    required this.settings,
    required this.conversations,
  });

  final DingTalkGatewaySettings settings;
  final List<DingTalkConversation> conversations;
}

class DingTalkMessageGatewayStore {
  DingTalkMessageGatewayStore({String? filePath})
    : filePath =
          filePath ??
          p.join(
            OpenHandPaths.defaultMessageGatewayDirectoryPath(),
            'dingtalk.json',
          );

  static const int _maxBytes = 512 * kBytesPerKiB;
  static const int _maxConversations = 200;
  static const int _maxMessagesPerConversation = 1000;
  static const int _maxMessageContentLength = 256 * kBytesPerKiB;
  final String filePath;
  String? _expectedContent;
  bool _loaded = false;
  List<DingTalkConversation> _cachedConversations =
      const <DingTalkConversation>[];

  Future<DingTalkGatewayStoreSnapshot> loadSnapshot() async {
    final file = File(filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await regularFileExistsBounded(file)) {
      _loaded = true;
      _expectedContent = null;
      _cachedConversations = const <DingTalkConversation>[];
      return const DingTalkGatewayStoreSnapshot(
        settings: DingTalkGatewaySettings(),
        conversations: <DingTalkConversation>[],
      );
    }
    final raw = await readBoundedFileString(file, maxBytes: _maxBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('钉钉网关配置必须为对象。');
    final data = stringKeyedMapFromValue(decoded);
    final settings = DingTalkGatewaySettings.fromJson(data);
    final conversations = <DingTalkConversation>[];
    final rawConversations = data['conversations'];
    if (rawConversations is List) {
      for (final item in rawConversations.take(_maxConversations)) {
        if (item is! Map) continue;
        try {
          final conversation = DingTalkConversation.fromJson(
            stringKeyedMapFromValue(item),
          );
          // 20 条限制只用于首次导入远端历史；重启后恢复全部已持久化消息。
          final messages = _keepRecentMessages(
            conversation.messages,
            maxMessages: _maxMessagesPerConversation,
          );
          conversation.messages
            ..clear()
            ..addAll(messages);
          conversations.add(conversation);
        } on FormatException {
          continue;
        }
      }
    }
    _loaded = true;
    _expectedContent = raw;
    _cachedConversations = List<DingTalkConversation>.unmodifiable(
      conversations,
    );
    return DingTalkGatewayStoreSnapshot(
      settings: settings,
      conversations: List<DingTalkConversation>.unmodifiable(conversations),
    );
  }

  Future<DingTalkGatewaySettings> load() async =>
      (await loadSnapshot()).settings;

  Future<void> save(DingTalkGatewaySettings value) =>
      saveSnapshot(settings: value, conversations: _cachedConversations);

  Future<void> saveSnapshot({
    required DingTalkGatewaySettings settings,
    required Iterable<DingTalkConversation> conversations,
  }) async {
    if (!_loaded) throw StateError('钉钉网关配置缺少可信快照。');
    final file = File(filePath);
    final exists = await regularFileExistsBounded(file);
    if (_expectedContent == null ? exists : !exists) {
      throw StateError('钉钉网关配置已被外部修改。');
    }
    if (_expectedContent != null &&
        await readBoundedFileString(file, maxBytes: _maxBytes) !=
            _expectedContent) {
      throw StateError('钉钉网关配置已被外部修改。');
    }
    final normalized = settings.normalized();
    final limitedConversations = conversations
        .take(_maxConversations)
        .map((conversation) {
          final messages = _keepRecentMessages(
            conversation.messages,
            maxMessages: _maxMessagesPerConversation,
          );
          return conversation.snapshot(messages: messages);
        })
        .toList(growable: true);
    limitedConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    String encodePayload() {
      final payload = <String, Object?>{
        ...normalized.toJson(),
        'conversations': limitedConversations
            .map((conversation) => conversation.toJson())
            .toList(growable: false),
      };
      return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
    }

    var content = encodePayload();
    while (utf8.encode(content).length > _maxBytes &&
        limitedConversations.isNotEmpty) {
      var largestIndex = -1;
      var largestMessageCount = 0;
      for (var index = 0; index < limitedConversations.length; index++) {
        final count = limitedConversations[index].messages.length;
        if (count > largestMessageCount) {
          largestMessageCount = count;
          largestIndex = index;
        }
      }
      if (largestIndex >= 0) {
        final messages = limitedConversations[largestIndex].messages;
        final removeCount = (messages.length ~/ 4).clamp(1, messages.length);
        messages.removeRange(0, removeCount);
      } else {
        limitedConversations.removeLast();
      }
      content = encodePayload();
    }
    await writeFileAtomically(file, content);
    _expectedContent = content;
    _cachedConversations = List<DingTalkConversation>.unmodifiable(
      limitedConversations,
    );
  }

  List<DingTalkGatewayMessage> _keepRecentMessages(
    Iterable<DingTalkGatewayMessage> source, {
    required int maxMessages,
  }) {
    final messages = source
        .where((message) => message.content.length <= _maxMessageContentLength)
        .toList(growable: true);
    final indexed = messages.asMap().entries.toList(growable: true);
    indexed.sort((left, right) {
      final created = left.value.createdAt.compareTo(right.value.createdAt);
      return created != 0 ? created : left.key.compareTo(right.key);
    });
    final ordered = indexed.map((entry) => entry.value).toList(growable: false);
    if (ordered.length <= maxMessages) {
      return List<DingTalkGatewayMessage>.unmodifiable(ordered);
    }
    return List<DingTalkGatewayMessage>.unmodifiable(
      ordered.skip(ordered.length - maxMessages),
    );
  }
}
