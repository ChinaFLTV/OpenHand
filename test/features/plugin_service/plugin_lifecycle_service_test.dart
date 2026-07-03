import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/model/plugin_info.dart';
import 'package:openhand/features/plugin_service/service/plugin_lifecycle_service.dart';
import 'package:openhand/features/plugin_service/service/plugin_toolchain_shell.dart';

void main() {
  group('Managed toolchain command probes', () {
    test('downgrades a missing executable to a shell preflight miss', () async {
      if (Platform.isWindows) return;

      const missingCommand = '__openhand_missing_command_for_test__';
      final result = await Process.run('/bin/sh', [
        '-c',
        pluginLifecycleManagedToolchainCommandScript(missingCommand, const [
          '--version',
        ]),
      ]);

      expect(result.exitCode, 127);
      expect(result.stderr.toString(), contains('$missingCommand not found'));
    });

    test('shell-quotes executable names and arguments', () {
      final script = pluginLifecycleManagedToolchainCommandScript(
        "hermes'agent",
        const <String>['--flag', 'value with spaces'],
      );

      expect(script, contains("'hermes'\"'\"'agent'"));
      expect(script, contains("'value with spaces'"));
      expect(script, contains('command -v'));
      expect(script, contains('exec'));
    });

    test('falls back to npm global bin when command is not on PATH', () async {
      if (Platform.isWindows) return;

      final temp = Directory.systemTemp.createTempSync(
        'openhand_plugin_lifecycle_',
      );
      try {
        final pyenvBin = Directory('${temp.path}/pyenv/bin')
          ..createSync(recursive: true);
        final npmPrefixBin = Directory('${temp.path}/npm-prefix/bin')
          ..createSync(recursive: true);
        final npm = File('${pyenvBin.path}/npm');
        npm.writeAsStringSync('''
#!/bin/sh
if [ "\$1" = "prefix" ] && [ "\$2" = "-g" ]; then
  printf '%s\\n' '${temp.path}/npm-prefix'
  exit 0
fi
exit 1
''');
        final command = File('${npmPrefixBin.path}/openhand-hermes-test');
        command.writeAsStringSync('''
#!/bin/sh
printf 'openhand-hermes-test 1.2.3\\n'
''');
        await Process.run('/bin/chmod', ['+x', npm.path, command.path]);

        final result = await Process.run(
          '/bin/sh',
          [
            '-c',
            pluginLifecycleManagedToolchainCommandScript(
              'openhand-hermes-test',
              const <String>['--version'],
            ),
          ],
          environment: <String, String>{
            'PATH': '/usr/bin:/bin',
            'NVM_DIR': '${temp.path}/nvm',
            'PYENV_ROOT': '${temp.path}/pyenv',
            'VOLTA_HOME': '${temp.path}/volta',
          },
          includeParentEnvironment: false,
        );

        expect(result.exitCode, 0);
        expect(result.stdout.toString(), contains('1.2.3'));
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('resolves npm global bin command paths for scanners', () async {
      if (Platform.isWindows) return;

      final temp = Directory.systemTemp.createTempSync(
        'openhand_plugin_scanner_',
      );
      try {
        final pyenvBin = Directory('${temp.path}/pyenv/bin')
          ..createSync(recursive: true);
        final npmPrefixBin = Directory('${temp.path}/npm-prefix/bin')
          ..createSync(recursive: true);
        final npm = File('${pyenvBin.path}/npm');
        npm.writeAsStringSync('''
#!/bin/sh
if [ "\$1" = "prefix" ] && [ "\$2" = "-g" ]; then
  printf '%s\\n' '${temp.path}/npm-prefix'
  exit 0
fi
exit 1
''');
        final command = File('${npmPrefixBin.path}/openhand-hermes-scan-test');
        command.writeAsStringSync('''
#!/bin/sh
printf 'openhand-hermes-scan-test 2.3.4\\n'
''');
        await Process.run('/bin/chmod', ['+x', npm.path, command.path]);

        final result = await Process.run(
          '/bin/sh',
          [
            '-c',
            pluginToolchainCommandPathScript(
              'openhand-hermes-scan-test',
              includeNpmGlobalBinFallback: true,
            ),
          ],
          environment: <String, String>{
            'PATH': '/usr/bin:/bin',
            'NVM_DIR': '${temp.path}/nvm',
            'PYENV_ROOT': '${temp.path}/pyenv',
            'VOLTA_HOME': '${temp.path}/volta',
          },
          includeParentEnvironment: false,
        );

        expect(result.exitCode, 0);
        expect(result.stdout.toString().trim(), command.path);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  });

  group('Hermes Agent npm failure diagnostics', () {
    test('prioritizes PyPI TLS failures over missing distribution noise', () {
      const output = '''
npm error Could not fetch URL https://pypi.org/simple/hermes-agent/: There was a problem confirming the ssl certificate
npm error SSLError(SSLCertVerificationError(1, '[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate'))
npm error ERROR: Could not find a version that satisfies the requirement hermes-agent==0.18.0 (from versions: none)
npm error ERROR: No matching distribution found for hermes-agent==0.18.0
''';

      expect(pluginLifecycleOutputHasPyPiTlsFailure(output), isTrue);

      final message = hermesAgentNpmFailureMessage(
        label: 'Hermes Agent',
        output: output,
      );

      expect(message, contains('证书校验失败'));
      expect(message, contains('Python 包元数据无法获取'));
      expect(message, contains('原始输出'));
    });

    test('records the CA bundle used for TLS retry', () {
      final message = hermesAgentNpmFailureMessage(
        label: 'Hermes Agent',
        output: 'CERTIFICATE_VERIFY_FAILED while reaching pypi.org/simple/',
        tlsRetryAttempted: true,
        tlsBundle: '/etc/ssl/cert.pem',
      );

      expect(message, contains('/etc/ssl/cert.pem'));
      expect(message, contains('已使用 CA bundle 重试'));
    });
  });

  group('PluginInfo.copyWith', () {
    test('can explicitly clear an existing error message', () {
      const plugin = PluginInfo(
        id: 'hermes_agent',
        name: 'Hermes Agent',
        description: 'runtime',
        status: PluginStatus.error,
        errorMessage: 'failed',
      );

      expect(plugin.copyWith().errorMessage, 'failed');
      expect(plugin.copyWith(clearErrorMessage: true).errorMessage, isNull);
    });
  });
}
