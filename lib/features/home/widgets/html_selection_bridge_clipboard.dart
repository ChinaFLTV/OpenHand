import 'package:flutter/services.dart';

class HtmlSelectionBridgeClipboard {
  static String? _selectedText;

  static bool get hasSelection =>
      _selectedText != null && _selectedText!.trim().isNotEmpty;

  static String? get selectedTextForTest => _selectedText;

  static void clear() {
    _selectedText = null;
  }

  static void update(String? text) {
    final normalized = text?.replaceAll(' ', ' ').trim();
    if (normalized == null || normalized.isEmpty) {
      clear();
      return;
    }
    _selectedText = normalized;
  }

  static Future<void> copySelection() async {
    final text = _selectedText;
    if (text == null || text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }
}
