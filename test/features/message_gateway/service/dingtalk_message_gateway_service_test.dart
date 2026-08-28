import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';
import 'package:openhand/features/message_gateway/service/dingtalk_message_gateway_service.dart';

void main() {
  group('钉钉已发送消息标识反查', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'openhand_dingtalk_lookup_test_',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('为网络请求保留充足时间并只选择本人精确正文', () async {
      final createdAt = DateTime(2026, 8, 28, 10);
      final argumentsFile = File('${temporaryDirectory.path}/arguments.txt');
      final service = await _createService(
        temporaryDirectory,
        argumentsFile: argumentsFile,
        payload: <String, Object?>{
          'data': <String, Object?>{
            'messages': <Object?>[
              _message(
                id: '错误消息',
                content: '其他正文',
                createdAt: createdAt,
                fromSelf: true,
              ),
              _message(
                id: '他人消息',
                content: '目标正文',
                createdAt: createdAt.add(const Duration(seconds: 1)),
                fromSelf: false,
              ),
              _message(
                id: '本人消息',
                content: '目标正文',
                createdAt: createdAt.add(const Duration(seconds: 2)),
                fromSelf: true,
              ),
            ],
          },
        },
      );

      final resolved = await service.resolveRecentSentMessage(
        conversation: _conversation(),
        content: '目标正文',
        createdAt: createdAt,
        senderName: 'OpenHand',
      );

      expect(resolved?.messageId, '本人消息');
      final arguments = await argumentsFile.readAsLines();
      final timeoutIndex = arguments.indexOf('--timeout');
      expect(timeoutIndex, isNonNegative);
      expect(arguments[timeoutIndex + 1], '12');
    });

    test('正文不一致时不绑定其他消息', () async {
      final createdAt = DateTime(2026, 8, 28, 10);
      final service = await _createService(
        temporaryDirectory,
        argumentsFile: File('${temporaryDirectory.path}/arguments.txt'),
        payload: <String, Object?>{
          'messages': <Object?>[
            _message(
              id: '其他消息',
              content: '其他正文',
              createdAt: createdAt,
              fromSelf: true,
            ),
          ],
        },
      );

      final resolved = await service.resolveRecentSentMessage(
        conversation: _conversation(),
        content: '目标正文',
        createdAt: createdAt,
        senderName: 'OpenHand',
      );

      expect(resolved, isNull);
    });
  });

  test('识别 dws 网络超时为可重试错误', () {
    const messageError = DingTalkGatewayCommandException(
      message: '[NETWORK_TIMEOUT] Request timed out',
    );
    const codeError = DingTalkGatewayCommandException(
      message: '请求失败',
      serverCode: 'NETWORK_TIMEOUT',
    );

    expect(messageError.isRetryable, isTrue);
    expect(codeError.isRetryable, isTrue);
  });
}

Future<DingTalkMessageGatewayService> _createService(
  Directory directory, {
  required File argumentsFile,
  required Map<String, Object?> payload,
}) async {
  final executable = File('${directory.path}/dws');
  await executable.writeAsString('''#!/bin/sh
printf '%s\\n' "\$@" > ${_shellQuote(argumentsFile.path)}
printf '%s\\n' ${_shellQuote(jsonEncode(payload))}
''');
  final chmod = await Process.run('chmod', <String>['+x', executable.path]);
  expect(chmod.exitCode, 0);
  return _TestDingTalkMessageGatewayService(executable.path);
}

Map<String, Object?> _message({
  required String id,
  required String content,
  required DateTime createdAt,
  required bool fromSelf,
}) => <String, Object?>{
  'messageId': id,
  'conversationId': 'conversation-1',
  'conversationType': 'direct',
  'content': content,
  'createTime': createdAt.toIso8601String(),
  'senderName': 'OpenHand',
  'isSelf': fromSelf,
};

DingTalkConversation _conversation() => DingTalkConversation(
  id: 'conversation-1',
  type: DingTalkConversationType.direct,
  title: '测试会话',
  directUserId: 'user-1',
);

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

class _TestDingTalkMessageGatewayService extends DingTalkMessageGatewayService {
  _TestDingTalkMessageGatewayService(this.path);

  final String path;

  @override
  Future<String?> executable() async => path;
}
