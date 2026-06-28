import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/android_reverse/android_reverse_session_config.dart';

void main() {
  test('fromJson normalizes persisted optional fields', () {
    final config = AndroidReverseSessionConfig.fromJson(<String, Object?>{
      'objective': ' inspect login flow ',
      'package_name': ' com.example.app ',
      'apk_path': '   ',
      'device_serial': 12345,
      'authorization_scope': ' self-owned test app ',
      'analysis_mode': 'dynamic_first',
      'adb_mcp_enabled': 'on',
      'frida_mcp_enabled': '0',
      'keywords': <Object?>[' token ', null, 42, '', ' login '],
      'notes': '   ',
    });

    expect(config, isNotNull);
    expect(config!.objective, 'inspect login flow');
    expect(config.packageName, 'com.example.app');
    expect(config.apkPath, isNull);
    expect(config.deviceSerial, '12345');
    expect(config.authorizationScope, 'self-owned test app');
    expect(config.analysisMode, AndroidReverseAnalysisMode.dynamicFirst);
    expect(config.adbMcpEnabled, isTrue);
    expect(config.fridaMcpEnabled, isFalse);
    expect(config.keywords, <String>['token', '42', 'login']);
    expect(config.notes, isNull);
  });

  test('fromJson rejects blank objectives', () {
    expect(
      AndroidReverseSessionConfig.fromJson(<String, Object?>{
        'objective': '   ',
        'adb_mcp_enabled': true,
      }),
      isNull,
    );
  });
}
