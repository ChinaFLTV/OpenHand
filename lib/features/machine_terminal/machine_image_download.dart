import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../shared/net/bounded_http_request.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_delete.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/timer_safety.dart';
import 'machine_containers.dart';

const _metadataLimit = 4 * 1024 * 1024;
const _imageLimit = 16 * 1024 * 1024 * 1024;
const _layerLimit = 8 * 1024 * 1024 * 1024 - 1;
const _layerCountLimit = 256;
const _connectionTimeout = Duration(seconds: 15);
const _idleTimeout = Duration(seconds: 30);
const _cleanupPolicy = BoundedDeletePolicy(
  maxEntries: 8,
  maxDepth: 2,
  totalTimeout: Duration(seconds: 10),
  operationTimeout: Duration(seconds: 5),
);
const _manifestTypes =
    'application/vnd.oci.image.index.v1+json, '
    'application/vnd.docker.distribution.manifest.list.v2+json, '
    'application/vnd.oci.image.manifest.v1+json, '
    'application/vnd.docker.distribution.manifest.v2+json';

typedef MachineImageCredential = ({String username, String secret});
typedef MachineImageDownloadProgress = void Function(int received, int total);

class MachineImageReference {
  MachineImageReference.parse(String value) {
    final input = value.trim();
    if (input.isEmpty ||
        input.length > 512 ||
        input.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      throw const MachineContainerConfigException('image');
    }
    final references = input.split('@');
    if (references.length > 2 ||
        references.length == 2 &&
            !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(references.last)) {
      throw const MachineContainerConfigException('image');
    }
    digest = references.length == 2 ? references.last : null;
    var name = references.first;
    final colon = name.lastIndexOf(':');
    var version = 'latest';
    if (colon > name.lastIndexOf('/')) {
      version = name.substring(colon + 1);
      if (!machineContainerValidImageTag(version)) {
        throw const MachineContainerConfigException('image');
      }
      name = name.substring(0, colon);
    }
    final parts = name.split('/');
    final qualified =
        parts.length > 1 &&
        (parts.first.contains('.') ||
            parts.first.contains(':') ||
            parts.first == 'localhost');
    registry = qualified
        ? parts.removeAt(0).toLowerCase()
        : 'registry-1.docker.io';
    final endpoint = Uri.tryParse('https://$registry');
    if (endpoint == null ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.port < 1 ||
        endpoint.port > 65535 ||
        !parts.every(
          (part) =>
              RegExp(r'^[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*$').hasMatch(part),
        )) {
      throw const MachineContainerConfigException('image');
    }
    if (const {'docker.io', 'index.docker.io'}.contains(registry)) {
      registry = 'registry-1.docker.io';
    }
    if (registry == 'registry-1.docker.io' && parts.length == 1) {
      parts.insert(0, 'library');
    }
    repository = parts.join('/');
    selector = digest ?? version;
    tag = digest == null
        ? '${registry == 'registry-1.docker.io' ? 'docker.io' : registry}/$repository:$version'
        : null;
  }

  late final String registry, repository, selector;
  late final String? digest, tag;
  Uri uri(String kind, String name) =>
      Uri.parse('https://$registry/v2/$repository/$kind/$name');
}

class MachineImageArchive {
  const MachineImageArchive(
    this.file,
    this.configDigest,
    this.manifestDigest,
    this.reference,
  );
  final File file;
  final String configDigest, manifestDigest, reference;
}

/// 所有仓库、鉴权与分层请求由应用下载；目标运行时只执行离线导入。
/// 直接流式写入兼容 Docker/OCI 的归档，不解压镜像层、不在内存缓存大文件。
class MachineImageDownload {
  MachineImageDownload({required this.clientFactory});

  final HttpClient Function() clientFactory;

  Future<T> withArchive<T>({
    required String image,
    required String os,
    required String architecture,
    String variant = '',
    required Duration timeout,
    required Future<T> Function(MachineImageArchive archive) consume,
    Future<MachineImageCredential?> Function(String registry)? credential,
    bool Function()? isCancelled,
    MachineImageDownloadProgress? onProgress,
  }) async {
    final reference = MachineImageReference.parse(image);
    final deadline = MonotonicDeadline(timeout, timeoutMessage: '镜像下载超过总时限。');
    final client = clientFactory()..autoUncompress = false;
    final transfer = _ImageTransfer(
      client,
      deadline,
      reference,
      credential,
      isCancelled,
    );
    Directory? directory;
    final cancellation = startSafePeriodicTimer(
      const Duration(milliseconds: 100),
      (_) {
        if ((isCancelled?.call() ?? false) || deadline.isExpired) {
          client.close(force: true);
        }
      },
      min: const Duration(milliseconds: 100),
    );
    try {
      transfer.check();
      var manifest = await transfer.json(
        reference.uri('manifests', reference.selector),
        digest: reference.digest,
      );
      var manifestBytes = manifest.$2;
      var data = manifest.$1;
      if (data['manifests'] case final List candidates) {
        final matches = candidates.whereType<Map>().where((entry) {
          final platform = entry['platform'];
          return platform is Map &&
              platform['os'] == os &&
              platform['architecture'] == architecture &&
              (variant.isEmpty || platform['variant'] == variant);
        }).toList();
        if (matches.isEmpty) {
          throw const MachineContainerConfigException('imagePlatform');
        }
        // 同架构优先无变体或 v8；避免误选 arm 的 v6/v7 镜像。
        final selected = matches.firstWhere(
          (entry) =>
              variant.isNotEmpty ||
              (entry['platform'] as Map)['variant'] == null ||
              architecture == 'arm64' &&
                  (entry['platform'] as Map)['variant'] == 'v8',
          orElse: () => matches.first,
        );
        final descriptor = _ImageDescriptor.parse(selected);
        manifest = await transfer.json(
          reference.uri('manifests', descriptor.digest),
          digest: descriptor.digest,
        );
        manifestBytes = manifest.$2;
        data = manifest.$1;
      }
      if (data['schemaVersion'] != 2 ||
          data['layers'] is! List ||
          data['config'] is! Map) {
        throw const FormatException('镜像清单格式不受支持。');
      }
      final config = _ImageDescriptor.parse(data['config'] as Map);
      final layers = (data['layers'] as List)
          .map(_ImageDescriptor.parse)
          .toList();
      final total =
          config.size + layers.fold<int>(0, (sum, layer) => sum + layer.size);
      if (config.size > _metadataLimit ||
          layers.length > _layerCountLimit ||
          total > _imageLimit) {
        throw const FormatException('镜像超过下载容量上限。');
      }
      final configuration = await transfer.json(
        reference.uri('blobs', config.digest),
        digest: config.digest,
      );
      if (configuration.$2.length != config.size ||
          configuration.$1['os'] != os ||
          configuration.$1['architecture'] != architecture) {
        throw const MachineContainerConfigException('imagePlatform');
      }
      final diffIds = configuration.$1['rootfs'];
      if (diffIds is! Map ||
          diffIds['diff_ids'] is! List ||
          (diffIds['diff_ids'] as List).length != layers.length) {
        throw const FormatException('镜像分层与配置不一致。');
      }
      transfer.check();
      directory = await createTemporaryDirectoryBounded(
        prefix: 'openhand-image-',
        timeout: deadline.limit(_connectionTimeout),
        cleanupPolicy: _cleanupPolicy,
      );
      final file = File('${directory.path}/image.tar');
      final archive = await file.open(mode: FileMode.write);
      var received = config.size;
      try {
        await _writeTarEntry(archive, config.path, configuration.$2);
        await _writeTarEntry(
          archive,
          'blobs/sha256/${sha256.convert(manifestBytes)}',
          manifestBytes,
        );
        final completed = <String>{config.digest};
        for (final layer in layers) {
          transfer.check();
          if (!const {
            'application/vnd.oci.image.layer.v1.tar',
            'application/vnd.oci.image.layer.v1.tar+gzip',
            'application/vnd.oci.image.layer.v1.tar+zstd',
            'application/vnd.oci.image.layer.nondistributable.v1.tar',
            'application/vnd.oci.image.layer.nondistributable.v1.tar+gzip',
            'application/vnd.docker.image.rootfs.diff.tar.gzip',
            'application/vnd.docker.image.rootfs.foreign.diff.tar.gzip',
          }.contains(layer.mediaType)) {
            throw const FormatException('镜像分层类型不受支持。');
          }
          if (!completed.add(layer.digest)) continue;
          await archive.writeFrom(_tarHeader(layer.path, layer.size));
          final response = await transfer.open(
            reference.uri('blobs', layer.digest),
            foreignUrls: layer.urls,
          );
          final hash = _DigestSink();
          final hasher = sha256.startChunkedConversion(hash);
          var size = 0;
          try {
            await for (final bytes in response.timeout(
              deadline.limit(_idleTimeout),
            )) {
              transfer.check();
              size += bytes.length;
              if (size > layer.size) throw const FormatException('镜像分层超过声明容量。');
              hasher.add(bytes);
              await archive.writeFrom(bytes);
              onProgress?.call(received + size, total);
            }
          } finally {
            hasher.close();
          }
          if (size != layer.size || 'sha256:${hash.value}' != layer.digest) {
            throw const FormatException('镜像分层完整性校验失败。');
          }
          await _tarPadding(archive, size);
          received += size;
        }
        final imageManifest = utf8.encode(
          jsonEncode([
            {
              'Config': config.path,
              'RepoTags': [if (reference.tag != null) reference.tag],
              'Layers': layers.map((layer) => layer.path).toList(),
            },
          ]),
        );
        await _writeTarEntry(archive, 'manifest.json', imageManifest);
        await _writeTarEntry(
          archive,
          'oci-layout',
          utf8.encode('{"imageLayoutVersion":"1.0.0"}'),
        );
        await _writeTarEntry(
          archive,
          'index.json',
          utf8.encode(
            jsonEncode({
              'schemaVersion': 2,
              'manifests': [
                {
                  'mediaType':
                      data['mediaType'] ??
                      'application/vnd.oci.image.manifest.v1+json',
                  'digest': 'sha256:${sha256.convert(manifestBytes)}',
                  'size': manifestBytes.length,
                  'annotations': {
                    'org.opencontainers.image.ref.name':
                        reference.tag ?? image.trim(),
                  },
                },
              ],
            }),
          ),
        );
        await archive.writeFrom(Uint8List(1024));
      } finally {
        await archive.close();
      }
      transfer.check();
      return await consume(
        MachineImageArchive(
          file,
          config.digest,
          'sha256:${sha256.convert(manifestBytes)}',
          reference.tag ?? config.digest,
        ),
      );
    } finally {
      cancellation.cancel();
      client.close(force: true);
      deadline.stop();
      if (directory != null) {
        await deletePathBounded(
          directory.path,
          policy: _cleanupPolicy,
          allowedRoot: Directory.systemTemp.path,
        );
      }
    }
  }
}

class _ImageDescriptor {
  const _ImageDescriptor(this.digest, this.size, this.mediaType, this.urls);
  factory _ImageDescriptor.parse(Object? row) {
    if (row is! Map) throw const FormatException('镜像分层描述无效。');
    final digest = row['digest'];
    final size = row['size'];
    if (digest is! String ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest) ||
        size is! int ||
        size < 0 ||
        size > _layerLimit) {
      throw const FormatException('镜像分层描述无效。');
    }
    return _ImageDescriptor(
      digest,
      size,
      '${row['mediaType'] ?? ''}',
      (row['urls'] as List? ?? []).whereType<String>().take(1).toList(),
    );
  }
  final String digest, mediaType;
  final int size;
  final List<String> urls;
  String get path => 'blobs/sha256/${digest.substring(7)}';
}

class _ImageTransfer {
  _ImageTransfer(
    this.client,
    this.deadline,
    this.reference,
    this.credential,
    this.isCancelled,
  );
  final HttpClient client;
  final MonotonicDeadline deadline;
  final MachineImageReference reference;
  final Future<MachineImageCredential?> Function(String)? credential;
  final bool Function()? isCancelled;
  String? _authorization;
  bool _credentialRead = false;
  MachineImageCredential? _credential;

  void check() {
    if (isCancelled?.call() ?? false) {
      throw const MachineContainerConfigException('cancelled');
    }
    deadline.remaining();
  }

  Future<(Map<String, dynamic>, Uint8List)> json(
    Uri uri, {
    String? digest,
  }) async {
    final response = await open(uri);
    final bytes = await readBoundedHttpResponseBytes(
      response,
      maxBytes: _metadataLimit,
      idleTimeout: deadline.limit(_idleTimeout),
      totalTimeout: deadline.remaining(),
    );
    check();
    if (digest != null && 'sha256:${sha256.convert(bytes)}' != digest) {
      throw const FormatException('镜像清单完整性校验失败。');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('镜像仓库响应格式无效。');
    }
    return (data, bytes);
  }

  Future<HttpClientResponse> _request(
    Uri uri, {
    String? authorization,
    Map<String, String>? form,
  }) async {
    check();
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('镜像仓库仅支持安全的 HTTPS 地址。');
    }
    final request = await openHttpClientRequestBounded(
      () => client.openUrl(form == null ? 'GET' : 'POST', uri),
      timeout: deadline.limit(_connectionTimeout),
    );
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, _manifestTypes);
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: form).query);
    }
    return closeHttpClientRequestBounded(
      request,
      timeout: deadline.limit(_connectionTimeout),
    );
  }

  Future<void> _authenticate(
    String challenge, {
    bool useCredentials = false,
  }) async {
    useCredentials =
        useCredentials || challenge.toLowerCase().startsWith('basic ');
    if (useCredentials && !_credentialRead) {
      _credentialRead = true;
      _credential = await credential?.call(reference.registry);
      check();
    }
    final credentials = useCredentials ? _credential : null;
    if (useCredentials && credentials == null) {
      throw const MachineContainerConfigException('imageAuth');
    }
    if (challenge.toLowerCase().startsWith('basic ')) {
      if (credentials == null || credentials.username == '<token>') {
        throw const MachineContainerConfigException('imageAuth');
      }
      _authorization =
          'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.secret}'))}';
      return;
    }
    if (!challenge.toLowerCase().startsWith('bearer ')) {
      throw const MachineContainerConfigException('imageAuth');
    }
    final parameters = {
      for (final match in RegExp(r'(\w+)="([^"\r\n]*)"').allMatches(challenge))
        match[1]!: match[2]!,
    };
    final realm = Uri.tryParse(parameters['realm'] ?? '');
    if (realm == null ||
        realm.scheme != 'https' ||
        realm.host.isEmpty ||
        realm.userInfo.isNotEmpty) {
      throw const MachineContainerConfigException('imageAuth');
    }
    // 私有凭据只发送给仓库同源鉴权端点；Docker Hub 使用其官方鉴权域。
    final trusted =
        realm.authority == reference.registry ||
        reference.registry == 'registry-1.docker.io' &&
            realm.host == 'auth.docker.io' &&
            realm.port == 443;
    if (credentials != null && !trusted) {
      throw const MachineContainerConfigException('imageAuth');
    }
    final query = <String, String>{
      ...realm.queryParameters,
      if (parameters['service'] case final service?) 'service': service,
      'scope': 'repository:${reference.repository}:pull',
    };
    final refresh = credentials?.username == '<token>';
    final response = await _request(
      realm.replace(queryParameters: refresh ? realm.queryParameters : query),
      authorization: credentials != null && !refresh
          ? 'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.secret}'))}'
          : null,
      form: refresh
          ? {
              ...query,
              'grant_type': 'refresh_token',
              'refresh_token': credentials!.secret,
              'client_id': 'openhand',
            }
          : null,
    );
    if (response.statusCode != 200) {
      await response.listen((_) {}).cancel();
      if (!useCredentials &&
          (response.statusCode == 401 || response.statusCode == 403)) {
        return _authenticate(challenge, useCredentials: true);
      }
      throw const MachineContainerConfigException('imageAuth');
    }
    final bytes = await readBoundedHttpResponseBytes(
      response,
      maxBytes: _metadataLimit,
      idleTimeout: deadline.limit(_idleTimeout),
      totalTimeout: deadline.remaining(),
    );
    Object? result;
    try {
      result = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const MachineContainerConfigException('imageAuth');
    }
    final token = result is Map
        ? result['token'] ?? result['access_token']
        : null;
    if (token is! String ||
        token.isEmpty ||
        token.contains(RegExp(r'[\r\n]'))) {
      throw const MachineContainerConfigException('imageAuth');
    }
    _authorization = 'Bearer $token';
  }

  Future<HttpClientResponse> open(
    Uri original, {
    List<String> foreignUrls = const [],
  }) async {
    var uri = original;
    var authAttempts = 0;
    var foreign = false;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final authorized = uri.authority == reference.registry
          ? _authorization
          : null;
      final response = await _request(uri, authorization: authorized);
      if (response.statusCode == 200) return response;
      final status = response.statusCode;
      final challenge = response.headers.value(
        HttpHeaders.wwwAuthenticateHeader,
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.listen((_) {}).cancel();
      if (status == 401 &&
          uri.authority == reference.registry &&
          authAttempts < 2 &&
          challenge != null) {
        await _authenticate(challenge, useCredentials: authAttempts++ > 0);
        continue;
      }
      if (const {301, 302, 303, 307, 308}.contains(status) &&
          location != null) {
        uri = uri.resolve(location);
        continue;
      }
      if (status == 404 && !foreign && foreignUrls.isNotEmpty) {
        foreign = true;
        uri = Uri.parse(foreignUrls.first);
        continue;
      }
      if (status == 401 || status == 403) {
        throw const MachineContainerConfigException('imageAuth');
      }
      throw HttpException('镜像仓库返回 HTTP $status。', uri: uri.replace(query: ''));
    }
    throw const HttpException('镜像仓库重定向次数超过上限。');
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Uint8List _tarHeader(String name, int size) {
  final header = Uint8List(512);
  void write(int offset, String value) =>
      header.setRange(offset, offset + value.length, ascii.encode(value));
  write(0, name);
  write(100, '0000600\u0000');
  write(108, '0000000\u0000');
  write(116, '0000000\u0000');
  write(124, '${size.toRadixString(8).padLeft(11, '0')}\u0000');
  write(136, '00000000000\u0000');
  write(148, '        ');
  write(156, '0');
  write(257, 'ustar\u0000');
  write(263, '00');
  write(
    148,
    '${header.fold<int>(0, (sum, byte) => sum + byte).toRadixString(8).padLeft(6, '0')}\u0000 ',
  );
  return header;
}

Future<void> _tarPadding(RandomAccessFile file, int size) async {
  final padding = (512 - size % 512) % 512;
  if (padding != 0) await file.writeFrom(Uint8List(padding));
}

Future<void> _writeTarEntry(
  RandomAccessFile file,
  String name,
  List<int> bytes,
) async {
  await file.writeFrom(_tarHeader(name, bytes.length));
  await file.writeFrom(bytes);
  await _tarPadding(file, bytes.length);
}
