import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
    String? authorizationCode;
    String? pendingUrl;

    Future<void> openPendingUrl() async {
      if (opened || pendingUrl == null) return;
      final rawUrl = pendingUrl!;
      final code = authorizationCode;
      var url = rawUrl;
      if (code != null && code.isNotEmpty) {
        final parsed = Uri.tryParse(rawUrl);
        if (parsed != null) {
          final query = <String, String>{
            ...parsed.queryParameters,
            'user_code': code,
          };
          url = parsed.replace(queryParameters: query).toString();
        }
      }
      opened = true;
      await onDeviceUrl(url);
    }

    void consume(String line) {
      output.writeln(line);
      if (opened) return;
      final code = RegExp(
        r'authorization\s+code\s*:\s*([A-Za-z0-9]+(?:-[A-Za-z0-9]+)?)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      if (code != null && code.trim().isNotEmpty) {
        authorizationCode = code.trim();
      }
      final url = RegExp(r'https?://[^\s]+').firstMatch(line)?.group(0);
      if (url != null) {
        pendingUrl = url.replaceAll(RegExp(r'[),.]+$'), '');
      }
      if (pendingUrl != null &&
          (authorizationCode != null || pendingUrl!.contains('user_code='))) {
        unawaited(openPendingUrl());
      }
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
    final allStartText = _formatChatDateTime(start);
    final allEndText = _formatChatDateTime(end);
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
      allStartText,
      '--end',
      allEndText,
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

  Future<List<DingTalkConversationTarget>> searchTargets({
    required DingTalkConversationType type,
    required String query,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const <DingTalkConversationTarget>[];
    final arguments = type == DingTalkConversationType.group
        ? <String>[
            'chat',
            '+chat-search',
            '--query',
            keyword,
            '--limit',
            '20',
            '--format',
            'json',
          ]
        : <String>[
            'contact',
            '+search-user',
            '--query',
            keyword,
            '--format',
            'json',
          ];
    final decoded = await _runJson(arguments);
    return _parseTargets(decoded, type: type);
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

  /// 查询会话及其关联资料。返回原始 JSON，调用方负责完整展示字段。
  Future<Object?> conversationDetails({
    required DingTalkConversation conversation,
  }) async {
    final details = await _loadConversationInfo(conversation);
    final result = <String, Object?>{'会话信息': details};
    if (conversation.type == DingTalkConversationType.group) {
      Object? members;
      try {
        members = await _loadAllGroupMembers(conversation.id);
        result['群成员'] = members;
      } catch (error, stack) {
        silentLog('dingtalk_gateway', '读取群成员详情', error, stack);
      }
      final memberUserIds = _extractUserIds(members);
      if (memberUserIds.isNotEmpty) {
        final memberProfiles = await _loadUserDetails(memberUserIds);
        if (memberProfiles != null) result['群成员资料'] = memberProfiles;
      }
    } else {
      Object? contact;
      try {
        contact = await _runJson(<String>[
          'contact',
          'user',
          'get',
          '--ids',
          conversation.id,
          '--format',
          'json',
        ]);
        result['联系人信息'] = contact;
      } catch (error, stack) {
        try {
          contact = await _runJson(<String>[
            'contact',
            '+lookup',
            '--name',
            conversation.title,
            '--format',
            'json',
          ]);
          result['联系人信息'] = contact;
        } catch (fallbackError, fallbackStack) {
          silentLog(
            'dingtalk_gateway',
            '读取联系人详情',
            fallbackError,
            fallbackStack,
          );
          silentLog('dingtalk_gateway', '联系人详情查询失败', error, stack);
        }
      }
      final staffId = _extractFirstStaffId(contact);
      if (staffId.isNotEmpty) {
        try {
          result['联系人档案'] = await _runJson(<String>[
            'contact',
            'user',
            'profile',
            'get',
            '--staff-id',
            staffId,
            '--format',
            'json',
          ]);
        } catch (error, stack) {
          // 花名册需要额外权限，没有权限时仍展示通讯录基础资料。
          silentLog('dingtalk_gateway', '读取联系人档案', error, stack);
        }
      }
    }
    return result;
  }

  Future<Object?> _loadConversationInfo(
    DingTalkConversation conversation,
  ) async {
    final primaryFlag = conversation.type == DingTalkConversationType.group
        ? '--group'
        : '--user';
    try {
      return await _runJson(<String>[
        'chat',
        'conversation-info',
        primaryFlag,
        conversation.id,
        '--format',
        'json',
      ]);
    } catch (error, stack) {
      if (conversation.type == DingTalkConversationType.direct) {
        try {
          return await _runJson(<String>[
            'chat',
            'conversation-info',
            '--open-dingtalk-id',
            conversation.id,
            '--format',
            'json',
          ]);
        } catch (fallbackError, fallbackStack) {
          silentLog('dingtalk_gateway', '读取会话基础信息', error, stack);
          silentLog(
            'dingtalk_gateway',
            '读取会话基础信息备用标识',
            fallbackError,
            fallbackStack,
          );
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<Object?> _loadUserDetails(List<String> userIds) async {
    final pages = <Object?>[];
    for (var offset = 0; offset < userIds.length; offset += 30) {
      final end = math.min(offset + 30, userIds.length);
      try {
        pages.add(
          await _runJson(<String>[
            'contact',
            'user',
            'get',
            '--ids',
            userIds.sublist(offset, end).join(','),
            '--format',
            'json',
          ]),
        );
      } catch (error, stack) {
        silentLog('dingtalk_gateway', '读取群成员组织资料', error, stack);
      }
    }
    if (pages.isEmpty) return null;
    return pages.length == 1 ? pages.first : <String, Object?>{'pages': pages};
  }

  List<String> _extractUserIds(Object? value) {
    final ids = <String>{};
    void visit(Object? current) {
      if (ids.length >= 300) return;
      if (current is Map) {
        final map = _asMap(current);
        for (final key in const <String>[
          'userId',
          'user_id',
          'orgUserId',
          'org_user_id',
          'memberUserId',
          'member_user_id',
        ]) {
          final id = '${map[key] ?? ''}'.trim();
          if (id.isNotEmpty) ids.add(id);
        }
        for (final item in map.values) {
          visit(item);
        }
      } else if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(value);
    return ids.toList(growable: false);
  }

  String _extractFirstUserId(Object? value) {
    return _extractUserIds(value).firstOrNull ?? '';
  }

  String _extractFirstStaffId(Object? value) {
    String? found;
    void visit(Object? current) {
      if (found != null) return;
      if (current is Map) {
        final map = _asMap(current);
        for (final key in const <String>['staffId', 'staff_id']) {
          final candidate = '${map[key] ?? ''}'.trim();
          if (candidate.isNotEmpty) {
            found = candidate;
            return;
          }
        }
        for (final item in map.values) {
          visit(item);
        }
      } else if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(value);
    return found ?? _extractFirstUserId(value);
  }

  Future<Object?> _loadAllGroupMembers(String conversationId) async {
    const maxPages = 100;
    final pages = <Object?>[];
    var cursor = '0';
    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final page = await _runJson(<String>[
        'chat',
        'group',
        'members',
        '--id',
        conversationId,
        '--cursor',
        cursor,
        '--format',
        'json',
      ]);
      pages.add(page);
      final map = _asMap(page);
      final data = _asMap(map['data']);
      final result = _asMap(map['result']);
      final hasMore =
          _asBool(map['hasMore']) ||
          _asBool(data['hasMore']) ||
          _asBool(result['hasMore']);
      final nextCursor = _firstValues(<Object?>[
        map['nextCursor'],
        map['next_cursor'],
        data['nextCursor'],
        data['next_cursor'],
        result['nextCursor'],
        result['next_cursor'],
      ]);
      if (!hasMore || nextCursor.isEmpty || nextCursor == cursor) break;
      cursor = nextCursor;
    }
    return pages.length == 1 ? pages.first : <String, Object?>{'pages': pages};
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

  List<DingTalkConversationTarget> _parseTargets(
    Object? raw, {
    required DingTalkConversationType type,
  }) {
    final result = <DingTalkConversationTarget>[];
    final seen = <String>{};
    void visit(Object? value, int depth) {
      if (depth > 4 || result.length >= 50) return;
      if (value is List) {
        for (final item in value) {
          visit(item, depth + 1);
          if (result.length >= 50) return;
        }
        return;
      }
      if (value is! Map) return;
      final map = _asMap(value);
      final id = type == DingTalkConversationType.group
          ? _first(map, const <String>[
              'openConversationId',
              'conversationId',
              'conversation_id',
              'id',
            ])
          : _first(map, const <String>[
              'userId',
              'user_id',
              'openDingTalkId',
              'open_dingtalk_id',
              'id',
            ]);
      final title = type == DingTalkConversationType.group
          ? _first(map, const <String>['name', 'groupName', 'title'])
          : _first(map, const <String>['name', 'nick', 'userName', 'title']);
      if (id.isNotEmpty && title.isNotEmpty && seen.add(id)) {
        result.add(
          DingTalkConversationTarget(
            id: id,
            title: title,
            type: type,
            subtitle: _first(map, const <String>[
              'subtitle',
              'departmentName',
              'department',
              'description',
            ]),
          ),
        );
      }
      for (final child in map.values) {
        if (child is Map || child is List) visit(child, depth + 1);
      }
    }

    visit(raw, 0);
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

  String _formatChatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _first(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    }
    return '';
  }

  String _firstValues(Iterable<Object?> values) {
    for (final value in values) {
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
