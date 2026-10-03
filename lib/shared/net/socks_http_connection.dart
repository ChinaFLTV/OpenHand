import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../util/argument_guards.dart';
import '../util/async_concurrency.dart';
import 'network_limits.dart';

const int _socksVersion = 5;
const int _socksAuthVersion = 1;
const int _socksNoAuth = 0;
const int _socksPasswordAuth = 2;
const int _socksConnect = 1;
const int _socksIpv4Address = 1;
const int _socksDomainAddress = 3;
const int _socksIpv6Address = 4;
const int _socksMaxFieldBytes = 255;
const int _socksMaxPort = 65535;

/// SOCKS 握手期间也持有连接的取消权，超时不遗留等待中的套接字。
Future<ConnectionTask<Socket>> startSocksHttpConnection(
  Uri target, {
  required String host,
  required int port,
  required Duration timeout,
  String? username,
  String? password,
  SecurityContext? context,
  bool Function(X509Certificate certificate)? onBadCertificate,
}) async {
  requirePositiveDurationAtMost(
    timeout,
    kOpenHandMaxNetworkOperationTimeout,
    'timeout',
  );
  requirePositiveIntAtMost(port, _socksMaxPort, 'port');
  requirePositiveIntAtMost(target.port, _socksMaxPort, 'target.port');
  if (host.trim().isEmpty ||
      target.host.isEmpty ||
      (target.scheme != 'http' && target.scheme != 'https')) {
    throw const FormatException('SOCKS 代理或目标地址无效。');
  }
  final user = username == null ? null : utf8.encode(username);
  final secret = utf8.encode(password ?? '');
  final address = InternetAddress.tryParse(target.host);
  final domain = address == null ? ascii.encode(target.host) : const <int>[];
  if (domain.length > _socksMaxFieldBytes ||
      (user != null && (user.isEmpty || user.length > _socksMaxFieldBytes)) ||
      secret.length > _socksMaxFieldBytes) {
    throw const FormatException('SOCKS 地址或凭据超过长度上限。');
  }
  final destination = <int>[
    if (address == null) ...[
      _socksDomainAddress,
      domain.length,
      ...domain,
    ] else ...[
      address.type == InternetAddressType.IPv4
          ? _socksIpv4Address
          : _socksIpv6Address,
      ...address.rawAddress,
    ],
    target.port >> 8,
    target.port & _socksMaxFieldBytes,
  ];

  ConnectionTask<Socket>? task;
  Socket? active;
  final cancellation = Completer<void>();
  var cancelled = false;
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    cancellation.complete();
    task?.cancel();
    active?.destroy();
  }

  Future<Socket> connect() async {
    // 连接任务的创建也可能等待 DNS，必须纳入完整连接时限。
    final connection = task = await Socket.startConnect(host, port);
    if (cancelled) connection.cancel();
    final socket = active = await connection.socket;
    if (cancelled) {
      socket.destroy();
      throw const SocketException('代理连接已取消。');
    }
    final proxy = _SocksHttpSocket(socket);
    try {
      await proxy.handshake(destination, user, secret);
      if (target.scheme == 'https') {
        active = await SecureSocket.secure(
          socket,
          host: target.host,
          context: context,
          onBadCertificate: onBadCertificate,
        );
        if (cancelled) {
          active!.destroy();
          throw const SocketException('代理连接已取消。');
        }
        return active!;
      }
      return proxy;
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  final future =
      awaitWithCancelSignal(connect(), cancelSignal: cancellation.future)
          .then((socket) => socket ?? (throw const SocketException('代理连接已取消。')))
          .timeout(
            timeout,
            onTimeout: () {
              cancel();
              throw TimeoutException('SOCKS 代理连接超时。', timeout);
            },
          );
  return ConnectionTask.fromSocket(future, cancel);
}

class _SocksHttpSocket extends Stream<Uint8List> implements Socket {
  _SocksHttpSocket(this.socket);
  final Socket socket;
  late final stream = socket.asBroadcastStream(
    onCancel: (subscription) => subscription.pause(),
    onListen: (subscription) => subscription.resume(),
  );
  late final _reader = StreamIterator(stream);
  var _buffer = <int>[];
  var _offset = 0;

  Future<List<int>> readBytes(int length) async {
    final result = <int>[];
    while (result.length < length) {
      if (_offset == _buffer.length) {
        if (!await _reader.moveNext()) {
          throw const SocketException('SOCKS 代理提前关闭连接。');
        }
        _buffer = _reader.current;
        _offset = 0;
      }
      final count = (length - result.length).clamp(0, _buffer.length - _offset);
      result.addAll(_buffer.getRange(_offset, _offset + count));
      _offset += count;
    }
    return result;
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Encoding get encoding => socket.encoding;
  @override
  set encoding(Encoding value) => socket.encoding = value;
  @override
  void add(List<int> value) => socket.add(value);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => socket.addStream(stream);
  @override
  Future<void> flush() => socket.flush();
  @override
  Future<void> close() => socket.close();
  @override
  Future<void> get done => socket.done;
  @override
  void destroy() => socket.destroy();
  @override
  InternetAddress get address => socket.address;
  @override
  InternetAddress get remoteAddress => socket.remoteAddress;
  @override
  int get port => socket.port;
  @override
  int get remotePort => socket.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => socket.setRawOption(option);
  @override
  void write(Object? value) => socket.write(value);
  @override
  void writeAll(Iterable values, [String separator = '']) =>
      socket.writeAll(values, separator);
  @override
  void writeCharCode(int value) => socket.writeCharCode(value);
  @override
  void writeln([Object? value = '']) => socket.writeln(value);

  Future<void> handshake(
    List<int> destination,
    List<int>? user,
    List<int> secret,
  ) async {
    add([
      _socksVersion,
      user == null ? 1 : 2,
      _socksNoAuth,
      if (user != null) _socksPasswordAuth,
    ]);
    await flush();
    final greeting = await readBytes(2);
    if (greeting[0] != _socksVersion) {
      throw const SocketException('SOCKS 代理协议无效。');
    }
    if (greeting[1] == _socksPasswordAuth && user != null) {
      add([_socksAuthVersion, user.length, ...user, secret.length, ...secret]);
      await flush();
      final result = await readBytes(2);
      if (result[0] != _socksAuthVersion || result[1] != 0) {
        throw const SocketException('SOCKS 代理鉴权失败。');
      }
    } else if (greeting[1] != _socksNoAuth) {
      throw const SocketException('SOCKS 代理不支持当前鉴权方式。');
    }
    add([_socksVersion, _socksConnect, 0, ...destination]);
    await flush();
    final result = await readBytes(4);
    if (result[0] != _socksVersion || result[1] != 0 || result[2] != 0) {
      throw const SocketException('SOCKS 代理无法连接目标服务器。');
    }
    final length = switch (result[3]) {
      _socksIpv4Address => 4,
      _socksIpv6Address => 16,
      _socksDomainAddress => (await readBytes(1)).single,
      _ => throw const SocketException('SOCKS 代理响应地址无效。'),
    };
    await readBytes(length + 2);
    if (_offset != _buffer.length) {
      throw const SocketException('SOCKS 代理握手包含多余数据。');
    }
    await _reader.cancel();
  }
}
