import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../shared/util/async_concurrency.dart';
import '../../shared/util/platform_shell.dart';
import 'machine_containers.dart';
import 'machine_image_download.dart';

enum MachineImageTransferStage { download, upload, import }

/// 下载与终端传输分别注入，网络路由与目标运行时上下文互不混淆。
class MachineImageOperations {
  const MachineImageOperations({
    required this.clientFactory,
    required this.run,
    required this.upload,
    required this.cleanup,
  });
  final HttpClient Function() clientFactory;
  final MachineContainerOperationRunner run;
  final Future<void> Function(
    File file,
    String directory,
    bool Function() isCancelled,
    void Function(int) onProgress,
  )
  upload;
  final Future<void> Function(String command) cleanup;

  Future<({String output, String image})> pull(
    MachineContainerClient client,
    String image, {
    required Duration timeout,
    bool Function()? isCancelled,
    void Function(MachineImageTransferStage stage, int received, int total)?
    onProgress,
    void Function(String)? onOutput,
  }) async {
    if (!client.supportsResources) {
      throw const MachineContainerConfigException('resourceUnsupported');
    }
    final deadline = MonotonicDeadline(timeout, timeoutMessage: '镜像拉取超过总时限。');
    bool stopped() => (isCancelled?.call() ?? false) || deadline.isExpired;
    Future<String> execute(String command, {bool output = false}) => run(
      command,
      timeout: output
          ? deadline.remaining()
          : deadline.limit(const Duration(seconds: 15)),
      isCancelled: stopped,
      onOutput: output ? onOutput : null,
    );
    try {
      final info =
          jsonDecode(await execute(client.command(client.metadataArguments)))
              as Map;
      final host = info['host'] ?? info['Host'];
      final os =
          '${info['OSType'] ?? (host is Map ? host['os'] ?? host['OS'] : null) ?? ''}'
              .toLowerCase();
      var arch =
          '${info['Architecture'] ?? (host is Map ? host['arch'] ?? host['Arch'] : null) ?? ''}'
              .toLowerCase();
      final variant = arch == 'armv7l' ? 'v7' : '';
      arch = switch (arch) {
        'x86_64' || 'x86-64' => 'amd64',
        'aarch64' => 'arm64',
        'armv7l' => 'arm',
        _ => arch,
      };
      if (!const {'linux', 'windows'}.contains(os) || arch.isEmpty) {
        throw const MachineContainerConfigException('imagePlatform');
      }
      return await MachineImageDownload(
        clientFactory: clientFactory,
      ).withArchive(
        image: image,
        os: os,
        architecture: arch,
        variant: variant,
        timeout: deadline.remaining(),
        isCancelled: stopped,
        credential: (registry) => _credential(client, registry, execute),
        onProgress: (received, total) => onProgress?.call(
          MachineImageTransferStage.download,
          received,
          total,
        ),
        consume: (archive) async {
          final createDirectory = client.windows
              ? powerShellEncodedCommand(
                  r"$p=Join-Path ([IO.Path]::GetTempPath()) ('openhand-image-'+[Guid]::NewGuid().ToString()); [IO.Directory]::CreateDirectory($p) | Out-Null; Write-Output $p",
                )
              : 'umask 077; mktemp -d "\${TMPDIR:-/tmp}/openhand-image-XXXXXXXX"';
          final directory = (await execute(createDirectory)).trim();
          if (!RegExp(
                r'[\\/]openhand-image-[A-Za-z0-9-]{8,}$',
              ).hasMatch(directory) ||
              directory.contains(RegExp(r'[\r\n\x00]'))) {
            throw const FormatException('镜像导入临时目录无效。');
          }
          final path = '$directory${client.windows ? '\\' : '/'}image.tar';
          final removeDirectory = client.windows
              ? "Remove-Item -LiteralPath '${escapePowerShellSingleQuotedString(directory)}' -Recurse -Force -ErrorAction SilentlyContinue"
              : 'rm -rf -- ${posixShellQuote(directory)}';
          try {
            final length = await archive.file.length();
            onProgress?.call(MachineImageTransferStage.upload, 0, length);
            await upload(
              archive.file,
              directory,
              stopped,
              (received) => onProgress?.call(
                MachineImageTransferStage.upload,
                received,
                length,
              ),
            );
            if (stopped()) {
              throw const MachineContainerConfigException('cancelled');
            }
            onProgress?.call(MachineImageTransferStage.import, 0, 0);
            final load = client.command([
              'load',
              '--input',
              path,
            ], readable: client.windows);
            // 导入被中断时，目标 Shell 仍负责删除自己的临时归档。
            final command = client.windows
                ? powerShellEncodedCommand(
                    "try { $load; \$code=\$LASTEXITCODE } finally { $removeDirectory }; exit \$code",
                  )
                : '(trap ${posixShellQuote(removeDirectory)} EXIT; $load)';
            final output = await execute(command, output: true);
            var imported = archive.reference;
            if (image.contains('@')) {
              // 传统镜像存储使用配置摘要，containerd 镜像存储使用清单摘要。
              for (final candidate in [
                archive.configDigest,
                archive.manifestDigest,
              ]) {
                try {
                  imported = (await execute(
                    client.command([
                      'image',
                      'inspect',
                      '--format',
                      '{{.Id}}',
                      candidate,
                    ]),
                  )).trim();
                  break;
                } on TimeoutException {
                  rethrow;
                } catch (_) {
                  if (stopped() || candidate == archive.manifestDigest) rethrow;
                }
              }
              if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(imported)) {
                throw const FormatException('导入后的镜像标识无效。');
              }
            }
            return (output: output, image: imported);
          } finally {
            await cleanup(
              client.windows
                  ? powerShellEncodedCommand(removeDirectory)
                  : removeDirectory,
            );
          }
        },
      );
    } finally {
      deadline.stop();
    }
  }

  Future<MachineImageCredential?> _credential(
    MachineContainerClient client,
    String registry,
    Future<String> Function(String) execute,
  ) async {
    try {
      const marker = '__OH_REGISTRY_CONFIG__';
      final script = client.windows
          ? powerShellEncodedCommand(r'''
$files=@(); if($env:REGISTRY_AUTH_FILE){$files+=$env:REGISTRY_AUTH_FILE}; if($env:DOCKER_CONFIG){$files+=(Join-Path $env:DOCKER_CONFIG 'config.json')}; $files+=(Join-Path $HOME '.docker/config.json'); $files+=(Join-Path $HOME '.config/containers/auth.json'); foreach($p in $files | Select-Object -Unique){ if(Test-Path -LiteralPath $p -PathType Leaf){if((Get-Item -LiteralPath $p).Length -gt 131072){throw '仓库凭据配置超过容量上限。'}; Write-Output '__OH_REGISTRY_CONFIG__'; [IO.File]::ReadAllText($p)}}
''')
          : r'''
for p in "${REGISTRY_AUTH_FILE:-/dev/null}" "${DOCKER_CONFIG:-$HOME/.docker}/config.json" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json" "${XDG_CONFIG_HOME:-$HOME/.config}/containers/auth.json" "$HOME/.docker/config.json"; do
  if [ -f "$p" ]; then printf '\n__OH_REGISTRY_CONFIG__\n'; head -c 131073 "$p"; fi
done
''';
      final response = await execute(script);
      for (final document in response.split(marker).skip(1)) {
        if (document.length > 131072 + 2) {
          throw const FormatException('仓库凭据配置超过容量上限。');
        }
        final config = jsonDecode(document.trim());
        if (config is! Map) throw const FormatException('仓库凭据配置格式无效。');
        bool matches(String address) {
          final uri = Uri.tryParse(
            address.contains('://') ? address : 'https://$address',
          );
          return uri?.authority == registry ||
              registry == 'registry-1.docker.io' &&
                  const {
                    'docker.io',
                    'index.docker.io',
                    'registry-1.docker.io',
                  }.contains(uri?.host);
        }

        final helpers = config['credHelpers'];
        final helperKey = helpers is Map
            ? helpers.keys.cast<String>().where(matches).firstOrNull
            : null;
        final helper = helperKey != null
            ? helpers[helperKey]
            : config['credsStore'];
        if (helper is String && helper.isNotEmpty) {
          if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(helper)) {
            throw const FormatException('仓库凭据助手名称无效。');
          }
          final address =
              helperKey ??
              (registry == 'registry-1.docker.io'
                  ? 'https://index.docker.io/v1/'
                  : registry);
          final command = client.windows
              ? powerShellEncodedCommand(
                  "'${escapePowerShellSingleQuotedString(address)}' | & 'docker-credential-$helper' get; exit \$LASTEXITCODE",
                )
              : 'printf %s ${posixShellQuote(address)} | ${posixShellQuote('docker-credential-$helper')} get';
          final result = await execute(command);
          final value = jsonDecode(result);
          if (value is Map &&
              value['Username'] is String &&
              value['Secret'] is String) {
            return (
              username: value['Username'] as String,
              secret: value['Secret'] as String,
            );
          }
          throw const MachineContainerConfigException('imageAuth');
        }
        final auths = config['auths'];
        if (auths is! Map) continue;
        for (final entry in auths.entries) {
          if (!matches('${entry.key}') || entry.value is! Map) continue;
          final row = entry.value as Map;
          if (row['identitytoken'] case final String token
              when token.isNotEmpty) {
            return (username: '<token>', secret: token);
          }
          if (row['auth'] case final String auth when auth.isNotEmpty) {
            final value = utf8.decode(base64Decode(auth));
            final colon = value.indexOf(':');
            if (colon < 0) {
              throw const MachineContainerConfigException('imageAuth');
            }
            return (
              username: value.substring(0, colon),
              secret: value.substring(colon + 1),
            );
          }
        }
      }
      return null;
    } on TimeoutException {
      rethrow;
    } on MachineContainerConfigException {
      rethrow;
    } catch (_) {
      // 凭据配置和助手输出不能进入错误详情。
      throw const MachineContainerConfigException('imageAuth');
    }
  }
}
