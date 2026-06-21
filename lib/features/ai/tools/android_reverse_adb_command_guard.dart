class AndroidReverseAdbCommandGuard {
  const AndroidReverseAdbCommandGuard._();

  static const String templateId = 'android_reverse_expert';

  static bool isAndroidReverseMetadata(Map<String, Object?> metadata) {
    if (metadata['android_reverse_runtime'] is Map ||
        metadata['android_reverse_config'] is Map) {
      return true;
    }
    final template =
        '${metadata['template_id'] ?? metadata['templateId'] ?? ''}'.trim();
    return template == templateId;
  }

  static bool requiresExplicitApproval({
    required String command,
    required Map<String, Object?> metadata,
  }) {
    if (!isAndroidReverseMetadata(metadata)) {
      return false;
    }
    return isGlobalAdbRecoveryCommand(command);
  }

  static bool isGlobalAdbRecoveryCommand(String command) {
    final normalized = _stripQuotedText(command).toLowerCase();
    if (normalized.trim().isEmpty) {
      return false;
    }
    for (final segment in normalized.split(_shellSegmentSeparator)) {
      final text = segment.trim();
      if (text.isEmpty) {
        continue;
      }
      if (_adbDaemonCommandPattern.hasMatch(text)) {
        return true;
      }
      if (_adbKillProcessPattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  static const Map<String, Object?> metadata = <String, Object?>{
    'android_reverse_adb_global_recovery_confirmation_required': true,
  };

  static final RegExp _shellSegmentSeparator = RegExp(r'(?:&&|\|\||[;\n])');
  static final RegExp _adbDaemonCommandPattern = RegExp(
    r'(^|\s)(?:[\w./-]*adb)\b(?:\s+-[^\s;&|]+(?:\s+[^\s;&|]+)?)*\s+'
    r'(?:kill-server|start-server)\b',
  );
  static final RegExp _adbKillProcessPattern = RegExp(
    r'(^|\s)(?:pkill|killall)\b(?:\s+-[a-z0-9]+)*\s+adb\b',
  );

  static String _stripQuotedText(String input) {
    final buffer = StringBuffer();
    String? quote;
    var escaped = false;
    for (final codeUnit in input.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      if (escaped) {
        escaped = false;
        if (quote == null) {
          buffer.write(ch);
        }
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        if (quote == null) {
          buffer.write(ch);
        }
        continue;
      }
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }
}
