import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

enum OpenHandNotificationLevel {
  info,
  success,
  warning,
  error,
  critical,
}

abstract final class OpenHandNotificationService {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static bool get supportsVibration => Platform.isAndroid || Platform.isIOS;

  static Future<void> showInApp({
    required String title,
    required String body,
    OpenHandNotificationLevel level = OpenHandNotificationLevel.info,
    bool playSound = false,
    bool vibrate = false,
  }) async {
    final messenger = scaffoldMessengerKey.currentState;
    final context = scaffoldMessengerKey.currentContext;
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

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, size: 18, color: foregroundColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foregroundColor),
              ),
            ),
          ],
        ),
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
    try {
      final result = await Process.run('osascript', [
        '-e',
        'display notification "$safeBody" with title "$safeTitle"',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _showLinux({
    required String title,
    required String body,
    required OpenHandNotificationLevel level,
  }) async {
    try {
      final whichResult = await Process.run('which', ['notify-send']);
      if (whichResult.exitCode != 0) return false;
      final urgency = switch (level) {
        OpenHandNotificationLevel.critical => 'critical',
        OpenHandNotificationLevel.error => 'critical',
        OpenHandNotificationLevel.warning => 'normal',
        _ => 'low',
      };
      final result = await Process.run('notify-send', ['-u', urgency, title, body]);
      return result.exitCode == 0;
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

    final script = r'''
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
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
      return result.exitCode == 0;
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
    try {
      final file = File(soundPath);
      if (file.existsSync()) {
        final result = await Process.run('afplay', [soundPath]);
        if (result.exitCode == 0) return true;
      }
      final fallback = await Process.run('osascript', ['-e', 'beep']);
      return fallback.exitCode == 0;
    } catch (_) {
      return false;
    }
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
        final result = await Process.run('canberra-gtk-play', ['-i', id]);
        if (result.exitCode == 0) return true;
      }
      if (await _commandExists('paplay')) {
        final result = await Process.run('paplay', [
          '/usr/share/sounds/freedesktop/stereo/message.oga',
        ]);
        if (result.exitCode == 0) return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<bool> _playSoundWindows(
    OpenHandNotificationLevel level,
  ) async {
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
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _commandExists(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
