import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/service/plugin_environment_probe.dart';

void main() {
  test('插件工具链版本解析兼容 Unix 与 Windows 路径', () {
    expect(
      extractPluginPyenvVersionFromPath(
        '/Users/test/.pyenv/versions/3.12.7/bin/python',
      ),
      '3.12.7',
    );
    expect(
      extractPluginPyenvVersionFromPath(
        r'C:\Users\test\.pyenv\pyenv-win\versions\3.11.9\python.exe',
      ),
      '3.11.9',
    );
    expect(
      extractPluginPyenvVersionFromPath(
        r'C:\Users\test\.pyenv\versions\preview\python.exe',
      ),
      isNull,
    );
    expect(
      extractPluginBrewPythonFormulaFromPath(
        '/opt/homebrew/Cellar/python@3.13/3.13.2/bin/python3',
      ),
      'python@3.13',
    );
    expect(normalizePluginPlaywrightVersion('  Version 1.52.0  '), '1.52.0');
    expect(
      extractPluginHomebrewStableVersion(<String, Object?>{
        'formulae': <Object?>[
          <String, Object?>{
            'versions': <String, Object?>{'stable': ' 3.13.2 '},
          },
        ],
      }),
      '3.13.2',
    );
    expect(
      extractPluginHomebrewStableVersion(<String, Object?>{
        'formulae': <Object?>[
          <String, Object?>{
            'versions': <String, Object?>{'stable': true},
          },
        ],
      }),
      isNull,
    );
  });

  test('pyenv 安装探测兼容 pyenv-win 目录结构', () async {
    final directory = Directory.systemTemp.createTempSync(
      'openhand-pyenv-probe-',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final bin = Directory(
      '${directory.path}${Platform.pathSeparator}.pyenv'
      '${Platform.pathSeparator}pyenv-win${Platform.pathSeparator}bin',
    )..createSync(recursive: true);
    File(
      '${bin.path}${Platform.pathSeparator}pyenv.bat',
    ).writeAsStringSync('@echo off\r\n');

    expect(
      await pluginPyenvInstallationExists(homeDirectory: directory.path),
      isTrue,
    );
  });
}
