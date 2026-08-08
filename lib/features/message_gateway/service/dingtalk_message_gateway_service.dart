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

/// dws 返回的业务错误。可选详情接口失败时由调用方按错误类别降级处理。
class DingTalkGatewayCommandException implements Exception {
  const DingTalkGatewayCommandException({
    required this.message,
    this.category,
    this.reason,
    this.serverCode,
    this.operation,
  });

  final String message;
  final String? category;
  final String? reason;
  final String? serverCode;
  final String? operation;

  bool get isBusinessError =>
      category == 'api' ||
      reason == 'business_error' ||
      (serverCode != null && serverCode!.trim().isNotEmpty);

  bool get isPermissionDenied =>
      serverCode == '2001' ||
      message.contains('无花名册管理权限') ||
      message.contains('权限不足') ||
      message.contains('无权限');

  @override
  String toString() => message;
}

class DingTalkMessageGatewayService {
  static const Duration _commandTimeout = Duration(seconds: 25);
  static const Duration _authTimeout = Duration(minutes: 15);
  static const int _batchSize = 30;
  static const int _detailConcurrency = 4;
  Process? _authProcess;
  String? _executable;
  bool _authCancelled = false;
  bool _rosterAccessDenied = false;

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
    _rosterAccessDenied = false;
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
    _rosterAccessDenied = false;
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

  /// 查询会话及其关联资料。返回原始 JSON，调用方负责结构化展示字段。
  Future<Object?> conversationDetails({
    required DingTalkConversation conversation,
  }) async {
    final result = <String, Object?>{};
    if (conversation.type == DingTalkConversationType.group) {
      final initialDetails = await Future.wait(
        <Future<MapEntry<String, Object?>?>>[
          _loadDetail('会话信息', () => _loadConversationInfo(conversation)),
          _loadDetail(
            '群聊设置',
            () => _runJson(<String>[
              'chat',
              'group',
              'user-settings',
              'query',
              '--groups',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail(
            '禁言配置',
            () => _runJson(<String>[
              'chat',
              'group',
              'get-mute-config',
              '--group',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail(
            '群机器人',
            () => _runJson(<String>[
              'chat',
              'group',
              'bots',
              '--group',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail(
            '群身份',
            () => _runJson(<String>[
              'chat',
              'group-role',
              'list',
              '--group',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail('群成员', () => _loadAllGroupMembers(conversation.id)),
        ],
      );
      for (final entry in initialDetails.nonNulls) {
        result[entry.key] = entry.value;
      }

      final members = result['群成员'];
      final memberUserIds = _extractUserIds(members);
      Object? memberProfiles;
      if (memberUserIds.isNotEmpty) {
        final profileEntry = await _loadDetail(
          '群成员资料',
          () => _loadUserDetails(memberUserIds),
        );
        if (profileEntry != null) {
          memberProfiles = profileEntry.value;
          result[profileEntry.key] = profileEntry.value;
        }
      }
      final memberOpenIds = <String>{
        ..._extractOpenDingTalkIds(members),
        ..._extractOpenDingTalkIds(memberProfiles),
      }.toList(growable: false);
      final enrichmentDetails =
          await Future.wait(<Future<MapEntry<String, Object?>?>>[
            if (memberOpenIds.isNotEmpty)
              _loadDetail(
                '群成员详情',
                () => _loadGroupMemberDetails(conversation.id, memberOpenIds),
              ),
            if (_extractGroupRoleIds(result['群身份']).isNotEmpty &&
                (memberUserIds.isNotEmpty || memberOpenIds.isNotEmpty))
              _loadDetail(
                '群成员身份',
                () => _loadGroupMemberRoles(
                  conversation.id,
                  memberUserIds.isNotEmpty ? memberUserIds : memberOpenIds,
                ),
              ),
          ]);
      for (final entry in enrichmentDetails.nonNulls) {
        result[entry.key] = entry.value;
      }
    } else {
      final initialDetails = await Future.wait(
        <Future<MapEntry<String, Object?>?>>[
          _loadDetail('会话信息', () => _loadConversationInfo(conversation)),
          _loadDetail('联系人信息', () => _loadContact(conversation)),
          _loadDetail('可见花名册字段', _loadRosterFields),
          _loadDetail(
            '特别关注列表',
            () => _runJson(const <String>[
              'contact',
              'relation',
              'list-my-followings',
              '--format',
              'json',
            ]),
          ),
        ],
      );
      for (final entry in initialDetails.nonNulls) {
        result[entry.key] = entry.value;
      }

      final contact = result['联系人信息'];
      final staffId = _extractFirstStaffId(contact);
      final departmentIds = _extractDepartmentIds(contact);
      final contactDetails =
          await Future.wait(<Future<MapEntry<String, Object?>?>>[
            if (staffId.isNotEmpty && !_rosterAccessDenied)
              _loadDetail('联系人档案', () => _loadRosterProfile(staffId)),
            if (departmentIds.isNotEmpty)
              _loadDetail('部门资料', () => _loadDepartmentDetails(departmentIds)),
          ]);
      for (final entry in contactDetails.nonNulls) {
        result[entry.key] = entry.value;
      }
      final following = result.remove('特别关注列表');
      if (following != null) {
        result['关注状态'] = _matchFollowingContact(following, <String>{
          conversation.id,
          ..._extractContactIds(contact),
        });
      }
    }
    return result;
  }

  Future<MapEntry<String, Object?>?> _loadDetail(
    String name,
    Future<Object?> Function() loader,
  ) async {
    try {
      final value = await loader();
      return MapEntry<String, Object?>(name, value);
    } catch (error, stack) {
      if (error is DingTalkGatewayCommandException && error.isBusinessError) {
        return null;
      }
      silentLog('dingtalk_gateway', '读取$name', error, stack);
      return null;
    }
  }

  Future<Object?> _loadContact(DingTalkConversation conversation) async {
    try {
      return await _runJson(<String>[
        'contact',
        'user',
        'get',
        '--ids',
        conversation.id,
        '--format',
        'json',
      ]);
    } catch (error, stack) {
      try {
        return await _runJson(<String>[
          'contact',
          '+lookup',
          '--name',
          conversation.title,
          '--format',
          'json',
        ]);
      } catch (fallbackError, fallbackStack) {
        silentLog('dingtalk_gateway', '按标识读取联系人', error, stack);
        silentLog('dingtalk_gateway', '按名称读取联系人', fallbackError, fallbackStack);
        rethrow;
      }
    }
  }

  Future<Object?> _loadRosterFields() async {
    try {
      return await _runJson(const <String>[
        'contact',
        'user',
        'profile',
        'fields',
        '--format',
        'json',
      ]);
    } on DingTalkGatewayCommandException catch (error) {
      if (error.isPermissionDenied) _rosterAccessDenied = true;
      rethrow;
    }
  }

  Future<Object?> _loadRosterProfile(String staffId) async {
    try {
      return await _runJson(<String>[
        'contact',
        'user',
        'profile',
        'get',
        '--staff-id',
        staffId,
        '--format',
        'json',
      ]);
    } on DingTalkGatewayCommandException catch (error) {
      if (error.isPermissionDenied) _rosterAccessDenied = true;
      rethrow;
    }
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
    final batches = <List<String>>[];
    for (var offset = 0; offset < userIds.length; offset += _batchSize) {
      final end = math.min(offset + _batchSize, userIds.length);
      batches.add(userIds.sublist(offset, end));
    }
    final pages = await _mapBounded<List<String>, Object?>(
      batches,
      (batch) => _runJson(<String>[
        'contact',
        'user',
        'get',
        '--ids',
        batch.join(','),
        '--format',
        'json',
      ]),
      onError: '读取群成员组织资料',
    );
    if (pages.isEmpty) return null;
    return pages.length == 1 ? pages.first : <String, Object?>{'pages': pages};
  }

  Future<Object?> _loadGroupMemberDetails(
    String groupId,
    List<String> openDingTalkIds,
  ) async {
    final batches = <List<String>>[];
    for (
      var offset = 0;
      offset < openDingTalkIds.length;
      offset += _batchSize
    ) {
      final end = math.min(offset + _batchSize, openDingTalkIds.length);
      batches.add(openDingTalkIds.sublist(offset, end));
    }
    final pages = await _mapBounded<List<String>, Object?>(
      batches,
      (batch) => _runJson(<String>[
        'chat',
        'group',
        'members',
        'list-by-ids',
        '--id',
        groupId,
        '--users',
        batch.join(','),
        '--format',
        'json',
      ]),
      onError: '读取群成员群内详情',
    );
    if (pages.isEmpty) return null;
    return pages.length == 1 ? pages.first : <String, Object?>{'pages': pages};
  }

  Future<Object?> _loadGroupMemberRoles(
    String groupId,
    List<String> userIds,
  ) async {
    final values = await _mapBounded<String, Object?>(userIds, (userId) async {
      final value = await _runJson(<String>[
        'chat',
        '+chat-role-query-user',
        '--group',
        groupId,
        '--user',
        userId,
        '--format',
        'json',
      ]);
      return <String, Object?>{'userId': userId, 'roles': value};
    }, onError: '读取群成员身份');
    return values.isEmpty ? null : values;
  }

  Future<Object?> _loadDepartmentDetails(List<String> departmentIds) async {
    final values = await _mapBounded<String, Object?>(departmentIds, (
      departmentId,
    ) async {
      final details = await Future.wait<Object?>(<Future<Object?>>[
        _runOptionalJson(<String>[
          'contact',
          'dept',
          'get-info',
          '--dept',
          departmentId,
          '--format',
          'json',
        ], '读取部门详情'),
        _runOptionalJson(<String>[
          'contact',
          'dept',
          'list-children',
          '--dept',
          departmentId,
          '--format',
          'json',
        ], '读取直属子部门'),
      ]);
      return <String, Object?>{
        'deptId': departmentId,
        if (details[0] != null) 'departmentInfo': details[0],
        if (details[1] != null) 'directSubdepartments': details[1],
      };
    }, onError: '读取所属部门资料');
    return values.isEmpty ? null : values;
  }

  Future<Object?> _runOptionalJson(List<String> arguments, String name) async {
    try {
      return await _runJson(arguments);
    } catch (error, stack) {
      if (error is DingTalkGatewayCommandException && error.isBusinessError) {
        return null;
      }
      silentLog('dingtalk_gateway', name, error, stack);
      return null;
    }
  }

  Future<List<R>> _mapBounded<T, R>(
    List<T> values,
    Future<R> Function(T value) action, {
    required String onError,
  }) async {
    if (values.isEmpty) return List<R>.empty();
    final results = List<R?>.filled(values.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= values.length) return;
        try {
          results[index] = await action(values[index]);
        } catch (error, stack) {
          if (error is DingTalkGatewayCommandException &&
              error.isBusinessError) {
            continue;
          }
          silentLog('dingtalk_gateway', onError, error, stack);
        }
      }
    }

    final workerCount = math.min(_detailConcurrency, values.length);
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return results
        .where((item) => item != null)
        .cast<R>()
        .toList(growable: false);
  }

  List<String> _extractUserIds(Object? value) {
    final ids = <String>{};
    void visit(Object? current) {
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
          final raw = map[key];
          if (raw is Map || raw is List) continue;
          final id = '$raw'.trim();
          if (id.isNotEmpty && id != 'null') ids.add(id);
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

  List<String> _extractOpenDingTalkIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'openDingTalkId',
      'openDingtalkId',
      'open_dingtalk_id',
    });
  }

  List<String> _extractContactIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'userId',
      'user_id',
      'openDingTalkId',
      'openDingtalkId',
      'open_dingtalk_id',
      'unionId',
      'union_id',
    });
  }

  List<String> _extractDepartmentIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'deptId',
      'dept_id',
      'departmentId',
      'department_id',
    });
  }

  List<String> _extractGroupRoleIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'openRoleId',
      'open_role_id',
      'roleId',
      'role_id',
    });
  }

  List<String> _extractValuesByKeys(Object? value, Set<String> keys) {
    final values = <String>{};
    void visit(Object? current) {
      if (current is Map) {
        final map = _asMap(current);
        for (final key in keys) {
          final raw = map[key];
          if (raw is Map || raw is List) continue;
          final candidate = '$raw'.trim();
          if (candidate.isNotEmpty && candidate != 'null') {
            values.add(candidate);
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
    return values.toList(growable: false);
  }

  Object _matchFollowingContact(Object? following, Set<String> contactIds) {
    final matches = <Object?>[];
    void visit(Object? current) {
      if (current is Map) {
        final map = _asMap(current);
        final ids = _extractContactIds(map);
        if (ids.any(contactIds.contains)) matches.add(current);
        for (final item in map.values) {
          visit(item);
        }
      } else if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(following);
    return <String, Object?>{
      'isFollowing': matches.isNotEmpty,
      if (matches.isNotEmpty) 'details': matches,
    };
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
          final raw = map[key];
          if (raw is Map || raw is List) continue;
          final candidate = '$raw'.trim();
          if (candidate.isNotEmpty && candidate != 'null') {
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
    final payload = _asMap(decoded);
    final error = _asMap(payload['error']);
    if (result.exitCode != 0 || error.isNotEmpty) {
      final message =
          error['message']?.toString().trim().ifEmpty('dws 执行失败。') ??
          payload['message']?.toString().trim().ifEmpty('dws 执行失败。') ??
          result.stderr.trim().ifEmpty('dws 执行失败。');
      throw DingTalkGatewayCommandException(
        message: message,
        category: error['category']?.toString(),
        reason: error['reason']?.toString(),
        serverCode: error['server_error_code']?.toString(),
        operation: error['operation']?.toString(),
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
