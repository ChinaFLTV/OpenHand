// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui' as ui show KeyData, KeyEventType;

import 'package:flutter/foundation.dart';
import '../features/home/openhand_home_page.dart';
import '../l10n/app_localizations.dart';
import 'model/app_language.dart';
import 'state/settings_controller.dart';
import 'theme/openhand_theme.dart';
import 'theme/openhand_theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class OpenHandApp extends StatefulWidget {
  const OpenHandApp({super.key, this.home = const OpenHandHomePage()});

  final Widget home;

  @override
  State<OpenHandApp> createState() => _OpenHandAppState();
}

class _OpenHandAppState extends State<OpenHandApp> {
  bool Function(ui.KeyData data)? _previousOnKeyData;
  Future<dynamic> Function(dynamic message)? _previousRawKeyMessageHandler;
  bool _keyboardStateSyncQueued = false;

  @override
  void initState() {
    super.initState();
    _installKeyboardGuard();
  }

  @override
  void dispose() {
    _restoreKeyboardHandlers();
    super.dispose();
  }

  void _installKeyboardGuard() {
    _previousOnKeyData ??= WidgetsBinding.instance.platformDispatcher.onKeyData;
    _previousRawKeyMessageHandler ??=
        ServicesBinding.instance.keyEventManager.handleRawKeyMessage;
    WidgetsBinding.instance.platformDispatcher.onKeyData = _handleKeyDataSafely;
    SystemChannels.keyEvent.setMessageHandler(_handleRawKeyMessageSafely);
  }

  void _restoreKeyboardHandlers() {
    WidgetsBinding.instance.platformDispatcher.onKeyData =
        _previousOnKeyData ??
        ServicesBinding.instance.keyEventManager.handleKeyData;
    SystemChannels.keyEvent.setMessageHandler(
      _previousRawKeyMessageHandler ??
          ServicesBinding.instance.keyEventManager.handleRawKeyMessage,
    );
  }

  bool _handleKeyDataSafely(ui.KeyData data) {
    final physicalKey =
        PhysicalKeyboardKey.findKeyByCode(data.physical) ??
        PhysicalKeyboardKey(data.physical);
    final logicalKey =
        LogicalKeyboardKey.findKeyByKeyId(data.logical) ??
        LogicalKeyboardKey(data.logical);
    final hardwareKeyboard = HardwareKeyboard.instance;
    final isPressed = hardwareKeyboard.physicalKeysPressed.contains(
      physicalKey,
    );

    if (data.type == ui.KeyEventType.up && !isPressed) {
      _debugKeyboardLog(
        'suppressing_orphan_key_up physical=$physicalKey logical=$logicalKey',
      );
      _scheduleKeyboardStateResync('orphan_key_up');
      return false;
    }
    if (data.type == ui.KeyEventType.down && isPressed) {
      _debugKeyboardLog(
        'suppressing_duplicate_key_down physical=$physicalKey logical=$logicalKey',
      );
      _scheduleKeyboardStateResync('duplicate_key_down');
      return false;
    }
    return _forwardKeyData(data);
  }

  Future<dynamic> _handleRawKeyMessageSafely(dynamic message) async {
    if (message is Map<Object?, Object?>) {
      late final RawKeyEvent rawEvent;
      try {
        rawEvent = RawKeyEvent.fromMessage(
          message.map((key, value) => MapEntry('$key', value)),
        );
      } catch (error, stackTrace) {
        _debugKeyboardGuardFailure(
          stage: 'raw_key_parse',
          error: error,
          stackTrace: stackTrace,
        );
        _scheduleKeyboardStateResync('raw_key_parse_failure');
        return _unhandledRawKeyMessage();
      }
      final physicalKey = rawEvent.physicalKey;
      final hardwarePressed = HardwareKeyboard.instance.physicalKeysPressed
          .contains(physicalKey);
      if (rawEvent is RawKeyDownEvent && !rawEvent.repeat && hardwarePressed) {
        _debugKeyboardLog(
          'suppressing_duplicate_raw_key_down physical=$physicalKey logical=${rawEvent.logicalKey}',
        );
        _scheduleKeyboardStateResync('duplicate_raw_key_down');
        return _unhandledRawKeyMessage();
      }
      if (rawEvent is RawKeyUpEvent && !hardwarePressed) {
        _debugKeyboardLog(
          'suppressing_orphan_raw_key_up physical=$physicalKey',
        );
        _scheduleKeyboardStateResync('orphan_raw_key_up');
        return _unhandledRawKeyMessage();
      }
    }
    return _forwardRawKeyMessage(message);
  }

  bool _forwardKeyData(ui.KeyData data) {
    final delegate =
        _previousOnKeyData ??
        ServicesBinding.instance.keyEventManager.handleKeyData;
    try {
      return delegate(data);
    } catch (error, stackTrace) {
      _debugKeyboardGuardFailure(
        stage: 'key_data',
        error: error,
        stackTrace: stackTrace,
      );
      _scheduleKeyboardStateResync('key_data_failure');
      return false;
    }
  }

  Future<dynamic> _forwardRawKeyMessage(dynamic message) async {
    final delegate =
        _previousRawKeyMessageHandler ??
        ServicesBinding.instance.keyEventManager.handleRawKeyMessage;
    try {
      return await delegate(message);
    } catch (error, stackTrace) {
      _debugKeyboardGuardFailure(
        stage: 'raw_key_message',
        error: error,
        stackTrace: stackTrace,
      );
      _scheduleKeyboardStateResync('raw_key_message_failure');
      return _unhandledRawKeyMessage();
    }
  }

  void _scheduleKeyboardStateResync(String reason) {
    if (_keyboardStateSyncQueued) {
      return;
    }
    _keyboardStateSyncQueued = true;
    unawaited(() async {
      try {
        await HardwareKeyboard.instance.syncKeyboardState();
        _debugKeyboardLog('state_resynced reason=$reason');
      } catch (error, stackTrace) {
        _debugKeyboardGuardFailure(
          stage: 'keyboard_state_resync',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _keyboardStateSyncQueued = false;
      }
    }());
  }

  Future<Map<String, dynamic>> _unhandledRawKeyMessage() {
    return Future<Map<String, dynamic>>.value(<String, dynamic>{
      'handled': false,
    });
  }

  void _debugKeyboardGuardFailure({
    required String stage,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[OpenHand][Keyboard] guard_failure stage=$stage error=$error',
    );
    debugPrintStack(
      label: '[OpenHand][Keyboard] guard_failure_stack stage=$stage',
      stackTrace: stackTrace,
    );
  }

  void _debugKeyboardLog(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[OpenHand][Keyboard] $message');
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsController, ThemeMode>(
      (controller) => controller.themeMode,
    );
    final themePreset = context.select<SettingsController, OpenHandThemePreset>(
      (controller) => controller.themePreset,
    );
    final locale = context.select<SettingsController, Locale?>(
      (controller) => controller.locale,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      themeMode: themeMode,
      theme: OpenHandTheme.light(themePreset),
      darkTheme: OpenHandTheme.dark(themePreset),
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      themeAnimationCurve: Curves.easeOutCubic,
      themeAnimationDuration: const Duration(milliseconds: 220),
      home: widget.home,
    );
  }
}
