import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('AiLspLanguageSettings.fromJson accepts JSON object text', () {
    final settings = AiLspLanguageSettings.fromJson('''
      {
        "backend_id": " dart-analysis-server ",
        "root_path": " /workspace ",
        "sdk_path": " /opt/dart ",
        "version": " latest "
      }
    ''');

    expect(settings.backendId, 'dart-analysis-server');
    expect(settings.rootPath, '/workspace');
    expect(settings.sdkPath, '/opt/dart');
    expect(settings.version, 'latest');
  });

  test('AiLspLanguageSettings.fromJson normalizes loose map keys', () {
    final settings = AiLspLanguageSettings.fromJson(<Object?, Object?>{
      1: 'ignored',
      'backend_id': 123,
      'version': ' stable ',
    });

    expect(settings.backendId, '123');
    expect(settings.rootPath, isEmpty);
    expect(settings.sdkPath, isEmpty);
    expect(settings.version, 'stable');
  });
}
