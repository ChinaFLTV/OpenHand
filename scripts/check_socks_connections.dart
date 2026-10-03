import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openhand/shared/net/socks_http_connection.dart';

Future<void> main() async {
  for (final cancelImmediately in [false, true]) {
    final launch = Completer<ConnectionTask<Socket>>();
    final connected = Completer<Socket>();
    var cancelled = false;
    await IOOverrides.runZoned(
      () async {
        final task = await startSocksHttpConnection(
          Uri.parse('http://example.com'),
          host: '代理测试',
          port: 1080,
          timeout: const Duration(milliseconds: 20),
        );
        final failure = task.socket.then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
        if (cancelImmediately) task.cancel();
        final error = await failure;
        _expect(
          cancelImmediately
              ? error is SocketException
              : error is TimeoutException,
          '连接任务创建阶段必须响应取消并遵守总时限。',
        );
        launch.complete(
          ConnectionTask.fromSocket(connected.future, () => cancelled = true),
        );
        final socket = _LateSocket();
        connected.complete(socket);
        await Future<void>.delayed(Duration.zero);
        _expect(cancelled && socket.destroyed, '取消后必须释放迟到连接任务和套接字。');
      },
      socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) =>
          launch.future,
    );
  }

  var launches = 0;
  await IOOverrides.runZoned(
    () async {
      for (final target in ['file:///tmp/测试', 'http://example.com:0']) {
        try {
          await startSocksHttpConnection(
            Uri.parse(target),
            host: '代理测试',
            port: 1080,
            timeout: const Duration(seconds: 1),
          );
          throw StateError('非法目标没有被拒绝。');
        } on FormatException {
          // 无效协议在连接前拒绝。
        } on ArgumentError {
          // 无效端口在连接前拒绝。
        }
      }
      try {
        await startSocksHttpConnection(
          Uri.parse('http://example.com'),
          host: '代理测试',
          port: 1080,
          username: '中' * 86,
          timeout: const Duration(seconds: 1),
        );
        throw StateError('超长凭据没有被拒绝。');
      } on FormatException {
        // 按 UTF-8 字节数验证凭据。
      }
      _expect(launches == 0, '无效请求不得占用网络资源。');
    },
    socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) {
      launches++;
      throw StateError('无效请求不应建立连接。');
    },
  );

  for (final authenticated in [false, true]) {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Socket? proxy;
    final handled = () async {
      proxy = await server.first;
      final reader = StreamIterator<List<int>>(proxy!);
      final buffer = <int>[];
      Future<List<int>> read(int count) async {
        while (buffer.length < count) {
          if (!await reader.moveNext()) throw StateError('测试代理连接提前关闭。');
          buffer.addAll(reader.current);
        }
        final value = buffer.sublist(0, count);
        buffer.removeRange(0, count);
        return value;
      }

      try {
        final greeting = await read(authenticated ? 4 : 3);
        _expect(
          greeting[0] == 5 && greeting.last == (authenticated ? 2 : 0),
          '鉴权协商无效。',
        );
        proxy!.add([5, authenticated ? 2 : 0]);
        await proxy!.flush();
        if (authenticated) {
          _expect((await read(2)).last == 3, '用户名长度必须按 UTF-8 字节计算。');
          _expect(utf8.decode(await read(3)) == '中', '用户名编码无效。');
          _expect((await read(1)).single == 3, '密码长度无效。');
          _expect(utf8.decode(await read(3)) == '密', '密码编码无效。');
          proxy!.add([1, 0]);
          await proxy!.flush();
        }
        final destination = await read(4);
        _expect(destination.join(',') == '5,1,0,3', '目标地址类型无效。');
        final domainLength = (await read(1)).single;
        _expect(
          ascii.decode(await read(domainLength)) == 'example.com',
          '目标域名无效。',
        );
        _expect((await read(2)).join(',') == '0,80', '目标端口无效。');
        // 分片返回握手响应，随后验证正常 HTTP 数据流仍然可读。
        for (final byte in [5, 0, 0, 1, 127, 0, 0, 1, 0, 80]) {
          proxy!.add([byte]);
          await proxy!.flush();
        }
        _expect(ascii.decode(await read(4)) == 'GET ', '请求数据丢失。');
        proxy!.add(utf8.encode('响应'));
        await proxy!.flush();
      } finally {
        await reader.cancel();
      }
    }();
    final client = await startSocksHttpConnection(
      Uri.parse('http://example.com'),
      host: server.address.address,
      port: server.port,
      username: authenticated ? '中' : null,
      password: authenticated ? '密' : null,
      timeout: const Duration(seconds: 2),
    );
    Socket? socket;
    try {
      socket = await client.socket;
      socket.add(ascii.encode('GET '));
      await socket.flush();
      _expect(utf8.decode(await socket.first) == '响应', '握手后的响应数据丢失。');
      await handled.timeout(const Duration(seconds: 2));
    } finally {
      client.cancel();
      proxy?.destroy();
      await server.close();
    }
  }
  stdout.writeln('[SOCKS 连接检查] 通过。');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class _LateSocket implements Socket {
  bool destroyed = false;

  @override
  void destroy() => destroyed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
