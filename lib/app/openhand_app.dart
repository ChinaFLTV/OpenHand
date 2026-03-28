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
  static const Object _invalidRawKeyField = Object();
  static const Set<String> _supportedRawKeymaps = <String>{
    'android',
    'fuchsia',
    'ios',
    'linux',
    'macos',
    'web',
    'windows',
  };
  static const Set<String> _rawKeyIntegerFields = <String>{
    'characterCodePoint',
    'codePoint',
    'deviceId',
    'flags',
    'hidUsage',
    'keyCode',
    'location',
    'metaState',
    'modifiers',
    'plainCodePoint',
    'productId',
    'repeatCount',
    'scanCode',
    'source',
    'specifiedLogicalKey',
    'unicodeScalarValues',
    'vendorId',
  };
  static const Set<String> _rawKeyStringFields = <String>{
    'character',
    'characters',
    'charactersIgnoringModifiers',
    'code',
    'key',
    'keymap',
    'toolkit',
    'type',
  };
  bool Function(ui.KeyData data)? _previousOnKeyData;
  Future<dynamic> Function(dynamic message)? _previousRawKeyMessageHandler;
  bool _keyboardStateSyncQueued = false;
  final Map<PhysicalKeyboardKey, LogicalKeyboardKey>
  _trackedRawLogicalKeysByPhysicalKey =
      <PhysicalKeyboardKey, LogicalKeyboardKey>{};

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
    _trackedRawLogicalKeysByPhysicalKey.clear();
  }

  bool _handleKeyDataSafely(ui.KeyData data) {
    final physicalKey =
        PhysicalKeyboardKey.findKeyByCode(data.physical) ??
        PhysicalKeyboardKey(data.physical);
    final hardwareKeyboard = HardwareKeyboard.instance;
    final isPressed = hardwareKeyboard.physicalKeysPressed.contains(
      physicalKey,
    );

    if (data.type == ui.KeyEventType.up && !isPressed) {
      _scheduleKeyboardStateResync('orphan_key_up');
      return false;
    }
    if (data.type == ui.KeyEventType.down && isPressed) {
      _scheduleKeyboardStateResync('duplicate_key_down');
      return false;
    }
    return _forwardKeyData(data);
  }

  Future<dynamic> _handleRawKeyMessageSafely(dynamic message) async {
    if (message is Map<Object?, Object?>) {
      final normalizedMessage = _normalizeRawKeyMessage(message);
      if (normalizedMessage == null) {
        _scheduleKeyboardStateResync('raw_key_payload_invalid');
        return _unhandledRawKeyMessage();
      }
      late final RawKeyEvent rawEvent;
      try {
        rawEvent = RawKeyEvent.fromMessage(normalizedMessage);
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
      final logicalKey = rawEvent.logicalKey;
      final hardwarePressed = HardwareKeyboard.instance.physicalKeysPressed
          .contains(physicalKey);
      final trackedLogicalKey =
          _trackedRawLogicalKeysByPhysicalKey[physicalKey];
      if (rawEvent is RawKeyDownEvent) {
        if (!rawEvent.repeat) {
          _trackedRawLogicalKeysByPhysicalKey[physicalKey] = logicalKey;
        }
        if (!rawEvent.repeat && hardwarePressed) {
          return _unhandledRawKeyMessage();
        }
      }
      if (rawEvent is RawKeyUpEvent) {
        _trackedRawLogicalKeysByPhysicalKey.remove(physicalKey);
        if (trackedLogicalKey != null && trackedLogicalKey != logicalKey) {
          _scheduleKeyboardStateResync('mismatched_raw_key_up');
          return _unhandledRawKeyMessage();
        }
        if (!hardwarePressed) {
          return _unhandledRawKeyMessage();
        }
      }
      if (rawEvent is RawKeyDownEvent &&
          trackedLogicalKey != null &&
          trackedLogicalKey != logicalKey) {
        _scheduleKeyboardStateResync('mismatched_raw_key_down');
        return _unhandledRawKeyMessage();
      }
      return _forwardRawKeyMessage(normalizedMessage);
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
      } catch (error, stackTrace) {
        _debugKeyboardGuardFailure(
          stage: 'keyboard_state_resync',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _trackedRawLogicalKeysByPhysicalKey.clear();
        _keyboardStateSyncQueued = false;
      }
    }());
  }

  Future<Map<String, dynamic>> _unhandledRawKeyMessage() {
    return Future<Map<String, dynamic>>.value(<String, dynamic>{
      'handled': false,
    });
  }

  Map<String, Object?>? _normalizeRawKeyMessage(Map<Object?, Object?> message) {
    final normalized = <String, Object?>{
      for (final entry in message.entries) '${entry.key}': entry.value,
    };
    for (final field in _rawKeyStringFields) {
      if (!normalized.containsKey(field)) {
        continue;
      }
      final value = normalized[field];
      if (value != null && value is! String) {
        return null;
      }
    }
    for (final field in _rawKeyIntegerFields) {
      if (!normalized.containsKey(field)) {
        continue;
      }
      final value = _normalizeRawKeyIntegerField(normalized[field]);
      if (identical(value, _invalidRawKeyField)) {
        return null;
      }
      normalized[field] = value;
    }
    final type = normalized['type'];
    if (type is! String || (type != 'keydown' && type != 'keyup')) {
      return null;
    }
    if (!kIsWeb) {
      final keymap = normalized['keymap'];
      if (keymap is! String || !_supportedRawKeymaps.contains(keymap)) {
        return null;
      }
    }
    return normalized;
  }

  Object? _normalizeRawKeyIntegerField(Object? value) {
    if (value == null || value is int) {
      return value;
    }
    if (value is num) {
      if (!value.isFinite || value != value.roundToDouble()) {
        return _invalidRawKeyField;
      }
      return value.toInt();
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) {
        return _invalidRawKeyField;
      }
      if (text.startsWith('0x') || text.startsWith('0X')) {
        return int.tryParse(text.substring(2), radix: 16) ??
            _invalidRawKeyField;
      }
      return int.tryParse(text) ?? _invalidRawKeyField;
    }
    return _invalidRawKeyField;
  }

  void _debugKeyboardGuardFailure({
    required String stage,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[OpenHand][Keyboard] guard_failure stage=$stage error=$error');
    debugPrintStack(
      label: '[OpenHand][Keyboard] guard_failure_stack stage=$stage',
      stackTrace: stackTrace,
    );
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
