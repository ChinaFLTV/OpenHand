import '../../../shared/ui/openhand_clipboard.dart';

class HtmlSelectionBridgeClipboard {
  static String? _selectedText;

  static bool get hasSelection =>
      _selectedText != null && _selectedText!.trim().isNotEmpty;

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
    await setOpenHandClipboardText(text);
  }
}
