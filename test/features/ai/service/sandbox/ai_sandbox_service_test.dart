import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_sandbox_settings.dart';
import 'package:openhand/features/ai/service/sandbox/ai_sandbox_service.dart';

void main() {
  group('AiSandboxService sandbox override', () {
    test(
      'denies dangerouslyDisableSandbox when unsandboxed commands are off',
      () async {
        final service = AiSandboxService(settings: _settings(allow: false));

        final spec = await service.prepareShellCommand(
          toolName: 'Bash',
          command: 'printf blocked',
          shellExecutable: '/bin/sh',
          shellArguments: const <String>['-lc', 'printf blocked'],
          workingDirectory: Directory.systemTemp.path,
          dangerouslyDisableSandbox: true,
        );

        expect(spec.blocked, isTrue);
        expect(spec.applied, isFalse);
        expect(spec.reason, contains('dangerouslyDisableSandbox'));
        expect(spec.metadata['sandbox_override_requested'], isTrue);
        expect(spec.metadata['sandbox_override_denied'], isTrue);
      },
    );

    test('honors dangerouslyDisableSandbox when settings allow it', () async {
      final service = AiSandboxService(settings: _settings(allow: true));

      final spec = await service.prepareShellCommand(
        toolName: 'Bash',
        command: 'printf allowed',
        shellExecutable: '/bin/sh',
        shellArguments: const <String>['-lc', 'printf allowed'],
        workingDirectory: Directory.systemTemp.path,
        dangerouslyDisableSandbox: true,
      );

      expect(spec.blocked, isFalse);
      expect(spec.applied, isFalse);
      expect(spec.metadata['sandbox_override_requested'], isTrue);
      expect(spec.metadata['sandbox_override_effective'], isTrue);
      expect(
        spec.metadata['sandbox_override_reason'],
        'dangerouslyDisableSandbox',
      );
    });
  });
}

AiSandboxSettings _settings({required bool allow}) {
  return AiSandboxSettings(
    enabled: true,
    failIfUnavailable: true,
    allowUnsandboxedCommands: allow,
    autoAllowBashIfSandboxed: false,
    sandboxedBuiltinTools: const <String>['Bash'],
    filesystemRules: const <AiSandboxFileRule>[],
    excludedCommands: const <AiSandboxPatternRule>[],
    allowedDomains: const <AiSandboxPatternRule>[],
    deniedDomains: const <AiSandboxPatternRule>[],
    httpProxyPort: 0,
    socksProxyPort: 0,
    allowNetworkWhenNoDomainRules: true,
  );
}
