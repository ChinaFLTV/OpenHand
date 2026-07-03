import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../shared/util/input_value_parsing.dart';
import 'safe_subprocess.dart';
import 'silent_log.dart';

const Duration _kRelaunchDelay = Duration(milliseconds: 1800);
const Duration _kExitRequestTimeout = Duration(seconds: 3);
const Duration _kRelaunchChmodTimeout = Duration(seconds: 2);

typedef AppRestartProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
      bool runInShell,
    });

typedef AppRestartExitApplication =
    Future<ui.AppExitResponse> Function(ui.AppExitType exitType, int exitCode);

typedef AppRestartForceExit = void Function(int exitCode);

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
  AppRelaunchTicket._({
    required this.scriptPath,
    required this.pendingFlagPath,
  });

  final String scriptPath;
  final String pendingFlagPath;

  Future<void> cancel() async {
    try {
      final flag = File(pendingFlagPath);
      if (await flag.exists()) {
        await flag.delete();
      }
    } catch (error, stack) {
      silentLog('app_restart', 'cancel relaunch ticket', error, stack);
    }
  }
}

class AppRestartService {
  AppRestartService({
    String Function()? executablePathProvider,
    Directory Function()? tempDirectoryProvider,
    AppRestartProcessStarter? processStarter,
    AppRestartExitApplication? exitApplication,
    AppRestartForceExit? forceExit,
    DateTime Function()? nowProvider,
    int Function()? pidProvider,
    bool? isMacOS,
    bool? isWindows,
    bool? isLinux,
    Duration relaunchDelay = _kRelaunchDelay,
    Duration exitRequestTimeout = _kExitRequestTimeout,
  }) : _executablePathProvider =
           executablePathProvider ?? (() => Platform.resolvedExecutable),
       _tempDirectoryProvider =
           tempDirectoryProvider ?? (() => Directory.systemTemp),
       _processStarter = processStarter ?? Process.start,
       _exitApplication =
           exitApplication ?? ServicesBinding.instance.exitApplication,
       _forceExit = forceExit ?? exit,
       _nowProvider = nowProvider ?? DateTime.now,
       _pidProvider = pidProvider ?? (() => pid),
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isWindows = isWindows ?? Platform.isWindows,
       _isLinux = isLinux ?? Platform.isLinux,
       _relaunchDelay = _nonNegativeDuration(relaunchDelay),
       _exitRequestTimeout = _positiveDuration(
         exitRequestTimeout,
         fallback: _kExitRequestTimeout,
       );

  static final AppRestartService instance = AppRestartService();

  final String Function() _executablePathProvider;
  final Directory Function() _tempDirectoryProvider;
  final AppRestartProcessStarter _processStarter;
  final AppRestartExitApplication _exitApplication;
  final AppRestartForceExit _forceExit;
  final DateTime Function() _nowProvider;
  final int Function() _pidProvider;
  final bool _isMacOS;
  final bool _isWindows;
  final bool _isLinux;
  final Duration _relaunchDelay;
  final Duration _exitRequestTimeout;

  Future<AppRelaunchTicket> prepareRelaunch() async {
    final rawExecutablePath = nullIfBlank(_executablePathProvider());
    if (rawExecutablePath == null) {
      throw const AppRestartException(AppRestartFailure.missingExecutable);
    }
    final executablePath = p.normalize(rawExecutablePath);

    final tempDir = _tempDirectoryProvider();
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    final suffix = '${_pidProvider()}_${_nowProvider().microsecondsSinceEpoch}';
    final pendingFlag = File(p.join(tempDir.path, 'relaunch_$suffix.pending'));
    await pendingFlag.writeAsString('pending', flush: true);

    final script = _isWindows
        ? File(p.join(tempDir.path, 'relaunch_$suffix.cmd'))
        : File(p.join(tempDir.path, 'relaunch_$suffix.sh'));
    final scriptBody = _isWindows
        ? _buildWindowsScript(
            executablePath: executablePath,
            pendingFlagPath: pendingFlag.path,
          )
        : _buildPosixScript(
            executablePath: executablePath,
            appBundlePath: _isMacOS
                ? resolveMacOSAppBundle(executablePath)
                : null,
            pendingFlagPath: pendingFlag.path,
            useMacOpen: _isMacOS,
          );

    try {
      await script.writeAsString(scriptBody, flush: true);
      if (!_isWindows) {
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
      return AppRelaunchTicket._(
        scriptPath: script.path,
        pendingFlagPath: pendingFlag.path,
      );
    } catch (error, stack) {
      silentLog('app_restart', 'prepare relaunch', error, stack);
      await _deleteIfExists(script);
      await _deleteIfExists(pendingFlag);
      throw AppRestartException(AppRestartFailure.prepareFailed, cause: error);
    }
  }

  Future<void> exitCurrentProcess({AppRelaunchTicket? ticket}) async {
    try {
      final response = await _exitApplication(
        ui.AppExitType.cancelable,
        0,
      ).timeout(_exitRequestTimeout);
      if (response == ui.AppExitResponse.cancel) {
        await ticket?.cancel();
        throw const AppRestartException(AppRestartFailure.exitCanceled);
      }
      _forceExit(0);
    } on TimeoutException {
      _forceExit(0);
    } on AppRestartException {
      rethrow;
    } catch (error, stack) {
      silentLog('app_restart', 'exit current process', error, stack);
      _forceExit(0);
    }
  }

  Future<void> restart({Duration beforeExitDelay = Duration.zero}) async {
    final ticket = await prepareRelaunch();
    if (beforeExitDelay > Duration.zero) {
      await Future<void>.delayed(beforeExitDelay);
    }
    await exitCurrentProcess(ticket: ticket);
  }

  Future<void> _startDetachedHelper(String scriptPath) async {
    if (_isWindows) {
      await _processStarter(
        'cmd.exe',
        <String>['/c', scriptPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return;
    }
    if (_isMacOS || _isLinux) {
      await _processStarter(
        '/bin/sh',
        <String>[scriptPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
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
    final delaySeconds = (_relaunchDelay.inMilliseconds / 1000).toStringAsFixed(
      3,
    );
    final quotedFlag = _shellQuote(pendingFlagPath);
    final quotedExecutable = _shellQuote(executablePath);
    final quotedBundle = appBundlePath == null
        ? null
        : _shellQuote(appBundlePath);
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
    final timeoutSeconds = (_relaunchDelay.inMilliseconds / 1000).ceil();
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

  static String? resolveMacOSAppBundle(String executablePath) {
    final normalized = p.normalize(executablePath);
    final marker = '${p.separator}Contents${p.separator}MacOS${p.separator}';
    final markerIndex = normalized.lastIndexOf(marker);
    if (markerIndex <= 0) return null;
    final bundle = normalized.substring(0, markerIndex);
    return p.extension(bundle).toLowerCase() == '.app' ? bundle : null;
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  static String _escapeWindowsPath(String value) {
    return value.replaceAll('"', r'\"');
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error, stack) {
      silentLog('app_restart', 'delete ${file.path}', error, stack);
    }
  }
}

Duration _nonNegativeDuration(Duration duration) {
  return duration < Duration.zero ? Duration.zero : duration;
}

Duration _positiveDuration(Duration duration, {required Duration fallback}) {
  return duration > Duration.zero ? duration : fallback;
}
