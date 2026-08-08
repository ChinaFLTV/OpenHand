import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../plugin_service/index.dart';
import '../model/dingtalk_message_gateway.dart';

class DingTalkGatewayQueryResult {
  const DingTalkGatewayQueryResult({required this.messages, this.warning});

  final List<DingTalkGatewayMessage> messages;
  final String? warning;
}

class DingTalkMessageGatewayService {
  static const Duration _commandTimeout = Duration(seconds: 25);
  static const Duration _authTimeout = Duration(minutes: 15);
  Process? _authProcess;
  String? _executable;
  bool _authCancelled = false;

  String? get cachedExecutable => _executable;

  Future<String?> executable() async {
    return _executable ??= await resolvePluginDingtalkWorkspaceCliExecutable();
  }

  Future<DingTalkAuthStatus> authStatus() async {
    final decoded = await _runJson(const <String>[
      'auth',
      'status',
      '--format',
      'json',
    ]);
    final map = _asMap(decoded);
    final authenticated =
        _asBool(map['authenticated']) ||
        _asBool(_asMap(map['data'])['authenticated']);
    final identityMap = _asMap(map['identity']).isNotEmpty
        ? _asMap(map['identity'])
        : _asMap(map['profile']);
    return DingTalkAuthStatus(
      authenticated: authenticated,
      identity: DingTalkIdentity(
        profile: '${identityMap['profile'] ?? map['profile'] ?? ''}',
        userId:
            '${identityMap['userId'] ?? identityMap['user_id'] ?? identityMap['openDingTalkId'] ?? ''}',
        name:
            '${identityMap['name'] ?? identityMap['nick'] ?? identityMap['userName'] ?? ''}',
      ),
    );
  }

  Future<DingTalkAuthStatus> authorize({
    required Future<void> Function(String url) onDeviceUrl,
  }) async {
    _authCancelled = false;
    final executable = await _requireExecutable();
    final process = await startTrackedProcessBounded(
      executable,
      const <String>[
        'auth',
        'login',
        '--device',
        '--no-browser',
        '--format',
        'json',
      ],
      timeout: const Duration(seconds: 8),
      tag: 'dingtalk.auth.login',
      startInNewProcessGroup: true,
    );
    _authProcess = process;
    final output = StringBuffer();
    late final StreamSubscription<String> stdoutSub;
    late final StreamSubscription<String> stderrSub;
    var opened = false;
    void consume(String line) {
      output.writeln(line);
      if (opened) return;
      final url = RegExp(r'https?://[^\s]+').firstMatch(line)?.group(0);
      if (url == null) return;
      opened = true;
      unawaited(onDeviceUrl(url));
    }

    stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          consume,
          onError: (Object error, StackTrace stack) {
            silentLog('dingtalk_gateway', '读取授权输出', error, stack);
          },
        );
    stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          consume,
          onError: (Object error, StackTrace stack) {
            silentLog('dingtalk_gateway', '读取授权错误输出', error, stack);
          },
        );
    try {
      final exitCode = await process.exitCode.timeout(
        _authTimeout,
        onTimeout: () async {
          await terminateTrackedProcessTree(
            process,
            gracefulTimeout: const Duration(seconds: 2),
          );
          return -1;
        },
      );
      if (exitCode != 0) {
        if (_authCancelled) return authStatus();
        throw StateError(
          output.toString().trim().isEmpty
              ? '钉钉授权未完成。'
              : output.toString().trim(),
        );
      }
      return await authStatus();
    } finally {
      _authProcess = null;
      await stdoutSub.cancel();
      await stderrSub.cancel();
    }
  }

  Future<void> cancelAuthorization() async {
    _authCancelled = true;
    final process = _authProcess;
    _authProcess = null;
    if (process != null) {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: const Duration(seconds: 1),
      );
    }
  }

  Future<DingTalkAuthStatus> logout({String? profile}) async {
    final args = <String>['auth', 'logout'];
    if (profile != null && profile.trim().isNotEmpty) {
      args.addAll(<String>['--profile', profile.trim()]);
    }
    args.addAll(const <String>['--yes', '--format', 'json']);
    await _runJson(args);
    return authStatus();
  }

  Future<DingTalkGatewayQueryResult> query({
    required DateTime start,
    required DateTime end,
  }) async {
    final startText = start.toIso8601String();
    final endText = end.toIso8601String();
    final mentions = await _runJson(<String>[
      'chat',
      'message',
      'list-mentions',
      '--start',
      startText,
      '--end',
      endText,
      '--limit',
      '50',
      '--cursor',
      '0',
      '--format',
      'json',
    ]);
    final all = await _runJson(<String>[
      'chat',
      'message',
      'list-all',
      '--start',
      startText,
      '--end',
      endText,
      '--limit',
      '50',
      '--cursor',
      '0',
      '--format',
      'json',
    ]);
    final messages = <DingTalkGatewayMessage>[
      ..._parseMessages(mentions),
      ..._parseMessages(all),
    ];
    final allMap = _asMap(all);
    final warning =
        allMap['friendly_hint']?.toString() ??
        _asMap(allMap['data'])['friendly_hint']?.toString();
    return DingTalkGatewayQueryResult(messages: messages, warning: warning);
  }

  Future<void> send({
    required DingTalkConversation conversation,
    required String text,
    required String uuid,
  }) async {
    final targetFlag = conversation.type == DingTalkConversationType.group
        ? '--group'
        : '--user';
    await _runJson(<String>[
      'chat',
      'message',
      'send',
      targetFlag,
      conversation.id,
      '--text',
      text,
      '--uuid',
      uuid,
      '--format',
      'json',
    ]);
  }

  Future<String> _requireExecutable() async {
    final path = await executable();
    if (path == null || path.trim().isEmpty) {
      throw StateError('未找到 DingTalk Workspace CLI（dws），请先在插件板块安装。');
    }
    return path;
  }

  Future<Object?> _runJson(List<String> arguments) async {
    final executable = await _requireExecutable();
    final result = await runTrackedProcessWithLineLogging(
      executable,
      arguments,
      timeout: _commandTimeout,
      tag: 'dingtalk_gateway.command',
      maxCapturedLinesPerStream: 4096,
    );
    final decoded = _decodeJson(result.stdout);
    if (result.exitCode != 0) {
      throw StateError(
        _asMap(decoded)['message']?.toString() ??
            result.stderr.trim().ifEmpty('dws 执行失败。'),
      );
    }
    return decoded;
  }

  Object? _decodeJson(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const <String, Object?>{};
    try {
      return jsonDecode(text);
    } catch (_) {
      for (final line in text.split(RegExp(r'\r?\n')).reversed) {
        final candidate = line.trim();
        if (!(candidate.startsWith('{') || candidate.startsWith('['))) continue;
        try {
          return jsonDecode(candidate);
        } catch (_) {}
      }
    }
    return const <String, Object?>{};
  }

  List<DingTalkGatewayMessage> _parseMessages(Object? raw) {
    final values = <Object?>[];
    void collect(Object? value) {
      if (value is List) {
        values.addAll(value);
        return;
      }
      if (value is Map) {
        for (final key in const <String>[
          'messages',
          'items',
          'records',
          'data',
          'result',
        ]) {
          final child = value[key];
          if (child is List) values.addAll(child);
          if (child is Map) collect(child);
        }
      }
    }

    collect(raw);
    final result = <DingTalkGatewayMessage>[];
    for (final value in values) {
      if (value is! Map) continue;
      final map = _asMap(value);
      final id = _first(map, const <String>[
        'openMessageId',
        'messageId',
        'id',
      ]);
      final content = _content(map);
      final conversationId = _first(map, const <String>[
        'openConversationId',
        'conversationId',
        'conversation_id',
      ]);
      if (id.isEmpty || content.isEmpty || conversationId.isEmpty) continue;
      final typeText = _first(map, const <String>[
        'conversationType',
        'conversation_type',
        'chatType',
      ]).toLowerCase();
      result.add(
        DingTalkGatewayMessage(
          id: id,
          conversationId: conversationId,
          conversationType: typeText.contains('group') || typeText == '2'
              ? DingTalkConversationType.group
              : DingTalkConversationType.direct,
          role: DingTalkGatewayMessageRole.user,
          content: content,
          createdAt:
              DateTime.tryParse(
                _first(map, const <String>[
                  'createTime',
                  'createdAt',
                  'create_time',
                ]),
              )?.toLocal() ??
              DateTime.now(),
          senderName: _first(map, const <String>[
            'senderName',
            'senderNick',
            'sender_name',
            'nick',
          ]),
          senderId: _first(map, const <String>[
            'senderId',
            'senderUserId',
            'senderOpenDingTalkId',
            'sender_id',
          ]),
          conversationTitle: _first(map, const <String>[
            'conversationTitle',
            'groupName',
            'title',
          ]),
          fromSelf: _asBool(map['isSelf']) || _asBool(map['isMine']),
        ),
      );
    }
    return result;
  }

  String _content(Map<String, Object?> map) {
    final value = map['content'] ?? map['text'] ?? map['msgContent'];
    if (value is String) return value.trim();
    if (value is Map) {
      return '${value['text'] ?? value['content'] ?? ''}'.trim();
    }
    return '';
  }

  String _first(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    }
    return '';
  }

  Map<String, Object?> _asMap(Object? value) => value is Map
      ? value.map((key, value) => MapEntry('$key', value))
      : <String, Object?>{};
  bool _asBool(Object? value) =>
      value == true || '$value'.toLowerCase() == 'true';
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
