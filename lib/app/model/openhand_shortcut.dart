import 'package:flutter/services.dart';

enum OpenHandShortcutAction {
  sendMessage,
  toggleComposer,
  selectPreviousModel,
  selectNextModel,
  toggleAutoFollow,
  selectPreviousSession,
  selectNextSession,
}

const int openHandShortcutMaxKeyCount = 4;

Map<OpenHandShortcutAction, List<int>> defaultOpenHandShortcutBindings() {
  return <OpenHandShortcutAction, List<int>>{
    OpenHandShortcutAction.sendMessage: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.enter.keyId,
    ]),
    OpenHandShortcutAction.toggleComposer: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyP.keyId,
    ]),
    OpenHandShortcutAction.selectPreviousModel: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.arrowLeft.keyId,
    ]),
    OpenHandShortcutAction.selectNextModel: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.arrowRight.keyId,
    ]),
    OpenHandShortcutAction.toggleAutoFollow: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyS.keyId,
    ]),
    OpenHandShortcutAction.selectPreviousSession: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.arrowUp.keyId,
    ]),
    OpenHandShortcutAction.selectNextSession: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.arrowDown.keyId,
    ]),
  };
}

String openHandShortcutActionStorageKey(OpenHandShortcutAction action) {
  return switch (action) {
    OpenHandShortcutAction.sendMessage => 'send_message',
    OpenHandShortcutAction.toggleComposer => 'toggle_composer',
    OpenHandShortcutAction.selectPreviousModel => 'select_previous_model',
    OpenHandShortcutAction.selectNextModel => 'select_next_model',
    OpenHandShortcutAction.toggleAutoFollow => 'toggle_auto_follow',
    OpenHandShortcutAction.selectPreviousSession => 'select_previous_session',
    OpenHandShortcutAction.selectNextSession => 'select_next_session',
  };
}

OpenHandShortcutAction? openHandShortcutActionFromStorageKey(String rawValue) {
  return switch (rawValue.trim()) {
    'send_message' => OpenHandShortcutAction.sendMessage,
    'toggle_composer' => OpenHandShortcutAction.toggleComposer,
    'select_previous_model' => OpenHandShortcutAction.selectPreviousModel,
    'select_next_model' => OpenHandShortcutAction.selectNextModel,
    'toggle_auto_follow' => OpenHandShortcutAction.toggleAutoFollow,
    'select_previous_session' => OpenHandShortcutAction.selectPreviousSession,
    'select_next_session' => OpenHandShortcutAction.selectNextSession,
    _ => null,
  };
}

List<int> normalizeShortcutKeyIds(Iterable<int> rawKeyIds) {
  final normalized = <int>{};
  for (final rawKeyId in rawKeyIds) {
    final logicalKey = LogicalKeyboardKey.findKeyByKeyId(rawKeyId);
    if (logicalKey == null) {
      continue;
    }
    normalized.add(normalizeShortcutLogicalKey(logicalKey).keyId);
  }
  final ordered = normalized.toList(growable: false)
    ..sort(compareShortcutKeyIds);
  return ordered;
}

Set<int> normalizedPressedShortcutKeyIds(Iterable<LogicalKeyboardKey> keys) {
  return normalizeShortcutKeyIds(keys.map((key) => key.keyId)).toSet();
}

LogicalKeyboardKey normalizeShortcutLogicalKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight) {
    return LogicalKeyboardKey.control;
  }
  if (key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight) {
    return LogicalKeyboardKey.shift;
  }
  if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) {
    return LogicalKeyboardKey.alt;
  }
  if (key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight) {
    return LogicalKeyboardKey.meta;
  }
  if (key == LogicalKeyboardKey.numpadEnter) {
    return LogicalKeyboardKey.enter;
  }
  return key;
}

bool isShortcutModifierKeyId(int keyId) {
  return keyId == LogicalKeyboardKey.control.keyId ||
      keyId == LogicalKeyboardKey.shift.keyId ||
      keyId == LogicalKeyboardKey.alt.keyId ||
      keyId == LogicalKeyboardKey.meta.keyId;
}

bool isValidShortcutBinding(Iterable<int> keyIds) {
  final normalized = normalizeShortcutKeyIds(keyIds);
  if (normalized.isEmpty || normalized.length > openHandShortcutMaxKeyCount) {
    return false;
  }
  return normalized.any((keyId) => !isShortcutModifierKeyId(keyId));
}

int compareShortcutKeyIds(int left, int right) {
  final leftWeight = _shortcutKeySortWeight(left);
  final rightWeight = _shortcutKeySortWeight(right);
  if (leftWeight != rightWeight) {
    return leftWeight.compareTo(rightWeight);
  }
  return shortcutKeyLabelForKeyId(
    left,
  ).compareTo(shortcutKeyLabelForKeyId(right));
}

String formatShortcutLabel(Iterable<int> keyIds) {
  final normalized = normalizeShortcutKeyIds(keyIds);
  if (normalized.isEmpty) {
    return 'Not set';
  }
  return normalized.map(shortcutKeyLabelForKeyId).join(' + ');
}

String shortcutKeyLabelForKeyId(int keyId) {
  if (keyId == LogicalKeyboardKey.control.keyId) {
    return 'Ctrl';
  }
  if (keyId == LogicalKeyboardKey.shift.keyId) {
    return 'Shift';
  }
  if (keyId == LogicalKeyboardKey.alt.keyId) {
    return 'Alt';
  }
  if (keyId == LogicalKeyboardKey.meta.keyId) {
    return 'Cmd';
  }
  if (keyId == LogicalKeyboardKey.enter.keyId) {
    return 'Enter';
  }
  if (keyId == LogicalKeyboardKey.arrowLeft.keyId) {
    return '←';
  }
  if (keyId == LogicalKeyboardKey.arrowRight.keyId) {
    return '→';
  }
  if (keyId == LogicalKeyboardKey.arrowUp.keyId) {
    return '↑';
  }
  if (keyId == LogicalKeyboardKey.arrowDown.keyId) {
    return '↓';
  }
  return _fallbackShortcutKeyLabel(keyId);
}

String _fallbackShortcutKeyLabel(int keyId) {
  final logicalKey = LogicalKeyboardKey.findKeyByKeyId(keyId);
  if (logicalKey == null) {
    return 'Key';
  }
  final keyLabel = logicalKey.keyLabel.trim();
  if (keyLabel.isNotEmpty) {
    return keyLabel.length == 1 ? keyLabel.toUpperCase() : keyLabel;
  }
  final debugName = logicalKey.debugName?.trim() ?? '';
  if (debugName.isEmpty) {
    return 'Key';
  }
  return switch (debugName) {
    'Space' => 'Space',
    'Tab' => 'Tab',
    'Escape' => 'Esc',
    'Backspace' => 'Backspace',
    _ => debugName,
  };
}

int _shortcutKeySortWeight(int keyId) {
  if (keyId == LogicalKeyboardKey.control.keyId) {
    return 0;
  }
  if (keyId == LogicalKeyboardKey.shift.keyId) {
    return 1;
  }
  if (keyId == LogicalKeyboardKey.alt.keyId) {
    return 2;
  }
  if (keyId == LogicalKeyboardKey.meta.keyId) {
    return 3;
  }
  return 10;
}
