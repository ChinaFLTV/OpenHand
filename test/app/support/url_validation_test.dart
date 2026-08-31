import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/url_validation.dart';

void main() {
  group('HTTP 地址校验', () {
    test('统一协议并拒绝危险结构', () {
      expect(tryParseValidHttpUrl('HTTPS://Example.com/path')?.scheme, 'https');
      expect(tryParseValidHttpUrl('ftp://example.com'), isNull);
      expect(tryParseValidHttpUrl('http://user:pass@example.com'), isNull);
      expect(
        tryParseValidHttpUrl(
          'http://user:pass@example.com',
          allowUserInfo: true,
        ),
        isNotNull,
      );
      expect(tryParseValidHttpUrl('http://example.com:0'), isNull);
      expect(tryParseValidHttpUrl('http://example.com:65535'), isNotNull);
      expect(tryParseValidHttpUrl('http://exa mple.com'), isNull);
    });

    test('从文本提取地址、去除尾部标点并去重', () {
      final uris = extractHttpUrisFromText(
        r'访问 https://example.com/a。镜像：https:\/\/example.com\/a，备用 http://openhand.test/path!',
      );
      expect(uris.map((uri) => uri.toString()), <String>[
        'https://example.com/a',
        'http://openhand.test/path',
      ]);
    });
  });

  group('智能体抓取网络隔离', () {
    test('直接阻止本机、回环和私有地址', () {
      expect(agentFetchBlockReasonForHost('localhost.'), '本机地址');
      expect(agentFetchBlockReasonForHost('localhost.localdomain'), '本机地址');
      expect(
        agentFetchBlockReasonForAddress(InternetAddress('127.0.0.1')),
        '回环地址',
      );
      expect(
        agentFetchBlockReasonForAddress(InternetAddress('192.168.1.10')),
        '私有或保留网络地址',
      );
      expect(
        agentFetchBlockReasonForAddress(InternetAddress('::ffff:127.0.0.1')),
        '回环地址',
      );
      expect(
        agentFetchBlockReasonForAddress(InternetAddress('8.8.8.8')),
        isNull,
      );
    });

    test('检查域名解析结果中的所有地址', () async {
      final reason = await agentFetchBlockReasonForResolvedUri(
        Uri.parse('https://example.com'),
        hostLookup: (_) async => <InternetAddress>[
          InternetAddress('8.8.8.8'),
          InternetAddress('10.0.0.8'),
        ],
      );
      expect(reason, contains('私有或保留网络地址'));
      expect(reason, contains('10.0.0.8'));
    });

    test('解析为空或失败时采用安全拒绝策略', () async {
      expect(
        await agentFetchBlockReasonForResolvedUri(
          Uri.parse('https://example.com'),
          hostLookup: (_) async => <InternetAddress>[],
        ),
        'DNS 未解析到可用地址',
      );
      expect(
        await agentFetchBlockReasonForResolvedUri(
          Uri.parse('https://example.com'),
          hostLookup: (_) => Future<List<InternetAddress>>.error(
            const SocketException('解析失败'),
          ),
        ),
        'DNS 解析失败',
      );
    });

    test('解析超时和非法超时配置均有明确结果', () async {
      expect(
        await agentFetchBlockReasonForResolvedUri(
          Uri.parse('https://example.com'),
          hostLookup: (_) => Completer<List<InternetAddress>>().future,
          dnsTimeout: const Duration(milliseconds: 5),
        ),
        'DNS 解析超时',
      );
      expect(
        () => agentFetchBlockReasonForResolvedUri(
          Uri.parse('https://example.com'),
          dnsTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });
}
