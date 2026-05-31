import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../shared/ui/openhand_snack_bar.dart';
import 'safe_subprocess.dart';

enum OpenHandNotificationLevel { info, success, warning, error, critical }

abstract final class OpenHandNotificationService {
  static bool get supportsVibration => Platform.isAndroid || Platform.isIOS;

  static Future<void> showInApp({
    required String title,
    required String body,
    OpenHandNotificationLevel level = OpenHandNotificationLevel.info,
    bool playSound = false,
    bool vibrate = false,
  }) async {
    final messenger = OpenHandSnackBar.rootMessengerKey.currentState;
    final context = OpenHandSnackBar.rootMessengerKey.currentContext;
    if (messenger == null || context == null) return;

    final colorScheme = Theme.of(context).colorScheme;
    final (icon, backgroundColor, foregroundColor) = switch (level) {
      OpenHandNotificationLevel.info => (
        Icons.info_outline_rounded,
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
      OpenHandNotificationLevel.success => (
        Icons.check_circle_outline_rounded,
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      OpenHandNotificationLevel.warning => (
        Icons.warning_amber_rounded,
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
      ),
      OpenHandNotificationLevel.error => (
        Icons.error_outline_rounded,
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      OpenHandNotificationLevel.critical => (
        Icons.dangerous_rounded,
        colorScheme.error,
        colorScheme.onError,
      ),
    };

    final text = body.trim().isEmpty ? title : '$title\n$body';

    OpenHandSnackBar.show(
      context,
      messenger,
      OpenHandSnackBar.notification(
        context,
        message: text,
        icon: icon,
        tint: foregroundColor,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      ),
    );

    if (playSound) {
      unawaited(_playSoundBestEffort(level));
    }
    if (vibrate) {
      unawaited(_vibrateBestEffort());
    }
  }

  static Future<bool> showSystem({
    required String title,
    required String body,
    OpenHandNotificationLevel level = OpenHandNotificationLevel.info,
    bool playSound = false,
    bool vibrate = false,
  }) async {
    var shown = false;
    if (Platform.isMacOS) {
      shown = await _showMacOs(title: title, body: body);
    } else if (Platform.isLinux) {
      shown = await _showLinux(title: title, body: body, level: level);
    } else if (Platform.isWindows) {
      shown = await _showWindows(title: title, body: body);
    }

    if (shown && playSound) {
      unawaited(_playSoundBestEffort(level));
    }
    if (shown && vibrate) {
      unawaited(_vibrateBestEffort());
    }

    return shown;
  }

  static Future<bool> _showMacOs({
    required String title,
    required String body,
  }) async {
    final safeTitle = _escapeAppleScript(title);
    final safeBody = _escapeAppleScript(body);
    final result = await runProcessWithTimeout('osascript', [
      '-e',
      'display notification "$safeBody" with title "$safeTitle"',
    ], tag: 'openhand_notification_service');
    return result?.exitCode == 0;
  }

  static Future<bool> _showLinux({
    required String title,
    required String body,
    required OpenHandNotificationLevel level,
  }) async {
    try {
      final whichResult = await runProcessWithTimeout(
        'which',
        const <String>['notify-send'],
        timeout: const Duration(seconds: 3),
        tag: 'openhand_notification_service',
      );
      if (whichResult == null || whichResult.exitCode != 0) return false;
      final urgency = switch (level) {
        OpenHandNotificationLevel.critical => 'critical',
        OpenHandNotificationLevel.error => 'critical',
        OpenHandNotificationLevel.warning => 'normal',
        _ => 'low',
      };
      final result = await runProcessWithTimeout(
        'notify-send',
        <String>['-u', urgency, title, body],
        timeout: const Duration(seconds: 5),
        tag: 'openhand_notification_service',
      );
      return result?.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _showWindows({
    required String title,
    required String body,
  }) async {
    final safeTitle = _escapeForSingleQuotedPowerShell(title);
    final safeBody = _escapeForSingleQuotedPowerShell(body);

    final script =
        r'''
$ErrorActionPreference = 'Stop'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null
$template = @"
<toast>
  <visual>
    <binding template='ToastGeneric'>
      <text>TITLE_PLACEHOLDER</text>
      <text>BODY_PLACEHOLDER</text>
    </binding>
  </visual>
</toast>
"@
$template = $template.Replace('TITLE_PLACEHOLDER', 'TITLE_VALUE').Replace('BODY_PLACEHOLDER', 'BODY_VALUE')
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($template)
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('OpenHand')
$notifier.Show($toast)
'''
            .replaceAll('TITLE_VALUE', safeTitle)
            .replaceAll('BODY_VALUE', safeBody);

    try {
      final result = await runProcessWithTimeout(
        'powershell',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        timeout: const Duration(seconds: 8),
        tag: 'openhand_notification_service',
      );
      return result?.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static String _escapeAppleScript(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', ' ')
        .trim();
  }

  static String _escapeForSingleQuotedPowerShell(String input) {
    return input.replaceAll("'", "''").replaceAll('\n', ' ').trim();
  }

  static Future<bool> _playSoundBestEffort(
    OpenHandNotificationLevel level,
  ) async {
    try {
      if (Platform.isMacOS) {
        return _playSoundMacOs(level);
      }
      if (Platform.isLinux) {
        return _playSoundLinux(level);
      }
      if (Platform.isWindows) {
        return _playSoundWindows(level);
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<bool> _vibrateBestEffort() async {
    // Desktop platforms generally do not expose a stable vibration API.
    if (!supportsVibration) return false;
    return false;
  }

  static Future<bool> _playSoundMacOs(OpenHandNotificationLevel level) async {
    final soundName = switch (level) {
      OpenHandNotificationLevel.success => 'Glass',
      OpenHandNotificationLevel.warning => 'Basso',
      OpenHandNotificationLevel.error => 'Sosumi',
      OpenHandNotificationLevel.critical => 'Sosumi',
      OpenHandNotificationLevel.info => 'Funk',
    };
    final soundPath = '/System/Library/Sounds/$soundName.aiff';
    final file = File(soundPath);
    if (file.existsSync()) {
      final result = await runProcessWithTimeout(
        'afplay',
        [soundPath],
        timeout: const Duration(seconds: 6),
        tag: 'openhand_notification_service',
      );
      if (result?.exitCode == 0) return true;
    }
    final fallback = await runProcessWithTimeout('osascript', [
      '-e',
      'beep',
    ], tag: 'openhand_notification_service');
    return fallback?.exitCode == 0;
  }

  static Future<bool> _playSoundLinux(OpenHandNotificationLevel level) async {
    try {
      if (await _commandExists('canberra-gtk-play')) {
        final id = switch (level) {
          OpenHandNotificationLevel.success => 'complete',
          OpenHandNotificationLevel.warning => 'dialog-warning',
          OpenHandNotificationLevel.error => 'dialog-error',
          OpenHandNotificationLevel.critical => 'dialog-error',
          OpenHandNotificationLevel.info => 'message-new-instant',
        };
        final result = await runProcessWithTimeout(
          'canberra-gtk-play',
          <String>['-i', id],
          timeout: const Duration(seconds: 5),
          tag: 'openhand_notification_service',
        );
        if (result?.exitCode == 0) return true;
      }
      if (await _commandExists('paplay')) {
        final result = await runProcessWithTimeout(
          'paplay',
          const <String>['/usr/share/sounds/freedesktop/stereo/message.oga'],
          timeout: const Duration(seconds: 5),
          tag: 'openhand_notification_service',
        );
        if (result?.exitCode == 0) return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<bool> _playSoundWindows(OpenHandNotificationLevel level) async {
    final command = switch (level) {
      OpenHandNotificationLevel.success =>
        '[System.Media.SystemSounds]::Asterisk.Play()',
      OpenHandNotificationLevel.warning =>
        '[System.Media.SystemSounds]::Exclamation.Play()',
      OpenHandNotificationLevel.error =>
        '[System.Media.SystemSounds]::Hand.Play()',
      OpenHandNotificationLevel.critical =>
        '[System.Media.SystemSounds]::Hand.Play()',
      OpenHandNotificationLevel.info =>
        '[System.Media.SystemSounds]::Beep.Play()',
    };
    try {
      final result = await runProcessWithTimeout(
        'powershell',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          command,
        ],
        timeout: const Duration(seconds: 6),
        tag: 'openhand_notification_service',
      );
      return result?.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _commandExists(String command) async {
    try {
      final result = await runProcessWithTimeout(
        'which',
        <String>[command],
        timeout: const Duration(seconds: 3),
        tag: 'openhand_notification_service',
      );
      return result?.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
