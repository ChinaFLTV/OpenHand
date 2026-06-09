import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  group('AiSandboxSettings', () {
    test('normalizes persisted ports, tools, and default file rules', () {
      final settings = AiSandboxSettings.fromJson(<String, Object?>{
        'enabled': true,
        'sandboxed_builtin_tools': <Object?>[
          ' Bash ',
          'bash',
          'BashBackground',
          '',
        ],
        'filesystem_rules': <Object?>[],
        'http_proxy_port': '70000',
        'socks_proxy_port': '1080',
      });

      expect(settings.enabled, isTrue);
      expect(settings.httpProxyPort, 0);
      expect(settings.socksProxyPort, 1080);
      expect(settings.filesystemRules.single.id, 'default-openhand-ro');
      expect(settings.shouldSandboxBuiltinTool('bash'), isTrue);
      expect(settings.shouldSandboxBuiltinTool('Bash Background'), isTrue);
      expect(settings.sandboxedBuiltinTools, <String>[
        'Bash',
        'bash',
        'BashBackground',
      ]);
    });

    test('ignores malformed or empty sandbox pattern rules', () {
      final settings = AiSandboxSettings.fromJson(<String, Object?>{
        'excluded_commands': <Object?>[
          <String, Object?>{'pattern': ''},
          <String, Object?>{
            'id': 'skip-rm',
            'pattern': 'rm *',
            'match_mode': 'simple',
          },
        ],
      });

      expect(settings.excludedCommands, hasLength(1));
      expect(settings.matchingExcludedCommand('rm build'), isNotNull);
      expect(settings.matchingExcludedCommand('git status'), isNull);
    });
  });
}
