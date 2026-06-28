import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('sandbox proxy ports normalize invalid and non-finite values', () {
    final settings = AiSandboxSettings.fromJson(<String, Object?>{
      'http_proxy_port': double.infinity,
      'socks_proxy_port': 70000,
    });

    expect(settings.httpProxyPort, 0);
    expect(settings.socksProxyPort, 0);
  });

  test('sandbox proxy ports keep valid persisted values', () {
    final settings = AiSandboxSettings.fromJson(<String, Object?>{
      'http_proxy_port': '8080',
      'socks_proxy_port': 1080,
    });

    expect(settings.httpProxyPort, 8080);
    expect(settings.socksProxyPort, 1080);
  });

  test('sandbox settings parse JSON text and loose list fields', () {
    final settings = AiSandboxSettings.fromJson('''
      {
        "enabled": "yes",
        "fail_if_unavailable": "off",
        "allow_unsandboxed_commands": "1",
        "auto_allow_bash_if_sandboxed": "true",
        "sandboxed_builtin_tools": "[\\"Bash\\", \\"bash\\", \\"Read\\"]",
        "filesystem_rules": [
          {
            "id": "workspace",
            "path": " . ",
            "access_mode": "rw",
            "match_mode": "simple"
          }
        ],
        "excluded_commands": "[{\\"pattern\\": \\"rm -rf\\", \\"match_mode\\": \\"simple\\"}]",
        "allowed_domains": [
          {"pattern": "example.com", "match_mode": "simple"}
        ],
        "allow_network_when_no_domain_rules": "no",
        "http_proxy_port": "8080"
      }
    ''');

    expect(settings.enabled, isTrue);
    expect(settings.failIfUnavailable, isFalse);
    expect(settings.allowUnsandboxedCommands, isTrue);
    expect(settings.autoAllowBashIfSandboxed, isTrue);
    expect(settings.sandboxedBuiltinTools, <String>['Bash', 'bash', 'Read']);
    expect(settings.filesystemRules, hasLength(1));
    expect(settings.filesystemRules.single.path, '.');
    expect(
      settings.filesystemRules.single.accessMode,
      AiSandboxFileAccessMode.readWrite,
    );
    expect(settings.excludedCommands, hasLength(1));
    expect(settings.excludedCommands.single.pattern, 'rm -rf');
    expect(settings.allowedDomains, hasLength(1));
    expect(settings.allowedDomains.single.pattern, 'example.com');
    expect(settings.allowNetworkWhenNoDomainRules, isFalse);
    expect(settings.httpProxyPort, 8080);
  });
}
