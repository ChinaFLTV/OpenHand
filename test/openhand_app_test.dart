// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/openhand_app.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';

void main() {
  testWidgets('OpenHandApp suppresses duplicate key down events', (
    tester,
  ) async {
    final settingsController = await SettingsController.create(
      store: _InMemorySettingsStore(),
    );
    addTearDown(settingsController.dispose);
    addTearDown(() {
      ServicesBinding.instance.keyEventManager.clearState();
      HardwareKeyboard.instance.clearState();
      RawKeyboard.instance.clearKeysPressed();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
        child: const OpenHandApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    await _dispatchAppKeyDown(
      tester,
      physicalKey: PhysicalKeyboardKey.keyD,
      logicalKey: LogicalKeyboardKey.keyD,
      webCode: 'KeyD',
      webKey: 'd',
      webKeyCode: 68,
      character: 'd',
    );
    expect(
      HardwareKeyboard.instance.physicalKeysPressed,
      contains(PhysicalKeyboardKey.keyD),
    );

    final duplicateHandled = tester.binding.platformDispatcher.onKeyData!(
      ui.KeyData(
        type: ui.KeyEventType.down,
        physical: PhysicalKeyboardKey.keyD.usbHidUsage,
        logical: LogicalKeyboardKey.keyD.keyId,
        timeStamp: Duration.zero,
        character: 'd',
        synthesized: false,
      ),
    );
    expect(duplicateHandled, isFalse);
    expect(
      HardwareKeyboard.instance.physicalKeysPressed,
      contains(PhysicalKeyboardKey.keyD),
    );

    final duplicateRawResponse =
        await _sendRawWebKeyMessage(tester, <String, dynamic>{
          'type': 'keydown',
          'keymap': 'web',
          'code': 'KeyD',
          'key': 'd',
          'location': 0,
          'metaState': 0,
          'keyCode': 68,
        });
    await tester.pump();
    expect(duplicateRawResponse, <String, dynamic>{'handled': false});
    expect(
      HardwareKeyboard.instance.physicalKeysPressed,
      contains(PhysicalKeyboardKey.keyD),
    );
    expect(tester.takeException(), isNull);
    await _dispatchAppKeyUp(
      tester,
      physicalKey: PhysicalKeyboardKey.keyD,
      logicalKey: LogicalKeyboardKey.keyD,
      webCode: 'KeyD',
      webKey: 'd',
      webKeyCode: 68,
    );
  });

  testWidgets(
    'OpenHandApp ignores orphan key up events and keeps later input working',
    (tester) async {
      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      addTearDown(settingsController.dispose);
      addTearDown(() {
        ServicesBinding.instance.keyEventManager.clearState();
        HardwareKeyboard.instance.clearState();
        RawKeyboard.instance.clearKeysPressed();
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
          child: const OpenHandApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      final orphanHandled = tester.binding.platformDispatcher.onKeyData!(
        ui.KeyData(
          type: ui.KeyEventType.up,
          physical: PhysicalKeyboardKey.metaLeft.usbHidUsage,
          logical: LogicalKeyboardKey.metaLeft.keyId,
          timeStamp: Duration.zero,
          character: null,
          synthesized: false,
        ),
      );
      expect(orphanHandled, isFalse);

      await _sendRawWebKeyMessage(tester, <String, dynamic>{
        'type': 'keyup',
        'keymap': 'web',
        'code': 'MetaLeft',
        'key': 'Meta',
        'location': 1,
        'metaState': 0,
        'keyCode': 91,
      });
      await tester.pump();

      expect(tester.takeException(), isNull);

      await _dispatchAppKeyDown(
        tester,
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        webCode: 'KeyD',
        webKey: 'd',
        webKeyCode: 68,
        character: 'd',
      );

      expect(
        HardwareKeyboard.instance.physicalKeysPressed,
        contains(PhysicalKeyboardKey.keyD),
      );
      expect(tester.takeException(), isNull);

      await _dispatchAppKeyUp(
        tester,
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        webCode: 'KeyD',
        webKey: 'd',
        webKeyCode: 68,
      );
    },
  );

  testWidgets(
    'OpenHandApp suppresses duplicate modifier key down events without crashing',
    (tester) async {
      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      addTearDown(settingsController.dispose);
      addTearDown(() {
        ServicesBinding.instance.keyEventManager.clearState();
        HardwareKeyboard.instance.clearState();
        RawKeyboard.instance.clearKeysPressed();
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
          child: const OpenHandApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      await _dispatchAppKeyDown(
        tester,
        physicalKey: PhysicalKeyboardKey.metaLeft,
        logicalKey: LogicalKeyboardKey.metaLeft,
        webCode: 'MetaLeft',
        webKey: 'Meta',
        webKeyCode: 91,
        character: null,
        location: 1,
        metaState: RawKeyEventDataWeb.modifierMeta,
      );
      expect(
        HardwareKeyboard.instance.physicalKeysPressed,
        contains(PhysicalKeyboardKey.metaLeft),
      );

      final duplicateHandled = tester.binding.platformDispatcher.onKeyData!(
        ui.KeyData(
          type: ui.KeyEventType.down,
          physical: PhysicalKeyboardKey.metaLeft.usbHidUsage,
          logical: LogicalKeyboardKey.metaLeft.keyId,
          timeStamp: Duration.zero,
          character: null,
          synthesized: false,
        ),
      );
      expect(duplicateHandled, isFalse);
      expect(
        HardwareKeyboard.instance.physicalKeysPressed,
        contains(PhysicalKeyboardKey.metaLeft),
      );

      final duplicateRawResponse =
          await _sendRawWebKeyMessage(tester, <String, dynamic>{
            'type': 'keydown',
            'keymap': 'web',
            'code': 'MetaLeft',
            'key': 'Meta',
            'location': 1,
            'metaState': RawKeyEventDataWeb.modifierMeta,
            'keyCode': 91,
          });
      await tester.pump();

      expect(duplicateRawResponse, <String, dynamic>{'handled': false});
      expect(tester.takeException(), isNull);
      expect(
        HardwareKeyboard.instance.physicalKeysPressed,
        contains(PhysicalKeyboardKey.metaLeft),
      );

      await _dispatchAppKeyUp(
        tester,
        physicalKey: PhysicalKeyboardKey.metaLeft,
        logicalKey: LogicalKeyboardKey.metaLeft,
        webCode: 'MetaLeft',
        webKey: 'Meta',
        webKeyCode: 91,
        location: 1,
      );
    },
  );

  testWidgets('OpenHandApp ignores malformed raw key channel payloads', (
    tester,
  ) async {
    final settingsController = await SettingsController.create(
      store: _InMemorySettingsStore(),
    );
    addTearDown(settingsController.dispose);
    var keyboardStateRequests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.keyboard,
      (methodCall) async {
        if (methodCall.method == 'getKeyboardState') {
          keyboardStateRequests += 1;
          return <int, int>{};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.keyboard,
        null,
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
        child: const OpenHandApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    final response = await _sendRawWebKeyMessage(tester, <String, dynamic>{
      'type': 'keydown',
      'keymap': 7,
      'keyCode': 'not-a-number',
    });
    await tester.pump();

    expect(response, <String, dynamic>{'handled': false});
    expect(keyboardStateRequests, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _dispatchAppKeyDown(
  WidgetTester tester, {
  required PhysicalKeyboardKey physicalKey,
  required LogicalKeyboardKey logicalKey,
  required String webCode,
  required String webKey,
  required int webKeyCode,
  required String? character,
  int location = 0,
  int metaState = 0,
}) async {
  final handled = tester.binding.platformDispatcher.onKeyData!(
    ui.KeyData(
      type: ui.KeyEventType.down,
      physical: physicalKey.usbHidUsage,
      logical: logicalKey.keyId,
      timeStamp: Duration.zero,
      character: character,
      synthesized: false,
    ),
  );
  expect(handled, isFalse);
  await _sendRawWebKeyMessage(tester, <String, dynamic>{
    'type': 'keydown',
    'keymap': 'web',
    'code': webCode,
    'key': webKey,
    'location': location,
    'metaState': metaState,
    'keyCode': webKeyCode,
  });
  await tester.pump();
}

Future<void> _dispatchAppKeyUp(
  WidgetTester tester, {
  required PhysicalKeyboardKey physicalKey,
  required LogicalKeyboardKey logicalKey,
  required String webCode,
  required String webKey,
  required int webKeyCode,
  int location = 0,
  int metaState = 0,
}) async {
  final handled = tester.binding.platformDispatcher.onKeyData!(
    ui.KeyData(
      type: ui.KeyEventType.up,
      physical: physicalKey.usbHidUsage,
      logical: logicalKey.keyId,
      timeStamp: Duration.zero,
      character: null,
      synthesized: false,
    ),
  );
  expect(handled, isFalse);
  await _sendRawWebKeyMessage(tester, <String, dynamic>{
    'type': 'keyup',
    'keymap': 'web',
    'code': webCode,
    'key': webKey,
    'location': location,
    'metaState': metaState,
    'keyCode': webKeyCode,
  });
  await tester.pump();
}

Future<Map<String, dynamic>> _sendRawWebKeyMessage(
  WidgetTester tester,
  Map<String, dynamic> message,
) async {
  final completer = Completer<Map<String, dynamic>>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.keyEvent.name,
    SystemChannels.keyEvent.codec.encodeMessage(message),
    (data) {
      final decoded =
          SystemChannels.keyEvent.codec.decodeMessage(data)!
              as Map<String, dynamic>;
      completer.complete(decoded);
    },
  );
  return completer.future;
}

class _InMemorySettingsStore extends SettingsStore {
  _InMemorySettingsStore()
    : super(settingsFilePath: '/tmp/openhand-app-test.toml');

  AppSettingsSnapshot _snapshot = AppSettingsSnapshot.defaults();

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
