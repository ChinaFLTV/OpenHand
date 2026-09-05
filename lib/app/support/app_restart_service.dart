import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/platform_shell.dart';
import 'app_runtime_cleanup_registry.dart';
import 'safe_subprocess.dart';
import 'silent_log.dart';

const Duration _kRelaunchDelay = Duration(milliseconds: 1800);
const Duration _kExitRequestCleanupGrace = Duration(seconds: 5);
final Duration _kExitRequestTimeout =
    kOpenHandApplicationRuntimeCleanupTotalTimeout + _kExitRequestCleanupGrace;
const Duration _kRelaunchChmodTimeout = Duration(seconds: 2);
const Duration _kRelaunchFileOperationTimeout = Duration(seconds: 5);
const Duration _kRelaunchProcessStartTimeout = Duration(seconds: 5);

enum AppRestartFailure {
  missingExecutable,
  prepareFailed,
  exitCanceled,
  unsupportedPlatform,
}

class AppRestartException implements Exception {
  const AppRestartException(this.failure, {this.cause});

  final AppRestartFailure failure;
  final Object? cause;

  @override
  String toString() {
    final detail = cause == null ? '' : ' ($cause)';
    return 'AppRestartException: ${failure.name}$detail';
  }
}

class AppRelaunchTicket {
  AppRelaunchTicket._({required this.pendingFlagPath});

  final String pendingFlagPath;

  Future<void> cancel() async {
    try {
      final flag = File(pendingFlagPath);
      if (await flag.exists().timeout(_kRelaunchFileOperationTimeout)) {
        await flag.delete().timeout(_kRelaunchFileOperationTimeout);
      }
    } catch (error, stack) {
      silentLog('app_restart', '取消重启任务', error, stack);
    }
  }
}

class AppRestartService {
  AppRestartService._();

  static final AppRestartService instance = AppRestartService._();

  Future<AppRelaunchTicket> prepareRelaunch() async {
    final rawExecutablePath = nullIfBlank(Platform.resolvedExecutable);
    if (rawExecutablePath == null) {
      throw const AppRestartException(AppRestartFailure.missingExecutable);
    }
    final executablePath = p.normalize(rawExecutablePath);

    final tempDir = Directory.systemTemp;
    if (!await tempDir.exists().timeout(_kRelaunchFileOperationTimeout)) {
      await tempDir
          .create(recursive: true)
          .timeout(_kRelaunchFileOperationTimeout);
    }

    final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final pendingFlag = File(p.join(tempDir.path, 'relaunch_$suffix.pending'));
    final script = Platform.isWindows
        ? File(p.join(tempDir.path, 'relaunch_$suffix.cmd'))
        : File(p.join(tempDir.path, 'relaunch_$suffix.sh'));
    final scriptBody = Platform.isWindows
        ? _buildWindowsScript(
            executablePath: executablePath,
            pendingFlagPath: pendingFlag.path,
          )
        : _buildPosixScript(
            executablePath: executablePath,
            appBundlePath: Platform.isMacOS
                ? _resolveMacOSAppBundle(executablePath)
                : null,
            pendingFlagPath: pendingFlag.path,
            useMacOpen: Platform.isMacOS,
          );

    try {
      await writeTemporaryFileTextBounded(
        pendingFlag,
        'pending',
        timeout: _kRelaunchFileOperationTimeout,
        onSecondaryError: (error, stack) =>
            silentLog('app_restart', '清理重启标记文件', error, stack),
      );
      await writeTemporaryFileTextBounded(
        script,
        scriptBody,
        timeout: _kRelaunchFileOperationTimeout,
        onSecondaryError: (error, stack) =>
            silentLog('app_restart', '清理重启脚本', error, stack),
      );
      if (!Platform.isWindows) {
        final chmodResult = await runTrackedProcessOrFailed(
          '/bin/chmod',
          <String>['700', script.path],
          timeout: _kRelaunchChmodTimeout,
          tag: 'app_restart.chmod_relaunch_script',
        );
        if (chmodResult.exitCode != 0) {
          final message = '${chmodResult.stderr}'.trim();
          throw FileSystemException(
            message.isEmpty
                ? 'Unable to mark relaunch helper executable.'
                : message,
            script.path,
          );
        }
      }
      await _startDetachedHelper(script.path);
      return AppRelaunchTicket._(pendingFlagPath: pendingFlag.path);
    } on AppRestartException {
      // 已经带了具体 failure 的异常原样上抛，否则会被下面统一包成
      // prepareFailed，unsupportedPlatform 分支的文案永远到不了 UI。
      await _deleteIfExists(script);
      await _deleteIfExists(pendingFlag);
      rethrow;
    } catch (error) {
      await _deleteIfExists(script);
      await _deleteIfExists(pendingFlag);
      throw AppRestartException(AppRestartFailure.prepareFailed, cause: error);
    }
  }

  Future<void> exitCurrentProcess({AppRelaunchTicket? ticket}) async {
    try {
      // onExitRequested 会等待运行时资源清理，短超时会截断关闭链路。
      final response = await ServicesBinding.instance
          .exitApplication(ui.AppExitType.cancelable)
          .timeout(_kExitRequestTimeout);
      if (response == ui.AppExitResponse.cancel) {
        await ticket?.cancel();
        throw const AppRestartException(AppRestartFailure.exitCanceled);
      }
      exit(0);
    } on TimeoutException {
      exit(0);
    } on AppRestartException {
      rethrow;
    } catch (error, stack) {
      silentLog('app_restart', '退出当前进程', error, stack);
      exit(0);
    }
  }

  Future<void> _startDetachedHelper(String scriptPath) async {
    if (Platform.isWindows) {
      await startDetachedProcessBounded(
        'cmd.exe',
        <String>['/c', scriptPath],
        timeout: _kRelaunchProcessStartTimeout,
        tag: 'app_restart.start_helper',
      );
      return;
    }
    if (Platform.isMacOS || Platform.isLinux) {
      await startDetachedProcessBounded(
        '/bin/sh',
        <String>[scriptPath],
        timeout: _kRelaunchProcessStartTimeout,
        tag: 'app_restart.start_helper',
      );
      return;
    }
    throw const AppRestartException(AppRestartFailure.unsupportedPlatform);
  }

  String _buildPosixScript({
    required String executablePath,
    required String? appBundlePath,
    required String pendingFlagPath,
    required bool useMacOpen,
  }) {
    final delaySeconds = (_kRelaunchDelay.inMilliseconds / 1000)
        .toStringAsFixed(3);
    final quotedFlag = posixShellQuote(pendingFlagPath);
    final quotedExecutable = posixShellQuote(executablePath);
    final quotedBundle = appBundlePath == null
        ? null
        : posixShellQuote(appBundlePath);
    final launch = useMacOpen && quotedBundle != null
        ? '/usr/bin/open -n -F -- $quotedBundle >/dev/null 2>&1\n'
        : 'rm -f -- "\$0"\nexec $quotedExecutable >/dev/null 2>&1\n';
    final cleanupAfterLaunch = useMacOpen && quotedBundle != null
        ? 'status=\$?\nrm -f -- "\$0"\nexit \$status\n'
        : '';

    return '#!/bin/sh\n'
        'sleep $delaySeconds\n'
        'if [ ! -f $quotedFlag ]; then\n'
        '  rm -f -- "\$0"\n'
        '  exit 0\n'
        'fi\n'
        'rm -f -- $quotedFlag\n'
        '${_buildPosixFlutterEngineSwitchCleanup()}'
        '$launch'
        '$cleanupAfterLaunch';
  }

  String _buildWindowsScript({
    required String executablePath,
    required String pendingFlagPath,
  }) {
    final timeoutSeconds = (_kRelaunchDelay.inMilliseconds / 1000).ceil();
    return '@echo off\r\n'
        'timeout /t $timeoutSeconds /nobreak >nul\r\n'
        'if not exist "${_escapeWindowsPath(pendingFlagPath)}" exit /b 0\r\n'
        'del /f /q "${_escapeWindowsPath(pendingFlagPath)}" >nul 2>nul\r\n'
        '${_buildWindowsFlutterEngineSwitchCleanup()}'
        'start "" "${_escapeWindowsPath(executablePath)}"\r\n'
        'del /f /q "%~f0" >nul 2>nul\r\n';
  }

  static String _buildPosixFlutterEngineSwitchCleanup() {
    return 'unset FLUTTER_ENGINE_SWITCHES\n'
        'i=1\n'
        'while [ "\$i" -le 256 ]; do\n'
        '  unset "FLUTTER_ENGINE_SWITCH_\$i"\n'
        '  i=\$((i + 1))\n'
        'done\n';
  }

  static String _buildWindowsFlutterEngineSwitchCleanup() {
    return 'set "FLUTTER_ENGINE_SWITCHES="\r\n'
        'for /L %%I in (1,1,256) do set "FLUTTER_ENGINE_SWITCH_%%I="\r\n';
  }

  static String? _resolveMacOSAppBundle(String executablePath) {
    final normalized = p.normalize(executablePath);
    final marker = '${p.separator}Contents${p.separator}MacOS${p.separator}';
    final markerIndex = normalized.lastIndexOf(marker);
    if (markerIndex <= 0) return null;
    final bundle = normalized.substring(0, markerIndex);
    return p.extension(bundle).toLowerCase() == '.app' ? bundle : null;
  }

  static String _escapeWindowsPath(String value) {
    return value.replaceAll('"', r'\"');
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists().timeout(_kRelaunchFileOperationTimeout)) {
        await file.delete().timeout(_kRelaunchFileOperationTimeout);
      }
    } catch (error, stack) {
      silentLog('app_restart', '删除 ${file.path}', error, stack);
    }
  }
}
