import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final task = await Socket.startConnect(host, port);
  Socket? active;
  var cancelled = false;
  void cancel() {
    cancelled = true;
    task.cancel();
    active?.destroy();
  }

  Future<Socket> connect() async {
    final socket = active = await task.socket;
    if (cancelled) {
      socket.destroy();
      throw const SocketException('代理连接已取消。');
    }
    final proxy = _SocksHttpSocket(socket);
    try {
      await proxy.handshake(target, username, password);
      if (target.scheme == 'https') {
        active = await SecureSocket.secure(
          socket,
          host: target.host,
          context: context,
          onBadCertificate: onBadCertificate,
        );
        if (cancelled) active!.destroy();
        return active!;
      }
      return proxy;
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  final future = connect().timeout(
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

  Future<void> handshake(Uri target, String? username, String? password) async {
    final user = username == null ? null : utf8.encode(username);
    final secret = utf8.encode(password ?? '');
    final domain = ascii.encode(target.host);
    if (domain.length > 255 ||
        (user?.length ?? 0) > 255 ||
        secret.length > 255) {
      throw const FormatException('SOCKS 地址或凭据超过长度上限。');
    }
    add([5, user == null ? 1 : 2, 0, if (user != null) 2]);
    await flush();
    final greeting = await readBytes(2);
    if (greeting[0] != 5) throw const SocketException('SOCKS 代理协议无效。');
    if (greeting[1] == 2 && user != null) {
      add([1, user.length, ...user, secret.length, ...secret]);
      await flush();
      final result = await readBytes(2);
      if (result[0] != 1 || result[1] != 0) {
        throw const SocketException('SOCKS 代理鉴权失败。');
      }
    } else if (greeting[1] != 0) {
      throw const SocketException('SOCKS 代理不支持当前鉴权方式。');
    }
    final address = InternetAddress.tryParse(target.host);
    add([
      5,
      1,
      0,
      if (address == null) ...[
        3,
        domain.length,
        ...domain,
      ] else ...[
        address.type == InternetAddressType.IPv4 ? 1 : 4,
        ...address.rawAddress,
      ],
      target.port >> 8,
      target.port & 255,
    ]);
    await flush();
    final result = await readBytes(4);
    if (result[0] != 5 || result[1] != 0 || result[2] != 0) {
      throw const SocketException('SOCKS 代理无法连接目标服务器。');
    }
    final length = switch (result[3]) {
      1 => 4,
      4 => 16,
      3 => (await readBytes(1)).single,
      _ => throw const SocketException('SOCKS 代理响应地址无效。'),
    };
    await readBytes(length + 2);
    if (_offset != _buffer.length) {
      throw const SocketException('SOCKS 代理握手包含多余数据。');
    }
    await _reader.cancel();
  }
}
